# 待机：没别的事干就在 home 附近游荡 / idle: wander around home when nothing else applies.
# 必须返回 SUCCESS：BTSelector 是带记忆的，子节点 RUNNING 它下帧就只继续跑那一个，
# 整棵树会永远钉在 Idle 上。SUCCESS 让这一轮结束，下帧从 Defend 重新评一遍。
# RUNNING would pin the memory-selector here forever; SUCCESS ends the round so the
# next tick re-evaluates from the top.
class_name Idle
extends BTAction


func _tick(delta: float) -> Status:
	if agent.has_method("wander"):
		agent.wander(delta)

	return SUCCESS
