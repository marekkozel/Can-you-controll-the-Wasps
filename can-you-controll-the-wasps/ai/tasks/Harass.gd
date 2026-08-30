# 骚扰 / harass: 叛军扑上去咬最近的自己人。
#
# 优先级压在 Sabotage 之下——拆巢才是它们的正事，打蜂是没巢可拆时干的。
# 挨咬的一方**不会还手**：Defend 只认 Enemy 组，叛军留在 wasps 组里，
# 所以普通工蜂始终把它们当自己人。清场是玩家一个人的活。
# The victims never fight back - Defend only looks at the Enemy group, and rebels are
# still wasps. Culling them is the player's job alone.
#
# **一次追击必须会结束。** 追不上的追击是这个任务最坏的形态：叛军黏在一只工蜂
# 屁股后面横穿地图，既咬不到也不拆巢，看着像卡住了。所以这里有三道闸——
# 锁定一个目标（不每帧改主意）、追击计时、离起追点的缰绳，任何一道到头就放弃并歇一会儿。
# A chase that cannot end is the worst shape this task takes: one target, one clock,
# one leash, and a rest afterwards so the rebel goes back to what it is actually for.
class_name Harass
extends BTAction

## 咬得到的距离。**要大于两只蜂 NavigationAgent2D radius 之和（20 + 20 = 40）**，
## 否则 RVO 会一直把它们推开，追一辈子也咬不到
## Must clear the avoidance radii or the bite never lands.
@export var reach: float = 46.0
## 追击速度，比巡航快 / faster than a cruise
@export var chase_speed: float = 130.0
## 进到这个半径就绕开 RVO 直冲。两只蜂互相避让的话最后那几十像素永远走不完
## Inside this, avoidance is bypassed - two wasps dodging each other never close.
@export var strike_radius: float = 90.0

@export_group("Leash")
## 一次追击最多追多久 / how long one chase may last
@export_range(1.0, 30.0, 0.5) var max_chase_time: float = 5.0
## 离**开始追的地方**多远就放弃。按起追点算而不是按巢算：叛军本来就该在巢附近活动，
## 拿巢当锚点等于允许它一路追到地图边上再说
## Measured from where the chase began, not from the hive: anchoring on the hive would
## license a chase all the way to the map edge.
@export_range(60.0, 800.0, 10.0) var leash_radius: float = 320.0
## 放弃之后歇多久。这段时间 Harass 直接失败，控制权还给 Sabotage
## The rest hands control back to Sabotage - without it the rebel re-locks instantly.
@export_range(0.0, 20.0, 0.5) var give_up_cooldown: float = 4.0

const WASP_GROUP: StringName = &"wasps"

## 不加类型：目标随时被咬死或被玩家一把拎走，类型化变量在赋值那一刻就抛错
## Untyped - the victim can die or be plucked away mid-chase.
var _victim = null
var _elapsed: float = 0.0
## 起追点，缰绳量的就是离它多远 / where this chase began
var _anchor: Vector2 = Vector2.ZERO


func _tick(delta: float) -> Status:
	var allegiance: AllegianceComponent = agent.allegiance()
	if allegiance.harass_cooldown > 0.0:
		return FAILURE

	# 锁定的那只还能追就继续追，不每帧改主意——每帧重选最近目标的话，
	# 两只工蜂交错飞过就能让叛军在半路上反复掉头
	# Re-picking the nearest victim every tick makes a rebel dither between two wasps
	# that happen to cross in front of it.
	if not _is_chaseable(_victim):
		_victim = _closest_victim()
		if _victim == null:
			return FAILURE
		_elapsed = 0.0
		_anchor = agent.global_position

	_elapsed += delta
	if _elapsed > max_chase_time or _anchor.distance_to(agent.global_position) > leash_radius:
		return _give_up(allegiance)

	var to_victim: float = agent.global_position.distance_to(_victim.global_position)
	# 贴身段不减速也不避让，剩下的路才走得完 / no braking and no dodging on the last stretch
	var closing: bool = to_victim <= strike_radius
	agent.steer_towards(_victim.global_position, delta, chase_speed, 0.08, 0.0 if closing else -1.0, closing)
	if to_victim > reach:
		return RUNNING

	# attack_enemy 走的是黄蜂现成的叮咬路径（带冷却），目标只要有 take_damage 就行
	# Reuses the wasp's own sting path, cooldown and all; any take_damage will do.
	agent.target_enemy = _victim
	if agent.attack_enemy():
		# 咬到了就收工。**不留着接着咬同一只**——叼住一只工蜂磨到死，玩家除了看着
		# 没有别的事可做，而叛军该干的是拆巢
		# One bite ends it: pinning a worker to death leaves the player nothing to do.
		return _give_up(allegiance)
	return RUNNING


func _exit() -> void:
	agent.target_enemy = null


func _give_up(allegiance: AllegianceComponent) -> Status:
	allegiance.harass_cooldown = give_up_cooldown
	_victim = null
	_elapsed = 0.0
	return FAILURE


func _is_chaseable(wasp) -> bool:
	if not is_instance_valid(wasp) or wasp == null:
		return false
	# 死了就不追。尸体退出了 wasps 组但实例还在（要躺 5 秒），
	# 只查 is_instance_valid 的话叛军会围着一具尸体咬到它消失
	# The corpse lingers and stays valid; only the group tells you it is over.
	if not wasp.is_in_group(WASP_GROUP):
		return false
	# 追丢了就重挑：目标飞出视野还硬追，缰绳就变成了唯一的出口
	# Losing sight ends the lock, or the leash becomes the only way out.
	return agent.can_see(wasp.global_position) and not wasp.allegiance().is_rebel()


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
