@tool
class_name Hive
extends Node2D

# 中央蜂巢 / the hive. 按 layout + radius 生成一片六边形格子。
# 格子不设 owner，不会被存进 Hive.tscn / cells have no owner, scene file stays clean.

signal cell_clicked(cell: HexCell)
signal cell_hover_changed(cell: HexCell, is_hovered: bool)
signal cell_progress_changed(cell: HexCell, progress: int, required: int)
signal cell_built(cell: HexCell)
signal cell_egg_laid(cell: HexCell)
signal cell_larva_hatched(cell: HexCell)
signal cell_larva_hungry(cell: HexCell)
signal cell_larva_starved(cell: HexCell)
signal cell_sealed(cell: HexCell)
signal cell_wasp_emerged(cell: HexCell, wasp: Wasp)
signal cell_cleaned(cell: HexCell)
signal cell_occupant_destroyed(cell: HexCell)
## 伪王后下了一颗异色卵。**只给氛围层用**，别拿它标记格子——标了就等于把答案画在巢上
## For atmosphere only: marking the cell would paint the answer onto the comb.
signal cell_rebel_egg_laid(cell: HexCell)

# demand() 是"还有多少活"，不是"完成了百分之几"。
#
# 曾经这里返回未完成的**比例**，于是完成度越高需求越低，可剩下的活一点没少：
# 一只被派在巢的蜂基线最高 0.37（posting_bias 0.28 + SWITCH_MARGIN 0.09），
# 阈值中位 0.385，要它出门得 demand > 0.755——巢建到四成就再没人肯搬纸板，
# 手动拖过去的蜂待一会儿也飘回来。剩下那截永远建不完。
#
# 下限只要压过"最勤快的那批"就够，不用压过所有蜂：cardboard_threshold 下限 0.22，
# 0.59 是"总有蜂肯干"的分界线，取 0.65 留一点余量。压过全部反而抹掉了分工。
# A ratio starves its own endgame; the floor only has to clear the keenest wasps.
const BUILD_FLOOR: float = 0.65
const FEED_FLOOR: float = 0.60
const FEED_CAP: float = 0.85

const HEX_CELL_SCENE: PackedScene = preload("res://Scenes/Entities/HexCell.tscn")

## 改这个资源，整片网格实时重建 / editing it rebuilds the whole grid
@export var layout: HexLayout = null:
	set(value):
		_disconnect_layout()
		layout = value
		_connect_layout()
		_request_rebuild()

## 半径。格子数 = 3N(N+1)+1 / radius, cell count is 3N(N+1)+1
@export_range(0, 8, 1) var radius: int = 3:
	set(value):
		radius = value
		_request_rebuild()

var _cells: Dictionary[Vector2i, HexCell] = {}

@onready var _container: Node2D = $HexGrid/Cells


func _ready() -> void:
	_connect_layout()
	rebuild()


func rebuild() -> void:
	if _container == null:
		return

	_clear()
	if layout == null:
		layout = HexLayout.new()

	for coord in HexLayout.hex_area(radius):
		var cell: HexCell = HEX_CELL_SCENE.instantiate()
		_container.add_child(cell)  # 先入树
		cell.setup(layout, coord)
		
		cell.clicked.connect(_on_cell_clicked)
		cell.hover_changed.connect(_on_cell_hover_changed)
		cell.progress_changed.connect(_on_cell_progress_changed)
		cell.built.connect(_on_cell_built)
		cell.egg_laid.connect(_on_cell_egg_laid)
		cell.larva_hatched.connect(func(c): cell_larva_hatched.emit(c))
		cell.larva_hungry.connect(func(c): cell_larva_hungry.emit(c))
		cell.larva_starved.connect(func(c): cell_larva_starved.emit(c))
		cell.sealed.connect(func(c): cell_sealed.emit(c))
		cell.wasp_emerged.connect(func(c, w): cell_wasp_emerged.emit(c, w))
		cell.cleaned.connect(func(c): cell_cleaned.emit(c))
		cell.occupant_destroyed.connect(func(c): cell_occupant_destroyed.emit(c))
		cell.rebel_egg_laid.connect(func(c, _v): cell_rebel_egg_laid.emit(c))
		_cells[coord] = cell

	
	var sorted_cells: Array = _cells.values()
	
	
	sorted_cells.sort_custom(func(a: HexCell, b: HexCell) -> bool:
		
		if abs(a.position.y - b.position.y) < 1.0:
			return a.position.x < b.position.x 
		return a.position.y < b.position.y
	)
	
	# Apply a safe, ordered Z-index from 0 to N
	for i in range(sorted_cells.size()):
		sorted_cells[i].z_index = i

func get_cell(coord: Vector2i) -> HexCell:
	return _cells.get(coord)


# 全局坐标 -> 格子，纸板落点判定用 / global point to cell, used for drop targeting
func cell_at_global(global_point: Vector2) -> HexCell:
	if layout == null:
		return null
	var local_point: Vector2 = _container.to_local(global_point)
	return get_cell(layout.local_to_axial(local_point))


func all_cells() -> Array:
	return _cells.values()


func all_coords() -> Array:
	return _cells.keys()


func count_content(kind: HexCell.Content) -> int:
	var total: int = 0
	for cell in _cells.values():
		if cell.content == kind:
			total += 1
	return total


# 还收不收这种货。黄蜂拿之前先问一声，否则巢满了还会不停搬
# Wasps ask before hauling - otherwise a full hive still gets a permanent supply run.
func accepts(payload: StringName) -> bool:
	match payload:
		&"cardboard":
			return built_count() < _cells.size()
		&"food", &"royal_jelly":
			return not hungry_cells().is_empty()
	return false


# 巢现在有多需要这类货，0..1。响应阈值模型的**刺激**那一半，蜂拿它跟自己的阈值比
# The stimulus half of the response-threshold model; each wasp weighs it against its own bar.
#
# 两条尺度是刻意不同的：
#   纸板看的是"还差多少格没建"——一个缓慢的、结构性的需求
#   食物看的是"最急的那只幼虫有多急"——一个尖锐的、会突然爆起来的需求
# 用同一条尺度的话，饿死一只幼虫的分量会被总格数稀释到看不见，没有蜂会回头救它
# Different scales on purpose: averaging the food demand over the whole hive would bury
# a starving larva under the cell count, and nobody would ever turn back for it.
func demand(payload: StringName) -> float:
	var total: int = _cells.size()
	if total == 0:
		return 0.0

	match payload:
		&"cardboard":
			var unbuilt: int = total - built_count()
			if unbuilt == 0:
				return 0.0  # 全建完才归零，蜂回巢待命——牌桌就是这么来的 / the floor is the point
			return clampf(BUILD_FLOOR + (1.0 - BUILD_FLOOR) * float(unbuilt) / float(total), 0.0, 1.0)
		&"food", &"royal_jelly":
			var urgent: float = 0.0
			for cell in hungry_cells():
				urgent = maxf(urgent, 1.0 - cell.larva_hunger_ratio())
			# 只看"已经饿着的"等于让蜂等到濒死才动身，它还要飞过去、采、再搬回来。
			# 幼虫越多备得越多；送不出去的那只就拿着等，下一只饿了立刻能喂
			# Waiting for hunger means arriving too late; carried food is stock, not waste.
			var brood: int = count_content(HexCell.Content.LARVA)
			var stock: float = 0.0 if brood == 0 else minf(FEED_FLOOR + 0.1 * float(brood - 1), FEED_CAP)
			return clampf(maxf(stock, urgent), 0.0, 1.0)
	return 0.0


# 有幼虫正饿着的格子，喂食提示用 / cells whose larva is hungry right now
func hungry_cells() -> Array:
	return _cells.values().filter(func(c): return c.content == HexCell.Content.LARVA and c.is_hungry_larva())


func egg_count() -> int:
	var total: int = 0
	for cell in _cells.values():
		if cell.content == HexCell.Content.EGG:
			total += 1
	return total


func built_count() -> int:
	var total: int = 0
	for cell in _cells.values():
		if cell.is_built:
			total += 1
	return total


func _clear() -> void:
	_cells.clear()
	for child in _container.get_children():
		_container.remove_child(child)
		child.queue_free()


func _request_rebuild() -> void:
	if not is_node_ready():  # setter 可能在 _ready 之前就跑了 / setters can fire before _ready
		return
	rebuild()


func _connect_layout() -> void:
	if layout != null and not layout.changed.is_connected(_request_rebuild):
		layout.changed.connect(_request_rebuild)


func _disconnect_layout() -> void:
	if layout != null and layout.changed.is_connected(_request_rebuild):
		layout.changed.disconnect(_request_rebuild)


func _on_cell_clicked(cell: HexCell) -> void:
	cell_clicked.emit(cell)


func _on_cell_hover_changed(cell: HexCell, is_hovered: bool) -> void:
	cell_hover_changed.emit(cell, is_hovered)


func _on_cell_progress_changed(cell: HexCell, progress: int, required: int) -> void:
	cell_progress_changed.emit(cell, progress, required)


func _on_cell_built(cell: HexCell) -> void:
	cell_built.emit(cell)


func _on_cell_egg_laid(cell: HexCell) -> void:
	cell_egg_laid.emit(cell)
