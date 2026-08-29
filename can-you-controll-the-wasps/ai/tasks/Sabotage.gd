# 破坏 / sabotage: 幼虫 > 卵 > 建造进度，按这个优先级找事干。
#
# 树里的位置：`Seq - Rebel` = IsRebel -> Selector(Sabotage, Harass, Idle)。
# 以前那格只有 IsRebel -> Sabotage，冷却一到整条序列就失败，叛军会掉到下面的
# Gather/Fidget 去**帮着干活**——它们是纯敌人，不该有那条出口。最后一格必须是
# 不会失败的（Idle），否则冷却期间照样漏下去。
# The rebel branch must never fall through to the worker branches, so the last slot
# in its selector is one that cannot fail.
#
# 母亲死了叛军**不再**自动屈服：异色就是敌人，清场是玩家的事
# A dead mother no longer pacifies them - culling is the player's job.
class_name Sabotage
extends BTAction

@export var reach: float = 26.0
@export var fly_speed: float = 95.0

@export_group("Chewing")
## 两次拆巢之间的间隔。**一口拆掉一整格**，所以这个数要顶下原来三口的总时长——
## 拆的速率没变，变的是它看得见了：一格一格地没，而不是整片巢室慢慢变暗
## One bite takes a whole cell, so this covers what used to be three of them: the rate
## is unchanged, the readability is not.
@export var bite_cooldown: float = 7.5

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

	# 妈叫去哪就去哪，哪怕那儿更远 / an order from the queen overrides the nearest target
	var ordered: HexCell = allegiance.decoy_cell as HexCell
	if allegiance.decoy_until > 0.0 and _is_usable(ordered, true):
		_cell = ordered
		_killing = true
	elif allegiance.decoy_until > 0.0 and _is_usable(ordered, false):
		_cell = ordered
		_killing = false
	elif not _is_usable(_cell, _killing):
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

	if not cell.demolish():
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
