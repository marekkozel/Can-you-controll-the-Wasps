# 骚扰 / harass: 叛军扑上去咬最近的自己人。
#
# 优先级压在 Sabotage 之下——拆巢才是它们的正事，打蜂是没巢可拆时干的。
# 挨咬的一方**不会还手**：Defend 只认 Enemy 组，叛军留在 wasps 组里，
# 所以普通工蜂始终把它们当自己人。清场是玩家一个人的活。
# The victims never fight back - Defend only looks at the Enemy group, and rebels are
# still wasps. Culling them is the player's job alone.
class_name Harass
extends BTAction

## 咬得到的距离。要大于两只蜂碰撞半径之和 / must clear both collision radii
@export var reach: float = 34.0
## 追击速度，比巡航快 / faster than a cruise
@export var chase_speed: float = 130.0

const WASP_GROUP: StringName = &"wasps"


func _tick(delta: float) -> Status:
	# 每帧重选：目标会被咬死，也可能被玩家一把拎走
	# Retarget every tick - victims die, and the player can pluck one out mid-chase.
	var victim: Wasp = _closest_victim()
	if victim == null:
		return FAILURE

	agent.steer_towards(victim.global_position, delta, chase_speed)
	if agent.global_position.distance_to(victim.global_position) > reach:
		return RUNNING

	# attack_enemy 走的是黄蜂现成的叮咬路径（带冷却），目标只要有 take_damage 就行
	# Reuses the wasp's own sting path, cooldown and all; any take_damage will do.
	agent.target_enemy = victim
	if agent.attack_enemy():
		return SUCCESS
	return RUNNING


func _exit() -> void:
	agent.target_enemy = null


# 只咬看得见的。全知的叛军会为了一只在地图另一头的蜂横穿整张图
# Local sight only, or a rebel crosses the whole map for a wasp it could not possibly see.
func _closest_victim() -> Wasp:
	# 生它的那只不咬。不加类型：她随时可能被玩家处决，类型化变量拒绝存已释放的实例
	# Untyped - she can be stung at any moment and a typed slot would throw on the corpse.
	var mother = agent.allegiance().mother
	if not is_instance_valid(mother):
		mother = null

	var best: Wasp = null
	var best_dist: float = INF
	for node in agent.get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Wasp = node as Wasp
		if wasp == null or wasp == agent or wasp.allegiance().is_rebel():
			continue
		# 叛军是从她下的卵里孵出来的，扑上去咬自己的妈说不通
		# It hatched from her egg; hunting her down makes no sense.
		if wasp == mother:
			continue
		if not agent.can_see(wasp.global_position):
			continue
		var dist: float = agent.global_position.distance_to(wasp.global_position)
		if dist < best_dist:
			best_dist = dist
			best = wasp
	return best
