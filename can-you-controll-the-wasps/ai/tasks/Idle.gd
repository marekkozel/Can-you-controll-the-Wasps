# 待机 / idle: 没别的事干就飘回巢里徘徊。
#
# **这不是一个待机动画，是一张牌桌。** 散在整张地图上的蜂没法互相比较，玩家只能一只只看；
# 闲下来的蜂都聚回巢室区之后，才第一次出现"十几只蜂在同一个空间里做同一类事"的画面，
# 而"这只跟别的不太一样"要成立，前提就是这个画面。
# The point is comparison: a swarm spread across the map cannot be read against itself.
#
# 副作用是巢里的闲蜂数量本身成了一个读数——活多的时候蜂都散出去了，你没法观察；
# 想看清楚就得先把经济做顺。观察是有成本的 / watching costs you something.
#
# 必须返回 SUCCESS：BTSelector 是带记忆的，子节点 RUNNING 它下帧就只继续跑那一个，
# 整棵树会永远钉在 Idle 上。SUCCESS 让这一轮结束，下帧从 Defend 重新评一遍。
# RUNNING would pin the memory-selector here forever; SUCCESS ends the round so the
# next tick re-evaluates from the top.
class_name Idle
extends BTAction

const HIVE_GROUP: StringName = &"hive"


func _tick(delta: float) -> Status:
	if not agent.has_method("wander"):
		return SUCCESS

	# 巢还没生成（或者这只蜂根本不在有巢的场景里）就退回原地游荡，别硬飞去 (0,0)
	# No hive yet - fall back to drifting in place rather than flying to the origin.
	var hive: Node2D = agent.get_tree().get_first_node_in_group(HIVE_GROUP) as Node2D
	if hive == null:
		agent.wander(delta)
		return SUCCESS

	agent.wander(delta, hive.global_position, agent.loiter_radius, agent.loiter_speed)
	return SUCCESS
