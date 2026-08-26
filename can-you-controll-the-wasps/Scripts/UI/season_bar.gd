class_name SeasonBar
extends PanelContainer

# 底部季节条 / bottom season tracker.
# 只管显示，推进季节的逻辑从外面驱动 / display only, driven from outside.

signal season_changed(index: int)

const SEASONS: PackedStringArray = ["Summer", "Autumn", "Winter", "Spring"]

@export_range(0, 3, 1) var current_season: int = 0:
	set(value):
		current_season = clampi(value, 0, SEASONS.size() - 1)
		_refresh()
		season_changed.emit(current_season)

@export var idle_color: Color = Color(0.67, 0.67, 0.67)
@export var active_color: Color = Color(1.0, 0.85, 0.35)

@onready var _slots: HBoxContainer = $Row/Seasons
@onready var _time_label: Label = $Row/Duration/Dial/Time


func _ready() -> void:
	_refresh()


# 外部的季节计时器调这个 / called by whatever drives the season timer
func set_time_left(seconds: float) -> void:
	if _time_label == null:
		return
	var total: int = int(maxf(seconds, 0.0))
	_time_label.text = "%02d:%02d" % [total / 60, total % 60]


func _refresh() -> void:
	if _slots == null:  # setter 可能在 _ready 之前跑 / setter can fire before _ready
		return
	for i in _slots.get_child_count():
		var slot: Label = _slots.get_child(i) as Label
		if slot != null:
			slot.add_theme_color_override("font_color", active_color if i == current_season else idle_color)
