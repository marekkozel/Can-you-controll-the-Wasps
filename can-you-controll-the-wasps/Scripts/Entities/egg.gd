class_name Egg
extends Node2D

# 一颗卵 / an egg. 出场弹一下、常驻呼吸，到点孵化。

signal hatched(egg: Egg)

## 多久孵出幼虫
@export_range(1.0, 120.0, 1.0) var hatch_duration: float = 10.0
@export_range(0.05, 2.0, 0.05) var pop_duration: float = 0.35
@export_range(0.0, 0.3, 0.01) var breathe_amount: float = 0.06
@export_range(0.2, 5.0, 0.1) var breathe_period: float = 1.4

var _time_left: float = 0.0
var _breathe: Tween


func _ready() -> void:
	_time_left = hatch_duration
	scale = Vector2.ZERO
	var pop: Tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(self, "scale", Vector2.ONE, pop_duration)
	pop.finished.connect(_start_breathing)


func _process(delta: float) -> void:
	_time_left -= delta
	if _time_left > 0.0:
		return
	set_process(false)
	hatched.emit(self)


func _start_breathing() -> void:
	if _breathe != null and _breathe.is_valid():
		_breathe.kill()
	var big: Vector2 = Vector2.ONE * (1.0 + breathe_amount)
	_breathe = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_breathe.tween_property(self, "scale", big, breathe_period * 0.5)
	_breathe.tween_property(self, "scale", Vector2.ONE, breathe_period * 0.5)
