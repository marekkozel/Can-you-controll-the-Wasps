class_name SettingsPanel
extends Control

# 设置面板 / the settings panel. 现在只有三条音量。
# 拆成独立场景是为了给以后的 ESC 暂停菜单复用同一份，不用抄第二遍
# Its own scene so a future pause menu reuses it instead of copying it.
#
# 三条滑条直接推 AudioServer 上的三条总线（Master / Music / SFX，
# 见 default_bus_layout.tres）。音效走 SFX 是 AudioManager 写的，音乐走 Music
# 在那两个 autoload 场景上——**改总线名字要三处一起改**，写错了声音会静默落回 Master
# The three buses are addressed by name in three places; a rename silently falls back.

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

## 存哪儿。**不能存 res://**，导出之后那是只读的
## Never res:// - it is read-only in an exported build.
const CONFIG_PATH: String = "user://settings.cfg"
const CONFIG_SECTION: String = "audio"

## 每条总线当前的值 / the live levels, mirrored to disk on close
var _levels: Dictionary = {}
## 有没有改过。没动过就不写盘，省得每次进菜单都碰一次文件
## Nothing changed means nothing to write.
var _dirty: bool = false

var _rows: Dictionary = {}


func _ready() -> void:
	hide()
	var saved: Dictionary = _load()
	for bus in BUSES:
		var row: Control = _panel.find_child(String(bus), true, false) as Control
		if row == null:
			push_warning("SettingsPanel: no row for bus %s" % bus)
			continue
		var slider: HSlider = row.get_node(^"Slider") as HSlider
		_rows[bus] = row
		# 先写滑条再连信号：反过来的话 set 会触发一次回调，把刚读出来的值
		# 当成"玩家拖的"记成脏数据
		# Set before connecting, or restoring the saved value counts as a user edit.
		slider.value = saved.get(bus, slider.value)
		_levels[bus] = slider.value
		# bus 绑进回调：三行共用一个处理函数，加第四条总线只要往 BUSES 里多一项
		# Bound so one handler serves every row - a fourth bus is one array entry.
		slider.value_changed.connect(_on_slider_changed.bind(bus))
		_apply_volume(bus, slider.value)
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
	_save()
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
	_dirty = true
	_refresh(bus)
	_apply_volume(bus, value)
	volume_changed.emit(bus, value)


# 推总线。**拉到 0 要走 mute 而不是音量**：linear_to_db(0) 是负无穷，
# 有些平台（web 尤其）拿到 -inf 会直接把这条总线弄坏，之后调回来也没声了
# At zero use mute: linear_to_db(0) is -inf and some backends never recover from it.
func _apply_volume(bus: StringName, value: float) -> void:
	var index: int = AudioServer.get_bus_index(String(bus))
	if index < 0:
		push_warning("SettingsPanel: no audio bus named %s" % bus)
		return
	AudioServer.set_bus_mute(index, value <= 0.0)
	if value > 0.0:
		AudioServer.set_bus_volume_db(index, linear_to_db(value))


# 关面板时落盘。**不能只在 close() 里存**——玩家调完音量直接按 Play，
# 面板是被整个场景一起释放掉的，close() 一次都不会走
# Play never calls close(): the whole menu is freed, so _exit_tree has to catch it.
func _exit_tree() -> void:
	_save()


func _load() -> Dictionary:
	var out: Dictionary = {}
	var file: ConfigFile = ConfigFile.new()
	if file.load(CONFIG_PATH) != OK:
		return out
	for bus in BUSES:
		if file.has_section_key(CONFIG_SECTION, String(bus)):
			out[bus] = clampf(float(file.get_value(CONFIG_SECTION, String(bus))), 0.0, 1.0)
	return out


func _save() -> void:
	if not _dirty:
		return
	var file: ConfigFile = ConfigFile.new()
	file.load(CONFIG_PATH)  # 别覆盖以后别人往这个文件里加的东西 / keep other sections
	for bus in BUSES:
		file.set_value(CONFIG_SECTION, String(bus), float(_levels.get(bus, 1.0)))
	file.save(CONFIG_PATH)
	_dirty = false


func _refresh(bus: StringName) -> void:
	var row: Control = _rows.get(bus) as Control
	if row == null:
		return
	var label: Label = row.get_node(^"Value") as Label
	label.text = "%d%%" % roundi(float(_levels[bus]) * 100.0)
