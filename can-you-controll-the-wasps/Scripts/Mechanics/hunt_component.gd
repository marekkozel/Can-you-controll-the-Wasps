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

@export_group("Leash")
## 离巢超过这个距离就丢下目标往回走 / drops the chase and heads back past this
@export_range(100.0, 1200.0, 10.0) var leash_radius: float = 420.0

var hunting: bool = false

var _body: RigidBody2D = null
var _steering: NavSteering = null
var _cooldown: float = 0.0
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
	_target = null
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _body == null:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)

	var home: Vector2 = _hive_position()
	# 拉出缰绳了：丢下目标往回走，回程路上不理任何蜂
	# Off the leash - drop the quarry and head home, ignoring everything on the way.
	if home != Vector2.INF and _body.global_position.distance_to(home) > leash_radius:
		_target = null
		_steering.steer(home, delta, fly_speed, steering)
		return

	if not is_instance_valid(_target):
		_target = _nearest_wasp()
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
		_target = null
		return
	victim.take_damage(damage, _body.global_position)
	_cooldown = bite_cooldown
	bit.emit(victim)


func _nearest_wasp():
	var best = null
	var best_dist: float = INF
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Node2D = node as Node2D
		if wasp == null:
			continue
		var dist: float = _body.global_position.distance_to(wasp.global_position)
		if dist < best_dist:
			best_dist = dist
			best = wasp
	return best


func _hive_position() -> Vector2:
	var hive: Node2D = get_tree().get_first_node_in_group(HIVE_GROUP) as Node2D
	return hive.global_position if hive != null else Vector2.INF
