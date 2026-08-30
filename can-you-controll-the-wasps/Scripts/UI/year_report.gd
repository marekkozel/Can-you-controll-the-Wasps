class_name YearReport
extends Control

# 年终结算 / the winter settlement.
# 冬天的最后一件事：暂停、摊开这一年的账、把基因点交到玩家手上。
# The one moment the game stops and tells you what the year amounted to.
#
# **它不是通知，是一拍**。整局唯一的暂停就在这里，所以它值得慢一点：
# 行一条一条落下来，点数最后砸下去。一次性全画出来的面板玩家不会读。
# The only pause in the run, so it earns its beat - rows land one at a time.
#
# 内容全靠 SeasonDirector.year_report() 那个字典，这里一个玩法数字都不算
# Every number comes from the director; this file computes none of them.

const GROUP: StringName = &"year_report"
const UPGRADE_GROUP: StringName = &"upgrade_panel"

@export_group("Look")
@export var dim_color: Color = Color(0.06, 0.04, 0.06, 0.62)
@export var panel_color: Color = Color(0.259, 0.169, 0.196, 0.97)
@export var border_color: Color = Color(1.0, 0.816, 0.459, 0.9)
@export var text_color: Color = Color(0.949, 0.910, 0.847)
## 数字用暖色，标签用素色，一眼能扫到右边那一列
## The values carry the colour so the eye can run down the right-hand column.
@export var value_color: Color = Color(1.0, 0.816, 0.459)
@export var points_color: Color = Color(0.514, 0.745, 0.341)
@export_range(200.0, 900.0, 10.0) var panel_width: float = 460.0

@export_group("Juice")
## 面板落下来用多久 / how long the panel takes to land
@export_range(0.05, 2.0, 0.05) var open_time: float = 0.32
## 两行之间隔多久。太快就又变成"一次性全画出来"了
## Any faster and the rows stop reading as separate beats.
@export_range(0.0, 0.6, 0.01) var row_stagger: float = 0.07
## 每行进场时从多小长回原样。**不要改成位移**——行在 VBoxContainer 里，
## 容器每次重排都会把 position 写回去，动画会跟它打架；scale 容器不碰
## Never animate position here: the container owns it and would fight the tween.
@export_range(0.5, 1.0, 0.01) var row_pop: float = 0.94

var _director: SeasonDirector = null
var _dim: ColorRect = null
var _panel: PanelContainer = null
var _rows: VBoxContainer = null
var _button: Button = null
var _upgrade: Node = null
var _upgrade_mode: int = Node.PROCESS_MODE_INHERIT


func _ready() -> void:
	add_to_group(GROUP)
	# 整棵树都停了，这一张还得动 / everything else is frozen; this one still runs
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()


func _build() -> void:
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = dim_color
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 暂停期间底下的东西不该还能点 / nothing underneath stays clickable while paused
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	var centre: CenterContainer = CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size.x = panel_width
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = panel_color
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(20.0)
	_panel.add_theme_stylebox_override("panel", style)
	centre.add_child(_panel)

	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", 6)
	_panel.add_child(_rows)


# SeasonDirector 在冬天最后一拍调这里 / called by the director on the closing beat
func present(report: Dictionary) -> void:
	_director = SeasonDirector.find(get_tree())
	_fill(report)

	visible = true
	get_tree().paused = true
	# 点数就在右边那张面板上花。暂停期间它也得能点，所以借用一下它的 process_mode，
	# 关闭时原样还回去 / borrowed for the pause, handed back on close
	_upgrade = get_tree().get_first_node_in_group(UPGRADE_GROUP)
	if _upgrade != null:
		_upgrade_mode = _upgrade.process_mode
		_upgrade.process_mode = Node.PROCESS_MODE_ALWAYS
		if _upgrade.has_method("set_expanded"):
			_upgrade.set_expanded(true)

	# 等一帧再动画：布局没跑完的话 size 还是 0，缩放的轴心会算到左上角。
	# 暂停不影响 process_frame，这个 await 一定会回来
	# One frame for the layout, else size is still zero. process_frame fires while paused.
	await get_tree().process_frame
	_play()


func _fill(report: Dictionary) -> void:
	# 先摘再 free：queue_free 要到帧末才生效，中间那一段 get_children() 还看得见它们
	# Detach first - queue_free lands at end of frame and _play would animate the corpses.
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()

	var queen: String = String(report.get(&"queen", ""))
	_add_title("Year %d ends" % int(report.get(&"generation", 1)), 22)
	var line: String = "No heir. The comb goes into spring on its own."
	if queen != "":
		line = "%s is your queen. Everything else stays in the winter." % queen
	_add_title(line, 12)
	_add_separator()

	for row in report.get(&"rows", []):
		_add_row(String(row.get(&"label", "")), int(row.get(&"value", 0)))

	_add_separator()
	var gained: int = int(report.get(&"points", 0))
	_add_row("Gene points earned", gained, points_color, 18)
	if gained > 0:
		_add_title("Spend them on the right - they only reach wasps born after you do.", 11)

	_button = Button.new()
	_button.name = "Continue"
	_button.text = "Into spring"
	_button.custom_minimum_size.y = 32.0
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(_close)
	_rows.add_child(_button)


func _add_title(text: String, size: int) -> void:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", text_color)
	_rows.add_child(label)


func _add_separator() -> void:
	var line: HSeparator = HSeparator.new()
	line.add_theme_constant_override("separation", 10)
	_rows.add_child(line)


# 标签靠左、数字靠右。中间撑开，右边那一列才能对齐成可以竖着扫的一条
# The spacer is what lines the numbers up into a column you can read down.
func _add_row(text: String, value: int, tint: Color = value_color, size: int = 14) -> void:
	var row: HBoxContainer = HBoxContainer.new()

	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", text_color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var amount: Label = Label.new()
	amount.text = str(value)
	amount.add_theme_font_size_override("font_size", size)
	amount.add_theme_color_override("font_color", tint)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(amount)

	_rows.add_child(row)


# 暗场 → 面板落下 → 行一条条进来 → 按钮
# 每一段都挂在这一个 tween 上，中途关掉面板它会跟着一起死
# One tween owns the whole sequence, so closing early kills all of it.
func _play() -> void:
	AudioManager.create_audio(SoundEffect.SoundEffectType.END_GAME_SCREEN)

	_dim.modulate.a = 0.0
	_panel.modulate.a = 0.0
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(row_pop, row_pop)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_dim, "modulate:a", 1.0, open_time)
	tween.tween_property(_panel, "modulate:a", 1.0, open_time)
	tween.tween_property(_panel, "scale", Vector2.ONE, open_time) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var at: float = open_time
	for item in _rows.get_children():
		var control: Control = item as Control
		if control == null:
			continue
		control.modulate.a = 0.0
		control.scale = Vector2(row_pop, row_pop)
		tween.tween_property(control, "modulate:a", 1.0, 0.18).set_delay(at)
		tween.tween_property(control, "scale", Vector2.ONE, 0.22) 			.set_delay(at).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		at += row_stagger


func _close() -> void:
	visible = false
	get_tree().paused = false

# --- MUSIC FADE-IN ---
	BackgroundMusic.volume_db = linear_to_db(0.01)
	BackgroundMusic.play()
	var tween: Tween = BackgroundMusic.create_tween()
	tween.tween_method(
		func(vol: float): BackgroundMusic.volume_db = linear_to_db(vol),
		0.01, 1.0, 1.5 # Fades in over 1.5 seconds
	)

	if _upgrade != null:
		_upgrade.process_mode = _upgrade_mode
		_upgrade = null
	if _director != null:
		_director.resume_after_report()
