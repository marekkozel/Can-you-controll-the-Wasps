@tool
class_name WanderComponent
extends Node

# 随机游荡 / random wander. 挂到 RigidBody2D 下，在 home 周围随机挑点飞过去。
# 到了或者超时就换一个 / repicks on arrival or on timeout.
# 被拖拽时必须 enabled = false，两边都写 linear_velocity 会打架 / would fight the drag spring.

signal target_changed(target: Vector2)

## 在 home 周围多大范围里挑点 / radius around home to pick targets in
@export_range(10.0, 800.0, 5.0) var wander_radius: float = 200.0
@export_range(5.0, 400.0, 5.0) var speed: float = 55.0
## 多久换一个目标点，到点了也会提前换 / retarget timeout, arrival also retargets
@export_range(0.5, 30.0, 0.1) var retarget_interval: float = 3.0
@export_range(2.0, 100.0, 1.0) var arrive_distance: float = 18.0
## 转向平滑，越小越飘 / steering smoothing, lower drifts more
@export_range(0.05, 1.0, 0.01) var steering: float = 0.08

@export var enabled: bool = true:
	set(value):
		enabled = value
		set_physics_process(enabled and _body != null and not Engine.is_editor_hint())

## 游荡的中心。生成方摆好位置之后要显式设一次 / set it from code after positioning
var home_position: Vector2 = Vector2.ZERO

var _body: RigidBody2D = null
var _target: Vector2 = Vector2.ZERO
var _timer: float = 0.0


func _ready() -> void:
	_body = get_parent() as RigidBody2D
	if _body == null:
		push_warning("WanderComponent needs a RigidBody2D parent: %s" % get_path())
		set_physics_process(false)
		return

	home_position = _body.global_position
	_pick_target()
	set_physics_process(enabled and not Engine.is_editor_hint())


func set_home(position: Vector2) -> void:
	home_position = position
	_pick_target()


func _physics_process(delta: float) -> void:
	if _body == null:
		return

	_timer -= delta
	var to_target: Vector2 = _target - _body.global_position
	if _timer <= 0.0 or to_target.length() < arrive_distance:
		_pick_target()
		to_target = _target - _body.global_position

	var desired: Vector2 = to_target.normalized() * speed
	_body.linear_velocity = _body.linear_velocity.lerp(desired, steering)


func _pick_target() -> void:
	# sqrt 让点在圆内均匀分布，不然会挤在中心 / sqrt gives uniform disc distribution
	var angle: float = randf_range(0.0, TAU)
	var distance: float = sqrt(randf()) * wander_radius
	_target = home_position + Vector2(cos(angle), sin(angle)) * distance
	_timer = retarget_interval * randf_range(0.7, 1.3)
	target_changed.emit(_target)
