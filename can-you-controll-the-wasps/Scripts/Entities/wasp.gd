class_name Wasp
extends RigidBody2D

signal slammed(speed: float)
## 死了。尸体系统以后接这里 —— 一只蜂是"建格子→产卵→孵化→喂满→封盖→羽化"整条链换来的，
## 它消失得无声无息是不对的。at 是倒下的位置，尸体就该出现在那儿。
## 处决不再是一个独立事件：玩家把她摔死和敌人咬死她走的是同一条血量路径，
## 区别只在 _slain_by_player —— 上报 BetrayalDirector 的判断在 _on_died 里
## No separate execution event any more: a wall slam and a hunter's bite share this path,
## and _slain_by_player is what tells them apart.
signal died(wasp: Wasp, at: Vector2)
## 岗位变了 / the wasp switched posts
signal job_changed(job: Job)

# 岗位由落点决定：扔到资源点就采集，扔回巢就待命
# The drop point decides the job - that is the whole point of dragging a wasp around.
enum Job { HIVE, GATHER }

## 四条专长，蜂王浆随机点亮其中一条 / the four perks royal jelly rolls against
enum Trait { SPEED, ATTACK, CARRY, BUILD }

## 巢里闲着时能做的五件事。下标顺序必须和 BehaviourProfile.roll() 里那个数组一致
## The five idle acts; index order must match BehaviourProfile.roll().
enum IdleAct { INSPECT, ATTEND, ANTENNATE, PATROL, GROOM }

## 揭穿她那一下喷的那团 / the puff a slammed false queen leaves behind
const REVEAL_BURST: PackedScene = preload("res://Scenes/Mechanics/RevealBurst.tscn")
## 她还没来得及挑血统就被摔了 / she lost the mask before a brood colour was rolled
const DISGUISE_SPILL_FALLBACK: Color = Color(0.88, 0.92, 1.0)
const ITEM_SOURCE_GROUP: StringName = &"item_source"
const HIVE_GROUP: StringName = &"hive"
## 专长轨道画到 7 格就读不出个数了（血统 4 + 基因 3），加成一律截在这里
## The pip track tops out readable at 7; every bonus clamps to it. See GeneBank.max_rank.
const MAX_UNITS: int = 7
## 当前岗位的惯性。两个分数接近时不加这个，蜂会在半路上反复掉头
## Hysteresis - without it a wasp dithers between two near-equal posts and does nothing.
const SWITCH_MARGIN: float = 0.09

@export_range(0.05, 2.0, 0.05) var emerge_duration: float = 0.45
## 每点蜂王浆加成让体型涨多少。**只跟蜂王浆挂钩，不算基因**——基因是全场蜂都有的，
## 全体一起变大等于没变；这一格标记的是"这只是你亲手喂出来的"
## Royal jelly only: genes apply colony-wide, so scaling on them would say nothing.
@export_range(0.0, 0.4, 0.01) var trait_growth: float = 0.09
@export_range(0.0, 20.0, 0.5) var bob_amount: float = 3.5
@export_range(0.1, 5.0, 0.1) var bob_period: float = 1.6
## 往右飞时翻面所需的最小横向速度。**死区不能省**：vx 在 0 附近抖动时，
## 没有死区会每帧翻一次，看着像抽搐 / without it a near-zero vx flips every frame
@export_range(0.0, 200.0, 1.0) var flip_threshold: float = 14.0
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
## 撞一次墙掉几点血。**固定值，不随速度加成**——按速度分档等于把一击必杀放回来，
## 而这套机制的全部意义就是处决得摔好几下
## Flat and never speed-scaled: tiering it by speed puts the one-shot execution back.
@export_range(0, 10, 1) var impact_damage: int = 1
## 两次撞墙伤害之间的间隔。一次碰撞会连着好几帧发接触事件，没有这道闸"一下"就是三下
## One collision fires contact events over several frames; without this a single hit kills.
@export_range(0.0, 2.0, 0.05) var impact_damage_cooldown: float = 0.15

# 线索全是区间，而且区间必须重叠。不重叠就不是推理了，是探测器：
# 玩家挖到一只就知道答案，唯一的策略变成挨个抓一遍。
# Every tell is a range, and the ranges must overlap - separate ranges make a detector,
# not a deduction, and the only strategy left is to grab every wasp in turn.
@export_group("Tells")
## 普通工蜂的拖拽手感区间 / an ordinary worker's drag feel
@export var loyal_stiffness: Vector2 = Vector2(12.0, 22.0)
## 第一代伪王后的区间，会随 cunning 向上面那个靠 / hers, drifting toward theirs
@export var queen_stiffness: Vector2 = Vector2(6.0, 9.0)
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

## 行为画像。加一种新蜂就换一个 .tres，代码和行为树都不用动
## Swap the resource to add a kind of wasp - no code, no tree edit. See BehaviourProfile.
@export_group("Behaviour")
@export var behaviour: BehaviourProfile
## 她被叫醒那一刻换上的画像。**把它和上面那个并排打开看区间有没有压住**——
## 那是这套设计唯一的验收标准，也是它放在同一个 Inspector 面板里的理由
## Open both side by side and check the ranges still overlap. That is the whole test.
@export var queen_behaviour: BehaviourProfile

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

# 出生时从 behaviour 的区间里抽一次，抽完定死。**每只蜂私有**——
# BehaviourProfile 本身是全场共享的 Resource，只有抽出来的这几个数是这只蜂的
# Rolled once at birth and private to this wasp; the profile itself is shared.
var sight_radius: float = 340.0
var loiter_radius: float = 190.0
var loiter_speed: float = 55.0
## 五项巢内行为的权重，按 IdleAct 下标 / weights per IdleAct, used for a weighted pick
var idle_weights: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0]
var linger_time: float = 2.2
var urge_interval: float = 4.0
## payload -> 阈值。刺激超过它这只蜂才会被拉去干那行
## The bar a stimulus has to clear before this wasp switches to that work.
var work_threshold: Dictionary = {}
var posting_bias: float = 0.55
var reconsider_interval: float = 4.5

## 你把它扔在哪个工作点旁边 / the post you dropped it next to
var _posted_post: Node2D = null
var _reconsider_timer: float = 0.0

var _emerging: bool = false
var _emerge_tween: Tween

var target_enemy: Node2D = null
var target_larva: Node2D = null
var target_build_cell: Node2D = null

## Debug
@export_group("Debug")
@export var debug_movement_speed: float = 0

@onready var _visual: Node2D = $Visual
## 翻的是贴图不是 Visual：Visual 的 scale 被羽化补间和 JuiceComponent 的
## base_scale（蜂王浆体型）占着，拿 scale.x = -1 去翻会跟它们打架
## Flip the sprite, never Visual.scale - the emerge tween and the jelly size own that.
@onready var _body_sprite: Sprite2D = $Visual/Body
@onready var _animator: SpriteAnimator = get_node_or_null(^"SpriteAnimator") as SpriteAnimator
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
var _impact_timer: float = 0.0
## 这一下是不是玩家造成的。敌人咬死的不能记成处决 / a hunter's kill is not your execution
var _slain_by_player: bool = false
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

# Audio
var _fly_player: AudioStreamPlayer2D = null


func _ready() -> void:
	wasp_name = WaspNames.pick(get_tree())
	_juice.target = _visual
	_t = randf() * TAU
	_roll_behaviour()

	# 每只蜂一份自己的 profile。不 duplicate 的话改一只等于改全场
	# Never share the resource: one wasp's feel would become every wasp's feel.
	_draggable.profile = _draggable.profile.duplicate()
	_apply_drag_feel()

	_nav.velocity_computed.connect(_on_avoidance_velocity)
	_allegiance.changed.connect(_on_allegiance_changed)
	_health.died.connect(_on_died)
	_health.damaged.connect(_on_damaged)
	_draggable.mouse_entered.connect(_on_hovered)

	_draggable.grabbed.connect(_on_grabbed)
	_draggable.released.connect(_on_released)
	body_entered.connect(_on_body_entered)

	_visual.scale = Vector2.ZERO
	_emerging = true
	_start_emerge_tween()

	_fly_player = AudioStreamPlayer2D.new()
	add_child(_fly_player)
	var fly_effect: SoundEffect = AudioManager.sound_effect_dict.get(SoundEffect.SoundEffectType.WASP_FLY) as SoundEffect
	if fly_effect != null and fly_effect.sound_effect != null:
		_fly_player.stream = fly_effect.sound_effect
		_fly_player.volume_db = fly_effect.volume
		_fly_player.finished.connect(func():
			if _health.is_alive() and linear_velocity.length() > 15.0 and not _draggable.is_grabbed():
				_fly_player.play()
		)


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


# 抽画像。没配 behaviour 就留着字段上的默认值，蜂照常能跑
# Falls back to the field defaults when no profile is assigned.
func _roll_behaviour() -> void:
	if behaviour == null:
		return
	_apply_roll(behaviour.roll())


func _apply_roll(rolled: Dictionary) -> void:
	sight_radius = rolled.get(&"sight_radius", sight_radius)
	loiter_radius = rolled.get(&"loiter_radius", loiter_radius)
	loiter_speed = rolled.get(&"loiter_speed", loiter_speed)
	linger_time = rolled.get(&"linger_time", linger_time)
	urge_interval = rolled.get(&"urge_interval", urge_interval)
	posting_bias = rolled.get(&"posting_bias", posting_bias)
	reconsider_interval = rolled.get(&"reconsider_interval", reconsider_interval)

	var weights: Variant = rolled.get(&"idle_weights")
	if weights is Array and (weights as Array).size() == idle_weights.size():
		for i in idle_weights.size():
			idle_weights[i] = float((weights as Array)[i])

	work_threshold = {
		&"cardboard": rolled.get(&"cardboard_threshold", 0.35),
		&"food": rolled.get(&"food_threshold", 0.32),
		# 蜂王浆跟食物共用一条阈值：它们是同一类活，分开配只会多一个要对齐的旋钮
		# Jelly shares the food bar - same job, and a separate knob would just be one
		# more thing to keep in sync.
		&"royal_jelly": rolled.get(&"food_threshold", 0.32),
	}
	_reconsider_timer = reconsider_interval * randf_range(0.3, 1.0)


# 加权随机挑一件闲事。权重是每只蜂自己的，所以"这只老在空格子附近晃"是个体特征
# Weighted pick; the weights are per-wasp, which is what makes the habit readable.
func pick_idle_act() -> IdleAct:
	var total: float = 0.0
	for w in idle_weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return IdleAct.GROOM

	var roll_value: float = randf() * total
	for i in idle_weights.size():
		roll_value -= maxf(idle_weights[i], 0.0)
		if roll_value <= 0.0:
			return i as IdleAct
	return IdleAct.GROOM


# 看得见这个点吗。**所有搜索都该走这里**——之前每个任务各自扫全场，
# 蜂是全知的，采食蜂会为了地上一块战利品横穿整张地图
# Every search goes through this. Wasps used to scan the whole map and behave like it.
func can_see(point: Vector2) -> bool:
	return global_position.distance_to(point) <= sight_radius


# 落地、刚羽化、被生成方摆位置都走这里，岗位重算挂在这一个口就够了
# Every reposition funnels through here, so the job recalc needs exactly one hook.
func set_wander_home(pos: Vector2) -> void:
	# 玩家完全可能把黄蜂扔到墙角里 / the player can absolutely drop a wasp into a corner
	_wander_home = _snap_to_navmesh(pos)
	_pick_wander_target()
	_update_posting()
	_choose_job()


# 离哪个工作点最近就干哪一行 / nearest post wins
# 落点最近的那个工作点。它**不再是命令**，只是给这只蜂一个偏向
# The nearest post to where you dropped it. No longer an order - just a bias.
func _update_posting() -> void:
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
	_posted_post = best


# 掂量一下现在该干什么 / weigh up what to do right now.
#
# 每个工作点算一个分：巢有多需要这类货（刺激）减去这只蜂自己的阈值。
# 你扔它的那个点额外加 posting_bias —— 所以它大部分时间待在你放它的地方，
# 但巢里出事、刺激盖过偏向时，它会自己走开。**你的指令是倾向，不是命令。**
# Stimulus minus this wasp's own bar, plus a bias for wherever you put it. It mostly
# obeys, and leaves on its own when something matters more. That gap is the whole point.
#
# 当前岗位额外拿 SWITCH_MARGIN 的惯性，否则两个分数接近的岗位会让蜂在半路上
# 反复掉头，什么都干不成 / hysteresis, or it dithers between two near-equal posts forever
func _choose_job() -> void:
	if not is_inside_tree():
		return
	_reconsider_timer = reconsider_interval * randf_range(0.85, 1.15)

	var hive: Hive = get_tree().get_first_node_in_group(HIVE_GROUP) as Hive

	# 基线是"回巢待命"。所有活的刺激都压不过阈值时就是它，Idle 接手把蜂带回巢
	# The baseline is loitering; when nothing clears its bar, Idle takes the wasp home.
	var best: Node2D = null
	var best_score: float = 0.0
	if _posted_post != null and _posted_post.is_in_group(HIVE_GROUP):
		best_score += posting_bias
	if job == Job.HIVE:
		best_score += SWITCH_MARGIN

	if hive != null:
		for node in get_tree().get_nodes_in_group(ITEM_SOURCE_GROUP):
			var post: Node2D = node as Node2D
			if post == null or not ("payload" in post):
				continue
			var payload: StringName = post.payload
			# 加工厂有两种需求：巢要它的成品（幼虫饿了），和它自己要原料（地上有战利品）。
			# 取大的那个——两者都是"该往这边跑"的理由，不该互相稀释
			# A refinery pulls for two reasons; take the stronger rather than blending them.
			var need: float = hive.demand(payload)
			var source: ItemSource = post as ItemSource
			if source != null and source.is_refinery():
				need = maxf(need, source.intake_demand())
			var score: float = need - float(work_threshold.get(payload, 0.35))

			#if (payload == &"food" or payload == &"royal_jelly") and need > 0.1:
			#	score += 0.5 

			if post == _posted_post:
				score += posting_bias
			if post == job_post:
				score += SWITCH_MARGIN
			if score > best_score:
				best_score = score
				best = post

	var new_job: Job = Job.GATHER if best != null else Job.HIVE
	var new_payload: StringName = best.payload if best != null else &""

	job_post = best if best != null else _hive_node()
	if new_job == job and new_payload == job_payload:
		return

	job = new_job
	job_payload = new_payload
	job_changed.emit(job)


# 玩家是不是真把它扔在巢边当卫兵。
#
# **不能拿 job == HIVE 代替这个判断。** 那个值现在的含义是"这会儿没活干"，
# 拿它当卫兵用的话，每一只闲蜂都会全额回防，rally_bias 那对重叠区间就被抹平了——
# 而"入侵时谁没回来"正是靠它成立的线索
# Never substitute job == HIVE: that now means "idle", and treating idle wasps as posted
# guards makes every one of them answer in full, erasing the rally_bias tell entirely.
func is_posted_to_hive() -> bool:
	return _posted_post != null and _posted_post.is_in_group(HIVE_GROUP)


func _hive_node() -> Node2D:
	return get_tree().get_first_node_in_group(HIVE_GROUP) as Node2D


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


func _on_allegiance_changed(state: AllegianceComponent.State) -> void:
	_apply_drag_feel()

	# 她被叫醒的那一刻换画像，重抽一次。**外观不变**——换的是她闲下来时干什么，
	# 以及她多容易脱岗。这跟"她不改颜色"是同一条原则：伪装的破绽只能出在行为上
	# Re-rolled on awakening. Nothing about her looks different; only what she does when
	# idle, and how readily she wanders off her post.
	if state == AllegianceComponent.State.FALSE_QUEEN and queen_behaviour != null:
		_apply_roll(queen_behaviour.roll())


# 她越老练，手感越往普通工蜂的区间里靠 / the more practised she is, the more she feels normal
# 现在这条线索只剩 stiffness（跟手程度）这一个通道——摆动那一路让位给了"不许旋转"
# The wobble channel is gone; this tell now rides on stiffness alone.
func _apply_drag_feel() -> void:
	var profile: DragProfile = _draggable.profile
	if profile == null:
		return

	# 摆动一律关掉。lock_rotation 只挡物理力矩，挡不住 _apply_wobble 直接写
	# angular_velocity——那就是拖拽时黄蜂被拧歪的来源。
	# 置 0 之后那段代码退化成一个把角度拉回 0 的弹簧，正好当扶正用。
	# lock_rotation only stops torque, not a direct angular_velocity write. Zeroing the
	# multiplier turns that same code into a spring that holds the wasp upright.
	profile.wobble_multiplier = 0.0

	if not _allegiance.is_false_queen():
		profile.stiffness = randf_range(loyal_stiffness.x, loyal_stiffness.y)
		return

	var c: float = _allegiance.cunning
	profile.stiffness = randf_range(
		lerpf(queen_stiffness.x, loyal_stiffness.x, c),
		lerpf(queen_stiffness.y, loyal_stiffness.y, c))


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


# 挨打闪一下白。挨咬和摔墙是两条独立的伤害路径，但都落在同一份血量上，
# 接 damaged 就不用在两边各写一遍——以后再加第三条也自动有
# Bites and slams are separate paths onto one health pool; hooking the signal covers
# both, and whatever comes third.
func _on_damaged(_amount: int, _remaining: int, _from: Vector2) -> void:
	if not _health.is_alive():
		return
	_juice.hit_flash(_body_sprite)

func _on_died(_from: Vector2) -> void:
	_carry.drop()
	_juice.burst()

	AudioManager.create_2d_audio_at_location(global_position, SoundEffect.SoundEffectType.WASP_DEATH)
	if _fly_player != null:
		_fly_player.stop()

	# 只有你摔死的才算处决。被猎手咬死的忠诚工蜂要是也记在你头上，
	# unrest 白涨 0.2、周围的蜂白记一次仇，而玩家根本没动手
	# 清叛军不算处决：它们是纯敌人，杀它们既不该推不安，也不该让旁观的蜂记仇
	if _slain_by_player and not _allegiance.is_rebel():
		var director: BetrayalDirector = BetrayalDirector.find(get_tree())
		if director != null:
			director.report_execution(self, _allegiance.was_false_queen)

	died.emit(self, global_position)
	
	# Turn off AI and interactions
	_btree.active = false
	if _draggable != null:
		_draggable.set_deferred("input_pickable", false)
		_draggable.set_deferred("monitorable", false)
		_draggable.set_deferred("monitoring", false)
		

	# Stop flying animation, switch to the 1-frame death pose
	if _animator != null:
		if _animator.has_clip(&"die"):
			_animator.play(&"die", true)
		else:
			_animator.set_process(false)
	
	# Remove from collision layer
	set_deferred("collision_layer", 0)
	
	gravity_scale = 1.0
	
	# --- DISABLE JUICE ---
	var dead_scale: Vector2 = _juice.base_scale
	
	_juice.target = null
	
	# If the component has particles attached, you can safely hide them now
	if _juice.has_method("hide"):
		_juice.hide() 

	set_process(false)
	set_physics_process(false)
	# Wait 5 seconds while the corpse lies on the ground
	await get_tree().create_timer(5.0).timeout
	
	if not is_instance_valid(self):
		return

	# Freeze physics completely before the fade
	set_deferred("freeze", true)
	set_deferred("collision_mask", 0)

	# Pop and fade out
	var pop_scale: float = 1.7
	var fade_duration: float = 0.6
	
	var tween: Tween = create_tween().set_parallel(true)
	
	# We use 'dead_scale' here instead of _juice.base_scale
	tween.tween_property(_visual, "scale", dead_scale * pop_scale, fade_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual, "modulate:a", 0.0, fade_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


# Code for instant death animation as the enemy does

# func _on_died(_from: Vector2) -> void:
# 	_carry.drop()
# 	_juice.burst()

# 	# 只有你摔死的才算处决。被猎手咬死的忠诚工蜂要是也记在你头上，
# 	# unrest 白涨 0.2、周围的蜂白记一次仇，而玩家根本没动手
# 	# 清叛军不算处决：它们是纯敌人，杀它们既不该推不安，也不该让旁观的蜂记仇
# 	if _slain_by_player and not _allegiance.is_rebel():
# 		var director: BetrayalDirector = BetrayalDirector.find(get_tree())
# 		if director != null:
# 			director.report_execution(self, _allegiance.was_false_queen)

# 	died.emit(self, global_position)
	
# 	# Turn off AI and interactions
# 	_btree.active = false
# 	if _draggable != null:
# 		_draggable.set_deferred("input_pickable", false)
# 		_draggable.set_deferred("monitorable", false)
# 		_draggable.set_deferred("monitoring", false)
		
# 	set_process(false)
# 	set_physics_process(false)

# 	# 原地停住，不要飞出去 / stop dead, no ragdoll flight
# 	linear_velocity = Vector2.ZERO
# 	angular_velocity = 0.0
# 	set_deferred("freeze", true)
# 	set_deferred("collision_layer", 0)
# 	set_deferred("collision_mask", 0)

# 	# 死亡段停在最后一帧，尸体保持死的样子 / the corpse holds its last frame
# 	var linger: float = 0.0
# 	if _animator != null and _animator.has_clip(&"die"):
# 		_animator.play(&"die", true)
# 		# 强制多等 0.8 秒，确保你能看清这个只有 1 帧的动画
# 		# Add 0.8 seconds to the clip duration so you can clearly see the death frame
# 		linger = _animator.clip_duration(&"die") + 0.8

# 	# 膨胀一下再消散。跟敌人的 juice 一样，但更慢
# 	# Pop and fade out, using the same logic as the enemy but slower.
# 	var pop_scale: float = 1.7
# 	var fade_duration: float = 0.6 # Slower than the enemy's 0.32
	
# 	var tween: Tween = create_tween().set_parallel(true)
# 	if linger > 0.0:
# 		tween.tween_interval(linger)
# 		tween = tween.chain().set_parallel(true)
	
# 	# 注意这里乘的是 _juice.base_scale，否则吃过蜂王浆的巨大黄蜂死时会瞬间缩水
# 	# Multiply by _juice.base_scale so jelly-fed wasps keep their size when dying.
# 	tween.tween_property(_visual, "scale", _juice.base_scale * pop_scale, fade_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
# 	tween.tween_property(_visual, "modulate:a", 0.0, fade_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
# 	tween.chain().tween_callback(queue_free)
		



# center 给 INF 就绕自己的落点转；Idle 会把巢的位置传进来
# INF means "drift around my own drop point"; Idle passes the hive in.
func _pick_wander_target(center: Vector2 = Vector2.INF, radius: float = -1.0) -> void:
	var home: Vector2 = _wander_home if center == Vector2.INF else center
	var spread: float = wander_radius if radius < 0.0 else radius
	var angle: float = randf_range(0.0, TAU)
	var dist: float = sqrt(randf()) * spread
	# 吸附回导航网格。不吸的话靠墙的 home 有一半游荡点落在墙里，
	# 目标不可达 → 退回直线 steering → 黄蜂直接碾在墙上磨到计时器超时
	# Snap back onto the navmesh: near a wall half the wander points land inside it,
	# the target reads as unreachable, steering falls back to a straight line, and the
	# wasp grinds against the wall until the retarget timer fires.
	_wander_target = _snap_to_navmesh(home + Vector2(cos(angle), sin(angle)) * dist)
	_wander_timer = retarget_interval * randf_range(0.7, 1.3)


func _snap_to_navmesh(point: Vector2) -> Vector2:
	if not is_inside_tree():
		return point
	var map: RID = get_world_2d().navigation_map
	if not map.is_valid():
		return point
	return NavigationServer2D.map_get_closest_point(map, point)


# Called continuously by Idle.gd BTAction
# center/radius/speed 不给就用落点和 @export 的那几个值，给了就绕指定的地方转
# Defaults keep the old behaviour; Idle passes the hive so idle wasps gather there.
func wander(delta: float, center: Vector2 = Vector2.INF, radius: float = -1.0, speed: float = -1.0) -> void:
	_wander_timer -= delta
	var to_target: Vector2 = _wander_target - global_position

	if _wander_timer <= 0.0 or to_target.length() < 18.0:
		_pick_wander_target(center, radius)

	# 游荡的制动半径得比干活时小：完全不制动会全速冲过目标点，
	# 靠墙的游荡点冲过头就是撞墙；用 arrive_radius 那么大又会让待机黄蜂营营地爬
	# Smaller brake radius than working moves: none at all overshoots into walls,
	# the full arrive_radius makes idle wasps crawl.
	steer_towards(_wander_target, delta, wander_speed if speed < 0.0 else speed, 0.08, 40.0)


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
	# --- Wasp Fly Loop ---
	if _fly_player != null and _fly_player.stream != null:
		var is_moving: bool = _health.is_alive() and linear_velocity.length() > 15.0 and not _draggable.is_grabbed()
		if is_moving:
			if not _fly_player.playing:
				_fly_player.play()
		else:
			if _fly_player.playing:
				_fly_player.stop()

	_last_speed = linear_velocity.length()
	# 冷却计时得走在提前 return 之前，否则被甩飞的黄蜂冷却会冻住
	# Must tick before the early returns - a flung wasp would freeze its cooldown otherwise.
	if _attack_timer > 0.0:
		_attack_timer = maxf(_attack_timer - delta, 0.0)
	if _impact_timer > 0.0:
		_impact_timer = maxf(_impact_timer - delta, 0.0)

	# 拿在手上、飞在空中、站在加冕队列里的时候不重新掂量：那几段行为树本来就不在跑，
	# 换了岗位也没人执行，落地时 set_wander_home 会重算一次
	# Not while held, flung, or attending - the tree is off in all three and landing re-runs it.
	if _btree.active and not _draggable.is_grabbed():
		_reconsider_timer -= delta
		if _reconsider_timer <= 0.0:
			_choose_job()
	if not _is_flung:
		# 拿在手上时别推：拖拽弹簧和这里都写 linear_velocity，两边会打架
		# Never while held - the drag spring writes the same velocity we would.
		if _attend_target != Vector2.INF and not _draggable.is_grabbed():
			# 方向还是听导航的：蜂可能在上带，直线飞过去会顶在巢室的墙上
			# Still navmesh-guided: a straight line from the upper band walks into a wall.
			# 制动半径要比容差大不少，转向权重也调高：站位是个点不是个区域，
			# 刹车刹得晚就会绕着自己的位置来回过冲，到场率永远差最后一口气
			# Brake early and steer hard - a slot is a point, and late braking orbits it.
			steer_towards(_attend_target, delta, attend_speed, 0.35, 30.0)
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

		


# 摔墙 / thrown into a wall.
# **只认静态墙体**：蜂撞蜂、蜂撞纸板都会走到这里，不过滤的话巢里挤着的十几只
# 会互相把对方撞死，减员跟玩家的手一点关系都没有
# Static bodies only - wasps jostle constantly, and counting that would quietly
# kill off the hive with nobody's hand on it.
func _on_body_entered(body: Node) -> void:
	if _last_speed < impact_speed or not (body is StaticBody2D):
		return

	# 被摔的黄蜂会记住。玩家拿它们当保龄球是有代价的
	# A slammed wasp remembers it - using them as bowling balls is not free.
	var director: BetrayalDirector = BetrayalDirector.find(get_tree())
	if director != null:
		director.report_slam(self)
	_juice.punch(0.78, 0.28)

	# 先结算伤害，再决定放不放通用迸射。揭穿她的那一下要**独占**这一帧：两团粒子叠在
	# 一起，玩家看到的就是平时打谁都有的那个暖黄爆点，星芒埋在里面根本读不出来
	# Damage first, so the burst knows whether this hit was the unmasking one - stacked
	# in one frame the familiar amber pop buries the stars and the effect is wasted.
	#
	# 判断必须用「**真的**揭穿了吗」，不能用「她是不是伪王后」：攥在手里贴着墙磨的那条
	# 路径根本走不到 unmask，用后者的话「迸射消失了」本身就成了一个零成本的探测器
	# Must ask whether the mask actually came off: a wasp held against a wall never
	# unmasks, and a missing burst would be a free detector.
	var unmasked: bool = _take_impact_damage()
	if _last_speed > impact_speed * 2.0 and not unmasked:
		_juice.burst()
	slammed.emit(_last_speed)


# 甩出去撞墙掉血。一次投掷弹好几面墙就是好几下，这是故意留的——
# 它自己会收敛，每次反弹速度大约减半，两三跳之后就低于 impact_speed 不再计数
# A single throw that ricochets lands several hits on purpose; it converges on its own,
# since each bounce roughly halves the speed until it drops under the threshold.
#
# 不走 take_damage()：那条是挨咬的路，会再记一次 report_wound，
# 而这一下已经由上面的 report_slam 记过账了
# Not take_damage(): that is the bite path and would file a second grudge for one hit.
# 返回「面具是不是这一下掉的」，调用方拿它决定放不放通用迸射
# Returns whether this hit is the one that took the mask off.
func _take_impact_damage() -> bool:
	if impact_damage <= 0 or _impact_timer > 0.0 or not _health.is_alive():
		return false
	# 还攥在手里的不算。不挡这一条的话按住她贴着墙磨 0.45 秒就能弄死，
	# 投掷机制当场退化回一击必杀的另一种按法
	# Not while she is still in your hand: grinding her along a wall would kill in 0.45s
	# and turn the throw back into a one-button execution.
	if _draggable.is_grabbed():
		return false
	_impact_timer = impact_damage_cooldown

	AudioManager.create_2d_audio_at_location(global_position, SoundEffect.SoundEffectType.WASP_HIT)

	# 摔一下面具就掉：她当场变回普通工蜂，停止下卵。伤害照扣，她跟别的蜂一样能被摔死。
	# 已经孵出来的叛军不跟着解散——那些是你自己惹出来的，自己清
	# One slam unmasks her: she reverts to an ordinary worker and stops laying. The hit
	# still lands, and her existing rebels stay rebels.
	var unmasked: bool = _allegiance.is_false_queen()
	if unmasked:
		# 颜色要在 unmask() **之前**读：那个函数第一句就把 brood_variant 清空了
		# Read the colour first - unmask() nulls brood_variant on its opening line.
		var brood: WaspVariant = _allegiance.brood_variant
		_allegiance.unmask()
		_spill_disguise(brood)
		var unmask_director: BetrayalDirector = BetrayalDirector.find(get_tree())
		if unmask_director != null:
			unmask_director.report_unmasked(self)

	# 死因必须在扣血**之前**定下来：_health.died 是同步发的，_on_died 当场就要读它
	# Set before the hit lands - died fires synchronously and _on_died reads this.
	_slain_by_player = true
	_health.take_damage(impact_damage, global_position)
	if _health.is_alive():
		_slain_by_player = false
	return unmasked


# 面具掉了那一下。挂到**世界层**而不是她身上：她被这一下撞飞了，这团还留在原地
# 慢慢飘散，读起来才是"从她身上掉下来的东西"，而不是她自带的光效
# Parented to the world on purpose - it should stay where it fell, not ride along with her.
func _spill_disguise(brood: WaspVariant) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var puff: RevealBurst = REVEAL_BURST.instantiate()
	host.add_child(puff)
	puff.global_position = global_position
	puff.play(brood.body_color if brood != null else DISGUISE_SPILL_FALLBACK)


func _process(delta: float) -> void:
	_t += delta

	_face_travel()
	_visual.position.y = sin(_t * TAU / bob_period) * bob_amount


# 只分左右，**不做任何旋转**。贴图有固定的上方，转起来会出现肚皮朝天。
# 图本身画的是朝左，所以往右飞才翻面。
# 之前是让贴图去追 linear_velocity.angle()，而黄蜂之间会撞、RVO 每帧改方向，
# 被撞一下速度就翻，图跟着甩——那才是"乱转"的来源，不是平滑不够。
# Left/right only, never rotated: the art has a fixed up. It used to chase the raw
# velocity angle, which every collision and every RVO nudge yanked around.
func _face_travel() -> void:
	if _body_sprite == null:
		return
	var vx: float = linear_velocity.x
	if absf(vx) < flip_threshold:
		return
	_body_sprite.flip_h = vx > 0.0


# 真的打出去了才返回 true，冷却中返回 false
# Returns true only when the sting actually landed; false while on cooldown.
# 挨咬 / bitten. 猎手走这条；玩家摔墙走 _take_impact_damage()，两条最后都落在同一份血量上
# Hunters come through here; a player's throw goes through _take_impact_damage().
func take_damage(amount: int, from: Vector2 = Vector2.ZERO) -> bool:
	if not _health.is_alive():
		return false
	if not _health.take_damage(amount, from):
		return false

	AudioManager.create_2d_audio_at_location(global_position, SoundEffect.SoundEffectType.WASP_HIT)

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


# 她被扶上了王座 / crowned. 纯表现，一个状态都不改
func hail() -> void:
	_juice.punch(1.45, 0.55)
	_juice.burst()


# 冬天带走的 / taken by winter.
# 不算处决、不记任何人的账，走的还是同一条死亡链（掉货、迸一下、发 died）
# Not an execution and nobody's grudge, but the same death chain all the same.
func perish() -> void:
	if not _health.is_alive():
		return
	_slain_by_player = false
	_health.take_damage(_health.health, global_position)


func attack_enemy() -> bool:
	if target_enemy == null or not is_instance_valid(target_enemy):
		return false
	if _attack_timer > 0.0:
		return false
	if not target_enemy.has_method("take_damage"):
		return false

	target_enemy.take_damage(attack_damage(), global_position)
	_attack_timer = attack_cooldown
	# 一次性段，播完自己回飞行 / one-shot: the animator hands back to the fly loop
	
	AudioManager.create_2d_audio_at_location(global_position, SoundEffect.SoundEffectType.WASP_ATTACK)
	
	if _animator != null:
		_animator.play(&"attack", true)
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
