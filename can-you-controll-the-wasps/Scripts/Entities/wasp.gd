class_name Wasp
extends RigidBody2D

signal slammed(speed: float)
## 岗位变了 / the wasp switched posts
signal job_changed(job: Job)

# 岗位由落点决定：扔到资源点就采集，扔回巢就待命
# The drop point decides the job - that is the whole point of dragging a wasp around.
enum Job { HIVE, GATHER }

const ITEM_SOURCE_GROUP: StringName = &"item_source"
const HIVE_GROUP: StringName = &"hive"

@export_range(0.05, 2.0, 0.05) var emerge_duration: float = 0.45
@export_range(0.0, 20.0, 0.5) var bob_amount: float = 3.5
@export_range(0.1, 5.0, 0.1) var bob_period: float = 1.6
@export_range(0.02, 1.0, 0.01) var facing_smoothing: float = 0.15
## 进到这个半径开始减速 / start braking within this radius of the target
@export_range(0.0, 400.0, 5.0) var arrive_radius: float = 45.0

@export_range(1, 100, 1) var damage: int = 1
## 两次叮咬的间隔 / seconds between stings
@export_range(0.0, 5.0, 0.05) var attack_cooldown: float = 0.6
## 缩一下的力道 / how hard a flinch pushes
@export_range(0.0, 400.0, 5.0) var dodge_impulse: float = 130.0

@export_group("Fling")
@export_range(10.0, 600.0, 5.0) var resume_wander_speed: float = 140.0
@export_range(0.5, 20.0, 0.5) var max_fling_time: float = 6.0
@export var rehome_on_landing: bool = true
@export_range(20.0, 2000.0, 10.0) var impact_speed: float = 260.0

# 线索全是区间，而且区间必须重叠。不重叠就不是推理了，是探测器：
# 玩家挖到一只就知道答案，唯一的策略变成挨个抓一遍。
# Every tell is a range, and the ranges must overlap - separate ranges make a detector,
# not a deduction, and the only strategy left is to grab every wasp in turn.
@export_group("Tells")
## 普通工蜂的拖拽手感区间 / an ordinary worker's drag feel
@export var loyal_stiffness: Vector2 = Vector2(12.0, 22.0)
## 第一代伪王后的区间，会随 cunning 向上面那个靠 / hers, drifting toward theirs
@export var queen_stiffness: Vector2 = Vector2(6.0, 9.0)
@export_range(0.0, 0.02, 0.0001) var loyal_wobble: float = 0.0012
@export_range(0.0, 0.02, 0.0001) var queen_wobble: float = 0.006
## 鼠标悬停时缩一下的概率。忠诚蜂也会缩，只是少 / loyal wasps flinch too, just rarely
@export_range(0.0, 1.0, 0.01) var loyal_dodge_chance: float = 0.15
@export_range(0.0, 1.0, 0.01) var queen_dodge_chance: float = 0.9

@export_group("Wander")
@export_range(10.0, 800.0, 5.0) var wander_radius: float = 200.0
@export_range(5.0, 400.0, 5.0) var wander_speed: float = 55.0
@export_range(0.5, 30.0, 0.1) var retarget_interval: float = 3.0

@export_group("AI Targets")
var job: Job = Job.HIVE
## 采集岗要搜什么 / what a GATHER wasp is after
var job_payload: StringName = &""
var job_post: Node2D = null

var target_enemy: Node2D = null
var target_larva: Node2D = null
var target_build_cell: Node2D = null

## Debug
@export_group("Debug")
@export var debug_movement_speed: float = 0

@onready var _visual: Node2D = $Visual
@onready var _draggable: Area2D = $DraggableComponent
@onready var _juice: JuiceComponent = $JuiceComponent
@onready var _btree: BTPlayer = $BTPlayer
@onready var _carry: CarryComponent = $CarryComponent
@onready var _nav: NavigationAgent2D = $NavigationAgent2D
@onready var _variant: VariantComponent = $VariantComponent
@onready var _allegiance: AllegianceComponent = $AllegianceComponent
@onready var _health: HealthComponent = $HealthComponent

var _t: float = 0.0
var _is_flung: bool = false
var _fling_time: float = 0.0
var _last_speed: float = 0.0
var _attack_timer: float = 0.0
var _nav_goal: Vector2 = Vector2.INF
var _steer_weight: float = 0.08

## 变种专长写进来的速度倍率 / written by VariantComponent
var speed_scale: float = 1.0
## 蜂群不安时的减速，由 BetrayalDirector 写入 / written by the director
var morale_scale: float = 1.0

# Wander internal states
var _wander_home: Vector2 = Vector2.ZERO
var _wander_target: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0


func _ready() -> void:
	_juice.target = _visual
	_t = randf() * TAU

	# 每只蜂一份自己的 profile。不 duplicate 的话改一只等于改全场
	# Never share the resource: one wasp's feel would become every wasp's feel.
	_draggable.profile = _draggable.profile.duplicate()
	_apply_drag_feel()

	_nav.velocity_computed.connect(_on_avoidance_velocity)
	_allegiance.changed.connect(_on_allegiance_changed)
	_health.died.connect(_on_died)
	_draggable.mouse_entered.connect(_on_hovered)

	_draggable.grabbed.connect(_on_grabbed)
	_draggable.released.connect(_on_released)
	body_entered.connect(_on_body_entered)

	_visual.scale = Vector2.ZERO
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
		.tween_property(_visual, "scale", Vector2.ONE, emerge_duration)


# 落地、刚羽化、被生成方摆位置都走这里，岗位重算挂在这一个口就够了
# Every reposition funnels through here, so the job recalc needs exactly one hook.
func set_wander_home(pos: Vector2) -> void:
	# 玩家完全可能把黄蜂扔到墙角里 / the player can absolutely drop a wasp into a corner
	_wander_home = _snap_to_navmesh(pos)
	_pick_wander_target()
	_update_job()


# 离哪个工作点最近就干哪一行 / nearest post wins
func _update_job() -> void:
	if not is_inside_tree():
		return

	var best: Node2D = null
	var best_dist: float = INF
	var posts: Array = get_tree().get_nodes_in_group(ITEM_SOURCE_GROUP) + get_tree().get_nodes_in_group(HIVE_GROUP)
	for node in posts:
		var post: Node2D = node as Node2D
		if post == null:
			continue
		var dist: float = _wander_home.distance_to(post.global_position)
		if dist < best_dist:
			best_dist = dist
			best = post

	var new_job: Job = Job.HIVE
	var new_payload: StringName = &""
	if best != null and best.is_in_group(ITEM_SOURCE_GROUP):
		new_job = Job.GATHER
		new_payload = best.payload if "payload" in best else &""

	job_post = best
	if new_job == job and new_payload == job_payload:
		return

	job = new_job
	job_payload = new_payload
	job_changed.emit(job)


func carry() -> CarryComponent:
	return _carry


func allegiance() -> AllegianceComponent:
	return _allegiance


func variant() -> VariantComponent:
	return _variant


# 异色卵孵出来的那一只 / hatched straight out of a rebel egg
func become_rebel(from_variant: WaspVariant, mother) -> void:
	_variant.apply(from_variant)
	_allegiance.make_rebel(mother)


func _on_allegiance_changed(_state: AllegianceComponent.State) -> void:
	_apply_drag_feel()


# 她越老练，手感越往普通工蜂的区间里靠 / the more practised she is, the more she feels normal
func _apply_drag_feel() -> void:
	var profile: DragProfile = _draggable.profile
	if profile == null:
		return

	if not _allegiance.is_false_queen():
		profile.stiffness = randf_range(loyal_stiffness.x, loyal_stiffness.y)
		profile.wobble_multiplier = loyal_wobble
		return

	var c: float = _allegiance.cunning
	profile.stiffness = randf_range(
		lerpf(queen_stiffness.x, loyal_stiffness.x, c),
		lerpf(queen_stiffness.y, loyal_stiffness.y, c))
	profile.wobble_multiplier = lerpf(queen_wobble, loyal_wobble, c)


# 悬停时缩一下。忠诚蜂也会，只是少很多——所以"它刚刚躲了"是弱证据，
# 不是铁证。她越老练，这个概率越往忠诚蜂那边靠。
# Loyal wasps flinch too, just far less often, so a flinch is weak evidence and never proof.
func _on_hovered() -> void:
	if _draggable.is_grabbed():
		return

	var chance: float = loyal_dodge_chance
	if _allegiance.is_false_queen():
		chance = lerpf(queen_dodge_chance, loyal_dodge_chance, _allegiance.cunning)
	if randf() > chance:
		return

	var away: Vector2 = (global_position - get_global_mouse_position()).normalized()
	if away == Vector2.ZERO:
		away = Vector2.UP
	linear_velocity += away * dodge_impulse * randf_range(0.7, 1.3)


func _on_died(_from: Vector2) -> void:
	_carry.drop()
	_juice.burst()
	queue_free()


func _pick_wander_target() -> void:
	var angle: float = randf_range(0.0, TAU)
	var dist: float = sqrt(randf()) * wander_radius
	# 吸附回导航网格。不吸的话靠墙的 home 有一半游荡点落在墙里，
	# 目标不可达 → 退回直线 steering → 黄蜂直接碾在墙上磨到计时器超时
	# Snap back onto the navmesh: near a wall half the wander points land inside it,
	# the target reads as unreachable, steering falls back to a straight line, and the
	# wasp grinds against the wall until the retarget timer fires.
	_wander_target = _snap_to_navmesh(_wander_home + Vector2(cos(angle), sin(angle)) * dist)
	_wander_timer = retarget_interval * randf_range(0.7, 1.3)


func _snap_to_navmesh(point: Vector2) -> Vector2:
	if not is_inside_tree():
		return point
	var map: RID = get_world_2d().navigation_map
	if not map.is_valid():
		return point
	return NavigationServer2D.map_get_closest_point(map, point)


# Called continuously by Idle.gd BTAction
func wander(delta: float) -> void:
	_wander_timer -= delta
	var to_target: Vector2 = _wander_target - global_position

	if _wander_timer <= 0.0 or to_target.length() < 18.0:
		_pick_wander_target()
	
	# 游荡的制动半径得比干活时小：完全不制动会全速冲过目标点，
	# 靠墙的游荡点冲过头就是撞墙；用 arrive_radius 那么大又会让待机黄蜂营营地爬
	# Smaller brake radius than working moves: none at all overshoots into walls,
	# the full arrive_radius makes idle wasps crawl.
	steer_towards(_wander_target, delta, wander_speed, 0.08, 40.0)


func _on_grabbed() -> void:
	# 抓黄蜂就扔货，玩家不用去抠它嘴里那块纸板 / grabbing the wasp makes it let go
	_carry.drop()
	_is_flung = false
	_btree.active = false


func _on_released() -> void:
	_is_flung = true
	_fling_time = 0.0
	_btree.active = false


func _physics_process(delta: float) -> void:
	_last_speed = linear_velocity.length()
	# 冷却计时得走在提前 return 之前，否则被甩飞的黄蜂冷却会冻住
	# Must tick before the early returns - a flung wasp would freeze its cooldown otherwise.
	if _attack_timer > 0.0:
		_attack_timer = maxf(_attack_timer - delta, 0.0)
	if not _is_flung:
		return

	_fling_time += delta
	if _last_speed > resume_wander_speed and _fling_time < max_fling_time:
		return

	_btree.active = true
	_is_flung = false
	if rehome_on_landing:
		set_wander_home(global_position)


func _on_body_entered(_body: Node) -> void:
	if _last_speed < impact_speed:
		return

	# 被摔的黄蜂会记住。玩家拿它们当保龄球是有代价的
	# A slammed wasp remembers it - using them as bowling balls is not free.
	var director: BetrayalDirector = BetrayalDirector.find(get_tree())
	if director != null:
		director.report_slam(self)
	_juice.punch(0.78, 0.28)
	if _last_speed > impact_speed * 2.0:
		_juice.burst()
	slammed.emit(_last_speed)


func _process(delta: float) -> void:
	_t += delta

	var speed: float = linear_velocity.length()
	if speed > 5.0:
		_visual.rotation = lerp_angle(_visual.rotation, linear_velocity.angle(), facing_smoothing)

	_visual.position.y = sin(_t * TAU / bob_period) * bob_amount


# 真的打出去了才返回 true，冷却中返回 false
# Returns true only when the sting actually landed; false while on cooldown.
func attack_enemy() -> bool:
	if target_enemy == null or not is_instance_valid(target_enemy):
		return false
	if _attack_timer > 0.0:
		return false
	if not target_enemy.has_method("take_damage"):
		return false

	target_enemy.take_damage(damage, global_position)
	_attack_timer = attack_cooldown
	return true


# brake_radius < 0 就用 arrive_radius；传 0 就完全不减速 / negative means "use arrive_radius"
func steer_towards(target_pos: Vector2, _delta: float, move_speed: float = 55.0, steering_weight: float = 0.08, brake_radius: float = -1.0) -> void:
	if _is_flung:
		return

	var goal_distance: float = global_position.distance_to(target_pos)
	if goal_distance < 0.01:
		return

	# 方向听导航网格的，朝目标直线飞会顶到墙上；减速用的还是到终点的真实距离
	# Direction comes from the navmesh - a straight line walks into walls.
	# Braking still uses the real distance to the goal, not to the waypoint.
	var heading: Vector2 = _heading_towards(target_pos)
	if heading == Vector2.ZERO:
		return

	var radius: float = arrive_radius if brake_radius < 0.0 else brake_radius
	var speed: float = move_speed * speed_scale * morale_scale
	if radius > 0.0 and goal_distance < radius:
		speed = move_speed * (goal_distance / radius)

	var desired: Vector2 = heading * speed
	# 开了避让就不能自己写速度，要等服务器把周围黄蜂算进去再回调
	# With avoidance on, the server owns the velocity - we only submit what we want.
	if _nav != null and _nav.avoidance_enabled:
		_steer_weight = steering_weight
		_nav.velocity = desired
		return

	linear_velocity = linear_velocity.lerp(desired, steering_weight)


func _on_avoidance_velocity(safe_velocity: Vector2) -> void:
	if _is_flung:
		return
	linear_velocity = linear_velocity.lerp(safe_velocity, _steer_weight)


# 下一个路径点的方向。导航还没算好、或者目标压根不在网格上就退回直线
# Falls back to a straight line while the path is still cooking or the goal is off-mesh.
func _heading_towards(target_pos: Vector2) -> Vector2:
	var direct: Vector2 = (target_pos - global_position).normalized()
	if _nav == null:
		return direct

	# 先把目标吸到网格上。目标本身在墙里（被撞进去的纸板、贴墙的巢室）时，
	# 直接拿原点寻路会算出"不可达"，然后退回直线 steering —— 那就是磨墙
	# Snap the goal first: an off-mesh goal reads as unreachable, steering falls back to
	# a straight line, and the wasp grinds into the wall. Path to the closest legal point
	# and cover the last few pixels directly.
	var goal: Vector2 = _snap_to_navmesh(target_pos)
	if _nav_goal.distance_squared_to(goal) > 256.0:
		_nav_goal = goal
		_nav.target_position = goal

	if _nav.is_navigation_finished():
		return direct

	var to_waypoint: Vector2 = _nav.get_next_path_position() - global_position
	return direct if to_waypoint.length() < 0.01 else to_waypoint.normalized()


func drop_carried_resource() -> void:
	_carry.drop()
