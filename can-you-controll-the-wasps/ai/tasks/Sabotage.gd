# 破坏 / sabotage: 幼虫 > 卵 > 建造进度，按这个优先级找事干。
# 母亲一死它们就不是 REBEL 了，这条分支自然失效 / dies with the mother.
class_name Sabotage
extends BTAction

@export var reach: float = 26.0
@export var fly_speed: float = 95.0

@export_group("Chewing")
## 两次听咬建造进度之间的间隔 / seconds between bites on build progress
@export var bite_cooldown: float = 2.5
@export_range(1, 5, 1) var bite_damage: int = 1

@export_group("Killing")
## 弄死一只幼虫后要缓很久。这是重击，不该是持续碾压，
## 不然玩家还没找到伪王后巢就空了
## The heavy hit needs a long cooldown, or the hive empties before the player can react.
@export var kill_cooldown: float = 12.0

const HIVE_GROUP: StringName = &"hive"

var _cell: HexCell = null
## true = 去弄死里面的东西，false = 去听建造进度 / what it flew over there to do
var _killing: bool = false


func _tick(delta: float) -> Status:
	var allegiance: AllegianceComponent = agent.allegiance()
	if allegiance.sabotage_cooldown > 0.0:
		return FAILURE

	if not _is_usable(_cell, _killing):
		if not _acquire():
			return FAILURE

	agent.steer_towards(_cell.global_position, delta, fly_speed)
	if agent.global_position.distance_to(_cell.global_position) > reach:
		return RUNNING

	var cell: HexCell = _cell
	var killing: bool = _killing
	_cell = null

	if killing:
		if not cell.destroy_occupant():
			return FAILURE
		allegiance.sabotage_cooldown = kill_cooldown
		return SUCCESS

	if not cell.damage_build(bite_damage):
		return FAILURE
	allegiance.sabotage_cooldown = bite_cooldown
	return SUCCESS


func _exit() -> void:
	_cell = null


func _is_usable(cell: HexCell, killing: bool) -> bool:
	if not is_instance_valid(cell):
		return false
	if killing:
		# 自家人的卵不能碰 / never touch its own brood
		if cell.rebel_brood:
			return false
		return cell.content == HexCell.Content.LARVA or cell.content == HexCell.Content.EGG
	return cell.progress > 0 and cell.content == HexCell.Content.NONE


# 幼虫最痛，卵次之，实在没得杀才去听墙 / brood first, masonry last
func _acquire() -> bool:
	var hive: Hive = agent.get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	if hive == null:
		return false

	var cells: Array = hive.all_cells()
	for wanted in [HexCell.Content.LARVA, HexCell.Content.EGG]:
		var victim: HexCell = _nearest(cells, func(c): return c.content == wanted and not c.rebel_brood)
		if victim != null:
			_cell = victim
			_killing = true
			return true

	var wall: HexCell = _nearest(cells, func(c): return c.progress > 0 and c.content == HexCell.Content.NONE)
	if wall == null:
		return false
	_cell = wall
	_killing = false
	return true


func _nearest(cells: Array, accepts: Callable) -> HexCell:
	var best: HexCell = null
	var best_dist: float = INF
	for node in cells:
		var cell: HexCell = node as HexCell
		if cell == null or not accepts.call(cell):
			continue
		var dist: float = agent.global_position.distance_to(cell.global_position)
		if dist < best_dist:
			best_dist = dist
			best = cell
	return best
