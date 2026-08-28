# 交货 / deliver: 手上有东西就找个收它的地方放下。
# 纸板找没建完的格，食物和蜂王浆找饿着的幼虫，战利品找加工厂
# Cardboard to unbuilt cells, food and jelly to hungry larvae, loot to a refinery post.
#
# 放下这一步走的还是 CarryComponent.drop() → DeliverableComponent，两种收货方
# 在那一层已经分好了，这里只负责**飞对地方**
# The drop itself still goes through DeliverableComponent, which already knows both
# receivers - this task only has to fly to the right one.
class_name Deliver
extends BTAction

## 多近算到位 / how close before it lets go
@export var drop_distance: float = 14.0
## 搬运时的飞行速度 / cruise speed while hauling
@export var fly_speed: float = 100.0

const HIVE_GROUP: StringName = &"hive"
const ITEM_SOURCE_GROUP: StringName = &"item_source"

# 锁定目标。每帧重选"最近的未建成格"会让黄蜂追着自己跑：
# 飞过头一点，更近的就换成下一格，于是一路往巢穴底部钻
# Re-picking the nearest cell every tick made the wasp chase its own overshoot down the hive.
# 可能是 HexCell，也可能是加工厂 / either a HexCell or a refinery ItemSource
var _target: Node2D = null


func _tick(delta: float) -> Status:
	# 叛军不帮工。已屈服的照干 / rebels do not work, subdued ones do
	if not agent.allegiance().works():
		return FAILURE

	var carry: CarryComponent = agent.carry()
	if carry == null or not carry.is_carrying():
		return FAILURE

	if not _is_usable(_target, carry.payload()):
		_target = _find_target(carry.payload())

	var target: Node2D = _target
	if target == null:
		# 备粮可能比幼虫饿得早。这时**拿着等**，不放下——放下就退回"等饿了才动身"，
		# 而蜂还要飞过去、采、再搬回来，那段时间幼虫等不起。
		# FAILURE 让树落到 Fidget/Idle，蜂叼着饭飘回巢里待命，下一只开口立刻能喂。
		# **不能在这里返回 RUNNING**：BTSelector 带记忆，会把蜂钉在这一条上，
		# 入侵来了它也不回防
		# Holding is the point of the lead time. FAILURE (never RUNNING - the selector has
		# memory and would pin the wasp here through a raid) drops it to Idle, cargo in hand.
		if _worth_holding(carry.payload()):
			return FAILURE
		# 没地方送就就地放下，别叼着飞一整局 / nowhere to take it, put it down
		carry.drop()
		return SUCCESS

	# 货物是挂在身下的，所以瞄准点要把 offset 减回去，否则扔进隔壁格
	# Cargo hangs below the wasp, so aim offset-corrected or it lands one cell down.
	var aim: Vector2 = target.global_position - carry.carry_offset
	agent.steer_towards(aim, delta, fly_speed)
	if agent.global_position.distance_to(aim) > drop_distance:
		return RUNNING

	carry.drop(_units_for(carry.payload()))
	_target = null
	return SUCCESS


# 载重对两种货都生效，筑巢只加纸板 / carrying counts for both, building only for cardboard
func _units_for(payload: StringName) -> int:
	# 问蜂不问血统资源：基因加成加在蜂身上，直接读 WaspVariant 会漏掉它
	# Ask the wasp, not the resource - the gene bonus lives on the wasp.
	var units: int = agent.carry_units()
	if payload == &"cardboard":
		units *= agent.build_units()
	return maxi(units, 1)


func _exit() -> void:
	_target = null


# 现在没地方送，但马上就有 / no sink right now, but one is about to open
func _worth_holding(payload: StringName) -> bool:
	if payload != &"food" and payload != &"royal_jelly":
		return false
	var hive: Hive = agent.get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	return hive != null and not hive.feedable_cells().is_empty()


# 目标格可能被别的黄蜂填满、幼虫可能被喂饱了 / another wasp may have finished it meanwhile
func _is_usable(target: Node2D, payload: StringName) -> bool:
	if not is_instance_valid(target):
		return false

	var post: ItemSource = target as ItemSource
	if post != null:
		return post.accepts_intake(payload)

	var cell: HexCell = target as HexCell
	if cell == null:
		return false
	match payload:
		&"cardboard":
			return not cell.is_built
		&"food", &"royal_jelly":
			return cell.is_hungry_larva()
	return false


# 先问加工厂：战利品的去处只有它，问巢是白问 / a refinery is loot's only sink
func _find_target(payload: StringName) -> Node2D:
	var refinery: ItemSource = _nearest_refinery(payload)
	if refinery != null:
		return refinery

	var hive: Hive = agent.get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	if hive == null:
		return null

	match payload:
		&"cardboard":
			return _nearest(_buildable_cells(hive))
		&"food", &"royal_jelly":
			return _most_urgent(hive.hungry_cells())
	return null


func _nearest_refinery(payload: StringName) -> ItemSource:
	var best: ItemSource = null
	var best_dist: float = INF
	for node in agent.get_tree().get_nodes_in_group(ITEM_SOURCE_GROUP):
		var post: ItemSource = node as ItemSource
		if post == null or not post.accepts_intake(payload):
			continue
		var dist: float = agent.global_position.distance_to(post.global_position)
		if dist < best_dist:
			best_dist = dist
			best = post
	return best


# 只往已建好的格旁边扩，巢就会从中心一圈圈长出去。
# 改成"挑最近的未建成格"的话，黄蜂从哪边飞来巢就往哪边长，一团乱
# Only grow next to finished cells - picking the globally nearest one makes the hive
# sprawl toward whichever side the wasps happen to come from.
func _buildable_cells(hive: Hive) -> Array:
	var unbuilt: Array = hive.all_cells().filter(func(c): return not c.is_built)
	if hive.built_count() == 0:
		# 空巢：从最靠中心的那一格开头 / empty hive, seed from the centre
		var seed: Array = unbuilt.filter(func(c): return c.coord == Vector2i.ZERO)
		return seed if not seed.is_empty() else unbuilt

	var frontier: Array = unbuilt.filter(func(c): return _touches_built(hive, c))
	return frontier if not frontier.is_empty() else unbuilt


func _touches_built(hive: Hive, cell: HexCell) -> bool:
	for other in hive.all_cells():
		if other.is_built and HexLayout.axial_distance(cell.coord, other.coord) == 1:
			return true
	return false


func _nearest(cells: Array) -> HexCell:
	var best: HexCell = null
	var best_dist: float = INF
	for node in cells:
		var cell: HexCell = node as HexCell
		if cell == null:
			continue
		var dist: float = agent.global_position.distance_to(cell.global_position)
		if dist < best_dist:
			best_dist = dist
			best = cell
	return best


# 先喂快饿死的。挑最近的会让远处那只一直没人管 / feed the one closest to starving
func _most_urgent(cells: Array) -> HexCell:
	var best: HexCell = null
	var best_ratio: float = INF
	for node in cells:
		var cell: HexCell = node as HexCell
		if cell == null:
			continue
		var ratio: float = cell.larva_hunger_ratio()
		if ratio < best_ratio:
			best_ratio = ratio
			best = cell
	return best
