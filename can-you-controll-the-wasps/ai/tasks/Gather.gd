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

var _target: Node2D = null


func _tick(delta: float) -> Status:
	var carry: CarryComponent = agent.carry()
	if carry == null or carry.is_carrying():
		return FAILURE

	# 巢建满了、或者没幼虫饿着，就别再搬了。不拦的话 Gather 捣起来、
	# Deliver 又找不到去处原地放下，两个任务会死循环
	# Without this the pair loops forever: Gather picks up, Deliver finds no target and
	# drops it right back down.
	var hive: Hive = agent.get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	if hive == null or not hive.accepts(agent.job_payload):
		return FAILURE

	if not _is_usable(carry, _target):
		_release_claim()
		_target = _acquire(carry)
		if _target == null:
			return FAILURE

	agent.steer_towards(_target.global_position, delta, fly_speed)
	if agent.global_position.distance_to(_target.global_position) > pick_distance:
		return RUNNING

	var picked: bool = carry.pick_up(_target)
	_release_claim()
	_target = null
	return SUCCESS if picked else FAILURE


# 被玩家拓走、或者岗位中途换了都会走到这里 / also fires when the player yanks the wasp away
func _exit() -> void:
	_release_claim()
	_target = null


func _acquire(carry: CarryComponent) -> Node2D:
	var wanted: StringName = agent.job_payload
	var best: Node2D = null
	var best_dist: float = INF

	for node in agent.get_tree().get_nodes_in_group(CARRIABLE_GROUP):
		var item: Node2D = node as Node2D
		if not _is_usable(carry, item):
			continue
		if wanted != &"" and CarryComponent.payload_of(item) != wanted:
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
