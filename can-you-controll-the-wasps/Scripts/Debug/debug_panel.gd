extends CanvasLayer

# 调试面板 / debug panel. F1 开关，按钮和快捷键都走 DebugActions。
# 只在 debug build 里存在，导出发布版会自己关掉 / removes itself in release builds.
# 不需要了从 world.tscn 删掉这个节点即可，别的代码不依赖它 / nothing depends on it.

## 每个按钮对应 DebugActions 上的一个方法 / each button maps to a DebugActions method
const ACTIONS: Array[Dictionary] = [
	{"label": "F2  Build all cells", "method": "build_all_cells", "key": KEY_F2},
	{"label": "F3  Complete one wasp", "method": "complete_one_wasp", "key": KEY_F3},
	{"label": "F4  Spawn wasp", "method": "spawn_wasp", "key": KEY_F4},
	{"label": "F5  Make larvae hungry", "method": "make_all_hungry", "key": KEY_F5},
	{"label": "F6  Feed all larvae", "method": "feed_all_larvae", "key": KEY_F6},
	{"label": "F7  Time scale x2", "method": "cycle_time_scale", "key": KEY_F7},
	{"label": "F8  Reset hive", "method": "reset_hive", "key": KEY_F8},
	{"label": "F9  Start a raid", "method": "start_raid", "key": KEY_F9},
	{"label": "F10 Kill all enemies", "method": "kill_all_enemies", "key": KEY_F10},
	{"label": "F12 Awaken a false queen", "method": "awaken_false_queen", "key": KEY_F12},
	{"label": "M   Toggle allegiance markers", "method": "toggle_markers", "key": KEY_M},
	{"label": "     Call off the raid", "method": "end_raid", "key": KEY_NONE},
	{"label": "     Spawn loose enemy", "method": "spawn_enemy", "key": KEY_NONE},
	{"label": "     Reveal allegiances", "method": "reveal_allegiances", "key": KEY_NONE},
	{"label": "     Unrest +0.2", "method": "bump_unrest", "key": KEY_NONE},
	{"label": "     Clear unrest + grudges", "method": "clear_unrest", "key": KEY_NONE},
	{"label": "     Spawn cardboard", "method": "spawn_cardboard", "key": KEY_NONE},
	{"label": "     Spawn food", "method": "spawn_food", "key": KEY_NONE},
	{"label": "     Clear wasps", "method": "clear_wasps", "key": KEY_NONE},
	{"label": "     Clear enemies", "method": "clear_enemies", "key": KEY_NONE},
]

@onready var _actions: DebugActions = $DebugActions
@onready var _buttons: VBoxContainer = $Root/Panel/Margin/Content/Buttons
@onready var _status: Label = $Root/Panel/Margin/Content/Status
@onready var _root: Control = $Root
@onready var _panel: PanelContainer = $Root/Panel
@onready var _perf: PanelContainer = $Root/Perf
@onready var _markers: Node2D = $Markers


func _ready() -> void:
	# 发布版里直接不存在 / gone in release builds
	if not OS.is_debug_build():
		queue_free()
		return

	_actions.action_done.connect(_on_action_done)
	_build_buttons()
	# 性能读数常驻，按钮那一坨太占地方所以默认收起 / perf stays up, the button stack does not
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	if event.keycode == KEY_F1:
		_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()
		return

	if event.keycode == KEY_F11:
		_perf.visible = not _perf.visible
		get_viewport().set_input_as_handled()
		return

	for entry in ACTIONS:
		if entry["key"] != KEY_NONE and event.keycode == entry["key"]:
			_run(entry["method"])
			get_viewport().set_input_as_handled()
			return


func _build_buttons() -> void:
	for entry in ACTIONS:
		var button: Button = Button.new()
		button.text = entry["label"]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_run.bind(entry["method"]))
		_buttons.add_child(button)


# 少数要带参数的在这里转一下 / the few that need arguments are routed here
func _run(method: String) -> void:
	match method:
		"toggle_markers":
			_markers.visible = not _markers.visible
			_on_action_done("allegiance markers %s" % ("on" if _markers.visible else "off"))
		"spawn_cardboard":
			_actions.spawn_items(&"cardboard", 3)
		"spawn_food":
			_actions.spawn_items(&"food", 3)
		_:
			_actions.call(method)


func _on_action_done(message: String) -> void:
	_status.text = "%s   |   time x%.2f" % [message, Engine.time_scale]
