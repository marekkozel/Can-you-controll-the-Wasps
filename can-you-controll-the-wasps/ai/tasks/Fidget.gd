# 闲事 / fidget: 巢里闲着的时候做点什么。五件事加权随机挑一件，权重每只蜂不同。
#
# **这是"谁是卧底"里的发言环节。** 蜂聚回巢只是坐下，坐下之后还得各自说一句话，
# 而且说的必须是同一套词汇——不然差异之间没有可比性。SecretLay 藏的就是这套词汇里
# 的 INSPECT：飞过去、停一会儿、走人，形状一模一样，区别只有停留稍长，
# 以及走了之后那格多了一颗卵。
# The five acts are the shared vocabulary SecretLay hides inside; without it, "a wasp
# lingering over an empty cell" is proof rather than a hint.
#
# 它排在 Gather 之后，所以"只在没活干的时候做闲事"是位置带来的，不用额外判断。
# Sitting below Gather in the tree is what makes it idle-only - no extra condition needed.
class_name Fidget
extends BTAction

## 飞过去的速度 / cruise speed while going somewhere to fidget
@export var fly_speed: float = 70.0
## 多近算到位 / arrival tolerance
@export var reach: float = 22.0
## 触角接触要多近。要大于两只蜂的碰撞半径之和（19.5 x 2 = 39）
## Must clear both collision radii, or they hover just short of each other forever.
@export var contact_reach: float = 44.0

const HIVE_GROUP: StringName = &"hive"
const WASP_GROUP: StringName = &"wasps"

var _act: Wasp.IdleAct = Wasp.IdleAct.GROOM
var _busy: bool = false
## 目标可能是巢室，也可能是另一只蜂（她随时会被处决），所以不加类型
## Untyped: the target may be another wasp, and she can be executed at any moment.
var _target = null
var _point: Vector2 = Vector2.INF
var _timer: float = 0.0
var _cooldown: float = 0.0


func _tick(delta: float) -> Status:
	if not _busy:
		_cooldown -= delta
		if _cooldown > 0.0:
			return FAILURE
		if not _begin():
			return FAILURE

	match _act:
		Wasp.IdleAct.GROOM:
			return _tick_linger(delta)
		Wasp.IdleAct.ANTENNATE:
			return _tick_contact(delta)
		_:
			return _tick_travel(delta)


func _exit() -> void:
	_busy = false
	_target = null
	_point = Vector2.INF


# 挑一件事。挑不动就作罢，让树往下走到 Idle
# Pick something to do; bail to Idle when there is nothing available.
func _begin() -> bool:
	_act = agent.pick_idle_act()
	_timer = agent.linger_time * randf_range(0.8, 1.25)
	_target = null
	_point = Vector2.INF

	match _act:
		Wasp.IdleAct.INSPECT:
			# 空的已建成格也算，而且**必须**算：伪王后专挑空格这件事本身就是线索，
			# 得有一批忠诚蜂也在做同样的事，它才不是证据
			# Empty built cells are in on purpose - loyal wasps must do this too.
			_target = _random_cell(func(c): return c.is_built)
		Wasp.IdleAct.ATTEND:
			_target = _random_cell(func(c): return c.content == HexCell.Content.LARVA)
		Wasp.IdleAct.ANTENNATE:
			_target = _random_wasp()
		Wasp.IdleAct.PATROL:
			_point = _rim_point()
		Wasp.IdleAct.GROOM:
			pass

	# 挑不到目标就退成原地梳理，别让这一帧白跑 / degrade to grooming rather than failing
	if _act != Wasp.IdleAct.GROOM and _target == null and _point == Vector2.INF:
		_act = Wasp.IdleAct.GROOM

	_busy = true
	return true


# 原地停着。留白是有用的：全员一刻不停，异常就无从凸显
# Standing still is load-bearing - constant motion hides the outlier.
func _tick_linger(delta: float) -> Status:
	_timer -= delta
	return RUNNING if _timer > 0.0 else _finish()


# 飞过去，到了停一会儿。**停留时长就是 SecretLay 要融进去的那条线索**
# The linger is the tell SecretLay's hover has to pass for.
func _tick_travel(delta: float) -> Status:
	var goal: Vector2 = _goal_position()
	if goal == Vector2.INF:
		return _finish()

	if agent.global_position.distance_to(goal) > reach:
		agent.steer_towards(goal, delta, fly_speed)
		return RUNNING
	return _tick_linger(delta)


# 触角接触：飞近另一只蜂，碰一下就分开。真实黄蜂靠这个交换信息，
# 而"她社交得比别人少"是一条不用另造系统的线索
# Antennation. "She mixes less than the others" is a tell that costs no new machinery.
func _tick_contact(delta: float) -> Status:
	if not is_instance_valid(_target):
		return _finish()

	var goal: Vector2 = (_target as Node2D).global_position
	if agent.global_position.distance_to(goal) > contact_reach:
		agent.steer_towards(goal, delta, fly_speed)
		return RUNNING

	# 碰上了只停很短一下，接触是个动作不是个姿势 / a contact is a beat, not a pose
	_timer -= delta * 2.5
	return RUNNING if _timer > 0.0 else _finish()


func _finish() -> Status:
	_busy = false
	_target = null
	_point = Vector2.INF
	_cooldown = agent.urge_interval * randf_range(0.7, 1.3)
	return SUCCESS


func _goal_position() -> Vector2:
	if _point != Vector2.INF:
		return _point
	if is_instance_valid(_target):
		return (_target as Node2D).global_position
	return Vector2.INF


func _hive() -> Hive:
	return agent.get_tree().get_first_node_in_group(HIVE_GROUP) as Hive


func _random_cell(accepts: Callable) -> HexCell:
	var hive: Hive = _hive()
	if hive == null:
		return null
	var cells: Array = hive.all_cells().filter(accepts)
	return cells[randi() % cells.size()] as HexCell if not cells.is_empty() else null


# 只找看得见的同伴。看不见的还去蹭，蜂又变回全知了
# Only wasps it can actually see - otherwise omniscience creeps back in.
func _random_wasp():
	var others: Array = []
	for node in agent.get_tree().get_nodes_in_group(WASP_GROUP):
		var other: Wasp = node as Wasp
		if other == null or other == agent:
			continue
		if agent.has_method("can_see") and not agent.can_see(other.global_position):
			continue
		others.append(other)
	return others[randi() % others.size()] if not others.is_empty() else null


# 巢外缘上的一点。巡边让画面不至于全挤在中心，也给蜂群一层"有人守着"的观感
# A point on the rim - keeps the crowd off the centre and reads as sentry work.
func _rim_point() -> Vector2:
	var hive: Hive = _hive()
	if hive == null:
		return Vector2.INF
	var angle: float = randf() * TAU
	return hive.global_position + Vector2(cos(angle), sin(angle)) * agent.loiter_radius
