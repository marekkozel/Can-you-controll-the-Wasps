class_name SeasonBar
extends PanelContainer

# 底部季节条 / bottom season tracker.
# 只管显示，推进季节的是 SeasonDirector / display only, SeasonDirector drives it.

signal season_changed(index: int)

const SEASONS: PackedStringArray = ["Summer", "Autumn", "Winter", "Spring"]

@export_range(0, 3, 1) var current_season: int = 0:
	set(value):
		current_season = clampi(value, 0, SEASONS.size() - 1)
		_refresh()
		season_changed.emit(current_season)

@export var idle_color: Color = Color(0.67, 0.67, 0.67)
@export var active_color: Color = Color(1.0, 0.85, 0.35)

@export_group("Countdown")
## 剩这么久开始变色。季节交替是玩家唯一能提前准备的节点，最后一段必须看得出来
## The turnover is the only beat the player can prepare for, so the tail must read.
@export_range(0.0, 60.0, 1.0) var warn_seconds: float = 15.0
@export var warn_color: Color = Color(0.95, 0.42, 0.3)

@onready var _slots: HBoxContainer = $Row/Seasons
@onready var _fill: SeasonProgress = $Fill
@onready var _time_label: Label = $Row/Duration/Dial/Time

var _ratio: float = 0.0
var _warning: bool = false


func _ready() -> void:
	_time_label.add_theme_color_override("font_color", active_color)
	_refresh()


# 外面的 SeasonDirector 调这两个 / called by the director
func set_time_left(seconds: float) -> void:
	if _time_label == null:
		return
	var total: int = int(ceilf(maxf(seconds, 0.0)))
	var text: String = "%02d:%02d" % [total / 60, total % 60]
	if _time_label.text != text:
		_time_label.text = text

	# 每帧都 override 会每帧触发一次主题变更 + 重排，只在跨过阈值时写
	# Overriding every frame re-notifies the theme and relayouts; only write on the flip.
	var warning: bool = seconds <= warn_seconds
	if warning != _warning:
		_warning = warning
		_time_label.add_theme_color_override("font_color", warn_color if warning else active_color)


func set_progress(ratio: float) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	_refresh_fill()


func _refresh() -> void:
	if _slots == null:  # setter 可能在 _ready 之前跑 / setter can fire before _ready
		return
	for i in _slots.get_child_count():
		var slot: Label = _slots.get_child(i) as Label
		if slot != null:
			slot.add_theme_color_override("font_color", active_color if i == current_season else idle_color)
	_refresh_fill()


# 格子的矩形每次都重算：容器要等一帧才定下来，缓存下来的第一帧是错的
# Recomputed every push - the container settles a frame late, so a cached rect starts wrong.
func _refresh_fill() -> void:
	if _fill == null or _slots == null:
		return
	var slot: Control = _slots.get_child(current_season) as Control
	if slot == null:
		return
	# Control 没有 to_local（那是 Node2D 的），两个都在同一层 CanvasLayer 下，减一下就行
	# Control has no to_local - same CanvasLayer, so subtracting the origins is enough.
	_fill.set_slot(Rect2(slot.global_position - _fill.global_position, slot.size), _ratio)
