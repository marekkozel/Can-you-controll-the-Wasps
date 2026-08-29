class_name HuntComponent
extends Node2D

# 索敌 / hunt: 追最近的黄蜂咬。跟 RaidComponent 互斥，一只敌人只开一个。
# 挂到 RigidBody2D 下，开着的时候 WanderComponent 必须关——两边都写 linear_velocity。
# Mutually exclusive with RaidComponent; wander must be off while this runs.
#
# **缰绳不是可选项。** 猎手永远不缺目标（场上总有蜂），所以它自己永远不会停下来。
# 没有 leash_radius 的话，它会追着一只被玩家甩到走廊的蜂跑出半张地图，
# 入侵就从"围着巢打"变成"满地图追逐战"。什么时候收兵仍然由 RaidDirector 说了算。
# The leash is not optional: a hunter never runs out of targets and never stops on its
# own. Without it one flung wasp drags the whole raid across the map.

signal bit(victim: Node2D)

const HIVE_GROUP: StringName = &"hive"
const WASP_GROUP: StringName = &"wasps"

@export_range(20.0, 400.0, 5.0) var fly_speed: float = 125.0
## 够得着就咬。要大于双方碰撞半径之和（敌人 20 + 黄蜂 19.5 = 39.5）
## Must clear both collision radii or it hovers just short forever.
@export_range(10.0, 120.0, 1.0) var reach: float = 46.0
@export_range(0.05, 1.0, 0.01) var steering: float = 0.10

@export_group("Combat")
@export_range(1, 10, 1) var damage: int = 1
## 两口之间的间隔。这个数**就是**玩家把伤蜂拖出来的窗口，改它等于改战斗手感
## This interval IS the player's window to drag a wounded wasp clear.
@export_range(0.2, 10.0, 0.1) var bite_cooldown: float = 1.5
## 一口扫到多大范围内的所有蜂，0 = 只咬目标那一只。由 EnemyVariant 写入
## Cleave radius, 0 = single target. Written by EnemyVariant.
@export_range(0.0, 160.0, 2.0) var bite_radius: float = 0.0

@export_group("Leash")
## 离巢超过这个距离就丢下目标往回走 / drops the chase and heads back past this
@export_range(100.0, 1200.0, 10.0) var leash_radius: float = 420.0

@export_group("Chase")
## 追这么久还没咬到就换人。蜂的巡航是 `任务速度 x speed_units`，点过 SPEED 的那只
## 谁都追不上——没有这条，猎手会咬死一只快蜂追到脱缰、回巢、再选中同一只
## A SPEED-gifted wasp simply outruns everyone; without this the hunter locks onto her,
## leashes out, comes home and picks her again.
@export_range(1.0, 20.0, 0.5) var give_up_time: float = 4.0
## 放弃之后多久内不再选它 / how long a given-up quarry stays off the list
@export_range(1.0, 30.0, 0.5) var forget_time: float = 6.0
## 每隔这么久回头看一眼有没有更近的 / how often it re-checks for a closer wasp
@export_range(0.2, 5.0, 0.1) var retarget_interval: float = 1.0
## 近这么多才值得改主意，否则两只蜂差不多远时它会一路来回摇摆
## Hysteresis - two near-equidistant wasps would make it dither the whole way there.
@export_range(0.0, 300.0, 5.0) var retarget_margin: float = 60.0

var hunting: bool = false

var _body: RigidBody2D = null
var _steering: NavSteering = null
var _cooldown: float = 0.0
var _chase_time: float = 0.0
var _retarget_time: float = 0.0
# 放弃过的目标：instance_id -> 还要忽略多久。存 id 不存引用，键不会变成悬空对象
# Given-up quarry: instance_id -> seconds left. Ids, not references, so nothing dangles.
var _ignored: Dictionary = {}
# 不加类型：追着的蜂随时可能被处决/打死，类型化变量拒绝存已释放的实例
# Untyped on purpose - the quarry can be freed at any moment.
var _target = null


func _ready() -> void:
	_body = get_parent() as RigidBody2D
	if _body == null:
		push_warning("HuntComponent needs a RigidBody2D parent: %s" % get_path())
		set_physics_process(false)
		return
	_steering = NavSteering.new(_body, get_node_or_null("NavigationAgent2D") as NavigationAgent2D)
	set_physics_process(false)


func begin() -> void:
	if _body == null:
		return
	hunting = true
	set_physics_process(true)


# 收兵或者死了都要停，不然会继续给一具冻住的尸体写速度
# Stop on death too, or this keeps steering a frozen corpse.
func stop() -> void:
	hunting = false
	_drop_target()
	_ignored.clear()
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _body == null:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)

	_forget(delta)

	var home: Vector2 = _hive_position()
	# 拉出缰绳了：丢下目标往回走，回程路上不理任何蜂
	# Off the leash - drop the quarry and head home, ignoring everything on the way.
	if home != Vector2.INF and _body.global_position.distance_to(home) > leash_radius:
		_drop_target()
		_steering.steer(home, delta, fly_speed, steering)
		return

	if is_instance_valid(_target):
		_chase_time += delta
		# 追了这么久都没咬到，说明它比自己快。挂起来一会儿，去找够得着的
		# Still out of reach means it is simply faster; shelve it and take a reachable one.
		if _chase_time >= give_up_time:
			_ignored[_target.get_instance_id()] = forget_time
			_drop_target()
		else:
			_retarget_time -= delta
			if _retarget_time <= 0.0:
				_retarget_time = retarget_interval
				_consider_closer()
	else:
		_drop_target()

	if _target == null:
		_acquire()
	if _target == null:
		# 一只蜂都没有就在巢边转悠等着 / nothing to hunt, hold near the nest
		if home != Vector2.INF:
			_steering.steer(home, delta, fly_speed, steering)
		return

	_steering.steer(_target.global_position, delta, fly_speed, steering)
	if _body.global_position.distance_to(_target.global_position) > reach:
		return
	if _cooldown > 0.0:
		return

	var victim: Node2D = _target
	if not victim.has_method("take_damage"):
		_ignored[victim.get_instance_id()] = forget_time  # 别下一帧又选中它 / don't re-pick it
		_drop_target()
		return
	victim.take_damage(damage, _body.global_position)
	_cleave(victim)
	_cooldown = bite_cooldown
	_chase_time = 0.0  # 咬到了就不算追不上 / a landed bite is not a stalled chase
	bit.emit(victim)


# 横扫：同一口打到范围内其余的蜂。伤害和冷却都跟正主共用一次，
# **不是**额外多咬一口——否则围得越多它打得越快，方向就反了
# One bite, several victims: the damage and the cooldown are the bite's, not per victim.
func _cleave(primary: Node2D) -> void:
	if bite_radius <= 0.0:
		return
	var at: Vector2 = _body.global_position
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Node2D = node as Node2D
		if wasp == null or wasp == primary or not is_instance_valid(wasp):
			continue
		if not wasp.has_method("take_damage"):
			continue
		if at.distance_to(wasp.global_position) <= bite_radius:
			wasp.take_damage(damage, at)


func _drop_target() -> void:
	_target = null
	_chase_time = 0.0
	_retarget_time = retarget_interval


func _acquire() -> void:
	_target = _nearest_wasp()
	# 全场的蜂都在忽略名单上（小群体里很容易发生）：宁可再追一次追不上的，
	# 也不能让猎手在巢边发呆 / better a hopeless chase than a hunter standing around
	if _target == null and not _ignored.is_empty():
		_ignored.clear()
		_target = _nearest_wasp()
	_chase_time = 0.0
	_retarget_time = retarget_interval


# 有明显更近的就换过去。差距要过 retarget_margin，否则会一路摇摆
# Swap only for a clearly closer wasp, or it dithers all the way there.
func _consider_closer() -> void:
	var other = _nearest_wasp()
	if other == null or other == _target:
		return
	var here: float = _body.global_position.distance_to(_target.global_position)
	var there: float = _body.global_position.distance_to(other.global_position)
	if there < here - retarget_margin:
		_target = other
		_chase_time = 0.0


func _forget(delta: float) -> void:
	for id in _ignored.keys():
		var left: float = _ignored[id] - delta
		if left <= 0.0:
			_ignored.erase(id)
		else:
			_ignored[id] = left


func _nearest_wasp():
	var best = null
	var best_dist: float = INF
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Node2D = node as Node2D
		if wasp == null:
			continue
		if _ignored.has(wasp.get_instance_id()):
			continue
		var dist: float = _body.global_position.distance_to(wasp.global_position)
		if dist < best_dist:
			best_dist = dist
			best = wasp
	return best


func _hive_position() -> Vector2:
	var hive: Node2D = get_tree().get_first_node_in_group(HIVE_GROUP) as Node2D
	return hive.global_position if hive != null else Vector2.INF
