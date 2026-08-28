class_name Defend
extends BTAction

## Wasps attacking range
@export var attack_distance: float = 50.0
## Wasps fly faster when angry
@export var chase_speed: float = 150.0
## 平时敌人进到这个半径内才管 / peacetime engagement radius
@export var alert_radius: float = 200.0
## 警报期间的集结半径。要够横穿地图，1280x720 的场子对角约 1470
## Rally radius during a raid - must span the map, this one's diagonal is about 1470.
@export var raid_alert_radius: float = 900.0
## 敌人摸到巢这么近，就算不在正式入侵期也当警报处理
## An enemy this close to the hive raises the alarm even outside a scheduled raid.
@export var hive_alarm_radius: float = 260.0

const HIVE_GROUP: StringName = &"hive"
const ENEMY_GROUP: StringName = &"Enemy"

# 别在这里做副作用。任务每帧都会进来一次，_tick 返回 FAILURE 就退出，下帧重来——
# 在 _enter 里扔货等于每秒把黄蜂手上的东西抢掉 60 次。
# Never put side effects here: a failing task re-enters every frame, so dropping cargo
# in _enter stripped the wasp's load 60 times a second.
func _enter() -> void:
	agent.target_enemy = null

func _tick(delta: float) -> Status:
	# 平时只有守巢岗应战。不分岗的话场上总有敌人，Defend 会把每一只黄蜂吃死，
	# 后面的采集分支永远轮不上——这条门当年就是为了这个加的
	# Peacetime: only hive-posted wasps fight. Without this gate the gather branches
	# never run, which is exactly why it exists.
	#
	# 问的是"玩家把它扔在巢边了吗"，不是"它这会儿闲着吗"。阈值模型上线之后
	# job == HIVE 的含义变成了后者，照旧用它会让全部闲蜂变成卫兵
	# Asks whether the player posted it here, not whether it happens to be idle.
	#
	# 警报期间门槛降下来，采集蜂也可能回防。这只有在入侵会结束的前提下才安全，
	# RaidDirector 的 raid_duration 就是那个前提
	# A raid lowers the bar. Safe only because raids end - see RaidDirector.raid_duration.
	# 敌人已经在啃巢的时候没人管，是这条门原来的漏洞：平时的门只放守巢岗过，
	# 而 RaidComponent 摸进来抢幼虫走的恰恰是"平时"这条路。
	# 这样加是安全的——入侵者要么被打死要么抢完就撤，警报照样会结束
	# The peacetime gate let raiders eat the brood unopposed. Safe to widen: an intruder
	# either dies or leaves, so the alarm still ends.
	var raiding: bool = _alarm_is_up() or _enemy_at_the_hive()
	if not raiding and not agent.is_posted_to_hive():
		return FAILURE

	# 罢工的和叛军不来支援。玩家看到的是"入侵时有几只蜂没动"，
	# 里头有记恨的忠诚蜂，也可能有她——这层重叠是白送的，不用另造机制
	# Strikers and rebels don't answer. The player just sees a few wasps sitting it out,
	# and the reason is ambiguous by construction.
	if raiding and not agent.allegiance().works():
		return FAILURE

	# 每帧重选最近目标：敌人会新生成，黄蜂也可能被玩家扔到别处
	# Retarget every tick - enemies keep spawning and the player can fling wasps away.
	var enemies: Array = agent.get_tree().get_nodes_in_group("Enemy")
	agent.target_enemy = _find_closest_enemy(enemies, _reach_for(raiding))

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

func _alarm_is_up() -> bool:
	var director: RaidDirector = RaidDirector.find(agent.get_tree())
	return director != null and director.is_raiding()


func _enemy_at_the_hive() -> bool:
	var hive: Node2D = agent.get_tree().get_first_node_in_group(HIVE_GROUP) as Node2D
	if hive == null:
		return false
	for node in agent.get_tree().get_nodes_in_group(ENEMY_GROUP):
		var enemy: Node2D = node as Node2D
		if enemy != null and enemy.global_position.distance_to(hive.global_position) <= hive_alarm_radius:
			return true
	return false


# 集结半径按个体算。**被玩家指派**的卫兵全额响应，其他人按自己的 rally_bias 打折——
# 忠诚蜂和伪王后的区间是重叠的，所以"谁没回来"永远不是确定答案
# Guards always answer in full; everyone else answers from their own band. The loyal and
# the false queen's bands overlap on purpose, so "who stayed away" is never proof.
#
# 闲蜂走的是打折那一路，这一点是有意的：入侵是玩家注意力最集中在战斗上的时候，
# 也就是她最好的作案窗口。她照样可能回防（rally_bias 上限 0.9，够近就来），
# 但她不是必然回防——这个"有时来有时不来"就是她的伪装本身
# Idle wasps take the discounted path on purpose: a raid is when the player's attention
# is furthest from the hive, which makes it her best window. She may still answer - that
# inconsistency is the disguise.
func _reach_for(raiding: bool) -> float:
	if not raiding:
		return alert_radius
	if agent.is_posted_to_hive():
		return raid_alert_radius
	return raid_alert_radius * agent.allegiance().rally_reach()


func _find_closest_enemy(enemies: Array, reach: float) -> Node2D:
	var closest_enemy: Node2D = null
	var min_dist: float = INF
	
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		var dist: float = agent.global_position.distance_to(enemy.global_position)
		if dist > reach:
			continue
		if dist < min_dist:
			min_dist = dist
			closest_enemy = enemy

	return closest_enemy
