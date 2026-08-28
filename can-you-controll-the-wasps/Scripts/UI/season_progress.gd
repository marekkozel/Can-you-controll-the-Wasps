class_name SeasonProgress
extends Control

# 季节进度填充 / the year's progress, drawn inside the season bar's pill.
# 程序绘制而不是出图：左端要贴合药丸的圆头，宽度又跟着条走，一张 PNG 接不住
# Drawn in code - it has to hug the pill's rounded cap at whatever width the bar is.

## 每一段自己的颜色，由 SeasonBar 写入。走过的春天是绿的、夏天是琥珀的——
## 一眼看得出年份走到哪，而且冬天那截蓝色是越走越近的，那才是玩家真正要提前知道的事
## Per-segment: the year reads as a ramp, and winter's blue is visibly approaching.
@export var colors: PackedColorArray = PackedColorArray([Color(1.0, 0.82, 0.46)])
## 前沿那条竖线。没有它就只是一块色，读不出"现在走到哪"
## Without the leading edge it is a coloured block, not a clock.
@export var edge_color: Color = Color(0.26, 0.16, 0.2, 0.9)
@export_range(1.0, 8.0, 0.5) var edge_width: float = 2.0
## 四周内缩，避开外框那圈 5px 粗边 / keeps the fill off the frame's thick border
@export_range(0.0, 16.0, 1.0) var inset: float = 5.0

var _ratio: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_ratio(value: float) -> void:
	var next: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(next, _ratio):
		return
	_ratio = next
	queue_redraw()


func set_colors(next: PackedColorArray) -> void:
	if next == colors or next.is_empty():
		return
	colors = next
	queue_redraw()


func _draw() -> void:
	var h: float = size.y - inset * 2.0
	var track: float = size.x - inset * 2.0
	if h <= 0.0 or track <= 0.0 or _ratio <= 0.0 or colors.is_empty():
		return

	var r: float = h * 0.5
	var count: int = colors.size()
	var seg: float = track / float(count)

	# 两端的圆头单独画，中间才用矩形——方角直接怼到药丸的圆端上会戳出去
	# The caps are drawn separately; a square edge would poke out of the pill's round end.
	draw_circle(Vector2(inset + r, inset + r), minf(r, maxf(track * _ratio, 1.0)), colors[0])

	for i in count:
		var t: float = clampf(_ratio * float(count) - float(i), 0.0, 1.0)
		if t <= 0.0:
			break
		var x0: float = inset + seg * float(i)
		var x1: float = x0 + seg * t
		var lo: float = maxf(x0, inset + r)
		var hi: float = minf(x1, inset + track - r)
		if hi > lo:
			draw_rect(Rect2(lo, inset, hi - lo, h), colors[i])
		if x1 >= inset + track - r:
			draw_circle(Vector2(inset + track - r, inset + r), r, colors[i])

	if _ratio < 1.0:
		var x: float = inset + track * _ratio
		draw_line(Vector2(x, inset), Vector2(x, inset + h), edge_color, edge_width)
