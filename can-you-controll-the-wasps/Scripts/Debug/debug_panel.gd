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
	{"label": "F9  Start a raid", "method": "start_raid", "key": KEY_F9},
	{"label": "F10 Kill all enemies", "method": "kill_all_enemies", "key": KEY_F10},
	{"label": "F12 Awaken a false queen", "method": "awaken_false_queen", "key": KEY_F12},
	{"label": "M   Toggle allegiance markers", "method": "toggle_markers", "key": KEY_M},
	{"label": "T   Cycle time scale", "method": "cycle_time_scale", "key": KEY_T},
	{"label": "     Time scale back to x1", "method": "reset_time_scale", "key": KEY_NONE},
	{"label": "     Skip to next season", "method": "skip_season", "key": KEY_NONE},
	{"label": "     Skip to winter", "method": "skip_to_winter", "key": KEY_NONE},
	{"label": "     Crown someone now", "method": "crown_someone", "key": KEY_NONE},
	{"label": "     Gene point +1", "method": "grant_gene_point", "key": KEY_NONE},
	{"label": "     Call off the raid", "method": "end_raid", "key": KEY_NONE},
	{"label": "     Reveal allegiances", "method": "reveal_allegiances", "key": KEY_NONE},
	{"label": "     Unrest +0.2", "method": "bump_unrest", "key": KEY_NONE},
	{"label": "     Clear unrest + grudges", "method": "clear_unrest", "key": KEY_NONE},
	{"label": "     Clear wasps", "method": "clear_wasps", "key": KEY_NONE},
	{"label": "     Clear enemies", "method": "clear_enemies", "key": KEY_NONE},
]

## 按钮堆最高长到这里，超了就滚。**面板是会长的**——刷怪那几行照品种表生成，
## 加一种敌人就多一行，早晚会顶到屏幕底下切掉一半
## The stack grows with the breed table; without a cap it runs off a 720px screen.
@export_range(160.0, 700.0, 10.0) var max_list_height: float = 520.0

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
	_cap_button_list()
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
		_add_button(entry["label"], _run.bind(entry["method"]))

	# 刷怪那几行是照 RaidDirector.breeds 现生成的，不写死在 ACTIONS 里——
	# 加第七种敌人只要往 world.tscn 的 breeds 塞一个 .tres，这里自动多一行
	# Generated from the director so a new breed needs no edit here.
	var breeds: Array = _actions.breeds()
	if breeds.is_empty():
		return
	_add_button("     Line up all breeds (frozen)", _actions.line_up_breeds)
	for i in breeds.size():
		var breed: EnemyVariant = breeds[i]
		_add_button("     Spawn %s  r%d  %dx  %dhp" % [
				breed.display_name, int(breed.collision_radius),
				int(breed.sprite_scale), breed.max_health],
			_actions.spawn_breed_index.bind(i))


# 给按钮堆套一层滚动区。在代码里套而不是在场景里摆：场景里那棵树是手写的，
# 多一层容器就要重连 @onready 路径，而这一层纯粹是长度问题，跟布局意图无关
# Wrapped here rather than in the scene: it is a length fix, not a layout decision.
func _cap_button_list() -> void:
	var host: Node = _buttons.get_parent()
	var slot: int = _buttons.get_index()

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "ButtonScroll"
	scroll.custom_minimum_size = Vector2(0.0, max_list_height)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	host.remove_child(_buttons)
	host.add_child(scroll)
	host.move_child(scroll, slot)
	scroll.add_child(_buttons)
	# 不填满宽度的话按钮会缩成文字宽，一行一个长度都不一样
	# Without this the buttons shrink to their text and every row is a different width.
	_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _add_button(label: String, action: Callable) -> void:
	var button: Button = Button.new()
	button.text = label
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(action)
	_buttons.add_child(button)


# 少数要带参数的在这里转一下 / the few that need arguments are routed here
func _run(method: String) -> void:
	match method:
		"toggle_markers":
			_markers.visible = not _markers.visible
			_on_action_done("allegiance markers %s" % ("on" if _markers.visible else "off"))
		_:
			_actions.call(method)


func _on_action_done(message: String) -> void:
	_status.text = "%s   |   time x%.2f" % [message, Engine.time_scale]
