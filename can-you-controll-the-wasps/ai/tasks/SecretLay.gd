# 偷产异色卵 / secret laying.
# 排在 Deliver 后面：她先把食物好好送回巢（伪装），然后才摸去空巢室。
# 所以"在空巢室徘徊"这条线索不是演出来的，是她真实意图漏出来的。
# The "loitering over empty cells" tell is not staged - it is her real goal leaking.
class_name SecretLay
extends BTAction

## 多近算到位 / how close before she can lay
@export var lay_distance: float = 18.0
@export var fly_speed: float = 85.0
## 基础冷却 / base seconds between eggs
@export var base_cooldown: float = 15.0
## 每多一只存活叛军就多等这么久——叛乱越大扩张越慢，自带刹车
## Each living rebel slows the next egg down, so the uprising throttles itself.
@export var cooldown_per_rebel: float = 12.0

const HIVE_GROUP: StringName = &"hive"
const WASP_GROUP: StringName = &"wasps"

var _cell: HexCell = null


func _tick(delta: float) -> Status:
	var allegiance: AllegianceComponent = agent.allegiance()
	if allegiance.brood_variant == null or allegiance.lay_cooldown > 0.0:
		return FAILURE
	# 手上还拿着货就先把活干完，反正 Deliver 排在前面 / finish the cover run first
	if agent.carry().is_carrying():
		return FAILURE

	if not _is_usable(_cell):
		_cell = _find_empty_cell()
		if _cell == null:
			return FAILURE

	agent.steer_towards(_cell.global_position, delta, fly_speed)
	if agent.global_position.distance_to(_cell.global_position) > lay_distance:
		return RUNNING

	var laid: bool = _cell.lay_rebel_egg(allegiance.brood_variant, agent)
	_cell = null
	if not laid:
		return FAILURE

	allegiance.lay_cooldown = base_cooldown + cooldown_per_rebel * float(_rebel_count(allegiance))
	return SUCCESS


func _exit() -> void:
	_cell = null


func _is_usable(cell: HexCell) -> bool:
	return is_instance_valid(cell) and cell.can_lay_egg()


# 只能产在已建成的空巢室里——玩家巢建得越大，她能下手的地方越多
# Built empty cells only: the bigger you build, the more room she has.
func _find_empty_cell() -> HexCell:
	var hive: Hive = agent.get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	if hive == null:
		return null

	var best: HexCell = null
	var best_dist: float = INF
	for node in hive.all_cells():
		var cell: HexCell = node as HexCell
		if cell == null or not cell.can_lay_egg():
			continue
		var dist: float = agent.global_position.distance_to(cell.global_position)
		if dist < best_dist:
			best_dist = dist
			best = cell
	return best


func _rebel_count(_allegiance: AllegianceComponent) -> int:
	var total: int = 0
	for node in agent.get_tree().get_nodes_in_group(WASP_GROUP):
		var other: Wasp = node as Wasp
		if other != null and other.allegiance().is_rebel() and other.allegiance().mother == agent:
			total += 1
	return total
