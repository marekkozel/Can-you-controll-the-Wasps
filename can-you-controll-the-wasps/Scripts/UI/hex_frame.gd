@tool
class_name HexFrame
extends Control

# 画一个六边形边框 / draws a hexagon outline.
# 当 Button 的子节点用（anchors 拉满 + mouse_filter = ignore），
# 这样按钮还是普通 Button，不用为了改外观去继承它。
# 顶点比例照参考稿的 clip-path。命中区仍是矩形，四角略微超出。

@export var fill_color: Color = Color(0.145, 0.145, 0.145):
	set(value):
		fill_color = value
		queue_redraw()
@export var border_color: Color = Color(0.53, 0.53, 0.53):
	set(value):
		border_color = value
		queue_redraw()
@export var border_width: float = 2.0:
	set(value):
		border_width = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var pts: PackedVector2Array = _hex_points()
	draw_colored_polygon(pts, fill_color)

	var outline: PackedVector2Array = pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, border_color, border_width, true)


func _hex_points() -> PackedVector2Array:
	var w: float = size.x
	var h: float = size.y
	return PackedVector2Array([
		Vector2(w * 0.5, 0.0),
		Vector2(w, h * 0.25),
		Vector2(w, h * 0.75),
		Vector2(w * 0.5, h),
		Vector2(0.0, h * 0.75),
		Vector2(0.0, h * 0.25),
	])
