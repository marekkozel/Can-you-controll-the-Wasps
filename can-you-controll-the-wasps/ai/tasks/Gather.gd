# 采集 / gather: 飞到最近一块岗位对应的材料旁边把它叼起来。
# 目标先认领再飞，否则一群黄蜂会扎堆在同一块纸板上
# Claim before flying, or the whole swarm converges on one piece.
class_name Gather
extends BTAction

## 多近算叼到。两者碰撞体撑在那里，太小的值永远走不到
## Must clear both collision radii (wasp 19.5 + cardboard 22), or it hovers forever.
@export var pick_distance: float = 48.0
## 去拿东西时的飞行速度 / cruise speed while fetching
@export var fly_speed: float = 90.0

const CARRIABLE_GROUP: StringName = &"carriable"
const HIVE_GROUP: StringName = &"hive"
const ITEM_SOURCE_GROUP: StringName = &"item_source"

var _target: Node2D = null


func _tick(delta: float) -> Status:
	# 叛军不帮工。已屈服的照干 / rebels do not work, subdued ones do
	if not agent.allegiance().works():
		return FAILURE

	var carry: CarryComponent = agent.carry()
	if carry == null or carry.is_carrying():
		return FAILURE

	# 巢建满了、或者没幼虫饿着，就别再搬了。不拦的话 Gather 捣起来、
	# Deliver 又找不到去处原地放下，两个任务会死循环
	# Without this the pair loops forever: Gather picks up, Deliver finds no target and
	# drops it right back down.
	#
	# 岗位可能管好几种货（加工厂那种），只要**还有一种**有去处就继续开工
	# A refinery post handles several payloads; one live sink is enough to keep working.
	var hive: Hive = agent.get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	if not _any_sink(hive):
		return FAILURE

	if not _is_usable(carry, _target):
		_release_claim()
		_target = _acquire(carry)

	# 地上没有现成的就去产出点现领一块 / nothing loose on the ground, draw one from the post
	if _target == null:
		return _fetch_from_post(carry, delta)

	agent.steer_towards(_target.global_position, delta, fly_speed)
	if agent.global_position.distance_to(_target.global_position) > pick_distance:
		return RUNNING

	var picked: bool = carry.pick_up(_target)
	_release_claim()
	_target = null
	return SUCCESS if picked else FAILURE


# 现取现做的产出点：飞到跟前才生成。路上什么都不存在，所以不用认领也没得抢
# An on-demand post mints on arrival - nothing exists en route, so there is nothing to claim.
func _fetch_from_post(carry: CarryComponent, delta: float) -> Status:
	var post: ItemSource = agent.job_post as ItemSource
	if post == null or post.payload != agent.job_payload:
		return FAILURE

	agent.steer_towards(post.global_position, delta, fly_speed)
	if agent.global_position.distance_to(post.global_position) > pick_distance:
		return RUNNING

	# 落在自己身上，pick_up 紧接着就把碰撞关掉，不会把自己顶开
	# Spawned on top of the wasp; pick_up kills its collision on the same frame.
	var piece: Node2D = post.take_at(agent.global_position)
	if piece == null:
		return FAILURE
	return SUCCESS if carry.pick_up(piece) else FAILURE


# 被玩家拓走、或者岗位中途换了都会走到这里 / also fires when the player yanks the wasp away
func _exit() -> void:
	_release_claim()
	_target = null


# 这个岗位管的货里，还有哪一种是有地方送的 / does any of this post's payloads have a sink
func _any_sink(hive: Hive) -> bool:
	for payload in agent.job_payloads():
		if _has_sink(hive, payload):
			return true
	return false


# 去处有两种：收原料的加工厂，和收货的巢。战利品的去处是工厂，跟巢完全无关，
# 所以光问 hive.accepts() 会把整条战利品线判死
# Two kinds of sink. Loot's is the refinery, never the hive - asking only the hive
# would declare the whole loot loop dead.
func _has_sink(hive: Hive, payload: StringName) -> bool:
	for node in agent.get_tree().get_nodes_in_group(ITEM_SOURCE_GROUP):
		var post: ItemSource = node as ItemSource
		if post != null and post.accepts_intake(payload):
			return true
	return hive != null and hive.accepts(payload)


func _acquire(carry: CarryComponent) -> Node2D:
	var wanted: Array[StringName] = agent.job_payloads()
	var hive: Hive = agent.get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	var best: Node2D = null
	var best_dist: float = INF

	for node in agent.get_tree().get_nodes_in_group(CARRIABLE_GROUP):
		var item: Node2D = node as Node2D
		if not _is_usable(carry, item):
			continue
		# 看不见的就当不存在。不加这道门每只蜂都在扫全场，采食蜂会为了地上一块
		# 战利品横穿整张地图——那不是聪明，那是开了全图
		# Out of sight is out of mind; without this every wasp behaves omnisciently.
		if agent.has_method("can_see") and not agent.can_see(item.global_position):
			continue
		var payload: StringName = CarryComponent.payload_of(item)
		if not wanted.is_empty() and not wanted.has(payload):
			continue
		# 捡起来没处送的别捡：巢建满时那堆纸板就该躺着
		# Don't pick up what has nowhere to go, or it gets carried in circles.
		if not _has_sink(hive, payload):
			continue
		var dist: float = agent.global_position.distance_to(item.global_position)
		if dist < best_dist:
			best_dist = dist
			best = item

	if best == null:
		return null

	# 抢不到认领就这一帧作罢，下帧重新挑 / lost the race, retry next tick
	var claim: ClaimComponent = ClaimComponent.of(best)
	if claim != null and not claim.claim(agent):
		return null
	return best


func _is_usable(carry: CarryComponent, item) -> bool:
	if not is_instance_valid(item) or not carry.can_pick_up(item):
		return false
	var claim: ClaimComponent = ClaimComponent.of(item)
	return claim == null or claim.can_claim(agent)


func _release_claim() -> void:
	var claim: ClaimComponent = ClaimComponent.of(_target)
	if claim != null:
		claim.release(agent)
