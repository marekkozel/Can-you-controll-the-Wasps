@tool
class_name HungerComponent
extends Node

# 饥饿循环 / hunger cycle: 饱腹 -> 饥饿窗口 -> 窗口内没喂满就饿死。
# 只管状态和计时，长什么样交给持有方 / timing only, visuals belong to the owner.

signal became_hungry
signal fed(current: int, required: int)
signal satisfied
signal starved

enum State { SATIATED, HUNGRY, DEAD }

## 吃饱之后多久再饿 / how long until hungry again
@export_range(1.0, 600.0, 1.0) var satiated_duration: float = 60.0
## 饿了之后有多久可以补救 / rescue window once hungry
@export_range(1.0, 120.0, 1.0) var hunger_window: float = 20.0
## 喂饱要几单位 / units needed to satisfy
@export_range(1, 10, 1) var required_units: int = 3
## 饱腹期最后这一段就开始算"快饿了"，urgency() 从这里起爬。蜂还要飞过去、采、
## 再搬回来，等它真饿了才起需求就已经晚了
## The tail of the satiated phase that already reads as hunger - a hauler needs lead time.
@export_range(0.0, 1.0, 0.05) var lead_ratio: float = 0.35

@export var active: bool = true:
	set(value):
		active = value
		set_process(active and state != State.DEAD and not Engine.is_editor_hint())

var state: State = State.SATIATED
var units: int = 0
var time_left: float = 0.0


func _ready() -> void:
	time_left = satiated_duration
	set_process(active and not Engine.is_editor_hint())


func is_hungry() -> bool:
	return state == State.HUNGRY


# 当前这一段还剩多少，饱腹和饥饿都算。饱腹那 60 秒是预告期，也该有读数
# Remaining ratio of whichever phase is running - the satiated stretch is the heads-up.
func phase_ratio() -> float:
	match state:
		State.SATIATED:
			return clampf(time_left / maxf(satiated_duration, 0.01), 0.0, 1.0)
		State.HUNGRY:
			return clampf(time_left / maxf(hunger_window, 0.01), 0.0, 1.0)
	return 0.0


# 饥饿窗口剩余比例 0~1，不在饥饿状态返回 0 / remaining ratio, 0 when not hungry
func hunger_ratio() -> float:
	if state != State.HUNGRY:
		return 0.0
	return clampf(time_left / maxf(hunger_window, 0.01), 0.0, 1.0)


# 连续紧迫度 0~1。饱腹期前段是 0，最后 lead_ratio 那一截爬到 HUNGRY_ONSET，
# 饥饿窗口里再从 HUNGRY_ONSET 爬到 1。hunger_ratio() 是个阶跃，需求侧不能用它
# hunger_ratio() is a step function; a demand curve needs this ramp instead.
const HUNGRY_ONSET: float = 0.5

func urgency() -> float:
	match state:
		State.SATIATED:
			if lead_ratio <= 0.0:
				return 0.0
			var left: float = clampf(time_left / maxf(satiated_duration, 0.01), 0.0, 1.0)
			if left >= lead_ratio:
				return 0.0
			return (1.0 - left / lead_ratio) * HUNGRY_ONSET
		State.HUNGRY:
			var remain: float = clampf(time_left / maxf(hunger_window, 0.01), 0.0, 1.0)
			return HUNGRY_ONSET + (1.0 - HUNGRY_ONSET) * (1.0 - remain)
	return 0.0


# 喂一口。只有饿着的时候才吃 / only eats while hungry, returns whether accepted
func feed(amount: int = 1) -> bool:
	if state != State.HUNGRY or amount <= 0:
		return false

	units = mini(units + amount, required_units)
	fed.emit(units, required_units)
	if units >= required_units:
		_become_satiated()
	return true


func _process(delta: float) -> void:
	if state == State.DEAD:
		return

	time_left -= delta
	if time_left > 0.0:
		return

	if state == State.SATIATED:
		state = State.HUNGRY
		units = 0
		time_left = hunger_window
		became_hungry.emit()
		return

	# 窗口走完还没喂满，攒的份数不保留 / partial units are lost on starve
	state = State.DEAD
	units = 0
	time_left = 0.0
	set_process(false)
	starved.emit()


func _become_satiated() -> void:
	state = State.SATIATED
	units = 0
	time_left = satiated_duration
	satisfied.emit()
