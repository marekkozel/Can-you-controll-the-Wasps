# 偷产异色卵 / secret laying.
# 排在 Deliver 后面：她先把食物好好送回巢（伪装），然后才摸去空巢室。
# 所以"在空巢室徘徊"这条线索不是演出来的，是她真实意图漏出来的。
# The "loitering over empty cells" tell is not staged - it is her real goal leaking.
class_name SecretLay
extends BTAction

## 多近算到位 / how close before she can lay
@export var lay_distance: float = 18.0
## 产卵前要悬停多久。第一代停得久得离谱，老练之后刚好落在 Fidget 的区间里
## Lingers conspicuously at first, then just long enough to pass for a Fidget inspection.
@export var hover_obvious: float = 5.0
@export var hover_blended: float = 2.5
@export var fly_speed: float = 85.0
## 基础冷却 / base seconds between eggs
@export var base_cooldown: float = 15.0
## 每多一只存活叛军就多等这么久——叛乱越大扩张越慢，自带刹车
## Each living rebel slows the next egg down, so the uprising throttles itself.
@export var cooldown_per_rebel: float = 12.0

const HIVE_GROUP: StringName = &"hive"
const WASP_GROUP: StringName = &"wasps"

var _cell: HexCell = null
var _hover_left: float = -1.0


func _tick(delta: float) -> Status:
	var allegiance: AllegianceComponent = agent.allegiance()
	if allegiance.brood_variant == null or allegiance.lay_cooldown > 0.0:
		return FAILURE
	# 手上还拿着货就先把活干完，反正 Deliver 排在前面 / finish the cover run first
	if agent.carry().is_carrying():
		return FAILURE

	if not _is_usable(_cell):
		_cell = _find_empty_cell()
		_hover_left = -1.0
		if _cell == null:
			return FAILURE

	if agent.global_position.distance_to(_cell.global_position) > lay_distance:
		agent.steer_towards(_cell.global_position, delta, fly_speed)
		return RUNNING

	# 到位了不马上产。这段悬停就是伪装本身，看起来和普通工蜂查巢室一样
	# The linger is the disguise - it reads exactly like a worker checking a cell.
	if _hover_left < 0.0:
		_hover_left = lerpf(hover_obvious, hover_blended, allegiance.cunning)
	_hover_left -= delta
	if _hover_left > 0.0:
		return RUNNING

	var laid: bool = _cell.lay_rebel_egg(allegiance.brood_variant, agent)
	_cell = null
	_hover_left = -1.0
	if not laid:
		return FAILURE

	allegiance.lay_cooldown = base_cooldown + cooldown_per_rebel * float(_rebel_count(allegiance))
	return SUCCESS


func _exit() -> void:
	_cell = null
	_hover_left = -1.0


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
