class_name Egg
extends Node2D

# 一颗卵 / an egg. 出场弹一下、常驻呼吸，到点孵化 / pops in, breathes, then hatches.
# 计时交给 MaturationComponent，跟封盖羽化是同一个组件 / same timer component as the cap.

signal hatched(egg: Egg)
## 孵化进度 0~1。之前 MaturationComponent 的信号没接到任何地方，这一段是全黑的
## Hatching progress - this used to go nowhere, leaving the whole stretch unreadable.
signal progress_changed(t: float)

@export_range(0.05, 2.0, 0.05) var pop_duration: float = 0.35
@export_range(0.0, 0.3, 0.01) var breathe_amount: float = 0.06
@export_range(0.2, 5.0, 0.1) var breathe_period: float = 1.4

## 孵化时长倍率，QUICK HATCH 用。**要在 add_child 之前设**——组件是 autostart，
## 一入树就按原时长跑起来了，这里只能把它重开
## Set before the egg enters the tree: the component autostarts and this restarts it.
var hatch_scale: float = 1.0

@onready var _maturation: MaturationComponent = $MaturationComponent

var _breathe: Tween


func _ready() -> void:
	_maturation.matured.connect(func(): hatched.emit(self))
	if not is_equal_approx(hatch_scale, 1.0):
		_maturation.start(_maturation.duration * hatch_scale)
	_maturation.progress_changed.connect(func(t: float): progress_changed.emit(t))

	scale = Vector2.ZERO
	var pop: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(self, "scale", Vector2.ONE, pop_duration)
	pop.finished.connect(_start_breathing)


func _start_breathing() -> void:
	if _breathe != null and _breathe.is_valid():
		_breathe.kill()
	var big: Vector2 = Vector2.ONE * (1.0 + breathe_amount)
	_breathe = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_breathe.tween_property(self, "scale", big, breathe_period * 0.5)
	_breathe.tween_property(self, "scale", Vector2.ONE, breathe_period * 0.5)
