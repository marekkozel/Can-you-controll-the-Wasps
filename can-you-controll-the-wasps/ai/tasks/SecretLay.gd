# 偷产异色卵 / secret laying.
# 排在 Deliver 后面：她先把食物好好送回巢（伪装），然后才摸去空巢室。
# 所以"在空巢室徘徊"这条线索不是演出来的，是她真实意图漏出来的。
# The "loitering over empty cells" tell is not staged - it is her real goal leaking.
class_name SecretLay
extends BTAction

## 多近算到位 / how close before she can lay
@export var lay_distance: float = 19
## 产卵前要悬停多久。第一代停得久得离谱，老练之后刚好落在 Fidget 的区间里
## Lingers conspicuously at first, then just long enough to pass for a Fidget inspection.
@export var hover_obvious: float = 5.0
@export var hover_blended: float = 2.5

@export_group("Caution")
## 玩家的注意力离目标格这么近就不动手 / she will not act with the cursor this close
@export_range(0.0, 800.0, 10.0) var caution_radius: float = 160.0
## 练到这个程度才会"等你移开" / cunning needed before she learns to wait
@export_range(0.0, 1.0, 0.05) var wait_cunning: float = 0.3
## 练到这个程度才会主动调虎离山 / cunning needed before she diverts you on purpose
@export_range(0.0, 1.0, 0.05) var decoy_cunning: float = 0.7
## 两次调虎离山的间隔，以及一次指令的持续时长 / cooldown, and how long an order stands
@export var decoy_cooldown: float = 20.0
@export var decoy_duration: float = 10.0
@export var fly_speed: float = 85.0
## 基础冷却 / base seconds between eggs
@export var base_cooldown: float = 10.0
## 每多一只存活叛军就多等这么久——叛乱越大扩张越慢，自带刹车。
## 12 秒踩得太死：第三颗卵要等一分钟，玩家根本感觉不到有人在下蛋
## Each living rebel slows the next egg; at 12 the third egg took a full minute.
@export var cooldown_per_rebel: float = 6.0

const HIVE_GROUP: StringName = &"hive"
const WASP_GROUP: StringName = &"wasps"

var _cell: HexCell = null
var _hover_left: float = -1.0
var _decoy_cooldown: float = 0.0


func _tick(delta: float) -> Status:
	var allegiance: AllegianceComponent = agent.allegiance()
	if allegiance.brood_variant == null or allegiance.lay_cooldown > 0.0:
		return FAILURE
	# 手上还拿着货就先把活干完，反正 Deliver 排在前面 / finish the cover run first
	if agent.carry().is_carrying():
		return FAILURE

	_decoy_cooldown = maxf(_decoy_cooldown - delta, 0.0)

	var cautious: bool = allegiance.cunning >= wait_cunning
	if not _is_usable(_cell):
		# 学乖了的先挑你没在看的格子，而不是死盯最近的那一个
		# She works the side of the hive you are not watching, rather than the nearest cell.
		_cell = _find_empty_cell(cautious)
		_hover_left = -1.0
		if _cell == null:
			return FAILURE

	# 实在没有你没盯着的格子了。笨的照产，学乖了的会等，老练的把你引走。
	# You are looking right at it: the naive one lays anyway, the practised one waits,
	# and the veteran arranges for you to look somewhere else.
	if cautious and _is_watched(_cell):
		if allegiance.cunning >= decoy_cunning and _decoy_cooldown <= 0.0:
			if _order_decoy():
				_decoy_cooldown = decoy_cooldown
		_hover_left = -1.0
		return FAILURE  # 装作去干别的 / go do something innocent instead

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
func _find_empty_cell(avoid_watched: bool) -> HexCell:
	var hive: Hive = agent.get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	if hive == null:
		return null

	var best: HexCell = null
	var best_dist: float = INF
	var fallback: HexCell = null
	var fallback_dist: float = INF

	for node in hive.all_cells():
		var cell: HexCell = node as HexCell
		if cell == null or not cell.can_lay_egg():
			continue
		var dist: float = agent.global_position.distance_to(cell.global_position)
		if dist < fallback_dist:
			fallback_dist = dist
			fallback = cell
		if avoid_watched and _is_watched(cell):
			continue
		if dist < best_dist:
			best_dist = dist
			best = cell

	# 全被盯着就还回最近的那个，上面的判断会接手决定是等还是引开你
	# If everything is watched, hand the nearest one back and let the caller decide.
	return best if best != null else fallback


func _is_watched(cell: HexCell) -> bool:
	var director: BetrayalDirector = BetrayalDirector.find(agent.get_tree())
	if director == null:
		return false
	return director.attention_point().distance_to(cell.global_position) <= caution_radius


# 挑一只自己的叛军，派它去离目标格最远的地方拆东西。
# 重点不是"离鼠标远"，是"离她要下手的地方远"——目的是把你拉走。
# Farthest from her target, not from the cursor: the point is to pull you away from her.
func _order_decoy() -> bool:
	var hive: Hive = agent.get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	if hive == null:
		return false

	var bait: HexCell = null
	var best_dist: float = -1.0
	for node in hive.all_cells():
		var other: HexCell = node as HexCell
		if other == null or other == _cell:
			continue
		if other.content != HexCell.Content.LARVA and other.content != HexCell.Content.EGG and other.progress <= 0:
			continue
		if other.rebel_brood:
			continue
		var dist: float = _cell.global_position.distance_to(other.global_position)
		if dist > best_dist:
			best_dist = dist
			bait = other
	if bait == null:
		return false

	for node in agent.get_tree().get_nodes_in_group(WASP_GROUP):
		var rebel: Wasp = node as Wasp
		if rebel == null or not rebel.allegiance().is_rebel() or rebel.allegiance().mother != agent:
			continue
		rebel.allegiance().decoy_cell = bait
		rebel.allegiance().decoy_until = decoy_duration
		rebel.allegiance().sabotage_cooldown = 0.0  # 马上去 / go now
		return true
	return false


func _rebel_count(_allegiance: AllegianceComponent) -> int:
	var total: int = 0
	for node in agent.get_tree().get_nodes_in_group(WASP_GROUP):
		var other: Wasp = node as Wasp
		if other != null and other.allegiance().is_rebel() and other.allegiance().mother == agent:
			total += 1
	return total
