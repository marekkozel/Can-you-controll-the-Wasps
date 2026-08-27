# 闲事 / fidget: 没活干时飞去某个巢室上方看一会儿，或者就地发呆。
#
# 这条分支存在的唯一理由是给伪王后当噪音。SecretLay 的形状和 Inspect 一模一样——
# 飞过去、停一会儿、走人——区别只有停留稍长，以及走了之后那格多了一颗卵。
# 没有这层噪音，"有只蜂在空巢室上方停着"就是铁证，玩家不需要推理。
# This branch exists to give the impostor cover: SecretLay has the exact same shape.
#
# 它排在 Gather 之后，所以"只在没活干的时候做闲事"是位置带来的，不用额外判断。
# Sitting below Gather in the tree is what makes it idle-only - no extra condition needed.
class_name Fidget
extends BTAction

## 多久考虑一次要不要找点事做 / seconds between urges
@export var idle_interval: Vector2 = Vector2(2.0, 6.0)
## 决定做事时飞去看巢室的概率，其余就地发呆 / go look at a cell, otherwise just hang there
@export_range(0.0, 1.0, 0.05) var inspect_chance: float = 0.55
## 停留多久 / how long it lingers
@export var hover_time: Vector2 = Vector2(1.5, 3.0)
@export var fly_speed: float = 70.0
@export var reach: float = 22.0

const HIVE_GROUP: StringName = &"hive"

enum Mode { NONE, INSPECT, REST }

var _mode: Mode = Mode.NONE
var _cell: HexCell = null
var _timer: float = 0.0
var _cooldown: float = 0.0


func _tick(delta: float) -> Status:
	if _mode == Mode.NONE:
		_cooldown -= delta
		if _cooldown > 0.0:
			return FAILURE
		_begin()
		if _mode == Mode.NONE:
			return FAILURE

	if _mode == Mode.REST:
		_timer -= delta
		if _timer > 0.0:
			return RUNNING
		return _finish()

	# INSPECT：先飞过去，到了再悬停 / fly first, linger on arrival
	if not is_instance_valid(_cell):
		return _finish()

	if agent.global_position.distance_to(_cell.global_position) > reach:
		agent.steer_towards(_cell.global_position, delta, fly_speed)
		return RUNNING

	_timer -= delta
	if _timer > 0.0:
		return RUNNING
	return _finish()


func _exit() -> void:
	_mode = Mode.NONE
	_cell = null


func _begin() -> void:
	_timer = randf_range(hover_time.x, hover_time.y)
	if randf() > inspect_chance:
		_mode = Mode.REST
		return

	# 空的已建成格也要看，不然伪王后专挑空格这件事本身就是线索
	# Empty built cells are included on purpose, or her preference for them becomes the tell.
	_cell = _random_cell()
	_mode = Mode.INSPECT if _cell != null else Mode.REST


func _finish() -> Status:
	_mode = Mode.NONE
	_cell = null
	_cooldown = randf_range(idle_interval.x, idle_interval.y)
	return SUCCESS


func _random_cell() -> HexCell:
	var hive: Hive = agent.get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	if hive == null:
		return null
	var cells: Array = hive.all_cells().filter(func(c): return c.is_built)
	if cells.is_empty():
		return null
	return cells[randi() % cells.size()] as HexCell
