@tool
class_name Larva
extends Node2D

# 幼虫 / larva. 身体是一条 Line2D，每帧按正弦重算控制点，
# 看起来就是从巢室里钻出来扭动的毛毛虫。根部不动，越往头部摆幅越大。
# 摆动的幅度和频率直接绑在饥饿状态上——饿了扭得又急又大，不用看数字就知道该喂了。

signal became_hungry(larva: Larva)
signal fed(larva: Larva, current: int, required: int)
signal satisfied(larva: Larva)
signal starved(larva: Larva)

@export_group("Shape")
## 体节数，越多越顺滑
@export_range(3, 24, 1) var segment_count: int = 9
## 从根部钻出来的长度
@export_range(6.0, 80.0, 1.0) var length: float = 26.0
## 往哪边钻出来
@export var emerge_direction: Vector2 = Vector2.UP
## 整条身体上的相位差，越大扭得越"波浪"
@export_range(0.5, 8.0, 0.1) var wave_length: float = 2.2

@export_group("Wiggle")
@export_range(0.0, 12.0, 0.1) var calm_amplitude: float = 1.8
@export_range(0.1, 6.0, 0.1) var calm_frequency: float = 0.8
@export_range(0.0, 12.0, 0.1) var hungry_amplitude: float = 4.2
@export_range(0.1, 6.0, 0.1) var hungry_frequency: float = 2.4

@export_group("Colors")
@export var calm_color: Color = Color(0.93, 0.89, 0.74)
@export var hungry_color: Color = Color(0.95, 0.62, 0.25)
@export var dead_color: Color = Color(0.34, 0.29, 0.22)

@onready var _body: Line2D = $Body
@onready var _eyes: Node2D = $Body/Eyes
@onready var _ring: ProgressRing = $Ring
@onready var _hunger: HungerComponent = $HungerComponent
@onready var _juice: JuiceComponent = $JuiceComponent

var _t: float = 0.0
var _amplitude: float = 0.0
var _frequency: float = 0.0
var _is_dead: bool = false


func _ready() -> void:
	_juice.target = $Body
	_amplitude = calm_amplitude
	_frequency = calm_frequency
	_body.default_color = calm_color
	_build_ring()
	_rebuild_body()

	if Engine.is_editor_hint():
		set_process(false)
		return

	_hunger.became_hungry.connect(_on_became_hungry)
	_hunger.fed.connect(_on_fed)
	_hunger.satisfied.connect(_on_satisfied)
	_hunger.starved.connect(_on_starved)


func _process(delta: float) -> void:
	_t += delta * _frequency * TAU
	_rebuild_body()
	if _hunger.is_hungry():
		_ring.set_progress(_hunger.hunger_ratio())


func feed(amount: int = 1) -> bool:
	return _hunger.feed(amount)


func is_hungry() -> bool:
	return _hunger.is_hungry()


# ---------------- 身体 ----------------

func _rebuild_body() -> void:
	var side: Vector2 = emerge_direction.orthogonal().normalized()
	var forward: Vector2 = emerge_direction.normalized()

	var pts: PackedVector2Array = PackedVector2Array()
	for i in segment_count:
		var f: float = float(i) / float(maxi(segment_count - 1, 1))
		# 乘 f 让根部钉在巢室里，只有伸出去的部分在扭
		var sway: float = sin(_t - f * wave_length) * _amplitude * f
		pts.append(forward * (length * f) + side * sway)
	_body.points = pts

	if pts.size() >= 2:
		_eyes.position = pts[pts.size() - 1]
		_eyes.rotation = (pts[pts.size() - 1] - pts[pts.size() - 2]).angle()


func _build_ring() -> void:
	var radius: float = length * 0.62
	var circle: PackedVector2Array = PackedVector2Array()
	for i in 24:
		var a: float = TAU * float(i) / 24.0
		circle.append(Vector2(cos(a), sin(a)) * radius)
	_ring.set_ring_path(circle)
	_ring.set_progress(0.0)


# ---------------- 状态反馈 ----------------

func _on_became_hungry() -> void:
	_amplitude = hungry_amplitude
	_frequency = hungry_frequency
	_tint(hungry_color, 0.4)
	_ring.set_progress(1.0)
	became_hungry.emit(self)


func _on_fed(current: int, required: int) -> void:
	_juice.punch(1.12, 0.22)
	_juice.burst()
	fed.emit(self, current, required)


func _on_satisfied() -> void:
	_amplitude = calm_amplitude
	_frequency = calm_frequency
	_tint(calm_color, 0.5)
	_ring.set_progress(0.0)
	_juice.punch(1.18, 0.4)
	satisfied.emit(self)


func _on_starved() -> void:
	_is_dead = true
	_amplitude = 0.0
	_ring.set_progress(0.0)
	_tint(dead_color, 0.8)
	set_process(false)
	_slump()
	starved.emit(self)


# 死了就塌下去，长度缩一半，看起来是瘫在巢室里
func _slump() -> void:
	var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_method(_set_length, length, length * 0.45, 0.7)
	_eyes.visible = false


func _set_length(value: float) -> void:
	length = value
	_rebuild_body()


func _tint(color: Color, duration: float) -> void:
	if Engine.is_editor_hint():
		_body.default_color = color
		return
	create_tween().tween_property(_body, "default_color", color, duration)
