class_name PauseMenu
extends Control

# 暂停菜单 / the pause menu. Esc 开关，右上角另有一个可点的按钮。
#
# **走 `get_tree().paused`，绝不碰 `Engine.time_scale`**——受击卡顿（Enemy 的 hit stop）
# 和调试面板的 T 键都在用那个全局倍率，拿它做暂停两边会互相覆盖，
# 表现是"暂停之后时间自己又跑起来了"
# Never time_scale: the hit stop and the debug key already own it.
#
# 暂停期间还要活着的东西全部设 PROCESS_MODE_ALWAYS：本菜单、SettingsPanel、HowToPlay、
# AudioManager（不然点按钮没声）、两个音乐 autoload（不然一暂停音乐跟着停，像崩了）
# Everything that must survive the pause is ALWAYS; the music especially, or a pause
# sounds like a crash.

const MENU_SCENE: String = "res://Scenes/UI/MainMenu.tscn"
## 年终结算在场时不许开。它自己已经 paused = true 了，再叠一层的话 resume 会把
## 那一拍一起解除暂停——整局唯一的叙事暂停就废了
## The year settlement already pauses; resuming from here would cancel its beat.
const REPORT_GROUP: StringName = &"year_report"

@export var settings_path: NodePath = ^"../SettingsPanel"
@export var howto_path: NodePath = ^"../HowToPlay"

@export_group("Juice")
@export_range(0.05, 1.0, 0.01) var open_time: float = 0.18
## 入场先缩到多小 / how far the panel starts squashed
@export_range(0.5, 1.0, 0.01) var open_pop: float = 0.94

@onready var _dim: ColorRect = $Dim
@onready var _panel: PanelContainer = $Panel
@onready var _rows: VBoxContainer = $Panel/Margin/Rows

var _settings: SettingsPanel = null
var _howto: HowToPlay = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 根节点整局都在（右上角那个按钮要一直看得见），所以它自己不能吃鼠标——
	# 只有遮罩和按钮该挡住底下的场面
	# The root stays visible for the corner button, so only Dim and the buttons take input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.visible = false
	_panel.visible = false

	_settings = get_node_or_null(settings_path) as SettingsPanel
	_howto = get_node_or_null(howto_path) as HowToPlay

	$PauseButton.pressed.connect(_toggle)
	_rows.get_node(^"Resume").pressed.connect(close)
	_rows.get_node(^"Settings").pressed.connect(_on_settings)
	_rows.get_node(^"HowTo").pressed.connect(_on_howto)
	_rows.get_node(^"Menu").pressed.connect(_on_menu)

	# 网页导出里 quit() 什么都不会发生，跟主菜单一个处理 / same as the main menu
	var quit: Button = _rows.get_node(^"Quit")
	quit.visible = not OS.has_feature("web")
	quit.pressed.connect(_on_quit)


# Esc 现在有三个抢：这一层、SettingsPanel、HowToPlay。**不靠节点顺序碰运气**——
# 那两个开着的时候这里直接不理，让它们各自关掉自己，判断写在一处
# Three consumers now; explicit checks beat relying on input order.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if _is_open(_settings) or _is_open(_howto):
		return
	if is_paused():
		close()
	elif _can_open():
		open()
	else:
		return
	get_viewport().set_input_as_handled()


func is_paused() -> bool:
	return _panel.visible


func open() -> void:
	if not _can_open():
		return
	get_tree().paused = true
	_dim.visible = true
	_panel.visible = true
	_dim.modulate.a = 0.0
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2.ONE * open_pop

	# 菜单是 PROCESS_MODE_ALWAYS，所以挂在它身上的 tween 在暂停期间照样跑
	# The tween runs because this node is ALWAYS; a pausable one would freeze mid-fade.
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "modulate:a", 1.0, open_time)
	tween.tween_property(_panel, "scale", Vector2.ONE, open_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not _panel.visible:
		return
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_dim, "modulate:a", 0.0, open_time * 0.7)
	tween.tween_property(_panel, "scale", Vector2.ONE * open_pop, open_time * 0.7)
	# 淡出跑完再解除暂停。先解除的话画面已经动起来了、面板还浮在上面淡，
	# 读起来像是没关掉 / unpausing first reads as a menu that failed to close
	tween.chain().tween_callback(_finish_close)


func _finish_close() -> void:
	_dim.visible = false
	_panel.visible = false
	get_tree().paused = false


func _toggle() -> void:
	if is_paused():
		close()
	else:
		open()


# 能不能开。年终结算在场时不行——它自己就是暂停，见上面 REPORT_GROUP 那段
# The settlement owns the pause while it is up.
func _can_open() -> bool:
	if _is_open(_settings) or _is_open(_howto):
		return false
	for node in get_tree().get_nodes_in_group(REPORT_GROUP):
		var report: CanvasItem = node as CanvasItem
		if report != null and report.visible:
			return false
	return true


func _is_open(panel: CanvasItem) -> bool:
	return panel != null and panel.visible


# 设置和玩法说明都开在暂停菜单**上面**，各自带遮罩，Esc 各自关掉自己。
# 这一层不用躲开——躲开的话关掉设置会露出没有菜单的暂停状态
# They layer on top and close themselves; hiding this one would leave a menuless pause.
func _on_settings() -> void:
	if _settings != null:
		_settings.open()


func _on_howto() -> void:
	if _howto != null:
		_howto.open()


# **先解除暂停再换场景**：换过去的菜单会继承 paused，那是一个动不了的主菜单
# Unpause first, or the menu inherits the pause and nothing responds.
func _on_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_quit() -> void:
	get_tree().quit()
