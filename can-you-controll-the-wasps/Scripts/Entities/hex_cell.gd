@tool
class_name HexCell
extends Area2D

# 蜂巢的一格 / one hive cell.
# 只管状态和接线：建造进度、内容槽、把组件信号转成反馈 / state and wiring only.
# 效果本身在 JuiceComponent 和 ProgressRing 里 / the effects live in those components.
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

const EGG_SCENE: PackedScene = preload("res://Scenes/Entities/Egg.tscn")
const LARVA_SCENE: PackedScene = preload("res://Scenes/Entities/Larva.tscn")
const WASP_SCENE: PackedScene = preload("res://Scenes/Entities/Wasp.tscn")
## 羽化出来的黄蜂挂到哪一层 / group that hosts emerged wasps
const ENTITIES_GROUP: StringName = &"entities"

## 建成这一格要几块纸板 / cardboard pieces needed to build
@export_range(1, 10, 1) var build_cost: int = 3
## 产卵要按住多久 / hold seconds to lay an egg
@export_range(0.5, 30.0, 0.5) var lay_duration: float = 5.0
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
## 抖动幅度上限，实际幅度 ∝ 进度² / cap, actual amplitude scales with progress squared
@export_range(0.0, 12.0, 0.1) var max_shake: float = 1.6
@export var flash_color: Color = Color(1.0, 0.98, 0.85, 0.9)
@export var rotten_fill_color: Color = Color(0.36, 0.31, 0.24, 0.55)
@export var sealed_border_color: Color = Color(0.85, 0.66, 0.32, 1.0)

# 里面这颗是不是异色卵。叛军靠它认自己人，不然会把自己姐妹吃了
# Rebels check this to spare their own brood - without it they eat their siblings.
var rebel_brood: bool = false
var coord: Vector2i = Vector2i.ZERO
var progress: int = 0
var is_built: bool = false
var content: Content = Content.NONE
## 这一格是不是当代的王座 / is this winter's throne
var is_royal: bool = false

@onready var _ring: ProgressRing = $Visual/HoldRing
@onready var _shape: CollisionPolygon2D = $Shape
@onready var _hold: HoldComponent = $HoldComponent
@onready var _juice: JuiceComponent = $JuiceComponent
@onready var _seal_timer: MaturationComponent = $SealTimer

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
	_ring.set_ring_path(corners)
	_refresh_visual()


# ---------------- 交付入口 / delivery ----------------

# 拖过来的东西都走这里，由格子决定怎么处理 / single entry point, cell routes by payload
func deliver(payload: StringName, amount: int = 1) -> bool:
	match payload:
		&"cardboard":
			return add_build_progress(amount)
		&"food":
			return _feed_occupant(amount)
	return false


func add_build_progress(amount: int = 1) -> bool:
	if is_built or amount <= 0:
		return false

	progress = mini(progress + amount, build_cost)
	_refresh_visual()
	progress_changed.emit(self, progress, build_cost)

	if progress >= build_cost:
		is_built = true
		_update_hold()
		built.emit(self)
	return true


# ---------------- 叛乱 / betrayal ----------------

# 异色卵。故意不走 卵→幼虫→封盖 那条链，自己计时直接孵出一只叛军。
# A rebel egg skips the normal growth chain and hatches a wasp on its own timer.
func lay_rebel_egg(variant: WaspVariant, mother: Node2D) -> bool:
	if not can_lay_egg() or variant == null:
		return false

	var egg: Egg = EGG_SCENE.instantiate()
	_set_occupant(egg, Content.EGG)
	rebel_brood = true
	egg.modulate = variant.body_color  # 异色，看到了就知道巢里进了东西 / visibly not one of ours
	egg.hatched.connect(_on_rebel_hatched.bind(variant, mother))
	# 线索全模糊化之后，这一下闪光是唯一不伪装的硬信息：
	# 它告诉你"一秒前有蜂来过这儿"，搜索范围从全场缩到附近那几只。
	# The one tell that is never disguised - it narrows the search from the whole hive
	# to whoever was standing nearby a second ago.
	_juice.flash(_cell, variant.body_color, _base_tint())
	_juice.punch(1.18, 0.32)
	rebel_egg_laid.emit(self, variant)
	return true


# mother 不加类型：孵化前她可能已经被处决了 / untyped: she may already be dead by now
func _on_rebel_hatched(_egg: Egg, variant: WaspVariant, mother) -> void:
	_set_occupant(null, Content.NONE)
	_refresh_visual()
	_juice.punch(1.25, 0.45)
	_juice.burst()

	var wasp: Wasp = _spawn_wasp()
	wasp.become_rebel(variant, mother)
	rebel_hatched.emit(self, wasp)


# 把巢室里的卵/幼虫弄死，格子变腐烂。完全走现成的腐烂链：
# 玩家得按住清理，清完之前这格不能产卵。一行新逻辑都不用写。
# Reuses the existing rot path wholesale - the player has to hold to clean it out.
func destroy_occupant() -> bool:
	if content != Content.EGG and content != Content.LARVA:
		return false

	_set_occupant(null, Content.ROTTEN)
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

	progress = maxi(progress - amount, 0)
	if is_built and progress < build_cost:
		is_built = false
		_update_hold()

	_refresh_visual()
	_juice.punch(0.88, 0.22)
	progress_changed.emit(self, progress, build_cost)
	build_damaged.emit(self, progress, build_cost)
	return true


# 羽化和异色卵孵化共用 / shared by emergence and rebel hatching
func _spawn_wasp() -> Wasp:
	var wasp: Wasp = WASP_SCENE.instantiate()
	var host: Node = get_tree().get_first_node_in_group(ENTITIES_GROUP)
	if host == null:
		host = get_tree().current_scene
	host.add_child(wasp)
	# 新蜂穿什么颜色、带多少基因加成，全由当代蜂后决定。格子不该知道这些
	# The reigning queen dresses every newborn; the cell has no business knowing how.
	var season: SeasonDirector = SeasonDirector.find(get_tree())
	if season != null:
		season.dress_newborn(wasp)
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


func can_lay_egg() -> bool:
	return is_built and content == Content.NONE


func is_rotten() -> bool:
	return content == Content.ROTTEN


func is_hungry_larva() -> bool:
	return content == Content.LARVA and _occupant != null and (_occupant as Larva).is_hungry()


# 喂食排序用，越小越快饿死 / feeding priority, smaller is more urgent
func larva_hunger_ratio() -> float:
	if not is_hungry_larva():
		return 1.0
	return (_occupant as Larva).hunger_ratio()


# 直接推进到下一个阶段，跳过所有计时和拖拽 / force the next stage, skips timers
# 给调试工具和脚本化流程用 / for the debug tools and scripted flows
func advance_stage() -> bool:
	if not is_built:
		return add_build_progress(build_cost - progress)

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
	_set_occupant(egg, Content.EGG)
	egg.hatched.connect(_on_egg_hatched)
	egg_laid.emit(self)


func _on_egg_hatched(_egg: Egg) -> void:
	var larva: Larva = LARVA_SCENE.instantiate()
	_set_occupant(larva, Content.LARVA)
	larva.became_hungry.connect(_on_larva_hungry)
	larva.satisfied.connect(_on_larva_satisfied)
	larva.starved.connect(_on_larva_starved)
	_juice.punch(1.15, 0.35)
	_juice.burst()
	larva_hatched.emit(self)


func _on_larva_hungry(_larva: Larva) -> void:
	larva_hungry.emit(self)
# 喂饱一次就封起来，10 秒后出黄蜂 / one full feed seals it, wasp emerges after the timer
func _on_larva_satisfied(_larva: Larva) -> void:
	_set_occupant(null, Content.SEALED)
	_seal_timer.start()
	_juice.punch(1.18, 0.4)
	_refresh_visual()
	sealed.emit(self)


func _on_seal_progress(t: float) -> void:
	_ring.set_progress(t)


func _on_seal_matured() -> void:
	_ring.set_progress(0.0)
	_juice.punch(1.25, 0.45)
	_juice.burst()

	var wasp: Wasp = _spawn_wasp()

	content = Content.NONE  # 巢室空出来，可以重新产卵 / cell is free again
	_update_hold()
	_refresh_visual()
	wasp_emerged.emit(self, wasp)


func _on_larva_starved(_larva: Larva) -> void:
	content = Content.ROTTEN  # 尸体留在原地，等玩家按住清理 / corpse stays until the player holds to clean it
	_update_hold()
	_refresh_visual()
	larva_starved.emit(self)


func _clean() -> void:
	_set_occupant(null, Content.NONE)
	_refresh_visual()
	cleaned.emit(self)


func _set_occupant(node: Node2D, new_content: Content) -> void:
	rebel_brood = false  # 换内容就不再是叛乱之卵了 / any content change clears it
	if _occupant != null:
		_occupant.queue_free()
	_occupant = node
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
	_ring.set_progress(t)
	_juice.shake_amount = max_shake * t * t


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

func _progress_ratio() -> float:
	return float(progress) / float(maxi(build_cost, 1))

func _refresh_visual() -> void:
	if _cell == null:
		return
	_cell.self_modulate = _base_tint()

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