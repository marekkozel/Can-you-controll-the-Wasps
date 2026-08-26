class_name Wasp
extends RigidBody2D

# 黄蜂 / a wasp. 会随机游荡，也能被抓起来甩出去撞墙 / wanders, can be grabbed and flung.
# 真正的行为要走 limboai 的行为树，是另一个任务 / real AI is a separate task.
#
# 朝向、悬停、扇翅都作用在 Visual 上，根节点留给物理和 AI / animate Visual, not the root,
# 不然移动逻辑会跟这里的动画抢同一个属性 / else movement fights the animation.

## 撞到东西时发出，参数是撞击瞬间的速度 / emitted on impact, carries the impact speed
signal slammed(speed: float)

@export_range(0.05, 2.0, 0.05) var emerge_duration: float = 0.45
## 悬停时上下浮动的幅度 / hover bob amplitude
@export_range(0.0, 20.0, 0.5) var bob_amount: float = 3.5
@export_range(0.1, 5.0, 0.1) var bob_period: float = 1.6
## 翅膀基础扇动频率，飞得越快扇得越急 / wing flap, scales with speed
@export_range(1.0, 60.0, 1.0) var wing_frequency: float = 18.0
## 转向跟随的平滑度 / how fast it turns to face travel direction
@export_range(0.02, 1.0, 0.01) var facing_smoothing: float = 0.15

@export_group("Fling")
## 甩出去后速度掉到这个值以下才恢复游荡 / wander resumes once it slows to this
@export_range(10.0, 600.0, 5.0) var resume_wander_speed: float = 140.0
## 保险：最多飞这么久就强制恢复，免得卡在墙角一直不落地 / safety timeout
@export_range(0.5, 20.0, 0.5) var max_fling_time: float = 6.0
## 落地后就地安家，而不是飞回原来的活动区 / settle where it lands
@export var rehome_on_landing: bool = true
## 撞击速度超过这个值才给反馈 / minimum speed to trigger impact feedback
@export_range(20.0, 2000.0, 10.0) var impact_speed: float = 260.0

@onready var _visual: Node2D = $Visual
@onready var _wings: Node2D = $Visual/Wings
@onready var _draggable: Area2D = $DraggableComponent
@onready var _wander: WanderComponent = $WanderComponent
@onready var _juice: JuiceComponent = $JuiceComponent

var _t: float = 0.0
var _is_flung: bool = false
var _fling_time: float = 0.0
var _last_speed: float = 0.0


func _ready() -> void:
	_juice.target = _visual
	_t = randf() * TAU  # 错开相位，多只不会整齐划一 / desync so wasps don't move in lockstep

	_draggable.grabbed.connect(_on_grabbed)
	_draggable.released.connect(_on_released)
	body_entered.connect(_on_body_entered)

	_visual.scale = Vector2.ZERO
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
		.tween_property(_visual, "scale", Vector2.ONE, emerge_duration)


# 生成方摆好位置之后调一次 / call once after the spawner has positioned it
func set_wander_home(position: Vector2) -> void:
	_wander.set_home(position)


func _on_grabbed() -> void:
	# 拖着的时候别让游荡去抢 linear_velocity / wander must not fight the drag
	_is_flung = false
	_wander.enabled = false


func _on_released() -> void:
	# 关键：甩出去这段时间也别让游荡接管，不然刚甩出去就被 lerp 拽回去
	# Key bit: keep wander off while it flies, or the throw gets steered away instantly.
	_is_flung = true
	_fling_time = 0.0
	_wander.enabled = false


func _physics_process(delta: float) -> void:
	_last_speed = linear_velocity.length()
	if not _is_flung:
		return

	_fling_time += delta
	if _last_speed > resume_wander_speed and _fling_time < max_fling_time:
		return

	_is_flung = false
	if rehome_on_landing:
		_wander.set_home(global_position)
	_wander.enabled = true


func _on_body_entered(_body: Node) -> void:
	if _last_speed < impact_speed:
		return
	# 撞墙的手感：横向压扁一下再弹回，快的话再爆点粒子
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
	# 翅膀只压扁 y，看起来就是在扇 / squashing y alone reads as flapping
	var flap: float = wing_frequency * (1.0 + speed / 120.0)
	_wings.scale.y = 0.35 + 0.65 * absf(sin(_t * flap))
