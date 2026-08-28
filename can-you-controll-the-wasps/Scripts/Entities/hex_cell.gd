@tool
class_name HexCell
extends Area2D

# 蜂巢的一格 / one hive cell.
# 只管状态和接线：建造进度、内容槽、把组件信号转成反馈 / state and wiring only.
# 效果本身在 JuiceComponent 和 BroodTimer 里 / the effects live in those components.
#
# 按住干什么取决于内容：空的产卵，腐烂的清理 / hold does a different thing per content.

signal clicked(cell: HexCell)
signal hover_changed(cell: HexCell, is_hovered: bool)
signal progress_changed(cell: HexCell, progress: int, required: int)
signal built(cell: HexCell)
signal egg_laid(cell: HexCell)
signal larva_hatched(cell: HexCell)
signal larva_hungry(cell: HexCell)
signal larva_starved(cell: HexCell)
signal sealed(cell: HexCell)
signal wasp_emerged(cell: HexCell, wasp: Wasp)
signal cleaned(cell: HexCell)
## 伪王后偷偷下了一颗 / a false queen slipped an egg in here
signal rebel_egg_laid(cell: HexCell, variant: WaspVariant)
signal rebel_hatched(cell: HexCell, wasp: Wasp)
## 叛军听掉了建造进度 / a rebel chewed this cell back down
signal build_damaged(cell: HexCell, progress: int, required: int)
## 里面的卵或幼虫被弄死了。不复用 larva_starved——"饿死"和"被杀"在背叛数值里权重不一样
## Not larva_starved: starving and being murdered must stay distinguishable.
signal occupant_destroyed(cell: HexCell)

enum Content { NONE, EGG, LARVA, SEALED, ROTTEN }

# 卵的染色 / egg recolour. Cells.png 的 frame 4 把卵画成青色，那不是玩家看到的颜色——
# 它只是个锚点，好让 shader 能把「卵的像素」和「巢室的像素」分开：巢室是 H=24..39 的
# 黄橙，卵是 H=171..186 的青，隔了 130 度，窗口再宽也咬不到巢室。
# The egg is painted cyan in the sheet purely so the shader can tell it from the cell -
# players never see cyan, it is tinted back to amber on the way to the screen.
const RECOLOUR: Shader = preload("res://Assets/Shaders/recolour.gdshader")
const EGG_REFERENCE: Color = Color(0.459, 0.941, 0.996)  # #75f0fe，图里那个青
const EGG_NORMAL: Color = Color(0.996, 0.812, 0.459)     # #fecf75，正常卵染回来的暖黄

const EGG_SCENE: PackedScene = preload("res://Scenes/Entities/Egg.tscn")
const LARVA_SCENE: PackedScene = preload("res://Scenes/Entities/Larva.tscn")
## **不能用 const preload。** 本脚本是 @tool，编辑器扫描阶段就会编译它，而那时
## Wasp.tscn 里的 BTPlayer(limboai GDExtension) 未必就绪——preload 会拿到一个
## node count 为 0 的空 PackedScene，并把这个空壳**永久固化进常量**。
## 后果是 instantiate() 一路返回 null，伪王后的异色卵一只叛军都孵不出来，
## 而且不报任何跟 limboai 有关的错，只说 "Failed to instantiate scene state of """。
## Egg/Larva 用 const 没事：它们不含 GDExtension 节点。
##
## Never const-preload a scene containing GDExtension nodes from a @tool script: it can
## be compiled before the extension is ready and the empty result is cached forever.
const WASP_SCENE_PATH: String = "res://Scenes/Entities/Wasp.tscn"
static var _wasp_scene: PackedScene
## 羽化出来的黄蜂挂到哪一层 / group that hosts emerged wasps
const ENTITIES_GROUP: StringName = &"entities"
## 喂下蜂王浆时格子闪的颜色 / the flash a jelly feeding paints on the cell
const JELLY_FLASH: Color = Color(1.0, 0.86, 0.35)

# 顶部读数的三种含义。方向也带信息：成熟正着长，倒计时反着退
# The three meanings of the top readout - maturing grows, countdowns drain.
## 孵化 / 羽化 / maturing
const MATURE_COLOR: Color = Color(0.56, 0.83, 0.89)
## 救援窗口，见底就死 / the rescue window
const HUNGRY_COLOR: Color = Color(0.98, 0.55, 0.3)
## 饱腹那 60 秒，只是预告 / the satiated stretch, just a heads-up
const CALM_COLOR: Color = Color(0.24, 0.42, 0.44)
## 玩家按住产卵 / 清理。只有这一条是你按出来的，所以独占黄色
## The only readout the player drives - it keeps the yellow to itself.
const HOLD_COLOR: Color = Color(1.0, 0.902, 0.502)

## 建成这一格要几块纸板 / cardboard pieces needed to build
@export_range(1, 10, 1) var build_cost: int = 3
## 产卵要按住多久 / hold seconds to lay an egg
@export_range(0.5, 30.0, 0.5) var lay_duration: float = 3.0
## 清理腐烂要按住多久 / hold seconds to clear rot
@export_range(0.5, 30.0, 0.5) var clean_duration: float = 2.0

## 冬天王座的底色。判定在 SeasonDirector 那边，这里只管认领和上色
## The throne's tint - the rules live on SeasonDirector, this only wears the badge.
@export var royal_color: Color = Color(1.0, 0.86, 0.45)

@export_group("Idle")
@export var fill_color: Color = Color(0.95, 0.75, 0.25, 0.1)
@export var hover_color: Color = Color(0.98, 0.85, 0.45, 0.3)
@export var border_color: Color = Color(0.94, 0.78, 0.3, 0.55)
@export_range(0.5, 20.0, 0.5) var border_width: float = 2.0

@export_group("Built")
@export var built_fill_color: Color = Color(0.95, 0.72, 0.2, 0.38)
@export var built_border_color: Color = Color(1.0, 0.87, 0.42, 1.0)
## 建成后的边框宽度，"加粗" 就是这个值 / border width once built
@export_range(0.5, 20.0, 0.5) var built_border_width: float = 7.0

@export_group("Juice")
## 抖动幅度上限 / cap on the shake amplitude
@export_range(0.0, 12.0, 0.1) var max_shake: float = 0.4
## 抖动随按住进度怎么长。留空走 smoothstep：两头平、中段起，
## 末段收住不炸——收尾的爆点已经由 punch + flash + burst 给了，抖动再冲一次就是重复
## Leave empty for a smoothstep ramp. The climax is already carried by the punch,
## the flash and the burst; a convex shake on top of them just doubles the same beat.
@export var shake_curve: Curve = null
@export var flash_color: Color = Color(1.0, 0.98, 0.85, 0.9)
@export var rotten_fill_color: Color = Color(0.36, 0.31, 0.24, 0.55)
@export var sealed_border_color: Color = Color(0.85, 0.66, 0.32, 1.0)

# 里面这颗是不是异色卵。叛军靠它认自己人，不然会把自己姐妹吃了
# Rebels check this to spare their own brood - without it they eat their siblings.
var rebel_brood: bool = false
# 叛乱身份要跨过 卵→幼虫→封盖 三个阶段才轮到羽化，所以存在格子上，不 bind 在信号里
# mother 不加类型：她可能在孩子长大之前就被处决了 / untyped, she may be dead by then
var _rebel_variant: WaspVariant = null
var _rebel_mother = null
## 这一格吃下了几份蜂王浆。羽化时刻印给新蜂，然后清零；幼虫死了就作废
## Jelly fed to this cell's brood; stamped at emergence, written off if the brood dies.
var _gifts: int = 0
var coord: Vector2i = Vector2i.ZERO
var progress: int = 0
var is_built: bool = false
var content: Content = Content.NONE
var _egg_tint: Color = EGG_NORMAL  # 异色卵会把它换成血统色 / a rebel egg swaps this
## 这一格是不是当代的王座 / is this winter's throne
var is_royal: bool = false

@onready var _shape: CollisionPolygon2D = $Shape
@onready var _hold: HoldComponent = $HoldComponent
@onready var _juice: JuiceComponent = $JuiceComponent
@onready var _seal_timer: MaturationComponent = $SealTimer
@onready var _brood: BroodTimer = $Visual/BroodTimer

## 基因库。@tool 脚本在编辑器里没有 director，所以查一次就把结果记死（包括查不到）
## Looked up once and remembered, misses included: there is no bank in the editor.
var _bank: GeneBank = null
var _bank_checked: bool = false

@onready var _cell: Sprite2D = $Visual/Cell

var _is_hovered: bool = false
var _occupant: Node2D = null


func _ready() -> void:
	# 显式接线。Visual 是被缩放/抖动的那层，Area2D 本身不能动 / never animate the Area2D
	_juice.target = $Visual

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)

	_hold.hold_progress.connect(_on_hold_progress)
	_hold.hold_tick.connect(_on_hold_tick)
	_hold.hold_completed.connect(_on_hold_completed)
	_seal_timer.progress_changed.connect(_on_seal_progress)
	_seal_timer.matured.connect(_on_seal_matured)
	_update_hold()


# Hive 调用。要在 add_child() 之后，不然 @onready 还没解析 / call after add_child
func setup(layout: HexLayout, hex_coord: Vector2i) -> void:
	coord = hex_coord
	position = layout.axial_to_local(hex_coord)

	# 三层可视件已经是贴图了，只剩碰撞和进度环还要顶点
	# The three visual layers are sprites now; only collision and the ring still need corners.
	var corners: PackedVector2Array = layout.corner_points()
	_shape.polygon = corners

	# 计时件停在顶点上，往上偏多少归它自己管 / parked on the apex; it offsets upwards itself
	var apex: float = 0.0
	for point in corners:
		apex = minf(apex, point.y)
	_brood.position = Vector2(0.0, apex)
	_refresh_visual()


# ---------------- 交付入口 / delivery ----------------

# 拖过来的东西都走这里，由格子决定怎么处理 / single entry point, cell routes by payload
func deliver(payload: StringName, amount: int = 1) -> bool:
	match payload:
		&"cardboard":
			return add_build_progress(amount)
		&"food":
			return _feed_occupant(amount)
		&"royal_jelly":
			return _feed_royal_jelly(amount)
	return false


func add_build_progress(amount: int = 1) -> bool:
	if is_built or amount <= 0:
		return false

	var cost: int = required_build()
	progress = mini(progress + amount, cost)
	_refresh_visual()
	progress_changed.emit(self, progress, cost)

	if progress >= cost:
		is_built = true
		_update_hold()
		built.emit(self)
	return true


# ---------------- 叛乱 / betrayal ----------------

# 异色卵。走的是跟正常卵完全相同的 卵→幼虫→封盖→羽化 链，只是颜色不一样。
# A rebel egg follows the ordinary chain; only its colour differs.
func lay_rebel_egg(variant: WaspVariant, mother: Node2D) -> bool:
	if not can_lay_egg() or variant == null:
		return false

	var egg: Egg = EGG_SCENE.instantiate()
	egg.hatch_scale = _maturation_scale()   # 必须在 add_child 之前 / before autostart fires
	_set_occupant(egg, Content.EGG)
	rebel_brood = true
	# 染的是 Cells.png 那一帧里的卵，不是 Egg 节点——后者 visible = false，从来没上过屏
	# Tints the egg drawn into the cell frame; the Egg node is invisible and always was.
	_egg_tint = variant.body_color  # 异色，看到了就知道巢里进了东西 / visibly not one of ours
	_refresh_visual()
	_rebel_variant = variant
	_rebel_mother = mother
	# 走的是跟正常卵一模一样的那条链：孵成幼虫、要喂、封盖、羽化。
	# 在流程上跳过阶段等于在流程上暴露自己——那就成了 100% 确定的探测器，
	# 而不是线索。她的破绽只准出在颜色上。
	# The same chain as any other egg: skipping stages would be a dead giveaway.
	egg.hatched.connect(_on_egg_hatched)
	egg.progress_changed.connect(_on_brood_progress)
	# 线索全模糊化之后，这一下闪光是唯一不伪装的硬信息：
	# 它告诉你"一秒前有蜂来过这儿"，搜索范围从全场缩到附近那几只。
	# The one tell that is never disguised - it narrows the search from the whole hive
	# to whoever was standing nearby a second ago.
	_juice.flash(_cell, variant.body_color, _base_tint())
	_juice.punch(1.18, 0.32)
	rebel_egg_laid.emit(self, variant)
	return true


# 把巢室里的卵/幼虫弄死，格子变腐烂。完全走现成的腐烂链：
# 玩家得按住清理，清完之前这格不能产卵。一行新逻辑都不用写。
# Reuses the existing rot path wholesale - the player has to hold to clean it out.
func destroy_occupant() -> bool:
	if content != Content.EGG and content != Content.LARVA:
		return false

	_set_occupant(null, Content.ROTTEN)
	_gifts = 0  # 喂进去的蜂王浆跟着这颗一起没了 / the jelly dies with the brood
	_refresh_visual()
	_juice.punch(0.82, 0.35)
	_juice.burst()
	occupant_destroyed.emit(self)
	return true


# 听掉建造进度。里面有卵/幼虫的格不能拆，否则内容槽会悬空
# Chews build progress back down. Occupied cells are off limits or the content slot dangles.
func damage_build(amount: int = 1) -> bool:
	if amount <= 0 or progress <= 0 or content != Content.NONE:
		return false

	var cost: int = required_build()
	progress = maxi(progress - amount, 0)
	if is_built and progress < cost:
		is_built = false
		_update_hold()

	_refresh_visual()
	_juice.punch(0.88, 0.22)
	progress_changed.emit(self, progress, cost)
	build_damaged.emit(self, progress, cost)
	return true


# 第一次真正要用的时候才加载，而且拿到空壳会重新加载一次
# Loaded on first real use, and re-loaded if what we hold turns out to be the empty shell.
static func _wasp_scene_ref() -> PackedScene:
	if _wasp_scene == null or not _wasp_scene.can_instantiate():
		_wasp_scene = load(WASP_SCENE_PATH)
	return _wasp_scene


# 羽化和异色卵孵化共用 / shared by emergence and rebel hatching
func _spawn_wasp() -> Wasp:
	var wasp: Wasp = _wasp_scene_ref().instantiate()
	if wasp == null:
		push_error("HexCell could not instantiate %s at %s" % [WASP_SCENE_PATH, coord])
		return null
	var host: Node = get_tree().get_first_node_in_group(ENTITIES_GROUP)
	if host == null:
		host = get_tree().current_scene
	host.add_child(wasp)
	# 新蜂穿什么颜色、带多少基因加成，全由当代蜂后决定。格子不该知道这些
	# The reigning queen dresses every newborn; the cell has no business knowing how.
	var season: SeasonDirector = SeasonDirector.find(get_tree())
	if season != null:
		season.dress_newborn(wasp)
	# 蜂王浆兑现：一份掷一次，随机点亮一条专长。掷点放在这里而不是喂食那一刻，
	# 是为了让开箱感落在蜂钻出来的瞬间 / rolled here so the reveal lands on emergence
	for i in _gifts:
		wasp.grant_random_trait()
	_gifts = 0
	wasp.global_position = global_position
	wasp.set_wander_home(global_position)
	return wasp


# ---------------- 王座 / the throne ----------------

# 冬天认领中心格。只上色 + 关掉按住，别的都在 SeasonDirector 手里
# Winter claims the centre cell; this only paints it and stops the hold.
func set_royal(on: bool) -> void:
	if is_royal == on:
		return
	is_royal = on
	if _cell != null:
		_cell.self_modulate = _base_tint()
	_update_hold()
	if _juice != null and not Engine.is_editor_hint():
		_juice.punch(1.16, 0.3)


# 登基那一下 / the moment somebody takes it
func celebrate() -> void:
	if _juice == null or Engine.is_editor_hint():
		return
	_juice.punch(1.32, 0.5)
	_juice.burst()


# flash 结束后恢复到哪个底色。硬编码回白色会把王座的高亮擦掉
# Where a flash lands back on - hardcoding white would wipe the throne's badge.
func _base_tint() -> Color:
	return royal_color if is_royal else Color.WHITE


# 腾空一格，不留腐烂。只给王座用——正常玩法里清东西必须按住
# Throne only: in play, clearing a cell always costs a hold.
func clear_content() -> void:
	if content == Content.NONE:
		return
	_set_occupant(null, Content.NONE)
	_gifts = 0  # 喂进去的蜂王浆不能跨过冬天留给下一窝 / jelly never survives the clearing
	_refresh_visual()


# 下一颗普通卵。新皇继位后的那一窝走这里，之后是完整的喂养链
# The new queen's brood comes through here and then onto the ordinary chain.
func lay_egg() -> bool:
	if not can_lay_egg():
		return false
	_lay_egg()
	return true


# ---------------- 内容槽 / content slot ----------------

func _feed_occupant(amount: int) -> bool:
	if content != Content.LARVA or _occupant == null:
		return false
	return (_occupant as Larva).feed(amount)


# 蜂王浆走普通食物那条路：它**占用**幼虫的饭份，不是额外附加。所以一只幼虫最多
# 吃下 required_units 份，加成上限自己就出来了，不用另写规则
# Jelly consumes the larva's meals instead of adding to them, so the cap comes for free.
#
# 账记在格子上而不是幼虫上：幼虫一吃饱就被换成 SEALED 丢掉了，活不到羽化那一刻
# Tracked here because the larva is discarded on satiation and never sees emergence.
func _feed_royal_jelly(amount: int) -> bool:
	if not _feed_occupant(amount):
		return false
	_gifts += amount
	_juice.flash(_cell, JELLY_FLASH, _base_tint())
	_juice.punch(1.22, 0.35)
	return true


func can_lay_egg() -> bool:
	return is_built and content == Content.NONE


func is_rotten() -> bool:
	return content == Content.ROTTEN


func is_hungry_larva() -> bool:
	return content == Content.LARVA and _occupant != null and (_occupant as Larva).is_hungry()


# 喂食**需求**用的连续紧迫度 0~1，跨饱腹和饥饿两段。跟上面那个不是一回事：
# larva_hunger_ratio() 只在已经饿着时才有读数，拿它算需求等于让蜂等到濒死才动身
# Not the same thing as the ratio above, which only starts reading once it is already
# too late to fly out, gather and haul back.
func larva_urgency() -> float:
	if content != Content.LARVA or _occupant == null:
		return 0.0
	return (_occupant as Larva).urgency()


# 喂食排序用，越小越快饿死 / feeding priority, smaller is more urgent
func larva_hunger_ratio() -> float:
	if not is_hungry_larva():
		return 1.0
	return (_occupant as Larva).hunger_ratio()


# 直接推进到下一个阶段，跳过所有计时和拖拽 / force the next stage, skips timers
# 给调试工具和脚本化流程用 / for the debug tools and scripted flows
func advance_stage() -> bool:
	if not is_built:
		return add_build_progress(required_build() - progress)

	match content:
		Content.NONE:
			_lay_egg()
		Content.EGG:
			_on_egg_hatched(_occupant as Egg)
		Content.LARVA:
			_on_larva_satisfied(_occupant as Larva)
		Content.SEALED:
			_seal_timer.stop()
			_on_seal_matured()
		Content.ROTTEN:
			_clean()
		_:
			return false
	return true


func _lay_egg() -> void:
	if content != Content.NONE:
		return
	var egg: Egg = EGG_SCENE.instantiate()
	egg.hatch_scale = _maturation_scale()   # 同上 / same reason
	_set_occupant(egg, Content.EGG)
	egg.hatched.connect(_on_egg_hatched)
	egg.progress_changed.connect(_on_brood_progress)
	egg_laid.emit(self)


func _on_egg_hatched(_egg: Egg) -> void:
	var larva: Larva = LARVA_SCENE.instantiate()
	_set_occupant(larva, Content.LARVA, true)
	larva.scale_satiation(_satiation_scale())
	larva.timer_changed.connect(_on_larva_timer)
	larva.became_hungry.connect(_on_larva_hungry)
	larva.satisfied.connect(_on_larva_satisfied)
	larva.starved.connect(_on_larva_starved)
	_juice.punch(1.15, 0.35)
	_juice.burst()
	larva_hatched.emit(self)


func _on_brood_progress(t: float) -> void:
	_brood.show_progress(t, MATURE_COLOR)


# 饿着的时候才喊，饱腹那段用暗色，是预告不是警报
# Only the rescue window shouts; the satiated stretch stays dim on purpose.
func _on_larva_timer(t: float, critical: bool) -> void:
	_brood.show_progress(t, HUNGRY_COLOR if critical else CALM_COLOR, true)


func _on_larva_hungry(_larva: Larva) -> void:
	larva_hungry.emit(self)
# 喂饱一次就封起来，10 秒后出黄蜂 / one full feed seals it, wasp emerges after the timer
func _on_larva_satisfied(_larva: Larva) -> void:
	_set_occupant(null, Content.SEALED, true)
	_seal_timer.start(_seal_timer.duration * _maturation_scale())
	_juice.punch(1.18, 0.4)
	_refresh_visual()
	sealed.emit(self)


func _on_seal_progress(t: float) -> void:
	_brood.show_progress(t, MATURE_COLOR)


func _on_seal_matured() -> void:
	_brood.clear()
	_juice.punch(1.25, 0.45)
	_juice.burst()

	var wasp: Wasp = _spawn_wasp()

	# 她的孩子走完了跟别人一样的整条链——一样要喂，不喂一样饿死。
	# 「不喂那一格」就是玩家看见异色卵之后唯一的处理手段
	# Starving it is the player's one answer to an egg they spotted in time.
	if rebel_brood and wasp != null:
		wasp.become_rebel(_rebel_variant, _rebel_mother)
		rebel_hatched.emit(self, wasp)
	_clear_rebel()

	content = Content.NONE  # 巢室空出来，可以重新产卵 / cell is free again
	_update_hold()
	_refresh_visual()
	wasp_emerged.emit(self, wasp)


func _on_larva_starved(_larva: Larva) -> void:
	_brood.clear()
	_clear_rebel()  # 这条路直接改 content，不经过 _set_occupant / bypasses _set_occupant
	_gifts = 0  # 同上：没能羽化就什么都没留下 / nothing survives an unfinished brood
	content = Content.ROTTEN  # 尸体留在原地，等玩家按住清理 / corpse stays until the player holds to clean it
	_update_hold()
	_refresh_visual()
	larva_starved.emit(self)


func _clean() -> void:
	_set_occupant(null, Content.NONE)
	_gifts = 0
	_refresh_visual()
	cleaned.emit(self)


# keep_brood 只给成长链用。默认清除是故意的：漏掉一处的后果是残留的叛乱标志
# 让下一颗正常卵孵出叛军，那种 bug 很难看出来
# Default clears - a stale flag would quietly turn someone else's egg into a rebel.
func _set_occupant(node: Node2D, new_content: Content, keep_brood: bool = false) -> void:
	if not keep_brood:
		_clear_rebel()
	if _occupant != null:
		_occupant.queue_free()
	_occupant = node
	if _brood != null:
		_brood.clear()
	if node != null:
		add_child(node) 
	content = new_content
	_update_hold()
	_refresh_visual()


# 按住这一格能干什么，跟着内容走 / what a hold does depends on the content
func _update_hold() -> void:
	if _hold == null:
		return
	# 王座期间不接受按住。往王座里产一颗普通卵就把继位口堵死了
	# Laying into the throne would seal off the only way to crown anyone.
	if is_royal:
		_hold.enabled = false
		return
	if is_rotten():
		_hold.hold_duration = clean_duration
		_hold.enabled = true
	elif can_lay_egg():
		_hold.hold_duration = lay_duration
		_hold.enabled = true
	else:
		_hold.enabled = false


func _can_hold() -> bool:
	return not is_royal and (is_rotten() or can_lay_egg())


# ---------------- 输入 / input ----------------

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		return

	clicked.emit(self)
	if _can_hold():
		_hold.press()
		_juice.punch(0.96, 0.14)


# 松手可能发生在格子外面，所以在这里收 / release can happen outside the area
func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not _hold.is_holding():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_hold.release()


func _on_mouse_entered() -> void:
	_is_hovered = true
	_refresh_visual()
	# 按住的时候手滑出去又滑回来，接着按 / resume if the cursor drifts back while held
	if not Engine.is_editor_hint() and _can_hold() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_hold.press()
	hover_changed.emit(self, true)


func _on_mouse_exited() -> void:
	_is_hovered = false
	_refresh_visual()
	_hold.release()
	hover_changed.emit(self, false)


# ---------------- 按住的反馈 / hold feedback ----------------

func _on_hold_progress(t: float) -> void:
	# 松手回退和完成都会发 0，这里就是收掉读数的地方 / both decay and completion land on 0
	if t <= 0.0:
		_brood.clear()
	else:
		_brood.show_progress(t, HOLD_COLOR)
	_juice.shake_amount = max_shake * _shake_ratio(t)


# 曲线在就用曲线，否则 smoothstep。别用 t²——它把八成的抖动堆在最后两成里，
# 按住时间越短越明显 / t squared piles most of the shake into the final fifth
func _shake_ratio(t: float) -> float:
	if shake_curve != null:
		return clampf(shake_curve.sample_baked(clampf(t, 0.0, 1.0)), 0.0, 1.0)
	return smoothstep(0.0, 1.0, t)


func _on_hold_tick(_index: int) -> void:
	_juice.punch(1.05, 0.18)


func _on_hold_completed() -> void:
	_juice.shake_amount = 0.0
	_juice.punch(1.22, 0.45)
	_juice.flash(_cell, flash_color, _base_tint())
	_juice.burst()

	if is_rotten():
		_clean()
	else:
		_lay_egg()


# ---------------- 视觉 / visuals ----------------

func genes() -> GeneBank:
	if not _bank_checked and not Engine.is_editor_hint() and is_inside_tree():
		_bank_checked = true
		_bank = GeneBank.find(get_tree())
	return _bank


# 建成这一格实际要几块纸板。THICK COMB 让它变便宜；至少留 1，不然一格白送
# THICK COMB shaves this; never below one, or a cell would cost nothing at all.
func required_build() -> int:
	var bank: GeneBank = genes()
	return maxi(build_cost - (bank.build_discount() if bank != null else 0), 1)


# 拿不到基因库就按原样跑，别让一个缺失的 director 卡住育儿链
# A missing bank must degrade to the authored numbers, never to a stall.
func _maturation_scale() -> float:
	var bank: GeneBank = genes()
	return bank.maturation_scale() if bank != null else 1.0


func _satiation_scale() -> float:
	var bank: GeneBank = genes()
	return bank.satiation_scale() if bank != null else 1.0


func _progress_ratio() -> float:
	return float(progress) / float(maxi(required_build(), 1))

func _refresh_visual() -> void:
	if _cell == null:
		return
	_cell.self_modulate = _base_tint()

	_recolour_egg()

	match content:
		Content.ROTTEN:
			_cell.frame = 7 # 7 died
		Content.SEALED:
			_cell.frame = 6 # 6 shut with cap (pupa)
		Content.LARVA:
			_cell.frame = 5 # 5 larva spawned
		Content.EGG:
			_cell.frame = 4 # 4 egg placed
		Content.NONE:
			# Maps exactly to 0: empty, 1: phase 1, 2: phase 2, 3: completed
			_cell.frame = clampi(progress, 0, 3)


# 只有卵那一帧需要换色，其余帧里根本没有青色像素，挂着也咬不到东西——
# 但材质留着会让每格白跑一遍 shader，所以不是卵就摘掉。
# ShaderMaterial 是共享 Resource，靠「场景里不预挂材质」拿到独立的一份
# Only the egg frame has cyan in it; drop the material otherwise rather than pay for it.
func _recolour_egg() -> void:
	# @tool 脚本在编辑器里设的属性会被存进场景。材质一旦固化进 HexCell.tscn，
	# 全场的格子就共用一份，最后一颗卵的颜色赢——正是要防的那件事
	# Editor-set properties get serialised; a baked-in material would be shared by every cell.
	if Engine.is_editor_hint():
		return
	if content != Content.EGG:
		_cell.material = null
		return

	var mat: ShaderMaterial = _cell.material as ShaderMaterial
	if mat == null or mat.shader != RECOLOUR:
		mat = ShaderMaterial.new()
		mat.shader = RECOLOUR
		_cell.material = mat
	mat.set_shader_parameter(&"reference", EGG_REFERENCE)
	mat.set_shader_parameter(&"tint", _egg_tint)
	mat.set_shader_parameter(&"hue_window", 40.0)


# 叛乱身份的唯一清除入口。成长链上的每一步都不碰它——她的孩子在流程上必须
# 跟别人的孩子一模一样，破绽只准出在颜色上
# The one place rebel state is dropped; the growth chain never touches it.
func _clear_rebel() -> void:
	rebel_brood = false
	_rebel_variant = null
	_rebel_mother = null
	_egg_tint = EGG_NORMAL
