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

@export_group("Juice")
# 手感一律按语气缩放（见 _tone_heat）。四个语气用同一份动作的话，「有传闻」和
# 「巢被抢了」砸下来的力度一样重，这条 UI 就没有轻重之分了——它大部分时候只是在陈述
# Everything here scales with tone: one motion for all four would make a rumour land as
# hard as a raid, and this bar is a remark far more often than it is an alarm.
## 入场先缩到多小再弹回来 / how far it squashes before springing back
@export_range(0.0, 0.4, 0.01) var pop_depth: float = 0.12
## 从顶上多高砸下来 / how far above its seat it drops from
@export_range(0.0, 48.0, 1.0) var drop_height: float = 18.0
## 逐字显示速度（字/秒），0 关掉。字一个一个出来，眼睛会跟着它走
## Chars per second; the text writing itself is what pulls the eye up there.
@export_range(0.0, 300.0, 5.0) var type_speed: float = 110.0
## 落地那一下框刷亮多少倍 / how hard the frame flares on arrival
@export_range(1.0, 2.0, 0.05) var flare: float = 1.35
## 只有威胁句会横向抖，幅度（像素）/ threat lines rattle sideways, in px
@export_range(0.0, 12.0, 0.5) var threat_shake: float = 3.5
## 抖动衰减速度 / how fast the rattle dies
@export_range(1.0, 40.0, 1.0) var shake_decay: float = 14.0

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
## 抖动叠在这个基准 x 上。直接读 position.x 的话，抖动会把自己的偏移当成新基准，
## 一路飘出屏幕 / the rattle rides on this, or it integrates its own offset away
var _center_x: float = 0.0
var _shake: float = 0.0
var _shake_time: float = 0.0
var _type_tween: Tween = null


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
	_leave()


# 退场：一边淡一边往上收一点。原地淡掉像是被关掉了，收一下才像说完了
# Fading in place reads as switched off; drifting up reads as finished.
func _leave() -> void:
	_shake = 0.0
	_panel.position.x = _center_x
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_panel, "modulate:a", 0.0, fade_out)
	_tween.tween_property(_panel, "position:y", top_margin - 5.0, fade_out) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_panel, "scale", Vector2.ONE * 0.97, fade_out)


func _trim() -> void:
	while _queue.size() > QUEUE_LIMIT:
		_queue.pop_back()   # 已按优先级降序，末尾就是最不要紧的 / sorted, so the tail is cheapest


func _process(delta: float) -> void:
	_tick_shake(delta)
	if _current.is_empty():
		return
	_time_left -= delta
	if _time_left > 0.0:
		return
	if _queue.is_empty():
		_current = {}
		_leave()
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
	var heat: float = _tone_heat(int(item[&"tone"]))
	_label.text = String(item[&"text"])
	# 等布局落定再动。缩放绕 pivot 转，pivot 要拿最终宽度算——不等的话入场第一帧
	# 是按上一句的宽度缩的，横幅会横着跳一下
	# The pop pivots on the final width; entering a frame early makes the pill jump.
	await _relayout()

	if from_hidden:
		_enter(tone, heat, int(item[&"tone"]))
	else:
		# 换句：压一下再回来，宽度靠 _relayout 自己补 / dip and return
		_fade(swap_dip, swap_time * 0.5)
		await get_tree().create_timer(swap_time * 0.5).timeout
		# 在最暗的那一帧换色，整块变色就看不出是硬切的
		# Swapped at the bottom of the dip, where a hard cut cannot be seen.
		_panel.self_modulate = tone
		_fade(1.0, swap_time * 0.5)
		# 接上来的那句只弹一半：整条已经在屏幕上了，再砸一次就是两次入场
		# Half a pop for a follow-up line - it is already on screen.
		_bounce(heat * 0.5)
		_type_out()


# 入场。砸下来 + 弹一下 + 框亮一下 + 字自己写出来，四件事同时发生
# The arrival: a drop, a spring, a flare and the text writing itself, all at once.
func _enter(tone: Color, heat: float, kind: int) -> void:
	_panel.self_modulate = tone * lerpf(1.0, flare, heat)
	_panel.scale = Vector2.ONE * (1.0 - pop_depth * heat)
	_panel.position.y = top_margin - lerpf(6.0, drop_height, heat)
	_type_out()

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_panel, "modulate:a", 1.0, fade_in)
	_tween.tween_property(_panel, "position:y", top_margin, fade_in * 2.0) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "scale", Vector2.ONE, fade_in * 2.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 亮回本色比另外三条都慢：闪光退得太快就只是一帧噪点，读不出「亮了一下」
	# The flare outlives the rest; a fast decay reads as a dropped frame, not a flash.
	_tween.tween_property(_panel, "self_modulate", tone, fade_in * 3.5)

	if kind == Tone.THREAT:
		_shake = threat_shake
		_shake_time = 0.0


# 只弹缩放，不动位置。换句时用 / a spring with no drop, for follow-up lines
func _bounce(heat: float) -> void:
	if heat <= 0.0:
		return
	_panel.scale = Vector2.ONE * (1.0 - pop_depth * heat)
	create_tween().tween_property(_panel, "scale", Vector2.ONE, fade_in * 1.8) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# 逐字。visible_ratio 不影响 Label 的最小尺寸，所以框的宽度一次到位，
# 不会跟着字一格一格长——那样整条横幅会抽搐
# visible_ratio leaves the minimum size alone, so the pill sizes once instead of
# growing a character at a time.
func _type_out() -> void:
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
	if type_speed <= 0.0:
		_label.visible_ratio = 1.0
		return
	_label.visible_ratio = 0.0
	var seconds: float = minf(float(_label.text.length()) / type_speed, seconds_clamp.x * 0.6)
	_type_tween = create_tween()
	_type_tween.tween_property(_label, "visible_ratio", 1.0, seconds)


# 横向抖。只抖 x：y 归入场那条 tween 管，两边都写就打架
# Sideways only - the entry tween owns y, and both writing it would fight.
func _tick_shake(delta: float) -> void:
	if _shake <= 0.0:
		return
	_shake = maxf(_shake - delta * shake_decay, 0.0)
	_shake_time += delta
	_panel.position.x = _center_x + sin(_shake_time * TAU * 18.0) * _shake
	if _shake <= 0.0:
		_panel.position.x = _center_x


# 只管透明度。入场和退场各有自己那条带位移/缩放的 tween，别再往这里塞
# Alpha only - entry and exit own their own motion tweens.
func _fade(to: float, seconds: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", to, seconds)


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
	_center_x = roundf((size.x - _panel.size.x) * 0.5)
	_panel.position.x = _center_x
	# 绕中心缩放。默认 pivot 在左上角，弹一下会把整条往左上角吸过去
	# Scale about the centre; the default top-left pivot sucks it into the corner.
	_panel.pivot_offset = _panel.size * 0.5
	_laying_out = false
	if _relayout_again:
		_relayout_again = false
		_relayout()


# 语气 → 手感强度。传闻压到四成：它可能是假的，砸得跟真事一样重就是在骗玩家的注意力
# A rumour may be a lie; landing it as hard as a fact would spend attention on nothing.
func _tone_heat(tone: int) -> float:
	match tone:
		Tone.THREAT:
			return 1.0
		Tone.RITE:
			return 1.0
		Tone.LOSS:
			return 0.8
	return 0.4


func _tone_color(tone: int) -> Color:
	match tone:
		Tone.THREAT:
			return threat_color
		Tone.LOSS:
			return loss_color
		Tone.RITE:
			return rite_color
	return rumour_color
