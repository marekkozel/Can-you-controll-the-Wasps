class_name Herald
extends Control

# 顶部横幅 / the herald. 一条自适应宽度的药丸，一次只说一句话。
# 只管排队和呈现，说什么由 Announcer 决定 / presentation only, Announcer writes the words.
#
# 大部分时间它是空的——空着，响的时候才有分量 / silence is what gives it weight.
#
# 类别靠**整块框换色**读，不是靠一条边上的色带——一小条彩色在纸板上根本抓不到眼睛。
# 底图 herald_frame.png 是**灰度**的（跟 bar_frame 同一个形状），颜色全走 self_modulate；
# 彩色的 bar_frame 乘不出冷色，它的蓝通道只有 0.51
# The frame art is greyscale on purpose: the colour is the message, and a warm
# cardboard texture multiplied by blue simply stays cardboard.

## 类别 = 框的颜色。跟血统色无关：位置固定、从不出现在实体身上
## A category, never an allegiance - see the red line in CLAUDE.md.
enum Tone { THREAT, LOSS, RITE, RUMOUR }

const GROUP: StringName = &"herald"
## 队列塞不下这么多就丢优先级最低的 / overflow drops the least important
const QUEUE_LIMIT: int = 3

@export_group("Layout")
## 距屏幕顶多远。框有 46 高，会盖住入场带上沿十来个像素——
## 这是把字放大到能一眼读完的代价，敌人本身是从 y=40 往下走进来的，不影响判断
## The pill overlaps the raiders' entry strip by ~10px; legibility won that trade.
@export_range(0.0, 64.0, 1.0) var top_margin: float = 6.0
## 超过这个宽度就折成两行 / wider than this and the line wraps
@export_range(200.0, 1000.0, 10.0) var max_width: float = 680.0

@export_group("Timing")
@export_range(0.5, 5.0, 0.1) var base_seconds: float = 2.0
## 长句多留一会儿，读得完 / longer lines get longer on screen
@export_range(0.0, 0.2, 0.005) var seconds_per_char: float = 0.045
@export var seconds_clamp: Vector2 = Vector2(2.5, 5.5)
@export_range(0.05, 1.0, 0.01) var fade_in: float = 0.15
@export_range(0.05, 1.0, 0.01) var fade_out: float = 0.25
## 换句时不整条闪掉，只压一下透明度——闪没再出来太吵
## A dip, not a full fade: blinking the whole pill between lines reads as noise.
@export_range(0.05, 0.6, 0.01) var swap_time: float = 0.12
@export_range(0.0, 1.0, 0.05) var swap_dip: float = 0.35

@export_group("Tones")
# 四个都是**同一块纸板的不同色温**，不是四个招牌色。整块变色已经够响了，
# 再上饱和色就会把横幅变成一个警告灯，而这条 UI 大部分时候只是在陈述
# Four temperatures of one material: saturated plates would turn a remark into an alarm.
## 威胁：入侵预警、抢走了东西 / raids
@export var threat_color: Color = Color(0.800, 0.420, 0.310)
## 损失：救不回来的那些 / what cannot be undone
@export var loss_color: Color = Color(0.855, 0.647, 0.325)
## 仪式：冬天的三拍 / the winter beats
@export var rite_color: Color = Color(0.560, 0.700, 0.835)
## 传闻。**它可能是假的**，所以这个颜色不等于"她在场" / a rumour can be a lie
@export var rumour_color: Color = Color(0.600, 0.510, 0.620)

@onready var _panel: PanelContainer = $Panel
@onready var _label: Label = $Panel/Margin/Row/Label

## 每项 {key, text, repeat, priority, tone, count}
var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _time_left: float = 0.0
var _tween: Tween = null
var _laying_out: bool = false
var _relayout_again: bool = false


static func find(tree: SceneTree) -> Herald:
	return tree.get_first_node_in_group(GROUP) as Herald


func _ready() -> void:
	add_to_group(GROUP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.modulate.a = 0.0
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	set_process(true)


# 有东西正在说话没有。传闻靠这个决定要不要延后 / rumours wait for silence
func is_busy() -> bool:
	return not _current.is_empty() or not _queue.is_empty()


# 唯一的入口。repeat 里的 {n} 会被重复次数替换，留空则重复只是续命不改字
# repeat's {n} becomes the merge count; leave it empty and a repeat only refreshes the ttl.
func push(key: StringName, text: String, priority: int, tone: int, repeat: String = "") -> void:
	if text.is_empty():
		return

	# 同一件事再次发生 —— 就地合并，不排第二条 / merge, never stack
	if _current.get(&"key", &"") == key:
		_current[&"count"] = int(_current[&"count"]) + 1
		if not repeat.is_empty():
			_current[&"text"] = repeat.replace("{n}", str(_current[&"count"]))
			_apply(_current, false)
		_time_left = _duration_for(String(_current[&"text"]))
		return
	for entry in _queue:
		if entry[&"key"] == key:
			entry[&"count"] = int(entry[&"count"]) + 1
			if not repeat.is_empty():
				entry[&"text"] = repeat.replace("{n}", str(entry[&"count"]))
			return

	var item: Dictionary = {
		&"key": key,
		&"text": text,
		&"repeat": repeat,
		&"priority": priority,
		&"tone": tone,
		&"count": 1,
	}

	# 更要紧的事当场插进来，不等前一句说完 / the urgent one cuts in
	if _current.is_empty():
		_show(item, true)
		return
	if priority > int(_current.get(&"priority", 0)):
		_queue.push_front(_current)
		_show(item, false)
		_trim()
		return

	_queue.append(item)
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a[&"priority"]) > int(b[&"priority"]))
	_trim()


func clear() -> void:
	_queue.clear()
	_current = {}
	_time_left = 0.0
	_fade(0.0, fade_out)


func _trim() -> void:
	while _queue.size() > QUEUE_LIMIT:
		_queue.pop_back()   # 已按优先级降序，末尾就是最不要紧的 / sorted, so the tail is cheapest


func _process(delta: float) -> void:
	if _current.is_empty():
		return
	_time_left -= delta
	if _time_left > 0.0:
		return
	if _queue.is_empty():
		_current = {}
		_fade(0.0, fade_out)
	else:
		_show(_queue.pop_front(), false)


func _duration_for(text: String) -> float:
	return clampf(base_seconds + text.length() * seconds_per_char, seconds_clamp.x, seconds_clamp.y)


func _show(item: Dictionary, from_hidden: bool) -> void:
	_current = item
	_time_left = _duration_for(String(item[&"text"]))
	_apply(item, from_hidden)


func _apply(item: Dictionary, from_hidden: bool) -> void:
	var tone: Color = _tone_color(int(item[&"tone"]))
	_label.text = String(item[&"text"])
	_relayout()

	if from_hidden:
		_panel.self_modulate = tone
		_panel.position.y = top_margin - 6.0
		_fade(1.0, fade_in, true)
	else:
		# 换句：压一下再回来，宽度靠 _relayout 自己补 / dip and return
		_fade(swap_dip, swap_time * 0.5)
		await get_tree().create_timer(swap_time * 0.5).timeout
		# 在最暗的那一帧换色，整块变色就看不出是硬切的
		# Swapped at the bottom of the dip, where a hard cut cannot be seen.
		_panel.self_modulate = tone
		_fade(1.0, swap_time * 0.5)


func _fade(to: float, seconds: float, slide: bool = false) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_panel, "modulate:a", to, seconds)
	if slide:
		_tween.tween_property(_panel, "position:y", top_margin, seconds) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# Label 的 minimum size 要下一帧才更新，不等的话第一帧拿到的是旧宽度，横幅会跳一下
# The label's minimum size lands next frame; measuring now makes the pill jump.
func _relayout() -> void:
	# 换句比一次布局还快时，守卫会吃掉后一次——记下来，跑完再补一遍
	# A second line can land mid-layout; remember it instead of dropping it.
	if _laying_out:
		_relayout_again = true
		return
	_laying_out = true

	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.custom_minimum_size.x = 0.0
	await get_tree().process_frame

	var wanted: float = _panel.get_combined_minimum_size().x
	if wanted > max_width:
		# 折行：把 Label 钉在剩下的宽度上，高度自己长 / pin the label, let the height grow
		_label.custom_minimum_size.x = max_width - (wanted - _label.get_combined_minimum_size().x)
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		await get_tree().process_frame

	_panel.size = Vector2.ZERO   # 会被顶回 minimum size / clamped back up to the minimum
	_panel.position.x = roundf((size.x - _panel.size.x) * 0.5)
	_laying_out = false
	if _relayout_again:
		_relayout_again = false
		_relayout()


func _tone_color(tone: int) -> Color:
	match tone:
		Tone.THREAT:
			return threat_color
		Tone.LOSS:
			return loss_color
		Tone.RITE:
			return rite_color
	return rumour_color
