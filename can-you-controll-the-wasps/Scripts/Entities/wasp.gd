class_name Wasp
extends RigidBody2D

signal slammed(speed: float)
## 死了。尸体系统以后接这里 —— 一只蜂是"建格子→产卵→孵化→喂满→封盖→羽化"整条链换来的，
## 它消失得无声无息是不对的。at 是倒下的位置，尸体就该出现在那儿。
## 想区分死因看**信号顺序**：处决时 StingComponent.killed 先发（还带 was_false_queen），
## 这一条后发；只收到这一条就是战死或其他。
## The corpse system hooks here. To tell an execution apart, watch the order: on a sting
## StingComponent.killed fires first and carries was_false_queen; this one always follows.
signal died(wasp: Wasp, at: Vector2)
## 岗位变了 / the wasp switched posts
signal job_changed(job: Job)

# 岗位由落点决定：扔到资源点就采集，扔回巢就待命
# The drop point decides the job - that is the whole point of dragging a wasp around.
enum Job { HIVE, GATHER }

## 四条专长，蜂王浆随机点亮其中一条 / the four perks royal jelly rolls against
enum Trait { SPEED, ATTACK, CARRY, BUILD }

const ITEM_SOURCE_GROUP: StringName = &"item_source"
const HIVE_GROUP: StringName = &"hive"
## 专长轨道画到 7 格就读不出个数了（血统 4 + 基因 3），加成一律截在这里
## The pip track tops out readable at 7; every bonus clamps to it. See GeneBank.max_rank.
const MAX_UNITS: int = 7

@export_range(0.05, 2.0, 0.05) var emerge_duration: float = 0.45
## 每点蜂王浆加成让体型涨多少。**只跟蜂王浆挂钩，不算基因**——基因是全场蜂都有的，
## 全体一起变大等于没变；这一格标记的是"这只是你亲手喂出来的"
## Royal jelly only: genes apply colony-wide, so scaling on them would say nothing.
@export_range(0.0, 0.4, 0.01) var trait_growth: float = 0.09
@export_range(0.0, 20.0, 0.5) var bob_amount: float = 3.5
@export_range(0.1, 5.0, 0.1) var bob_period: float = 1.6
@export_range(0.02, 1.0, 0.01) var facing_smoothing: float = 0.15
## 进到这个半径开始减速 / start braking within this radius of the target
@export_range(0.0, 400.0, 5.0) var arrive_radius: float = 45.0

## 叮一下的基准伤害。全局旋钮：改这里影响所有蜂
## Global knob - every wasp's base sting. Per-lineage multipliers ride on top of it.
@export_range(1, 100, 1) var damage: int = 1
## 两次叮咬的间隔 / seconds between stings
@export_range(0.0, 5.0, 0.05) var attack_cooldown: float = 0.6
## 缩一下的力道 / how hard a flinch pushes
@export_range(0.0, 400.0, 5.0) var dodge_impulse: float = 130.0
## 挨咬时被推开的力度。要小于 dodge_impulse，不然会被顶出猎手的攻击范围，
## 变成永远打不死 / smaller than a flinch, or a bite knocks the wasp out of reach forever
@export_range(0.0, 400.0, 5.0) var bite_knockback: float = 70.0

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

@export_group("Coronation")
## 飞向加冕站位的速度。比游荡快，仪式不该看着像散步
## Faster than a wander - a procession should not read as loitering.
@export_range(20.0, 400.0, 5.0) var attend_speed: float = 180.0

@export_group("Wander")
@export_range(10.0, 800.0, 5.0) var wander_radius: float = 200.0
@export_range(5.0, 400.0, 5.0) var wander_speed: float = 55.0
@export_range(0.5, 30.0, 0.1) var retarget_interval: float = 3.0

@export_group("AI Targets")
var job: Job = Job.HIVE
## 采集岗要搜什么 / what a GATHER wasp is after
var job_payload: StringName = &""
var job_post: Node2D = null
## 个体名。在 _ready 里领，**领的时候它还是 LOYAL**——这一点是名字不泄露立场的全部理由
## Drawn in _ready, while every wasp is still LOYAL. That ordering is the whole safeguard.
var wasp_name: String = ""
## 血统写进来的攻击倍率，跟 speed_scale 一个路子 / written by VariantComponent, like speed_scale
var damage_scale: int = 1
## 基因加成，四条专长通加。羽化时由 SeasonDirector 写死，之后不再变——
## 已经在场的蜂不会因为你解锁了新基因而变强，加成只跟着新生的那一批
## Stamped once at birth: unlocking a gene never upgrades the wasps already flying.
var perk_bonus: int = 0
## 蜂王浆加成，按 Trait 下标存。跟 perk_bonus 分开是因为两者语义不同：
## 基因是全场普适的，这个是**这一只**幼虫吃出来的，而且只点亮随机一条
## Kept apart from perk_bonus on purpose: genes are colony-wide, this is one larva's meal.
var trait_bonus: Array[int] = [0, 0, 0, 0]

var _emerging: bool = false
var _emerge_tween: Tween

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
## 加冕时该站的位置。INF = 没在集结 / the coronation slot, INF when not attending
var _attend_target: Vector2 = Vector2.INF

## 变种专长写进来的速度倍率 / written by VariantComponent
var speed_scale: float = 1.0
## 蜂群不安时的减速，由 BetrayalDirector 写入 / written by the director
var morale_scale: float = 1.0

# Wander internal states
var _wander_home: Vector2 = Vector2.ZERO
var _wander_target: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0


func _ready() -> void:
	wasp_name = WaspNames.pick(get_tree())
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
	_emerging = true
	_start_emerge_tween()


# 羽化的目标大小可能在动画途中才定下来：格子是 add_child() 之后才刻印蜂王浆加成的，
# 那会儿这个 tween 已经在跑了，所以要能重新瞄准
# The jelly bonus is stamped after add_child(), by which time this tween is already
# running - hence re-aimable rather than fire-and-forget.
func _start_emerge_tween() -> void:
	if _emerge_tween != null and _emerge_tween.is_valid():
		_emerge_tween.kill()
	_emerge_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_emerge_tween.tween_property(_visual, "scale", _juice.base_scale, emerge_duration)
	_emerge_tween.tween_callback(func(): _emerging = false)


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


# 这个岗位能搬哪几种货。主业永远在第一个；岗位挂在加工厂上的话，
# 连它的原料和成品一起管——搬战利品进来，也把加工好的送出去
# The post's own payload comes first. A refinery post owns its whole loop, so its
# intake and output ride along - haul the raw in, carry the refined out.
#
# 范围由加工厂自己的配置决定，这里**不写死任何 payload 名**：再加一种加工厂
# 只要配 .tscn，这条不用回来改
# Nothing is hardcoded here on purpose - a second refinery needs no change to this.
func job_payloads() -> Array[StringName]:
	if job != Job.GATHER or job_payload == &"":
		return []

	var list: Array[StringName] = [job_payload]
	var post: ItemSource = job_post as ItemSource
	if post == null or not post.is_refinery():
		return list

	if not list.has(post.intake_payload):
		list.append(post.intake_payload)
	if post.output_payload != &"" and not list.has(post.output_payload):
		list.append(post.output_payload)
	return list


func carry() -> CarryComponent:
	return _carry


func allegiance() -> AllegianceComponent:
	return _allegiance


# 四条专长的对外口径 = 血统值 + 基因加成。**别绕过这几个函数直接读 WaspVariant**：
# 那样拿到的是没算基因的裸值，而面板、行为树和伤害计算必须报同一个数
# The wasp is the authority on its own numbers; reading the variant directly skips genes.
func speed_units() -> int:
	return _units(int(round(speed_scale)), Trait.SPEED)


func attack_units() -> int:
	return _units(maxi(damage_scale, 1), Trait.ATTACK)


func carry_units() -> int:
	var v: WaspVariant = _variant.variant
	return _units(v.carry_units if v != null else 1, Trait.CARRY)


func build_units() -> int:
	var v: WaspVariant = _variant.variant
	return _units(v.build_units if v != null else 1, Trait.BUILD)


# 血统值 + 基因（全属性）+ 蜂王浆（单项），最后截到轨道画得下的格数
# Lineage + genes (all four) + jelly (one), clamped to what the pip track can render.
func _units(base: int, which: Trait) -> int:
	return mini(base + perk_bonus + trait_bonus[which], MAX_UNITS)


# 随机点亮一条专长，返回中了哪条。幼虫吃下蜂王浆时**不掷**，掷点留到羽化那一刻——
# 喂的时候就知道结果的话，这东西就退化成一个普通的加号了
# Rolled at emergence, never at feeding time: knowing the outcome while you feed would
# turn the whole thing back into a plain plus-one.
func grant_random_trait() -> Trait:
	var which: Trait = (randi() % trait_bonus.size()) as Trait
	trait_bonus[which] += 1
	_refresh_size()
	return which


# 体型跟着蜂王浆总数走 / size tracks the jelly count, nothing else
func _refresh_size() -> void:
	var total: int = 0
	for value in trait_bonus:
		total += value
	var scale_factor: float = 1.0 + float(total) * trait_growth
	# 只放大 Visual，**碰撞体不动**：采集/叮咬/猎手的判定距离全是按半径 19.5 手算死的
	# Visual only - every reach in the project is hand-tuned against a 19.5 radius.
	_juice.base_scale = Vector2.ONE * scale_factor
	if _emerging:
		_start_emerge_tween()  # 动画还在跑，换个目标继续 / re-aim, don't snap
		return
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
		.tween_property(_visual, "scale", _juice.base_scale, 0.3)


func variant() -> VariantComponent:
	return _variant


# ---------------- 加冕集结 / the coronation gathering ----------------

# 冬天被叫到王座边站位。行为树整个关掉，改由 _physics_process 直接把它推过去——
# 走的是被甩飞时那条现成的路子，不用碰行为树，也就不会碰上"警报永远不结束"那类坑
# Reuses the fling path: the tree goes quiet and physics steers, so no BT branch can hang.
func attend(slot: Vector2) -> void:
	_attend_target = slot
	_btree.active = false
	# 集结时必须关掉 RVO。避让的职责是"别占同一块地方"，而站位已经把这件事解决了——
	# 两者一起跑的结果是蜂被互相推开，速度掉到 0 还在往外漂，永远到不了位
	# Avoidance solves a problem the slots already solved; together they deadlock and the
	# wasps drift outward at zero speed instead of landing.
	if _nav != null:
		_nav.avoidance_enabled = false


func stop_attending() -> void:
	if _attend_target == Vector2.INF:
		return
	_attend_target = Vector2.INF
	if _nav != null:
		_nav.avoidance_enabled = true
	_btree.active = true
	set_wander_home(global_position)


func is_attending() -> bool:
	return _attend_target != Vector2.INF


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
	# queue_free 之前发。接收方要留住尸体的话得自己 instantiate 一个，
	# 别指望在这只蜂身上做文章 / emit before freeing; listeners must spawn their own corpse
	died.emit(self, global_position)
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
		# 拿在手上时别推：拖拽弹簧和这里都写 linear_velocity，两边会打架
		# Never while held - the drag spring writes the same velocity we would.
		if _attend_target != Vector2.INF and not _draggable.is_grabbed():
			# 方向还是听导航的：蜂可能在上带，直线飞过去会顶在巢室的墙上
			# Still navmesh-guided: a straight line from the upper band walks into a wall.
			# 制动半径要比容差大不少，转向权重也调高：站位是个点不是个区域，
			# 刹车刹得晚就会绕着自己的位置来回过冲，到场率永远差最后一口气
			# Brake early and steer hard - a slot is a point, and late braking orbits it.
			steer_towards(_attend_target, delta, attend_speed, 0.35, 60.0)
		return

	_fling_time += delta
	if _last_speed > resume_wander_speed and _fling_time < max_fling_time:
		return

	_is_flung = false
	# 集结中的那只被你抢过又扔回去了，落地后接着往王座飞，别让行为树抢回控制权
	# A wasp yanked out of the procession resumes it on landing; the tree stays out.
	_btree.active = not is_attending()
	if rehome_on_landing and not is_attending():
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
# 挨咬 / bitten. 猎手走这条；处决走 StingComponent，那边直接打满血量
# Hunters come through here; executions go via StingComponent and bypass it.
func take_damage(amount: int, from: Vector2 = Vector2.ZERO) -> bool:
	if not _health.is_alive():
		return false
	if not _health.take_damage(amount, from):
		return false

	_juice.burst()
	var away: Vector2 = (global_position - from).normalized()
	if away != Vector2.ZERO:
		linear_velocity += away * bite_knockback

	# 你把它扔进去挨打，它记着。数值放在 director 上，不安相关的常数统一在那儿调
	# It remembers being sent to bleed - the constant lives on the director with the rest.
	var betrayal_director: BetrayalDirector = BetrayalDirector.find(get_tree())
	if betrayal_director != null:
		betrayal_director.report_wound(self)
	return true


func attack_enemy() -> bool:
	if target_enemy == null or not is_instance_valid(target_enemy):
		return false
	if _attack_timer > 0.0:
		return false
	if not target_enemy.has_method("take_damage"):
		return false

	target_enemy.take_damage(attack_damage(), global_position)
	_attack_timer = attack_cooldown
	return true


# brake_radius < 0 就用 arrive_radius；传 0 就完全不减速 / negative means "use arrive_radius"
# 实际叮咬伤害 = 全局基准 x 血统倍率。属性面板读的也是这个
# Panel reads this too, so what it shows is what actually lands.
func attack_damage() -> int:
	return damage * maxi(attack_units(), 1)


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
	var speed: float = move_speed * float(maxi(speed_units(), 1)) * morale_scale
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
