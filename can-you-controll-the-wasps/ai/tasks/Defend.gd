class_name Defend
extends BTAction

## 攻击判定距离，**照中型敌人（半径 22）写的**。别的体型按半径差往上补——
## 黄蜂身体半径 16，甲虫 36 的话两个刚体最近只能贴到 52，写死 50 等于
## 甲虫/蜘蛛/鸟对蜂群完全无敌：飞过去、被身体挡在 52、判定要 50、一口不咬地绕圈
## Authored for the medium build and grown per breed: two bodies can never come closer
## than the sum of their radii, so a flat 50 made the big raiders literally invulnerable.
@export var attack_distance: float = 50.0
## 围攻的站位半径 = 敌人半径 + 这个。每只蜂按自己的 id 分一个角度站，
## 不然所有蜂都瞄同一个中心点，全挤在最近的那一侧靠 RVO 互相顶——
## 那看起来是"绕圈"，不是"围攻"
## Everyone aiming at one point piles onto the near side and reads as circling.
@export var ring_gap: float = 20.0
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

## 攻击距离照哪个体型写的 / the build attack_distance was authored for
const REFERENCE_RADIUS: float = 22.0
## 围圈分几个位置。取 12 是因为一波最多也就十来只蜂扑上来，再多就该有人站外圈了
## Twelve slots: more wasps than that on one target should be standing further out.
const RING_SLOTS: int = 12

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
	#
	# 警报期间和平时一视同仁：叛军是纯敌人，任何时候都不该站到防线这一边
	# Raid or not: a rebel must never end up defending the comb it is there to wreck.
	if not agent.allegiance().works():
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
	var reach: float = _reach_of(agent.target_enemy)

	if agent.has_method("steer_towards"):
		# 飞的是围圈上属于自己的那个点，不是敌人的中心。
		# 近身段不减速：默认 arrive_radius 是 45，最后那截会爬过去，一群蜂爬着更难看
		# No braking on the last stretch - the default arrive radius makes them crawl.
		var spot: Vector2 = _ring_spot(agent.target_enemy)
		var closing: bool = dist_to_enemy <= reach * 1.6
		agent.steer_towards(spot, delta, chase_speed, 0.08, 0.0 if closing else -1.0)

	# 到位了就叮一下；冷却未好时继续 RUNNING 贴着敌人，不让树切走
	# In range: sting. While on cooldown stay RUNNING and hover on the target.
	if dist_to_enemy <= reach and agent.attack_enemy():
		return SUCCESS

	return RUNNING


# 判定距离照体型放大，跟 Enemy._apply_build 里给 HuntComponent 补 reach 是同一套算法。
# 参照体型是半径 22，每个品种在这个基础上按差值补，所有体型都留同样的 12 像素余量
# Same growth Enemy._apply_build applies to the hunter's reach; every breed keeps the
# same margin over "sum of the two radii" instead of only the medium one working.
func _reach_of(enemy: Node2D) -> float:
	var radius: float = enemy.body_radius() if enemy.has_method("body_radius") else REFERENCE_RADIUS
	return attack_distance + maxf(0.0, radius - REFERENCE_RADIUS)


# 围圈上属于这只蜂的位置。角度取自 instance id：同一只蜂每帧算出来都一样，
# 不用存状态，也不用谁来分配号码 / stable per wasp, stateless, nobody hands out slots
func _ring_spot(enemy: Node2D) -> Vector2:
	var radius: float = enemy.body_radius() if enemy.has_method("body_radius") else REFERENCE_RADIUS
	var slot: int = int(agent.get_instance_id() % RING_SLOTS)
	var angle: float = float(slot) / float(RING_SLOTS) * TAU
	# 站位半径也要按蜂错开，**不能都站在同一个圈上**：一圈等距的话，
	# 横扫这类范围攻击就变成了要么全中要么全不中——螳螂要么一下清场，
	# 要么一只都打不着，中间那个"围太紧的会被扫到"才是它存在的意义
	# A perfect ring turns every cleave into all-or-nothing; the point of a cleave is
	# that crowding in costs you, not that it wipes the swarm or misses it entirely.
	var spread: float = 0.7 + 0.6 * float(slot % 5) / 4.0
	return enemy.global_position + Vector2.from_angle(angle) * (radius + ring_gap * spread)

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
