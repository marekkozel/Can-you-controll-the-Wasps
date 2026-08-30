class_name HitStop
extends RefCounted

# 全局卡顿 / global hit stop. 停半拍的唯一入口，Engine.time_scale 只准这里写。
#
# **必须只有一个所有者**。各写各的"存档-还原"在重叠时会互相还原对方的减速值：
# 加冕停 0.15 的那半拍里敌人挨一下打，敌人存下的"原值"就是 0.15，等它还原完，
# 整局就永远停在 15% 速度上——而且不会自己恢复
# One owner only. Two independent save/restore pairs restore each other's slowed value
# when they overlap, and the game never comes back to full speed.

## 已经在停了 / a freeze is running
static var _held: bool = false
## 停之前的全局倍率，由**最外层**那次捕获 / captured by the outermost hold
static var _baseline: float = 1.0


## 停半拍。已经在停就直接忽略这一次——排队或叠加只会让停顿变长，
## 而卡顿的意义是"一下"，不是"一段" / ignored while one is running
static func hold(tree: SceneTree, duration: float, scale: float) -> void:
	if tree == null or duration <= 0.0 or _held:
		return
	_held = true
	# 基准是进来时的值，不是写死的 1.0：调试面板的时间倍率是合法的非 1 值，
	# 硬还原会把它吃掉 / the debug key legitimately owns a non-1.0 scale
	_baseline = Engine.time_scale
	Engine.time_scale = scale

	# 计时器要 ignore_time_scale，否则减速会把它自己拖长，越慢回得越晚。
	# process_always 是为了年终结算那次真暂停：暂停期间它也得走完
	# Ignores time_scale or it would stretch itself; ticks while the year report pauses.
	var timer: SceneTreeTimer = tree.create_timer(duration, true, false, true)
	await timer.timeout

	# 还原挂在**静态函数**上，不挂调用方。挂调用方的话，刚被打死的敌人在这半拍里
	# 被 queue_free()，协程跟着没了，时间就再也回不来
	# Static, so a caller freed mid-freeze cannot take the restore down with it.
	Engine.time_scale = _baseline
	_held = false


## 调试用的兜底：把时间掰回正常 / debug escape hatch
static func release() -> void:
	Engine.time_scale = 1.0
	_baseline = 1.0
	_held = false
