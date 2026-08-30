class_name SettingsPanel
extends Control

# 设置面板 / the settings panel. 现在只有三条音量。
# 拆成独立场景是为了给以后的 ESC 暂停菜单复用同一份，不用抄第二遍
# Its own scene so a future pause menu reuses it instead of copying it.
#
# **这里现在一行音频代码都没有。** 队友的 AudioManager 还在 audio_manager 分支上，
# 而且那套目前没有音频总线（所有 AudioStreamPlayer 都走 Master，音量在每个
# SoundEffect 资源里单独配），所以滑条暂时无处可接。
# 接线的时候只改 _apply_volume() 一个函数——UI 这边不用动。
# No audio code yet: the AudioManager lives on another branch and has no buses to
# address. When it lands, _apply_volume() is the only function that changes.

## 哪条总线被拖了。参数是 &"Master" / &"Music" / &"SFX"，值是 0~1 线性
## Which bus moved; the value is linear 0..1, not dB.
signal volume_changed(bus: StringName, value: float)
signal closed

const BUSES: Array[StringName] = [&"Master", &"Music", &"SFX"]

@export_group("Juice")
## 面板落下来用多久 / how long the panel takes to land
@export_range(0.05, 1.0, 0.01) var open_time: float = 0.22
## 入场先缩到多小 / how far it starts squashed
@export_range(0.5, 1.0, 0.01) var open_pop: float = 0.92

@onready var _dim: ColorRect = $Dim
@onready var _panel: PanelContainer = $Panel

## 每条总线当前的值。**没有落盘**——存 user://settings.cfg 那步跟接 AudioServer
## 是同一件事，一起做，现在留在内存里
## Kept in memory only; persistence lands together with the audio wiring.
var _levels: Dictionary = {}

var _rows: Dictionary = {}


func _ready() -> void:
	hide()
	for bus in BUSES:
		var row: Control = _panel.find_child(String(bus), true, false) as Control
		if row == null:
			push_warning("SettingsPanel: no row for bus %s" % bus)
			continue
		var slider: HSlider = row.get_node(^"Slider") as HSlider
		_rows[bus] = row
		_levels[bus] = slider.value
		# bus 绑进回调：三行共用一个处理函数，加第四条总线只要往 BUSES 里多一项
		# Bound so one handler serves every row - a fourth bus is one array entry.
		slider.value_changed.connect(_on_slider_changed.bind(bus))
		_refresh(bus)

	$Panel/Margin/Rows/Back.pressed.connect(close)


# Esc 关掉。开着的时候要把这个输入吃掉，不然以后接了暂停菜单，一次 Esc 会同时
# 关设置和开暂停 / swallowed while open, or one Esc would also toggle a future pause menu
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed(&"ui_cancel"):
		return
	close()
	get_viewport().set_input_as_handled()


func open() -> void:
	show()
	_dim.modulate.a = 0.0
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2.ONE * open_pop
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "modulate:a", 1.0, open_time)
	tween.tween_property(_panel, "scale", Vector2.ONE, open_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	AudioManager.create_audio(SoundEffect.SoundEffectType.FOOD_POP)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "modulate:a", 0.0, open_time * 0.7)
	tween.tween_property(_panel, "scale", Vector2.ONE * open_pop, open_time * 0.7)
	tween.chain().tween_callback(hide)
	closed.emit()


func volume_of(bus: StringName) -> float:
	return float(_levels.get(bus, 1.0))


func _on_slider_changed(value: float, bus: StringName) -> void:
	_levels[bus] = value
	_refresh(bus)
	_apply_volume(bus, value)
	volume_changed.emit(bus, value)


# 接线点。AudioManager 合进 main 之后，这里加两件事：
#   1. AudioServer.set_bus_volume_db(bus_index, linear_to_db(value))
#   2. 写 user://settings.cfg
# 在那之前它是空的——**空着比接一半强**，接一半就得记得回来删
# The wiring point. Deliberately empty until there are buses to address.
func _apply_volume(_bus: StringName, _value: float) -> void:
	pass


func _refresh(bus: StringName) -> void:
	var row: Control = _rows.get(bus) as Control
	if row == null:
		return
	var label: Label = row.get_node(^"Value") as Label
	label.text = "%d%%" % roundi(float(_levels[bus]) * 100.0)
