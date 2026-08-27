# 交货 / deliver: 手上有东西就找个收它的巢室放下。
# 纸板找没建完的格，食物找饿着的幼虫，两者都落到 HexCell.deliver()
# Cardboard goes to unbuilt cells, food to hungry larvae - both land in HexCell.deliver().
class_name Deliver
extends BTAction

## 多近算到位 / how close before it lets go
@export var drop_distance: float = 14.0
## 搬运时的飞行速度 / cruise speed while hauling
@export var fly_speed: float = 100.0

const HIVE_GROUP: StringName = &"hive"

# 锁定目标格。每帧重选"最近的未建成格"会让黄蜂追着自己跑：
# 飞过头一点，更近的就换成下一格，于是一路往巢穴底部钻
# Re-picking the nearest cell every tick made the wasp chase its own overshoot down the hive.
var _cell: HexCell = null


func _tick(delta: float) -> Status:
	var carry: CarryComponent = agent.carry()
	if carry == null or not carry.is_carrying():
		return FAILURE

	if not _is_usable(_cell, carry.payload()):
		_cell = _find_cell(carry.payload())

	var cell: HexCell = _cell
	if cell == null:
		# 没地方送就就地放下，别叼着飞一整局 / nowhere to take it, put it down
		carry.drop()
		return SUCCESS

	# 货物是挂在身下的，所以瞄准点要把 offset 减回去，否则扔进隔壁格
	# Cargo hangs below the wasp, so aim offset-corrected or it lands one cell down.
	var aim: Vector2 = cell.global_position - carry.carry_offset
	agent.steer_towards(aim, delta, fly_speed)
	if agent.global_position.distance_to(aim) > drop_distance:
		return RUNNING

	carry.drop()
	_cell = null
	return SUCCESS


func _exit() -> void:
	_cell = null


# 目标格可能被别的黄蜂填满、幼虫可能被喂饱了 / another wasp may have finished it meanwhile
func _is_usable(cell: HexCell, payload: StringName) -> bool:
	if not is_instance_valid(cell):
		return false
	match payload:
		&"cardboard":
			return not cell.is_built
		&"food":
			return cell.is_hungry_larva()
	return false


func _find_cell(payload: StringName) -> HexCell:
	var hive: Hive = agent.get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	if hive == null:
		return null

	match payload:
		&"cardboard":
			return _nearest(_buildable_cells(hive))
		&"food":
			return _most_urgent(hive.hungry_cells())
	return null


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
