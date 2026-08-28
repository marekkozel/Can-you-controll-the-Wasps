class_name DraggableComponent
extends Area2D

# 物理拖拽 / physics drag. 挂到任意 RigidBody2D 下就能拖。
# 手感参数全走 profile / all feel params come from the DragProfile resource.

signal grabbed
signal released

@export var profile:DragProfile

# 同一时刻只允许一个，重叠的物体不会被一起抓起来 / only one at a time
static var _active_component: Node = null

const MOUSE_VELOCITY_SMOOTHING: float = 0.4

var _body: RigidBody2D = null
var _is_grabbed: bool = false
var _grab_offset: Vector2 = Vector2.ZERO  # 抓在哪一点，别让物体中心跳到鼠标上 / keep grab point, don't snap centre to cursor
var _previous_mouse_pos: Vector2 = Vector2.ZERO
var _smoothed_mouse_velocity: Vector2 = Vector2.ZERO

# 抓之前的刚体状态，松手时还原 / body state saved on grab, restored on release
var _saved_gravity_scale: float = 1.0
var _saved_linear_damp: float = 0.0
var _saved_z_index: int = 0
var _saved_ccd: int = RigidBody2D.CCD_MODE_DISABLED


# 黄蜂要知道一件东西是不是玩家正拿着 / wasps must not yank cargo out of the player's hand
func is_grabbed() -> bool:
	return _is_grabbed


# 场上有没有东西正被拖着 / is anything under the cursor right now
static func is_dragging() -> bool:
	return _active_component != null


# 手上那个刚体本身。给 UI 用：拿着什么就说明什么，不用满场扫 is_grabbed()
# For the readout - what is in hand right now, without scanning every draggable.
static func held_body() -> RigidBody2D:
	if _active_component == null:
		return null
	return (_active_component as DraggableComponent)._body


# 给生成方用：刚造出来的物件直接落到光标上，跳过"先点中它"这一步
# For spawners: a freshly minted piece goes straight onto the cursor, no click needed.
# 抓在正中心，不留 _grab_offset / dead-centre grab, no offset to preserve
func grab_at_cursor() -> bool:
	if _body == null or _is_grabbed or _active_component != null:
		return false
	_body.global_position = get_global_mouse_position()
	_grab()
	_grab_offset = Vector2.ZERO
	return true


func _ready() -> void:
	_body = get_parent() as RigidBody2D
	if _body == null:
		push_warning("DraggableComponent needs a RigidBody2D parent: %s" % get_path())
		input_pickable = false
		set_process_input(false)
		set_physics_process(false)
		return

	if profile == null:
		profile = DragProfile.new()

	input_pickable = true
	set_physics_process(false)  # 只有抓着的时候才需要跑 / only runs while held


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if _body == null or _is_grabbed or _active_component != null:
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return

	_grab()
	get_viewport().set_input_as_handled()  # 别让下面重叠的 Area2D 也收到 / stop the click reaching areas underneath


func _input(event: InputEvent) -> void:
	if not _is_grabbed:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_release()


func _physics_process(delta: float) -> void:
	if not _is_grabbed or not is_instance_valid(_body):
		return

	var mouse_pos: Vector2 = get_global_mouse_position()
	# 单帧差分噪声太大，平滑之后再用 / raw per-frame delta is too noisy
	var raw_velocity: Vector2 = (mouse_pos - _previous_mouse_pos) / delta
	_smoothed_mouse_velocity = _smoothed_mouse_velocity.lerp(raw_velocity, MOUSE_VELOCITY_SMOOTHING)
	_previous_mouse_pos = mouse_pos

	_apply_follow(mouse_pos, delta)
	_apply_wobble()


# 拖着时退场或窗口失焦：兜底还原重力，不然会永远悬空 / safety net, else gravity stays 0
func _exit_tree() -> void:
	if _is_grabbed:
		_release(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _is_grabbed:
		_release()


func _grab() -> void:
	_is_grabbed = true
	_active_component = self

	_previous_mouse_pos = get_global_mouse_position()
	_smoothed_mouse_velocity = Vector2.ZERO
	_grab_offset = _body.global_position - _previous_mouse_pos

	_saved_gravity_scale = _body.gravity_scale
	_saved_linear_damp = _body.linear_damp
	_saved_z_index = _body.z_index
	_saved_ccd = _body.continuous_cd

	_body.gravity_scale = 0.0
	if profile.drag_linear_damp >= 0.0:
		_body.linear_damp = profile.drag_linear_damp
	_body.z_index = _saved_z_index + profile.grab_z_offset
	_body.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE  # 高速拖拽别穿墙 / continuous collision so it can't tunnel

	set_physics_process(true)
	grabbed.emit()


func _release(notify: bool = true) -> void:
	if not _is_grabbed:
		return

	_is_grabbed = false
	if _active_component == self:
		_active_component = null
	set_physics_process(false)

	if is_instance_valid(_body):
		_body.gravity_scale = _saved_gravity_scale
		_body.linear_damp = _saved_linear_damp
		_body.z_index = _saved_z_index
		_body.continuous_cd = _saved_ccd
		# 用手速甩出去，不用刚体当前速度——后者被弹簧带偏了 / spring-skewed velocity feels wrong
		var throw: Vector2 = _smoothed_mouse_velocity * profile.throw_multiplier
		_body.linear_velocity = throw.limit_length(profile.max_throw_speed)
		_body.angular_velocity *= profile.spin_retention

	# 拆树时不发：兄弟组件的 get_tree() 已经是 null，监听方一查全场就炸
	# Not while tearing down - siblings are already detached and any group lookup is null
	if notify:
		released.emit()


# 弹簧 + 阻尼跟随：stiffness 管跟手程度，damping 管刚性还是果冻 / spring-damper follow
func _apply_follow(mouse_pos: Vector2, delta: float) -> void:
	var target: Vector2 = mouse_pos + _grab_offset

	var stiffness: float = profile.stiffness
	if profile.mass_scaling:
		stiffness /= maxf(_body.mass, 0.01)

	var desired_velocity: Vector2 = (target - _body.global_position) * stiffness
	# 换成和帧率无关的插值系数，60fps 时正好等于 damping / framerate independent
	var blend: float = 1.0 - pow(1.0 - clampf(profile.damping, 0.0, 1.0), delta * 60.0)
	var velocity: Vector2 = _body.linear_velocity.lerp(desired_velocity, blend)
	_body.linear_velocity = velocity.limit_length(profile.max_speed)


# 走 angular_velocity 而不是直接写 rotation，松手后才能带自旋 / keeps physics in charge
func _apply_wobble() -> void:
	var target_rotation: float = clampf(
		_smoothed_mouse_velocity.x * profile.wobble_multiplier,
		-profile.max_wobble_angle,
		profile.max_wobble_angle
	)
	var angle_error: float = wrapf(target_rotation - _body.rotation, -PI, PI)
	_body.angular_velocity = angle_error * profile.rotation_stiffness
