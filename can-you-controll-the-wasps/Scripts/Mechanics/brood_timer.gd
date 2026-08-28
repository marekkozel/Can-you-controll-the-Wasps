@tool
class_name BroodTimer
extends Node2D

# 巢室顶上的倒计时 / the brood countdown floating above a cell.
# 孵化、羽化、饥饿共用这一个件，形状在 Inspector 里切 / one node for all three, shape is an export.
# 画在六边形轮廓外，会压到上一排格子身上，所以 z_index 必须抬起来、底板不能关
# It lands on the row above, so the z_index has to be raised and the plate is not optional.

enum Style { RING, BAR }

## 圆环还是长条 / donut or bar
@export var style: Style = Style.BAR:
	set(value):
		style = value
		queue_redraw()

@export_group("Placement")
## 从格子顶点再往上多少 / how far above the cell's apex
@export_range(0.0, 40.0, 0.5) var offset_y: float = 9.0:
	set(value):
		offset_y = value
		queue_redraw()

@export_group("Ring")
@export_range(2.0, 20.0, 0.5) var ring_radius: float = 8.5:
	set(value):
		ring_radius = value
		queue_redraw()
@export_range(1.0, 6.0, 0.5) var ring_width: float = 2.5:
	set(value):
		ring_width = value
		queue_redraw()

@export_group("Bar")
@export_range(8.0, 64.0, 1.0) var bar_width: float = 34.0:
	set(value):
		bar_width = value
		queue_redraw()
@export_range(2.0, 12.0, 0.5) var bar_height: float = 5.0:
	set(value):
		bar_height = value
		queue_redraw()

@export_group("Backing")
## 底板。读数压在邻格贴图上，关掉就糊了 / without it the readout smears into the neighbour's sprite
@export var plate: bool = true:
	set(value):
		plate = value
		queue_redraw()
@export var plate_color: Color = Color(0.04, 0.12, 0.13, 0.78)
@export var track_color: Color = Color(0.04, 0.12, 0.13, 0.85)

var _t: float = 0.0
var _color: Color = Color.WHITE
var _drains: bool = false
var _shown: bool = false


func _ready() -> void:
	# 编辑器里摆位置要看得见，运行时等第一个信号 / visible in-editor for placement, silent at runtime
	if Engine.is_editor_hint():
		show_progress(0.62, Color(0.56, 0.83, 0.89))
		return
	visible = false


# t 是 0~1 的填充量；drains = 从满往空退，饥饿那类走这条 / drains = counts down instead of up
func show_progress(t: float, color: Color, drains: bool = false) -> void:
	var next: float = clampf(t, 0.0, 1.0)
	var same: bool = _shown and _drains == drains and _color == color and is_equal_approx(_t, next)
	_t = next
	_color = color
	_drains = drains
	_shown = true
	visible = true
	if not same:
		queue_redraw()


func clear() -> void:
	_shown = false
	visible = false


func _draw() -> void:
	if not _shown:
		return
	var origin: Vector2 = Vector2(0.0, -offset_y)
	if style == Style.RING:
		_draw_ring(origin)
	else:
		_draw_bar(origin)


func _draw_ring(origin: Vector2) -> void:
	if plate:
		draw_circle(origin, ring_radius + ring_width * 0.5 + 1.5, plate_color)
	draw_arc(origin, ring_radius, 0.0, TAU, 28, track_color, ring_width, true)
	if _t <= 0.002:
		return
	# 从 12 点方向顺时针 / clockwise from 12 o'clock
	draw_arc(origin, ring_radius, -PI * 0.5, -PI * 0.5 + TAU * _t, 28, _color, ring_width, true)


func _draw_bar(origin: Vector2) -> void:
	var size: Vector2 = Vector2(bar_width, bar_height)
	var half: Vector2 = size * 0.5
	if plate:
		draw_rect(Rect2(origin - half - Vector2.ONE * 1.5, size + Vector2.ONE * 3.0), plate_color)
	draw_rect(Rect2(origin - half, size), track_color)

	var filled: float = bar_width * _t
	if filled <= 0.5:
		return
	# 成熟从左往右长，倒计时从右往左退。方向本身就是"这是好事还是坏事"
	# Maturing grows left to right, countdowns drain right to left - the direction is the tell.
	var x: float = origin.x - half.x + (bar_width - filled if _drains else 0.0)
	draw_rect(Rect2(Vector2(x, origin.y - half.y), Vector2(filled, bar_height)), _color)
