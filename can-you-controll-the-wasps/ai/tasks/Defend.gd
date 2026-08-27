class_name Defend
extends BTAction

## Wasps attacking range
@export var attack_distance: float = 50.0
## Wasps fly faster when angry
@export var chase_speed: float = 150.0
## 敌人进到这个半径内才管 / only engage enemies this close
@export var alert_radius: float = 200.0

# 别在这里做副作用。任务每帧都会进来一次，_tick 返回 FAILURE 就退出，下帧重来——
# 在 _enter 里扔货等于每秒把黄蜂手上的东西抢掉 60 次。
# Never put side effects here: a failing task re-enters every frame, so dropping cargo
# in _enter stripped the wasp's load 60 times a second.
func _enter() -> void:
	agent.target_enemy = null

func _tick(delta: float) -> Status:
	# 采集岗不打架，扔到巢边的那批才是卫兵。不分岗的话场上总有敌人，
	# Defend 会把每一只黄蜂吃死，后面的采集分支永远轮不上
	# Gatherers work, hive-posted wasps fight. Without this gate a permanently populated
	# enemy band keeps every wasp in Defend and the gather branches never run.
	if agent.job != Wasp.Job.HIVE:
		return FAILURE

	# 每帧重选最近目标：敌人会新生成，黄蜂也可能被玩家扔到别处
	# Retarget every tick - enemies keep spawning and the player can fling wasps away.
	var enemies: Array = agent.get_tree().get_nodes_in_group("Enemy")
	agent.target_enemy = _find_closest_enemy(enemies)

	# 场上没敌人（或正在追的那只刚被点死）就交给下一条分支
	# No enemy left - hand over to the next branch. Must come after the retarget above,
	# 否则 target_enemy 刚被置 null 就去取 global_position，直接崩
	if not is_instance_valid(agent.target_enemy):
		return FAILURE

	# 确定真要打了才扔货 / only ditch the cargo once we are committed to a target
	if agent.has_method("drop_carried_resource"):
		agent.drop_carried_resource()

	var dist_to_enemy: float = agent.global_position.distance_to(agent.target_enemy.global_position)

	if agent.has_method("steer_towards"):
		agent.steer_towards(agent.target_enemy.global_position, delta, chase_speed)

	# 到位了就叮一下；冷却未好时继续 RUNNING 贴着敌人，不让树切走
	# In range: sting. While on cooldown stay RUNNING and hover on the target.
	if dist_to_enemy <= attack_distance and agent.attack_enemy():
		return SUCCESS

	return RUNNING

func _exit() -> void:
	# Clean up the target when we are done defending
	agent.target_enemy = null

func _find_closest_enemy(enemies: Array) -> Node2D:
	var closest_enemy: Node2D = null
	var min_dist: float = INF
	
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		var dist: float = agent.global_position.distance_to(enemy.global_position)
		if dist > alert_radius:
			continue
		if dist < min_dist:
			min_dist = dist
			closest_enemy = enemy

	return closest_enemy
