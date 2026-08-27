# 待机：没别的事干就在 home 附近游荡 / idle: wander around home when nothing else applies.
# 它是 Selector 的兵局，永远 RUNNING，等更高优先级的分支把它抢走。
# Last resort in the Selector - stays RUNNING so higher-priority branches preempt it.
class_name Idle
extends BTAction


func _tick(delta: float) -> Status:
	if agent.has_method("wander"):
		agent.wander(delta)

	# 返回 SUCCESS 会让整棵树每帧从头重评，_enter/_exit 也跟着空转
	# SUCCESS here would re-evaluate the whole tree every frame for nothing.
	return RUNNING
