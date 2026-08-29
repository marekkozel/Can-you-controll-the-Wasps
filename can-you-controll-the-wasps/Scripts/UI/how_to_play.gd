class_name HowToPlay
extends Control

# 玩法说明 / the reference page. 主菜单上一页，七条，随时可查。
# 游戏内的教程是按事情**发生的顺序**一点点喂的，好处是不打断，坏处是玩家五分钟后
# 忘了蜂王浆是干嘛的没地方查；而且 jam 评委平均只玩三分钟，卡片可能才弹到第二张。
# 这一页就是补这两个洞——它不教节奏，只当字典。
# The in-game cards teach in order of events; this page is the dictionary they need
# five minutes later, and the only thing a three-minute judge will actually read.
#
# 结构跟 SettingsPanel 一样（遮罩 + 面板 + 缩放弹入 + Esc 关），文案全在场景里，改字不碰代码
# Same shell as SettingsPanel; every word lives in the scene.

signal closed

## 游戏里按这个键开/关。主菜单上有按钮，但玩到一半忘了蜂王浆是干嘛的，
## 总不能退回菜单去查 / the menu has a button; mid-run you need it without leaving
@export var hotkey: Key = KEY_H

@export_group("Juice")
@export_range(0.05, 1.0, 0.01) var open_time: float = 0.22
@export_range(0.5, 1.0, 0.01) var open_pop: float = 0.92

@onready var _dim: ColorRect = $Dim
@onready var _panel: PanelContainer = $Panel


func _ready() -> void:
	hide()
	$Panel/Margin/Rows/Back.pressed.connect(close)


# H 开关、Esc 只关。两条都把输入吃掉——以后接暂停菜单时，
# 一次 Esc 不能既关这页又开暂停
# Both swallow the event so a future pause menu does not fire on the same Esc.
func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == hotkey:
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
		return

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
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "modulate:a", 0.0, open_time * 0.7)
	tween.tween_property(_panel, "scale", Vector2.ONE * open_pop, open_time * 0.7)
	tween.chain().tween_callback(hide)
	closed.emit()
