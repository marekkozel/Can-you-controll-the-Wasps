class_name SeasonProgress
extends Control

# 季节进度填充 / season progress fill. 铺在 SeasonBar 的季节格子底下，把当前那一格从左往右填满。
# 跟进度环一样是程序绘制的，**不要出图**——它的尺寸跟着布局走，一张 PNG 接不住
# Drawn in code like the progress rings: it tracks the slot layout, a PNG cannot.

## 已走过的部分 / the elapsed part
@export var fill_color: Color = Color(1.0, 0.85, 0.35, 0.18)
## 前沿那条竖线。有它才读得出"现在几点"，光靠色块看不出走到哪了
## The leading edge is what reads as a hand on a dial; a plain block does not.
@export var edge_color: Color = Color(1.0, 0.85, 0.35, 0.7)
@export_range(1.0, 8.0, 0.5) var edge_width: float = 2.0

var _slot: Rect2 = Rect2()
var _ratio: float = 0.0


func set_slot(rect: Rect2, ratio: float) -> void:
	var next: float = clampf(ratio, 0.0, 1.0)
	if rect == _slot and is_equal_approx(next, _ratio):
		return
	_slot = rect
	_ratio = next
	queue_redraw()


func _draw() -> void:
	if _slot.size.x <= 0.0 or _slot.size.y <= 0.0:
		return

	var filled: Rect2 = Rect2(_slot.position, Vector2(_slot.size.x * _ratio, _slot.size.y))
	draw_rect(filled, fill_color)
	if _ratio <= 0.0:
		return
	var x: float = filled.position.x + filled.size.x
	draw_line(Vector2(x, _slot.position.y), Vector2(x, _slot.end.y), edge_color, edge_width)
