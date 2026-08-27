class_name BetrayalDirector
extends Node2D

# 叛乱调度 / betrayal director. 挂在 world.tscn 的 Queen_controller 下。
# 负责的只有一件事：什么时候从现有工蜂里叫醒一只伪王后。
# 叛军屈服不归它管——AllegianceComponent 发现母亲没了会自己屈服。
# It only decides when a false queen wakes up; rebels give in on their own.

signal false_queen_awakened(wasp: Wasp)
signal false_queen_gone(wasp: Wasp)

## 羽化多少只之后叫醒第一只 / emergences before the first impostor wakes
@export_range(1, 40, 1) var awaken_after: int = 4
## 上一只被处决后，再羽化几只才出下一只 / emergences before each successor
@export_range(1, 40, 1) var respawn_after: int = 6
## 每代叛军的颜色，依次取用 / brood colours, used in order
@export var brood_variants: Array[WaspVariant] = []

const HIVE_GROUP: StringName = &"hive"
const WASP_GROUP: StringName = &"wasps"

var _queen: Wasp = null
var _emerged_since: int = 0
var _generation: int = 0


func _ready() -> void:
	var hive: Hive = get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	if hive == null:
		push_warning("BetrayalDirector found no hive, betrayal is disabled")
		return
	hive.cell_wasp_emerged.connect(_on_wasp_emerged)


func has_false_queen() -> bool:
	return is_instance_valid(_queen)


# 调试用，也给以后的背叛数值系统留个入口 / debug hook, and the betrayal system will use it
func awaken_now() -> Wasp:
	if has_false_queen():
		return _queen

	var candidates: Array = []
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Wasp = node as Wasp
		if wasp != null and wasp.allegiance().is_loyal():
			candidates.append(wasp)
	if candidates.is_empty():
		return null

	_queen = candidates[randi() % candidates.size()]
	_queen.allegiance().brood_variant = _next_variant()
	_queen.allegiance().make_false_queen()
	# 她不改颜色。改了就不叫伪装了 / no recolour: that is the whole point
	_queen.tree_exited.connect(_on_queen_gone.bind(_queen), CONNECT_ONE_SHOT)
	_emerged_since = 0
	_generation += 1
	false_queen_awakened.emit(_queen)
	return _queen


func _on_wasp_emerged(_cell: HexCell, _wasp: Wasp) -> void:
	if has_false_queen():
		return
	_emerged_since += 1
	var needed: int = awaken_after if _generation == 0 else respawn_after
	if _emerged_since >= needed:
		awaken_now()


func _on_queen_gone(wasp: Wasp) -> void:
	_queen = null
	_emerged_since = 0
	false_queen_gone.emit(wasp)


func _next_variant() -> WaspVariant:
	if brood_variants.is_empty():
		return null
	return brood_variants[(_generation) % brood_variants.size()]
