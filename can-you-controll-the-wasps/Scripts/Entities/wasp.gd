class_name Wasp
extends RigidBody2D

signal slammed(speed: float)

@export_range(0.05, 2.0, 0.05) var emerge_duration: float = 0.45
@export_range(0.0, 20.0, 0.5) var bob_amount: float = 3.5
@export_range(0.1, 5.0, 0.1) var bob_period: float = 1.6
@export_range(1.0, 60.0, 1.0) var wing_frequency: float = 18.0
@export_range(0.02, 1.0, 0.01) var facing_smoothing: float = 0.15

@export_range(1, 100, 1) var damage: int = 1

@export_group("Fling")
@export_range(10.0, 600.0, 5.0) var resume_wander_speed: float = 140.0
@export_range(0.5, 20.0, 0.5) var max_fling_time: float = 6.0
@export var rehome_on_landing: bool = true
@export_range(20.0, 2000.0, 10.0) var impact_speed: float = 260.0

@export_group("Wander")
@export_range(10.0, 800.0, 5.0) var wander_radius: float = 200.0
@export_range(5.0, 400.0, 5.0) var wander_speed: float = 55.0
@export_range(0.5, 30.0, 0.1) var retarget_interval: float = 3.0

@export_group("AI Targets")
var target_enemy: Node2D = null
var target_larva: Node2D = null
var target_build_cell: Node2D = null

## Debug
@export_group("Debug")
@export var debug_movement_speed: float = 0

@onready var _visual: Node2D = $Visual
@onready var _wings: Node2D = $Visual/Wings
@onready var _draggable: Area2D = $DraggableComponent
@onready var _juice: JuiceComponent = $JuiceComponent
@onready var _btree: BTPlayer = $BTPlayer

var _t: float = 0.0
var _is_flung: bool = false
var _fling_time: float = 0.0
var _last_speed: float = 0.0

# Wander internal states
var _wander_home: Vector2 = Vector2.ZERO
var _wander_target: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0


func _ready() -> void:
	_juice.target = _visual
	_t = randf() * TAU

	_draggable.grabbed.connect(_on_grabbed)
	_draggable.released.connect(_on_released)
	body_entered.connect(_on_body_entered)

	_visual.scale = Vector2.ZERO
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
		.tween_property(_visual, "scale", Vector2.ONE, emerge_duration)


func set_wander_home(pos: Vector2) -> void:
	_wander_home = pos
	_pick_wander_target()


func _pick_wander_target() -> void:
	var angle: float = randf_range(0.0, TAU)
	var dist: float = sqrt(randf()) * wander_radius
	_wander_target = _wander_home + Vector2(cos(angle), sin(angle)) * dist
	_wander_timer = retarget_interval * randf_range(0.7, 1.3)


# Called continuously by Idle.gd BTAction
func wander(delta: float) -> void:
	_wander_timer -= delta
	var to_target: Vector2 = _wander_target - global_position
  
	if _wander_timer <= 0.0 or to_target.length() < 18.0:
		_pick_wander_target()
	
	steer_towards(_wander_target, delta, wander_speed)


func _on_grabbed() -> void:
	_is_flung = false
	_btree.active = false


func _on_released() -> void:
	_is_flung = true
	_fling_time = 0.0
	_btree.active = false


func _physics_process(delta: float) -> void:
	_last_speed = linear_velocity.length()
	if not _is_flung:
		return

	_fling_time += delta
	if _last_speed > resume_wander_speed and _fling_time < max_fling_time:
		return

	_btree.active = true
	_is_flung = false
	if rehome_on_landing:
		set_wander_home(global_position)


func _on_body_entered(_body: Node) -> void:
	if _last_speed < impact_speed:
		return
	_juice.punch(0.78, 0.28)
	if _last_speed > impact_speed * 2.0:
		_juice.burst()
	slammed.emit(_last_speed)


func _process(delta: float) -> void:
	_t += delta

	var speed: float = linear_velocity.length()
	if speed > 5.0:
		_visual.rotation = lerp_angle(_visual.rotation, linear_velocity.angle(), facing_smoothing)

	_visual.position.y = sin(_t * TAU / bob_period) * bob_amount
	var flap: float = wing_frequency * (1.0 + speed / 120.0)
	_wings.scale.y = 0.35 + 0.65 * absf(sin(_t * flap))


func attack_enemy() -> void:
	if target_enemy == null or not is_instance_valid(target_enemy):
		return
  
	if target_enemy.has_method("take_damage"):
		target_enemy.take_damage(damage, global_position)
	# TODO: Add a cooldown


func steer_towards(target_pos: Vector2, _delta: float, move_speed: float = 55.0, steering_weight: float = 0.08) -> void:
	if _is_flung:
		return

	var to_target: Vector2 = target_pos - global_position
	var desired: Vector2 = to_target.normalized() * move_speed
	linear_velocity = linear_velocity.lerp(desired, steering_weight)


func drop_carried_resource() -> void:
  # TODO: Implement logic to drop food/cardboard
	pass
