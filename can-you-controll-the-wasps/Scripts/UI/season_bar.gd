class_name SeasonBar
extends Control

# 底部季节条 / the year at a glance. 一整条药丸，四段等宽，每段开头一个季节图标。
# 只管显示，推进的是 SeasonDirector / display only, SeasonDirector drives it.
#
# 进度画的是**整年**（SeasonDirector.year_progress），不是当前季节。
# 玩家最需要知道的是「离冬天还有多远」——冬天要做继位决策，提前看得见才来得及准备。
# The bar answers "how far to winter", which is the only beat the player can prepare for.

signal season_changed(index: int)

## 顺序要和 SeasonDirector.Season 以及 Segments 底下四个节点一致
## Must match the enum and the child order.
const SEASONS: PackedStringArray = ["Spring", "Summer", "Autumn", "Winter"]

## 四季各自的填充色，取自 33 调色盘。
## 这几个色相和血统色有重叠（春绿≈Lime、夏琥珀≈Amber），但**位置固定、四色永远同时出现、
## 而且从不出现在实体身上**，所以不会被读成血统提示。别把它们用到任何会动的东西上。
## They overlap the lineage hues, and that is only safe because the bar never moves.
const SEASON_COLORS: PackedColorArray = [
	Color(0.514, 0.745, 0.341),  # Spring 83be57
	Color(1.0, 0.816, 0.459),    # Summer ffd075
	Color(0.773, 0.404, 0.161),  # Autumn c56729
	Color(0.459, 0.647, 0.824),  # Winter 75a5d2
]

## 当前季节的图标和文字 / the active segment
@export var active_color: Color = Color(0.263, 0.161, 0.196)   # 432932
## 其余三段**压淡**，不是压暗。纸板是亮底，深灰和深紫在上面一样黑，
## 分不出哪个是当前季节——要拉开的是不透明度，不是色相
## The panel is light, so two dark inks read the same. Separate them by alpha.
@export var idle_color: Color = Color(0.263, 0.161, 0.196, 0.32)

@export_group("Countdown")
## 剩这么久时把当前季节的图标转成警告色。季节交替是玩家唯一能提前准备的节点，
## 条上没有数字，所以最后这一段必须用颜色喊出来
## No digits on the bar, so the tail has to shout in colour.
@export_range(0.0, 60.0, 1.0) var warn_seconds: float = 15.0
@export var warn_color: Color = Color(0.886, 0.227, 0.090)     # e23a17

@export_range(0, 3, 1) var current_season: int = 0:
	set(value):
		var next: int = clampi(value, 0, SEASONS.size() - 1)
		if next == current_season and _ready_done:
			return
		current_season = next
		_refresh()
		season_changed.emit(current_season)

@onready var _fill: SeasonProgress = $Fill
@onready var _segments: HBoxContainer = $Segments

var _ready_done: bool = false
var _warning: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ready_done = true
	_refresh()


# SeasonDirector 每帧调这两个 / called every frame by the director
func set_time_left(seconds: float) -> void:
	# 每帧 override 主题颜色会每帧触发一次主题变更 + 重排，只在跨过阈值时写
	# Overriding every frame re-notifies the theme and relayouts; only write on the flip.
	var warning: bool = seconds <= warn_seconds
	if warning == _warning:
		return
	_warning = warning
	_paint_segments()


func set_progress(ratio: float) -> void:
	if _fill != null:
		_fill.set_ratio(ratio)


func _refresh() -> void:
	if not _ready_done:
		return
	if _fill != null:
		_fill.set_colors(SEASON_COLORS)
	_paint_segments()


func _paint_segments() -> void:
	if _segments == null:
		return
	for i in _segments.get_child_count():
		var seg: Node = _segments.get_child(i)
		var on: bool = i == current_season
		var tint: Color = active_color if on else idle_color
		if on and _warning:
			tint = warn_color

		# 图标画的是灰度，靠 self_modulate 上色（`modulate` 会连子节点一起染）
		# The icons are greyscale on purpose; self_modulate, never modulate.
		var icon: CanvasItem = seg.get_node_or_null(^"Icon") as CanvasItem
		if icon != null:
			icon.self_modulate = tint
		var label: Label = seg.get_node_or_null(^"Name") as Label
		if label != null:
			label.add_theme_color_override("font_color", tint)
