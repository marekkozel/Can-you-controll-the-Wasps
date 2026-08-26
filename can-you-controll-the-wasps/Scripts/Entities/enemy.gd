class_name Enemy
extends RigidBody2D

# 敌人 / an enemy. 在刷新带里游荡，鼠标点一下就打死 / wanders the spawn band, one click kills it.
# 用刚体本身的 input_event 收点击，不额外挂 Area2D / the body is pickable, no extra Area2D.

signal killed(enemy: Enemy)

@export_group("Combat")
## 每次点击造成几点伤害 / damage per click
@export_range(1, 20, 1) var click_damage: int = 1
## 击退力度，只对没被打死的生效 / knockback, only applied when the hit is not lethal
@export_range(0.0, 4000.0, 10.0) var knockback_force: float = 600.0
## 击退时顺带给的旋转 / spin that comes with the knockback
@export_range(0.0, 2000.0, 10.0) var knockback_spin: float = 300.0

@export_group("Juice")
## 命中瞬间的卡顿时长（真实秒，不受 time_scale 影响）/ hit stop, in real seconds
@export_range(0.0, 0.3, 0.01) var hit_stop_duration: float = 0.05
## 卡顿期间的时间倍率 / time scale during the hit stop
@export_range(0.01, 1.0, 0.01) var hit_stop_scale: float = 0.05
## 死亡时膨胀到多大 / how far it swells before it pops
@export_range(1.0, 4.0, 0.05) var death_pop_scale: float = 1.7
## 膨胀消散用多久 / how long the pop takes
@export_range(0.05, 2.0, 0.05) var death_duration: float = 0.32
@export var hover_tint: Color = Color(1.35, 1.1, 1.1)

@onready var _visual: Node2D = $Visual
@onready var _wings: Node2D = $Visual/Wings
@onready var _health: HealthComponent = $HealthComponent
@onready var _juice: JuiceComponent = $JuiceComponent
@onready var _wander: WanderComponent = $WanderComponent

## 同一帧多个敌人被打时只卡一次 / guard so overlapping hits don't stack
static var _hit_stop_busy: bool = false

var _t: float = 0.0
var _is_dead: bool = false


func _ready() -> void:
	_juice.target = _visual
	_t = randf() * TAU

	input_pickable = true
	input_event.connect(_on_input_event)
	mouse_entered.connect(func(): if not _is_dead: _visual.modulate = hover_tint)
	mouse_exited.connect(func(): if not _is_dead: _visual.modulate = Color.WHITE)

	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)

	_visual.scale = Vector2.ZERO
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
		.tween_property(_visual, "scale", Vector2.ONE, 0.3)


func set_wander_home(position: Vector2) -> void:
	_wander.set_home(position)


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if _is_dead:
		return
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		return

	_health.take_damage(click_damage, get_global_mouse_position())
	get_viewport().set_input_as_handled()  # 别让点击穿到下面的东西 / don't let it fall through


func _on_damaged(_amount: int, remaining: int, from: Vector2) -> void:
	_juice.burst()
	_hit_stop()

	# 被打死的走 _on_died 的膨胀消散，别在这里再动 scale，两个 tween 会抢
	# A lethal hit pops in _on_died; don't touch scale here or the tweens fight.
	if remaining <= 0:
		return

	var direction: Vector2 = (global_position - from).normalized()
	if direction == Vector2.ZERO:  # 正好点在中心 / clicked dead centre
		direction = Vector2.RIGHT.rotated(randf() * TAU)

	_wander.enabled = false
	apply_central_impulse(direction * knockback_force)
	apply_torque_impulse(randf_range(-knockback_spin, knockback_spin))
	_juice.punch(0.65, 0.3)


func _on_died(_from: Vector2) -> void:
	_is_dead = true
	input_pickable = false
	_wander.enabled = false
	_visual.modulate = Color.WHITE
	set_process(false)
	killed.emit(self)

	# 原地停住，不要飞出去 / stop dead, no ragdoll flight
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	set_deferred("freeze", true)
	$CollisionShape2D.set_deferred("disabled", true)

	# 膨胀一下再消散 / swell, then fade out
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_visual, "scale", Vector2.ONE * death_pop_scale, death_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual, "modulate:a", 0.0, death_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


# 命中卡顿。用真实时间计时，不然自己会被自己的减速拖长
# Hit stop. Timed in real seconds, otherwise it would stretch itself out.
func _hit_stop() -> void:
	if hit_stop_duration <= 0.0 or _hit_stop_busy:
		return
	_hit_stop_busy = true
	var previous: float = Engine.time_scale
	Engine.time_scale = hit_stop_scale
	await get_tree().create_timer(hit_stop_duration, true, false, true).timeout
	Engine.time_scale = previous
	_hit_stop_busy = false


func _process(delta: float) -> void:
	_t += delta
	var speed: float = linear_velocity.length()
	_wings.scale.y = 0.3 + 0.7 * absf(sin(_t * 26.0 * (1.0 + speed / 150.0)))
