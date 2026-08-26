@tool
class_name JuiceComponent
extends Node2D

# 通用反馈效果 / feedback effects: punch, shake, flash, burst.
# 挂到实体下，target 指向要被缩放/抖动的那一层 / target is the layer that gets animated.
# 千万别把 target 指到 Area2D 上，命中区会跟着抖 / never target the Area2D, hitbox would shake.

## 被 punch / shake 作用的节点，一般是实体的 Visual 层 / usually the entity's Visual node.
## 在场景里连 NodePath 解析不出来，由持有方在 _ready() 里赋值 / assign it from code
@export var target: Node2D

## 抖动频率 Hz。逐帧取随机数等于 60Hz 白噪声，又刺又乱 / per-frame random reads as harsh noise,
## 所以走平滑正弦；x/y 频率错开，走小八字 / so use a smooth sine, x and y offset for a figure-eight
@export_range(0.5, 30.0, 0.5) var shake_frequency: float = 5.0

## 抖动幅度（像素），设 0 停止 / shake amplitude in px, 0 stops it
var shake_amount: float = 0.0:
	set(value):
		shake_amount = maxf(value, 0.0)
		if is_zero_approx(shake_amount):
			set_process(false)
			if target != null:
				target.position = _base_position
		else:
			if not is_processing():
				_base_position = target.position if target != null else Vector2.ZERO
				_shake_time = 0.0
			set_process(true)

var _base_position: Vector2 = Vector2.ZERO
var _shake_time: float = 0.0
var _punch_tween: Tween
var _flash_tween: Tween

@onready var _burst: CPUParticles2D = $Burst


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	if target == null:
		return
	_shake_time += delta * shake_frequency * TAU
	var offset: Vector2 = Vector2(sin(_shake_time), sin(_shake_time * 1.37 + 1.1)) * shake_amount
	target.position = _base_position + offset


# 缩放弹一下。amount < 1 是按下去，> 1 是弹出来 / <1 presses in, >1 pops out
func punch(amount: float = 1.15, duration: float = 0.25) -> void:
	if target == null or Engine.is_editor_hint():
		return
	if _punch_tween != null and _punch_tween.is_valid():
		_punch_tween.kill()
	target.scale = Vector2.ONE * amount
	_punch_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_punch_tween.tween_property(target, "scale", Vector2.ONE, duration)


# 把 item 刷成 color 再退回 restore / flash to color, tween back to restore
func flash(item: CanvasItem, color: Color, restore: Color, duration: float = 0.45) -> void:
	if item == null or Engine.is_editor_hint():
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	item.set("color", color)
	_flash_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(item, "color", restore, duration)


# 闪色期间调用方别抢同一个颜色属性 / don't fight the flash tween over the same property
func is_flashing() -> bool:
	return _flash_tween != null and _flash_tween.is_valid()


func burst() -> void:
	if Engine.is_editor_hint() or _burst == null:
		return
	_burst.restart()
