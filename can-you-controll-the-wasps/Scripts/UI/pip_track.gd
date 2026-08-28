@tool
class_name PipTrack
extends Control

# 格子条 / pip track: 画 total 个格子，点亮前 filled 个。血量和专长都用它。
#
# **必须程序绘制，不能用字符。** Godot 的 fallback 字体是 Open Sans，
# ●○■□▮▯◆◇ 一个都没有（has_char 全 false），拿字符画出来是一排豆腐块。
# 这也跟 HoldRing / ItemSource.Ring 一样，是这个项目画指示器的既有路子。
# Never draw these with glyphs: the fallback font has none of the geometric shapes.

# 新形状一律**追加在末尾**：场景里存的是枚举的整数值，往中间插一个会让所有轨道错位
# Append only - scenes store the integer, so inserting in the middle silently reshapes them.
enum Shape {
	ROUND,   ## 圆点 / plain dot
	SQUARE,  ## 方块 / plain square
	HEART,   ## 心形，血量用 / hearts, for health
	HEX,     ## 六边形，专长用。跟巢室同一个朝向（尖角在上下）/ pointy-top, like the cells
}

@export var shape: Shape = Shape.ROUND:
	set(value):
		shape = value
		queue_redraw()
@export_range(0, 12, 1) var filled: int = 0:
	set(value):
		filled = value
		queue_redraw()
@export_range(0, 12, 1) var total: int = 3:
	set(value):
		total = value
		_resize()
@export_range(3.0, 24.0, 1.0) var pip_size: float = 9.0:
	set(value):
		pip_size = value
		_resize()
@export_range(0.0, 16.0, 1.0) var gap: float = 4.0:
	set(value):
		gap = value
		_resize()

@export_group("Colours")
## 方案 C 的面板是纸板色亮底，所以格子走深色；点亮的用强调橙
## The panel is light cardboard, so pips are dark and the lit ones take the accent.
@export var fill_color: Color = Color(0.7725, 0.4039, 0.1608)
@export var empty_color: Color = Color(0.2627, 0.1608, 0.1961, 0.15)
## 空格子描一圈边，不然亮背景上空格子几乎看不见 / empty pips vanish without an outline
@export var outline_color: Color = Color(0.2627, 0.1608, 0.1961, 0.45)
@export_range(0.0, 4.0, 0.5) var outline_width: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resize()


func set_values(next_filled: int, next_total: int) -> void:
	total = maxi(next_total, 0)
	filled = clampi(next_filled, 0, total)


func _resize() -> void:
	var count: float = float(maxi(total, 1))
	custom_minimum_size = Vector2(count * pip_size + maxf(count - 1.0, 0.0) * gap, pip_size)
	queue_redraw()


## 心形取样点数。再多在 10px 上也看不出来，反而多算 / more than this is invisible at 10px
const HEART_STEPS: int = 22


func _draw() -> void:
	var y: float = (size.y - pip_size) * 0.5
	for i in total:
		var x: float = float(i) * (pip_size + gap)
		var lit: bool = i < filled
		var box: Rect2 = Rect2(x, y, pip_size, pip_size)
		match shape:
			Shape.ROUND:
				var centre: Vector2 = box.position + box.size * 0.5
				draw_circle(centre, pip_size * 0.5, fill_color if lit else empty_color)
				if not lit and outline_width > 0.0:
					draw_arc(centre, pip_size * 0.5, 0.0, TAU, 16, outline_color, outline_width, true)
			Shape.SQUARE:
				draw_rect(box, fill_color if lit else empty_color, true)
				if not lit and outline_width > 0.0:
					draw_rect(box, outline_color, false, outline_width)
			Shape.HEART:
				_draw_poly(_heart_points(box), lit)
			Shape.HEX:
				_draw_poly(_hex_points(box), lit)


func _draw_poly(points: PackedVector2Array, lit: bool) -> void:
	draw_colored_polygon(points, fill_color if lit else empty_color)
	if lit or outline_width <= 0.0:
		return
	# 空格子描一圈边，不然亮背景上几乎看不见 / empty pips vanish without an outline
	var loop: PackedVector2Array = points.duplicate()
	loop.append(points[0])
	draw_polyline(loop, outline_color, outline_width, true)


# 尖角在上下、竖边在左右，跟巢室的六边形同朝向 / pointy-top, matching the hive cells
func _hex_points(box: Rect2) -> PackedVector2Array:
	var centre: Vector2 = box.position + box.size * 0.5
	var radius: float = box.size.y * 0.5
	var points: PackedVector2Array = PackedVector2Array()
	for i in 6:
		var angle: float = PI / 6.0 + TAU * float(i) / 6.0
		points.append(centre + Vector2(cos(angle) * radius * 0.92, sin(angle) * radius))
	return points


# 标准心形曲线，算完之后按实际包围盒缩放进格子——直接写死系数会在某些尺寸下溢出
# Fitted to its own bounding box; hardcoded factors overflow the cell at some sizes.
func _heart_points(box: Rect2) -> PackedVector2Array:
	var raw: PackedVector2Array = PackedVector2Array()
	var lo: Vector2 = Vector2(INF, INF)
	var hi: Vector2 = Vector2(-INF, -INF)
	for i in HEART_STEPS:
		var t: float = TAU * float(i) / float(HEART_STEPS)
		var hx: float = pow(sin(t), 3.0) * 16.0
		# 曲线的 y 朝上，屏幕坐标朝下，所以取负 / the curve points up, the screen points down
		var hy: float = -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		raw.append(Vector2(hx, hy))
		lo = Vector2(minf(lo.x, hx), minf(lo.y, hy))
		hi = Vector2(maxf(hi.x, hx), maxf(hi.y, hy))

	var span: Vector2 = Vector2(maxf(hi.x - lo.x, 0.001), maxf(hi.y - lo.y, 0.001))
	var points: PackedVector2Array = PackedVector2Array()
	for p in raw:
		points.append(box.position + (p - lo) / span * box.size)
	return points
