@tool
class_name PipTrack
extends Control

# 格子条 / pip track: 画 total 个格子，点亮前 filled 个。血量和专长都用它。
#
# **必须程序绘制，不能用字符。** Godot 的 fallback 字体是 Open Sans，
# ●○■□▮▯◆◇ 一个都没有（has_char 全 false），拿字符画出来是一排豆腐块。
# 这也跟 HoldRing / ItemSource.Ring 一样，是这个项目画指示器的既有路子。
# Never draw these with glyphs: the fallback font has none of the geometric shapes.

enum Shape {
	ROUND,   ## 血量用。轨道长度会随 max_health 变 / health, whose track length varies
	SQUARE,  ## 专长用。轨道恒定四格 / perks, always a fixed four
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
@export var fill_color: Color = Color(0.95, 0.82, 0.35)
@export var empty_color: Color = Color(1.0, 1.0, 1.0, 0.18)
## 空格子描一圈边，不然暗背景上空格子几乎看不见 / empty pips vanish without an outline
@export var outline_color: Color = Color(1.0, 1.0, 1.0, 0.3)
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


func _draw() -> void:
	var y: float = (size.y - pip_size) * 0.5
	for i in total:
		var x: float = float(i) * (pip_size + gap)
		var lit: bool = i < filled
		match shape:
			Shape.ROUND:
				var centre: Vector2 = Vector2(x + pip_size * 0.5, y + pip_size * 0.5)
				draw_circle(centre, pip_size * 0.5, fill_color if lit else empty_color)
				if not lit and outline_width > 0.0:
					draw_arc(centre, pip_size * 0.5, 0.0, TAU, 16, outline_color, outline_width, true)
			Shape.SQUARE:
				var rect: Rect2 = Rect2(x, y, pip_size, pip_size)
				draw_rect(rect, fill_color if lit else empty_color, true)
				if not lit and outline_width > 0.0:
					draw_rect(rect, outline_color, false, outline_width)
