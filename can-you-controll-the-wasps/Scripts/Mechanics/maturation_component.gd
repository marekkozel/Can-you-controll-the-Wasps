@tool
class_name MaturationComponent
extends Node

# 定时成熟 / timed maturation: 跑够 duration 就发 matured。
# 卵孵化、封盖羽化都用它。默认不自动开始，由持有方调 start() / shared by egg and cap.

signal matured
signal progress_changed(t: float)  # 0~1，接到 BroodTimer 上就能看见倒计时 / wire to a BroodTimer to show it

@export_range(0.1, 600.0, 0.1) var duration: float = 10.0
## 入树就开始跑 / start as soon as it enters the tree
@export var autostart: bool = false

var _time_left: float = 0.0
var _running: bool = false


func _ready() -> void:
	set_process(false)
	if autostart and not Engine.is_editor_hint():
		start()


# 传 override 可以临时换时长，不改 duration 本身 / override without touching duration
func start(override_duration: float = -1.0) -> void:
	if Engine.is_editor_hint():
		return
	var total: float = override_duration if override_duration > 0.0 else duration
	_time_left = total
	_running = true
	set_process(true)
	progress_changed.emit(0.0)


func stop() -> void:
	_running = false
	_time_left = 0.0
	set_process(false)


func is_running() -> bool:
	return _running


func progress() -> float:
	if not _running or duration <= 0.0:
		return 0.0
	return clampf(1.0 - _time_left / duration, 0.0, 1.0)


func _process(delta: float) -> void:
	_time_left -= delta
	if _time_left > 0.0:
		progress_changed.emit(progress())
		return

	_running = false
	_time_left = 0.0
	set_process(false)
	progress_changed.emit(1.0)
	matured.emit()
