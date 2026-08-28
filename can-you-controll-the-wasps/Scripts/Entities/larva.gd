@tool
class_name Larva
extends Node2D

# 幼虫 / larva. 身体是一条 Line2D，每帧按正弦重算控制点 / spine rebuilt per frame.
# 看起来是从巢室里钻出来扭动的毛毛虫，根部不动，越往头部摆幅越大 / root pinned, tip sways.
# 摆幅和频率绑在饥饿状态上，饿了扭得又急又大 / wiggle doubles as the hunger tell.

signal became_hungry(larva: Larva)
signal fed(larva: Larva, current: int, required: int)
signal satisfied(larva: Larva)
signal starved(larva: Larva)
## 倒计时，饱腹和饥饿两段都发。critical = 已经在救援窗口里了
## Both phases report here; critical means the rescue window is already running.
signal timer_changed(t: float, critical: bool)



@export_group("Shape")
## 从根部钻出来的长度 / how far it pokes out
@export_range(6.0, 80.0, 1.0) var length: float = 26.0
## 往哪边钻出来 / direction it emerges towards
@export var emerge_direction: Vector2 = Vector2.UP

@export_group("Colors")
@export var calm_color: Color = Color(0.93, 0.89, 0.74)
@export var hungry_color: Color = Color(0.95, 0.62, 0.25)
@export var dead_color: Color = Color(0.34, 0.29, 0.22)

@onready var _body: Sprite2D = $Body
@onready var _hunger: HungerComponent = $HungerComponent
@onready var _juice: JuiceComponent = $JuiceComponent

var _is_dead: bool = false

# I am adding the concept of rezervation, so only few wasps can feed this larvae and not all of them at once.
var claimed_by: int = 0

# Called by BTCondition script
func can_be_claimed() -> bool:
	return claimed_by < (_hunger.required_units - _hunger.units) and is_hungry()

# Called by BTAction script when starting the feed sequence
func claim() -> void:
	claimed_by += 1

func unclaim() -> void:
	claimed_by -= 1


func _ready() -> void:
	_juice.target = $Body
	_body.self_modulate = calm_color
	_body.rotation = emerge_direction.angle() + PI * 0.5  # 贴图朝上画的 / the sprite is drawn pointing up

	if Engine.is_editor_hint():
		set_process(false)
		return

	_hunger.became_hungry.connect(_on_became_hungry)
	_hunger.fed.connect(_on_fed)
	_hunger.satisfied.connect(_on_satisfied)
	_hunger.starved.connect(_on_starved)


func _process(_delta: float) -> void:
	timer_changed.emit(_hunger.phase_ratio(), _hunger.is_hungry())


# FAT RESERVES。饱腹期一变，正在跑的那一段也要跟着重置——组件 _ready 时就按
# 原时长起表了，只改上限的话这一轮还是老数
# The component already started its clock, so the running phase has to be re-armed.
func scale_satiation(factor: float) -> void:
	if factor <= 1.0:
		return
	_hunger.satiated_duration *= factor
	_hunger.time_left = _hunger.satiated_duration


func feed(amount: int = 1) -> bool:
	return _hunger.feed(amount)


func is_hungry() -> bool:
	return _hunger.is_hungry()


# 饱饵时返回 0，饿着时 1→ 0 倒数，越小越急 / 0 when fed, counts 1 -> 0 while starving
func hunger_ratio() -> float:
	return _hunger.hunger_ratio()


# ---------------- 身体 / body ----------------

# ---------------- 状态反馈 / state feedback ----------------

func _on_became_hungry() -> void:
	_tint(hungry_color, 0.4)
	became_hungry.emit(self)


func _on_fed(current: int, required: int) -> void:
	_juice.punch(1.12, 0.22)
	_juice.burst()
	fed.emit(self, current, required)


func _on_satisfied() -> void:
	_tint(calm_color, 0.5)
	_juice.punch(1.18, 0.4)
	satisfied.emit(self)


func _on_starved() -> void:
	_is_dead = true
	_tint(dead_color, 0.8)
	set_process(false)
	_slump()
	starved.emit(self)


# 死了就塌下去，缩到一半高 / on death it slumps to half height
func _slump() -> void:
	create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN) 		.tween_property(_body, "scale:y", 0.45, 0.7)


func _tint(color: Color, duration: float) -> void:
	if Engine.is_editor_hint():
		_body.self_modulate = color
		return
	create_tween().tween_property(_body, "self_modulate", color, duration)
