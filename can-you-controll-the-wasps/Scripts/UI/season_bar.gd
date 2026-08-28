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

@export_group("Raids")
## 入侵图标是**纯白剪影**（整张图只有 255,255,255 一种 RGB，形状全在 alpha 上），
## 跟季节图标一个路子，必须靠 self_modulate 上色才看得见——条底是浅色纸板，
## 不上色的话它就是白的，等于没画
## A white silhouette: it does not exist until self_modulate gives it a colour.
@export var raid_icon: Texture2D = preload("res://Assets/UI/icon_enemy.png")
## 源图是 24x24 且内容占满 22x23。24 是 1:1 最锐利，48 是整数二倍；
## 中间的值会插值糊一点，不过剪影糊一点看不太出来
## 48 等于条高，会顶满上下沿，别再往上加
## The source is 24px; 24 is pixel-exact, 48 is a clean 2x but fills the bar's height.
@export_range(8.0, 48.0, 1.0) var raid_icon_size: float = 28.0

# 四个状态**全部不透明**，靠色相和明度分，不靠 alpha 压淡。
# 压淡的图标在纸板底上会糊成一团看不清，而入侵预告是要玩家一眼扫到的东西
# All four are solid: a faded icon on this light panel reads as noise, and the whole
# point of the schedule is that it can be read at a glance.
## 还没到的那一波。跟当前季节图标同一个墨色，实心 / same ink as the active season icon
@export var raid_pending_color: Color = Color(0.263, 0.161, 0.196)
## 正在打的那一波 / the one happening right now
@export var raid_active_color: Color = Color(0.886, 0.227, 0.090)
## 打完的。沉下去但仍然看得清——玩家要能数出"今年还剩几波"
## Sunk, not hidden: the player still needs to count what is left this year.
@export var raid_done_color: Color = Color(0.42, 0.39, 0.38)
## 到点了但巢里没东西可抢。冷灰跟 done 的暖灰分开，读作"没发生"而不是"发生过"
## Cool grey, so it reads as "never happened" rather than "already over".
@export var raid_misfire_color: Color = Color(0.53, 0.58, 0.61)

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
## 入侵图标层，代码建：一代来几波是随机的，摆在场景里不合适
## Built in code - the count is rolled per generation, so it cannot live in the scene.
var _raids: Control = null
var _marks: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raids = Control.new()
	_raids.name = "Raids"
	_raids.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raids.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_raids)          # 最后加，画在段落文字之上 / added last, drawn on top
	resized.connect(_layout_raids)
	_ready_done = true
	_refresh()


# RaidDirector 掷完点就推过来。每项 {at: float, state: RaidDirector.MarkState}
# Pushed by RaidDirector whenever the schedule is rolled or a mark changes state.
func set_raid_marks(marks: Array) -> void:
	_marks = marks.duplicate()
	if not _ready_done:
		return
	_rebuild_raids()


func _rebuild_raids() -> void:
	if _raids == null:
		return
	for child in _raids.get_children():
		child.queue_free()

	for mark in _marks:
		var icon: TextureRect = TextureRect.new()
		icon.texture = raid_icon
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(raid_icon_size, raid_icon_size)
		icon.size = Vector2(raid_icon_size, raid_icon_size)
		icon.self_modulate = _raid_tint(int(mark[&"state"]))
		_raids.add_child(icon)

	_layout_raids()


# 位置必须和 SeasonProgress 用**同一条公式**（inset + track * ratio），
# 否则进度前沿走到图标那儿时对不上，玩家会觉得预告不准
# Same formula as the progress edge, or the icon and the edge disagree on where "now" is.
func _layout_raids() -> void:
	if _raids == null or _fill == null:
		return
	var inset: float = _fill.inset
	var track: float = size.x - inset * 2.0
	if track <= 0.0:
		return

	for i in _raids.get_child_count():
		if i >= _marks.size():
			break
		var icon: Control = _raids.get_child(i) as Control
		if icon == null:
			continue
		var at: float = clampf(float(_marks[i][&"at"]), 0.0, 1.0)
		icon.position = Vector2(
			inset + track * at - raid_icon_size * 0.5,
			(size.y - raid_icon_size) * 0.5)


func _raid_tint(state: int) -> Color:
	match state:
		RaidDirector.MarkState.ACTIVE:
			return raid_active_color
		RaidDirector.MarkState.DONE:
			return raid_done_color
		RaidDirector.MarkState.MISFIRE:
			return raid_misfire_color
	return raid_pending_color


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
