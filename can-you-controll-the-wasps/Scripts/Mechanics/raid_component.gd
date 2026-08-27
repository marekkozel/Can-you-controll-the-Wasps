class_name RaidComponent
extends Node2D

# 入侵 / raid: 从入口一路摸进巢里，抢走一只幼虫或者卵就撤；抢不到就啃建造进度。
# 挂到 RigidBody2D 下。开着的时候必须把 WanderComponent 关掉——两边都写 linear_velocity
# Attach under a RigidBody2D. WanderComponent must be off while this runs; both write
# linear_velocity and would fight, exactly like the drag spring does.
#
# 方向听导航网格：地图是"上走廊 + 下巢室"的 T 形，从边缘直线飞过去会顶在隔断上
# Headings come from the navmesh - the map is a T and a straight line hits the divider.

signal raided(cell: HexCell, took_brood: bool)
signal retreated

enum Phase {
	DORMANT,  ## 还没被叫起来 / not called up yet
	RAID,     ## 摸向巢室 / heading for the hive
	RETREAT,  ## 得手了或者收兵了，往出口飞 / got what it came for, or the raid was called off
}

## 巡航速度。比工蜂的 90~100 快一点，入侵要有压迫感 / faster than a worker's cruise
@export_range(20.0, 400.0, 5.0) var fly_speed: float = 115.0
## 多近算够得着。要大于双方碰撞半径之和（敌人 20 + 巢室），否则永远啃不到
## Must clear both collision radii or it hovers just short forever.
@export_range(10.0, 120.0, 1.0) var reach: float = 34.0
@export_range(0.05, 1.0, 0.01) var steering: float = 0.10

@export_group("Chewing")
## 两次啃建造进度之间的间隔 / seconds between bites on build progress
@export_range(0.2, 10.0, 0.1) var bite_cooldown: float = 1.6
@export_range(1, 5, 1) var bite_damage: int = 1

const HIVE_GROUP: StringName = &"hive"

var phase: Phase = Phase.DORMANT

var _body: RigidBody2D = null
var _nav: NavigationAgent2D = null
var _cell: HexCell = null
var _cooldown: float = 0.0
var _nav_goal: Vector2 = Vector2.INF
# 从哪进来的就从哪出去 / leaves the way it came
var _exit_point: Vector2 = Vector2.INF


func _ready() -> void:
	_body = get_parent() as RigidBody2D
	if _body == null:
		push_warning("RaidComponent needs a RigidBody2D parent: %s" % get_path())
		set_physics_process(false)
		return
	_nav = get_node_or_null("NavigationAgent2D") as NavigationAgent2D
	set_physics_process(false)


# 叫起来。exit_point 是收兵时往哪撤，不给就用当前位置
# Called up by the director; exit_point is where it leaves from when the raid ends.
func begin(exit_point: Vector2 = Vector2.INF) -> void:
	if _body == null:
		return
	_exit_point = exit_point if exit_point != Vector2.INF else _body.global_position
	phase = Phase.RAID
	set_physics_process(true)


# 收兵。已经在撤的不用再叫一次 / calling off an already-retreating raider is a no-op
func retreat() -> void:
	if _body == null or phase == Phase.RETREAT:
		return
	_cell = null
	phase = Phase.RETREAT
	set_physics_process(true)


func is_raiding() -> bool:
	return phase == Phase.RAID


func _physics_process(delta: float) -> void:
	if _body == null:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)

	match phase:
		Phase.RETREAT:
			_do_retreat(delta)
		Phase.RAID:
			_do_raid(delta)
		_:
			set_physics_process(false)


func _do_raid(delta: float) -> void:
	if not _is_usable(_cell) and not _acquire():
		# 巢里已经没什么可抢的了，那就没必要待着 / nothing left worth taking
		retreat()
		return

	_steer(_cell.global_position, delta)
	if _body.global_position.distance_to(_cell.global_position) > reach:
		return
	if _cooldown > 0.0:
		return

	var cell: HexCell = _cell
	# 有幼虫或者卵就是奔着这个来的，得手立刻撤——它不是叛军，不会赖在巢里慢慢碾
	# Brood is what it came for: take one and leave. Unlike a rebel it does not linger.
	if cell.content == HexCell.Content.LARVA or cell.content == HexCell.Content.EGG:
		if cell.destroy_occupant():
			raided.emit(cell, true)
			retreat()
			return
		_cell = null
		return

	if cell.damage_build(bite_damage):
		raided.emit(cell, false)
		_cooldown = bite_cooldown
	_cell = null


func _do_retreat(delta: float) -> void:
	if _exit_point == Vector2.INF:
		_despawn()
		return
	_steer(_exit_point, delta)
	if _body.global_position.distance_to(_exit_point) <= reach:
		retreated.emit()
		_despawn()


# 被打死的时候得停下来，不然组件会继续给一具冻住的尸体写速度
# Must be called on death, or this keeps steering a frozen corpse.
func stop() -> void:
	phase = Phase.DORMANT
	_cell = null
	set_physics_process(false)


# 撤走的敌人是整只消失，不是只关组件 / the whole raider leaves, not just this component
func _despawn() -> void:
	stop()
	if is_instance_valid(_body):
		_body.queue_free()


# 幼虫最痛，卵次之，实在没得抢才去啃墙 / brood first, masonry last
func _acquire() -> bool:
	var hive: Hive = get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	if hive == null:
		return false

	var cells: Array = hive.all_cells()
	for wanted in [HexCell.Content.LARVA, HexCell.Content.EGG]:
		var victim: HexCell = _nearest(cells, func(c): return c.content == wanted)
		if victim != null:
			_cell = victim
			return true

	var wall: HexCell = _nearest(cells, func(c): return c.progress > 0 and c.content == HexCell.Content.NONE)
	if wall == null:
		return false
	_cell = wall
	return true


func _nearest(cells: Array, accepts: Callable) -> HexCell:
	var best: HexCell = null
	var best_dist: float = INF
	for node in cells:
		var cell: HexCell = node as HexCell
		if cell == null or not accepts.call(cell):
			continue
		var dist: float = _body.global_position.distance_to(cell.global_position)
		if dist < best_dist:
			best_dist = dist
			best = cell
	return best


func _is_usable(cell: HexCell) -> bool:
	if not is_instance_valid(cell):
		return false
	if cell.content == HexCell.Content.LARVA or cell.content == HexCell.Content.EGG:
		return true
	return cell.progress > 0 and cell.content == HexCell.Content.NONE


func _steer(target: Vector2, delta: float) -> void:
	var heading: Vector2 = _heading_towards(target)
	if heading == Vector2.ZERO:
		return
	var desired: Vector2 = heading * fly_speed
	# 换成和帧率无关的插值系数 / framerate independent, matches the drag spring's blend
	var blend: float = 1.0 - pow(1.0 - clampf(steering, 0.0, 1.0), delta * 60.0)
	_body.linear_velocity = _body.linear_velocity.lerp(desired, blend)


# 抄的是 Wasp.steer_towards 那套：目标先吸到网格上，否则贴墙的巢室会被判成不可达，
# 退回直线 steering 就是原地磨墙
# Same trick as Wasp: snap the goal first, or a wall-hugging cell reads as unreachable
# and the fallback straight line grinds into the divider.
func _heading_towards(target: Vector2) -> Vector2:
	var direct: Vector2 = (target - _body.global_position).normalized()
	if _nav == null:
		return direct

	var goal: Vector2 = _snap_to_navmesh(target)
	if _nav_goal.distance_squared_to(goal) > 256.0:
		_nav_goal = goal
		_nav.target_position = goal

	if _nav.is_navigation_finished():
		return direct

	var to_waypoint: Vector2 = _nav.get_next_path_position() - _body.global_position
	return direct if to_waypoint.length() < 0.01 else to_waypoint.normalized()


func _snap_to_navmesh(point: Vector2) -> Vector2:
	if not is_inside_tree():
		return point
	var map: RID = get_world_2d().navigation_map
	if not map.is_valid():
		return point
	return NavigationServer2D.map_get_closest_point(map, point)
