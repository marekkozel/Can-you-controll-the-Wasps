class_name Enemy
extends RigidBody2D

# 敌人 / an enemy. 平时不存在，由 RaidDirector 成批放进来直扑巢室 / raiders, not scenery.
# 鼠标点一下能打，工蜂也能叮（take_damage）/ clickable by the player, stingable by wasps.
# 用刚体本身的 input_event 收点击，不额外挂 Area2D / the body is pickable, no extra Area2D.
# 游荡和入侵是互斥的：两边都写 linear_velocity / wander and raid both write linear_velocity.

signal killed(enemy: Enemy)

## 品种：颜色 + 血量 + 干什么。不设就是默认的小偷色和 1 血
## Breed - colour, health, and which behaviour component runs. See EnemyVariant.
@export var variant: EnemyVariant

@export_group("Combat")
## 每次点击造成几点伤害 / damage per click
@export_range(1, 20, 1) var click_damage: int = 1
## 击退力度，只对没被打死的生效。跟黄蜂一样 lock_rotation，所以只推不转——
## 打一下就转个角度的话贴图朝向会乱掉，也看不出它在往哪走
## Knockback on non-lethal hits. Rotation is locked like the wasp's: shoved, never spun.
@export_range(0.0, 4000.0, 10.0) var knockback_force: float = 280.0

@export_group("Juice")
## 命中瞬间的卡顿时长（真实秒，不受 time_scale 影响）/ hit stop, in real seconds
@export_range(0.0, 0.3, 0.01) var hit_stop_duration: float = 0.05
## 卡顿期间的时间倍率 / time scale during the hit stop
@export_range(0.01, 1.0, 0.01) var hit_stop_scale: float = 0.05
## 死亡时膨胀到多大 / how far it swells before it pops
@export_range(1.0, 4.0, 0.05) var death_pop_scale: float = 1.7
## 膨胀消散用多久 / how long the pop takes
@export_range(0.05, 2.0, 0.05) var death_duration: float = 0.32
@export var hover_tint: Color = Color(1.35, 1.1, 1.1)

@onready var _visual: Node2D = $Visual
@onready var _health: HealthComponent = $HealthComponent
@onready var _juice: JuiceComponent = $JuiceComponent
@onready var _wander: WanderComponent = $WanderComponent
@onready var _raid: RaidComponent = $RaidComponent
@onready var _hunt: HuntComponent = $HuntComponent
@onready var _loot: LootComponent = $LootComponent
@onready var _animator: SpriteAnimator = get_node_or_null(^"SpriteAnimator") as SpriteAnimator

## 同一帧多个敌人被打时只卡一次 / guard so overlapping hits don't stack
static var _hit_stop_busy: bool = false

var _is_dead: bool = false

# 场景里那几个 reach 是照这个半径调的，别的体型按差值往上补
# The scene's reach values are tuned for this radius; other builds scale off it.
const BUILD_REFERENCE_RADIUS: float = 22.0


func _ready() -> void:
	_juice.target = _visual
	_apply_variant()

	input_pickable = true
	input_event.connect(_on_input_event)
	mouse_entered.connect(func(): if not _is_dead: _visual.modulate = hover_tint)
	mouse_exited.connect(func(): if not _is_dead: _visual.modulate = Color.WHITE)

	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)

	# 咬蜂和啃巢室是两个组件各自的事，这里只借它们已有的信号播动画，
	# 不往组件里塞"通知父级"那种反向依赖 / animation rides existing signals, no back-reference
	_hunt.bit.connect(func(_victim): _play(&"attack", true))
	_raid.raided.connect(func(_cell, _took): _play(&"attack", true))

	_visual.scale = Vector2.ZERO
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
		.tween_property(_visual, "scale", Vector2.ONE, 0.3)


func set_wander_home(position: Vector2) -> void:
	_wander.set_home(position)


# 入场。开哪个组件由品种决定，exit_point 是收兵时往哪撤
# Which component drives it is the breed's call; exit_point is where it leaves from.
func begin_raid(exit_point: Vector2 = Vector2.INF) -> void:
	_wander.enabled = false
	if hunts():
		# 猎手不碰巢室，但离场还是走 RaidComponent，两种敌人共用一条撤退逻辑
		# Hunters never touch a cell, but they leave through RaidComponent all the same.
		_raid.arm_exit(exit_point)
		_hunt.begin()
		return
	_raid.begin(exit_point)


# 时间到了收兵，路上照样能被打死 / called off; still killable on the way out
func retreat() -> void:
	_hunt.stop()
	_raid.retreat()


func hunts() -> bool:
	return variant != null and variant.behavior == EnemyVariant.Behavior.HUNTER


func is_raiding() -> bool:
	if _is_dead:
		return false
	return _hunt.hunting or _raid.is_raiding()


# 血量要在 HealthComponent._ready() 之后再写：子节点先 _ready，那时 health 已经按
# max_health 初始化过一遍了，只改 max_health 不改 health 会得到一只 1 血的敌人
# Children _ready first, so health is already initialised - both fields must be set here.
func _apply_variant() -> void:
	if variant == null:
		return
	_health.max_health = variant.max_health
	_health.health = variant.max_health
	_loot.count = variant.loot_count
	_apply_build()

	# 三种敌人各有一张彩色专图，再乘 body_color 就是乘两遍，一片脏。
	# 那几个颜色字段是灰度占位图那个年代留下的，只在没给 texture 时才有意义
	# The colour fields date from the greyscale placeholders; a real sprite overrides them.
	if variant.texture != null:
		var body: Sprite2D = _visual.get_node_or_null(^"Body") as Sprite2D
		if body != null:
			body.self_modulate = Color.WHITE
		return

	_tint(_visual.get_node_or_null(^"Body"), variant.body_color)
	_tint(_visual.get_node_or_null(^"Sheen"), variant.sheen_color)
	_tint(_visual.get_node_or_null(^"Head"), variant.head_color)
	_tint(_visual.get_node_or_null(^"EyeL"), variant.eye_color)
	_tint(_visual.get_node_or_null(^"EyeR"), variant.eye_color)
	var outline: Line2D = _visual.get_node_or_null(^"Outline") as Line2D
	if outline != null:
		outline.default_color = variant.outline_color


# 体型：贴图、碰撞、速度。三种敌人共用 Enemy.tscn，靠这里拉开
# One scene for all three builds; this is where they stop looking alike.
func _apply_build() -> void:
	var body: Sprite2D = _visual.get_node_or_null(^"Body") as Sprite2D
	if body != null and variant.texture != null:
		body.texture = variant.texture
		body.offset = variant.sprite_offset  # 图的中心 = 实体原点 / art centre is the origin

	# 图集切几列几行由动画表说了算，所以必须在贴图换完之后 / the table owns the grid
	if _animator != null:
		_animator.set_animation(variant.animation)
		if variant.animation == null and body != null:
			body.hframes = 1  # 静态图别留着上一张图集的切法 / a still is one cel
			body.vframes = 1

	# CircleShape2D 是场景里的 SubResource，实例之间**共享**——直接改半径会改全场，
	# 最后一只生成的敌人的体型会套到所有敌人身上。跟 DragProfile 一个坑
	# Shapes authored in a scene are shared between instances; duplicate before touching.
	var col: CollisionShape2D = get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if col != null:
		var circle: CircleShape2D = col.shape as CircleShape2D
		if circle != null:
			circle = circle.duplicate()
			circle.radius = variant.collision_radius
			col.shape = circle

	mass = variant.body_mass

	if _wander != null:
		_wander.speed = variant.move_speed

	# 追击速度也得跟着品种走。以前这里只写了 wander，三种猎手全在用组件默认的 125，
	# .tres 里那些速度对追击完全没影响
	# Chase speed used to stay at the component default for every breed.
	if _hunt != null:
		_hunt.fly_speed = variant.chase_speed

	# **判定距离必须大于两者碰撞半径之和，否则永远走不到。**
	# 场景里的 reach 是照中型（半径 22）调的：蜘蛛半径 48，加上黄蜂 grab 的 23，
	# 不放大的话它会贴着蜂原地转圈，一口也咬不着
	# Scene reach is tuned for the medium build; the spider would never land a bite.
	var grew: float = maxf(0.0, variant.collision_radius - BUILD_REFERENCE_RADIUS)
	if grew > 0.0:
		if _hunt != null:
			_hunt.reach += grew
		if _raid != null:
			_raid.reach += grew

	var bar: Node2D = get_node_or_null(^"HealthBarComponent") as Node2D
	if bar != null:
		bar.visible = variant.show_health_bar


# 没接动画表的品种（还是静态图）就什么都不做，不刷警告
# A breed with no table is a still image, not a mistake.
func _play(clip_name: StringName, restart: bool = false) -> void:
	if _animator != null and _animator.has_clip(clip_name):
		_animator.play(clip_name, restart)


func _tint(node: Node, color: Color) -> void:
	var poly: Polygon2D = node as Polygon2D
	if poly != null:
		poly.color = color
		return
	var sprite: Sprite2D = node as Sprite2D
	if sprite != null:
		sprite.self_modulate = color  # 贴图画灰度，白 x 色 = 色 / greyscale sprites tint clean


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if _is_dead:
		return
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		return

	_health.take_damage(click_damage, get_global_mouse_position())
	get_viewport().set_input_as_handled()  # 别让点击穿到下面的东西 / don't let it fall through

# take_damage function for the wasp to attack the enemy
func take_damage(amount: int, from: Vector2) -> void:
	if _is_dead:
		return
	_health.take_damage(amount, from)

func _on_damaged(_amount: int, remaining: int, from: Vector2) -> void:
	_juice.burst()
	_hit_stop()

	# 被打死的走 _on_died 的膨胀消散，别在这里再动 scale，两个 tween 会抢
	# A lethal hit pops in _on_died; don't touch scale here or the tweens fight.
	if remaining <= 0:
		return

	var direction: Vector2 = (global_position - from).normalized()
	if direction == Vector2.ZERO:  # 正好点在中心 / clicked dead centre
		direction = Vector2.RIGHT.rotated(randf() * TAU)

	# 只在击退期间停游荡，落地后要开回来。以前这里是永久关闭——1 血时非致命分支
	# 根本走不到第二次所以没人发现，敌人一有血量就会让散兵挨一下之后永久僵住
	# Wander must come back: this used to switch off for good, which only stayed invisible
	# while one hit was always lethal.
	_wander.enabled = false
	apply_central_impulse(direction * knockback_force)
	_juice.punch(0.65, 0.3)
	_resume_wander_after_knockback()


func _on_died(_from: Vector2) -> void:
	_is_dead = true
	input_pickable = false
	_wander.enabled = false
	_raid.stop()  # 不停的话组件会继续给冻住的尸体写速度 / else it steers a frozen corpse
	_hunt.stop()
	_visual.modulate = Color.WHITE
	set_process(false)
	killed.emit(self)

	# 原地停住，不要飞出去 / stop dead, no ragdoll flight
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	set_deferred("freeze", true)
	$CollisionShape2D.set_deferred("disabled", true)

	# 死亡段停在最后一帧，尸体保持死的样子 / the corpse holds its last frame
	var linger: float = 0.0
	if _animator != null and _animator.has_clip(&"death"):
		_animator.play(&"death", true)
		linger = _animator.clip_duration(&"death")

	# 膨胀一下再消散。有死亡动画的话先让它播完，不然刚死就被淡掉了
	# The pop waits out the death clip, or the animation would never be seen.
	var tween: Tween = create_tween().set_parallel(true)
	if linger > 0.0:
		tween.tween_interval(linger)
		tween = tween.chain().set_parallel(true)
	tween.tween_property(_visual, "scale", Vector2.ONE * death_pop_scale, death_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual, "modulate:a", 0.0, death_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


# 击退飞完再恢复游荡。入侵中的敌人本来就没开游荡，这条只对散兵有意义
# Only loose wanderers care - a raider never had wander on in the first place.
func _resume_wander_after_knockback() -> void:
	await get_tree().create_timer(0.6).timeout
	if _is_dead or not is_instance_valid(self):
		return
	if not _raid.is_raiding() and not _hunt.hunting:
		_wander.enabled = true


# 命中卡顿。用真实时间计时，不然自己会被自己的减速拖长
# Hit stop. Timed in real seconds, otherwise it would stretch itself out.
func _hit_stop() -> void:
	if hit_stop_duration <= 0.0 or _hit_stop_busy:
		return
	_hit_stop_busy = true
	var previous: float = Engine.time_scale
	Engine.time_scale = hit_stop_scale
	await get_tree().create_timer(hit_stop_duration, true, false, true).timeout
	Engine.time_scale = previous
	_hit_stop_busy = false
