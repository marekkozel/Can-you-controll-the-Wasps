class_name AttentionRing
extends Node2D

# 指路光圈 / the attention ring. 套在教程当前那一步要玩家看的东西上，慢慢脉动。
# A pulsing ring around whatever the current tutorial step wants you to look at.
#
# **坐标全部从目标节点身上取，不写死。** 教程要指的是"纸板点""某个空巢室"这类东西，
# 而它们的位置在场景里随时可能被挪——写死坐标的话美术调一次布局，光圈就指向空气
# Positions come from the target node itself: hard-coded ones point at nothing the
# moment somebody nudges the layout.
#
# 画在**世界层**而不是 UI 层：它要贴着实体，UI 层还得做一次坐标换算
# Drawn in world space; a CanvasLayer would need the transform juggled by hand.

const GROUP: StringName = &"attention_ring"

@export_group("Look")
@export var color: Color = Color(1.0, 0.816, 0.459, 0.9)
## 静止时的半径 / resting radius
@export_range(8.0, 200.0, 1.0) var radius: float = 34.0
## 脉动时最多胀多少 / how far it swells
@export_range(0.0, 60.0, 1.0) var swell: float = 10.0
@export_range(1.0, 10.0, 0.5) var thickness: float = 3.0
## 一次脉动几秒。太快就成了警告灯，这东西只是"看这里"
## Any faster and it reads as an alarm; this only means "look here".
@export_range(0.3, 5.0, 0.1) var period: float = 1.6

@export_group("Motion")
## 跟随的柔和程度。目标是刚体时会抖，硬跟着画会一起抖
## Targets are rigid bodies and jitter; following softly hides it.
@export_range(0.01, 1.0, 0.01) var follow: float = 0.25
@export_range(0.05, 1.0, 0.01) var fade_time: float = 0.25

# 不加类型：指着的巢室/资源点随时可能被清掉，类型化变量拒绝存已释放的实例
# Untyped on purpose - the thing it points at can be freed at any moment.
var _target = null
var _t: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	z_index = 30
	modulate.a = 0.0
	set_process(false)


static func find(tree: SceneTree) -> AttentionRing:
	return tree.get_first_node_in_group(GROUP) as AttentionRing


# 指向谁。传 null 就收起来 / point at a node, or null to retire
func point_at(node) -> void:
	if node == _target:
		return
	_target = node
	if not is_instance_valid(_target):
		_hide()
		return
	# 换目标时**瞬移过去**，不插值。从上一个目标一路飘到新目标看着像是有东西在飞
	# Snap on retarget: gliding across the map reads as a creature, not a pointer.
	global_position = _target.global_position
	set_process(true)
	create_tween().tween_property(self, "modulate:a", 1.0, fade_time)


func _hide() -> void:
	create_tween().tween_property(self, "modulate:a", 0.0, fade_time) \
		.finished.connect(func(): set_process(false))


func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		_target = null
		_hide()
		return
	global_position = global_position.lerp(_target.global_position, follow)
	_t += delta
	queue_redraw()


func _draw() -> void:
	# 两圈：主圈脉动，外面一圈很淡的跟着涨得更多，看起来像扩散出去的
	# Two rings - the faint outer one swells further and reads as a ripple.
	var beat: float = 0.5 - 0.5 * cos(_t * TAU / period)
	draw_arc(Vector2.ZERO, radius + swell * beat, 0.0, TAU, 48, color, thickness, true)
	var faint: Color = color
	faint.a *= 0.28 * (1.0 - beat)
	draw_arc(Vector2.ZERO, radius + swell * (0.6 + beat), 0.0, TAU, 48, faint, thickness, true)
