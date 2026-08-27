# 破坏 / sabotage: 叛军把已有的建造进度听回去。
# 母亲一死它们就不是 REBEL 了，这条分支自然失效 / dies with the mother.
class_name Sabotage
extends BTAction

@export var reach: float = 26.0
@export var fly_speed: float = 95.0
## 两次听咬之间的间隔 / seconds between bites
@export var bite_cooldown: float = 2.5
@export_range(1, 5, 1) var bite_damage: int = 1

const HIVE_GROUP: StringName = &"hive"

var _cell: HexCell = null


func _tick(delta: float) -> Status:
	var allegiance: AllegianceComponent = agent.allegiance()
	if allegiance.sabotage_cooldown > 0.0:
		return FAILURE

	if not _is_usable(_cell):
		_cell = _find_target()
		if _cell == null:
			return FAILURE

	agent.steer_towards(_cell.global_position, delta, fly_speed)
	if agent.global_position.distance_to(_cell.global_position) > reach:
		return RUNNING

	var bit: bool = _cell.damage_build(bite_damage)
	_cell = null
	if not bit:
		return FAILURE

	allegiance.sabotage_cooldown = bite_cooldown
	return SUCCESS


func _exit() -> void:
	_cell = null


# 有进度、又没装东西的格 / cells with progress and nothing living in them
func _is_usable(cell: HexCell) -> bool:
	return is_instance_valid(cell) and cell.progress > 0 and cell.content == HexCell.Content.NONE


func _find_target() -> HexCell:
	var hive: Hive = agent.get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	if hive == null:
		return null

	var best: HexCell = null
	var best_dist: float = INF
	for node in hive.all_cells():
		var cell: HexCell = node as HexCell
		if not _is_usable(cell):
			continue
		var dist: float = agent.global_position.distance_to(cell.global_position)
		if dist < best_dist:
			best_dist = dist
			best = cell
	return best
