@tool
class_name HoldComponent
extends Node

# 按住 N 秒 / hold-to-activate.
# 不自己收输入，由父节点调 press() / release()，这样按钮和 Area2D 都能用。
# 松手不清零，按 decay_multiplier 倍速往回退，退完之前重新按住能接上。

signal hold_started
signal hold_progress(t: float)  # 0~1，按住和回退时都会发
signal hold_tick(index: int)    # 每满一秒一次，给节奏感
signal hold_completed
signal hold_cancelled

@export_range(0.1, 30.0, 0.1) var hold_duration: float = 5.0
## 松手后回退速度是前进的几倍
@export_range(0.1, 10.0, 0.1) var decay_multiplier: float = 2.0
@export var enabled: bool = true:
	set(value):
		enabled = value
		if not enabled:
			cancel()

var progress: float = 0.0

var _is_holding: bool = false
var _last_tick: int = 0


func _ready() -> void:
	set_process(false)


func is_holding() -> bool:
	return _is_holding


func press() -> void:
	if not enabled or _is_holding:
		return
	_is_holding = true
	_last_tick = int(progress * hold_duration)
	set_process(true)
	hold_started.emit()


func release() -> void:
	if not _is_holding:
		return
	_is_holding = false
	hold_cancelled.emit()  # 只是"手松了"，进度还在往回退


# 直接归零，不走回退
func cancel() -> void:
	var was_active: bool = _is_holding or progress > 0.0
	_is_holding = false
	progress = 0.0
	_last_tick = 0
	set_process(false)
	if was_active:
		hold_progress.emit(0.0)
		hold_cancelled.emit()


func _process(delta: float) -> void:
	var before: float = progress
	var step: float = delta / maxf(hold_duration, 0.01)

	if _is_holding:
		progress = minf(progress + step, 1.0)
	else:
		progress = maxf(progress - step * decay_multiplier, 0.0)
		if progress < 0.0005:
			progress = 0.0  # 不吸到 0 的话会留 3e-9 这种残值，描边环清不干净

	# 这里必须精确比较：残值和 0 在 is_equal_approx 眼里相等，就不会发最后那次归零
	if progress != before:
		hold_progress.emit(progress)

	if _is_holding:
		var tick: int = int(progress * hold_duration)
		if tick > _last_tick:
			_last_tick = tick
			hold_tick.emit(tick)

		if progress >= 1.0:
			_is_holding = false
			progress = 0.0
			_last_tick = 0
			set_process(false)
			hold_progress.emit(0.0)
			hold_completed.emit()
		return

	_last_tick = int(progress * hold_duration)
	if progress <= 0.0:
		set_process(false)
