@tool
class_name ItemSource
extends Node2D

# 资源产出点 / item spawner. 纸板和食物共用，换 piece_scene 就行 / swap piece_scene.
# 两种模式：ON_DEMAND 现取现做，地上平时空的，玩家伸手拖或者工蜂飞到跟前才生成一块；
# STOCKED 是老行为，周围始终维持 max_pieces 个，敌人刷新带用的是这个。
# ON_DEMAND mints on reach - a piece exists only once somebody actually takes one.
# STOCKED keeps a standing pile; the enemy spawn band still needs that.

# 第三种角色：**加工厂**。填了 Refinery 那组参数之后，这个点除了产出还能收料——
# 攒够 intake_required 份原料就吐一份成品到地上。收料走的是 DeliverableComponent，
# 跟往巢室交货是同一条路，所以玩家手拖和工蜂搬运自动都通
# A post with the Refinery group filled also takes deliveries: enough raw units in, one
# refined piece out on the ground. Intake reuses the delivery path, so both the player's
# drag and a wasp's haul work without either knowing this exists.

signal piece_taken(piece: Node2D)
## 收到一份原料 / one unit of raw stock arrived
signal intake_changed(current: int, required: int)
## 加工出了一份成品 / a refined piece popped out
signal refined(piece: Node2D)

enum Mode {
	STOCKED,    ## 维持 max_pieces 个在场 / keeps max_pieces lying around
	ON_DEMAND,  ## 有人来拿才生成 / mints one per reach, nothing sits on the ground
}

## 默认 STOCKED 是为了不改到敌人刷新带 / STOCKED default keeps the enemy band untouched
@export var mode: Mode = Mode.STOCKED
@export var piece_scene: PackedScene
## 这个点产出什么，黄蜂靠它定岗位 / what this post yields, wasps pick their job from it
@export var payload: StringName = &"cardboard"

@export_group("Stocked")
@export_range(1, 12, 1) var max_pieces: int = 3
## 秒。0 = 立刻补 / seconds, 0 = refill immediately
@export_range(0.0, 20.0, 0.1) var respawn_delay: float = 2.0

@export_group("Scatter")
@export_range(0.0, 200.0, 1.0) var scatter_radius: float = 48.0
## 非零时按矩形散布，用于横条状的刷新带 / rectangular scatter, for a wide spawn band
@export var scatter_size: Vector2 = Vector2.ZERO

@export_group("Limits")
## 场上同类散件的上限，到顶就不再出货。**玩家和工蜂走的是同一条路**，
## 只挡玩家的话蜂群照样能把地面堆满。0 = 不限
## ON_DEMAND 的点不设上限就是无限的：一次点击凭空生成一块，连点即可刷满整张图
## An ON_DEMAND post with no ceiling is an infinite fountain - one click, one piece.
@export_range(0, 200, 1) var loose_limit: int = 24
## 玩家从堆上连着扯两块之间的最短间隔。只挡连点：工蜂领货不吃这个，
## 它们本来就被来回飞的时间限着
## Throttles click-spam only - a wasp's round trip is its own cooldown.
@export_range(0.0, 2.0, 0.05) var grab_interval: float = 0.18
## 上限的读数：绕产出点一圈，画的是**已经占掉多少**，画满 = 现在拿不出货了。
## 没有它的话上限是一条隐形规则——玩家只知道点了没反应，不知道为什么
## Without it the ceiling is an invisible rule and a refused click reads as a dead button.
@export var show_stock_meter: bool = true
## 占掉这个比例才显形。平时不占视野，开始见底了才浮出来
## Stays out of sight until the ceiling starts to matter.
@export_range(0.0, 1.0, 0.05) var meter_reveal_at: float = 0.35
## 环画在哪，相对本节点。产出点的原点是**蜂飞过来的落脚点**，不一定是贴图中心，
## 环套在原点上未必好看——挪它不影响任何判定
## The post's origin is where wasps fly to, not the middle of the art; moving the ring
## changes nothing but the picture.
##
## 挂一个名叫 Meter 的 Marker2D 当子节点就用它的位置，在编辑器里直接拖着调，
## 比在这里填数字好使（跟 Drop 一个规矩）/ a child Marker2D named "Meter" wins
##
## 留 (0,0) = 自动贴在 reaction_path 那张贴图的**正上方**
## Left at zero it rides above the reaction sprite's top edge.
@export var meter_offset: Vector2 = Vector2.ZERO
## 自动摆位时离贴图顶多远 / the gap above the sprite's top edge
@export_range(0.0, 80.0, 1.0) var meter_gap: float = 8.0
## 环的半径。**16 是贴图自己的半径**（32x32 撑满），这个数缩放正好 1:1；
## 改大就是在放一张 32 的图，描边会跟着糊——真要更大的环回 gen_ui.py 重出一张
## 16 keeps the texture at 1:1; anything else scales 32px of pixel art and smears the edge.
@export_range(4.0, 200.0, 1.0) var meter_radius: float = 16.0

@export_group("Refinery")
## 收什么原料。留空 = 这个点不加工 / raw payload accepted, empty means not a refinery
@export var intake_payload: StringName = &""
## 几份原料换一份成品。这是战利品的汇率，也是调难度的主旋钮
## The exchange rate for loot, and the main difficulty knob on this whole loop.
@export_range(1, 10, 1) var intake_required: int = 2
## 多近算送到了。要大于黄蜂半径 + 一点余量，否则工蜂会停在门口交不掉
## Must clear the wasp radius with slack, or a hauler hovers just outside and never delivers.
@export_range(20.0, 200.0, 2.0) var intake_radius: float = 56.0
## 加工出来的东西 / what comes out
@export var output_scene: PackedScene
## 成品的 payload，只用来记日志和给外部查询 / for logging and outside queries
@export var output_payload: StringName = &""
## 地上堆到这么多原料就算"满需求"。它决定蜂群多快回头去收拾战场
## Raw units on the ground that count as full demand - sets how fast the swarm reacts.
@export_range(1, 12, 1) var intake_saturation: int = 3
## 成品掉在哪，相对本节点。皇后的兑换台在走廊尽头，成品落在她脚下的话，
## 喂幼虫的蜂每次都要多跑一趟整条走廊
## Dropping at the queen's feet would cost every nurse a round trip down the corridor.
##
## 挂一个名叫 Drop 的 Marker2D 当子节点就用它的位置，在编辑器里直接拖着调，
## 比在这里填数字好使 / a child Marker2D named "Drop" wins, and can just be dragged
@export var output_at: Vector2 = Vector2.ZERO

# 点击判定比散布范围放宽一点，不然贴着边缘按下去没反应 / a little slack around the visual
const GRAB_PADDING: float = 12.0

## 冬天停产，继位之后恢复。由 SeasonDirector 写入 / winter shuts the sources down
var producing: bool = true:
	set(value):
		if producing == value:
			return
		producing = value
		if producing:
			_refill()

var _pieces: Array[Node] = []
var _intake: int = 0
## 下一次允许玩家扯货的时刻。走引擎毫秒而不是 _process 计时：运行时这个节点
## set_process(false)（@tool 那半边才要每帧重画）
## Engine time, not a ticked timer: this node runs with processing off.
var _next_grab_msec: int = 0
var _meter: TextureProgressBar = null
var _meter_shown: bool = false
var _meter_tween: Tween = null

# 生成到父节点下而不是自己的子节点 / spawn into the parent, not as our own child;
# 刚体挂在带位移的父节点下算全局坐标很绕 / a translated parent makes global maths awkward
## 收料/出货时点头的那一层，一般指到皇后贴图。没挂 JuiceComponent 就整套不生效
## The sprite that reacts, usually the Queen; without a JuiceComponent child nothing runs.
@export_group("Feedback")
@export var reaction_path: NodePath
## 取货时迸的那点粒子的颜色，按资源配：纸板土黄、食物绿。
## 加一种资源只要在场景里改这个，不用回来加一条 payload -> 颜色的映射
## Authored per source so a new resource needs no payload-to-colour table here.
@export var puff_color: Color = Color(0.85, 0.72, 0.45)

# 肉进去和成品出来是两拍，颜色必须分开：白色只说「有事发生」，
# 肉色说「肉进去了」、金色说「东西做出来了」
# One generic puff for both beats and the 2-for-1 recipe stays invisible.
const MEAT_PUFF: Color = Color(0.72, 0.24, 0.22)
const JELLY_PUFF: Color = Color(1.0, 0.86, 0.35)

var _juice: JuiceComponent = null

@onready var _spawn_parent: Node = get_parent()


func _ready() -> void:
	# @tool 只为了画编辑器辅助线，运行时逻辑一条都不要在编辑器里跑
	# The @tool half only draws gizmos - none of the runtime logic may run in the editor.
	if Engine.is_editor_hint():
		set_process(true)
		return
	set_process(false)

	var ring: Node2D = get_node_or_null("Ring")
	if ring != null:
		# 环画的是"东西会从这儿冒出来"。矩形散布画不出来，只收料不发货的点则根本没东西冒
		# The ring means "things appear here" - untrue for a band, and for a pure refinery.
		ring.visible = scatter_size == Vector2.ZERO and piece_scene != null

	# 要排在 ON_DEMAND 那条 return 前面——加工厂正好是 ON_DEMAND，写在后面等于没接
	# Must precede the early return: the refinery is ON_DEMAND and would never get wired.
	_juice = get_node_or_null(^"JuiceComponent") as JuiceComponent
	if _juice != null:
		var reactor: Node2D = get_node_or_null(reaction_path) as Node2D
		_juice.target = reactor
		# punch 是乘基准再弹回基准，基准默认 1。皇后在场景里是放大的，
		# 不把她当前的缩放交上去的话，弹一下就被永久打回标准大小
		# punch springs back to base_scale, which defaults to 1 - hand it the authored
		# scale or the first punch shrinks a scaled-up sprite for good.
		if reactor != null:
			_juice.base_scale = reactor.scale
		intake_changed.connect(_on_intake)
		refined.connect(_on_refined)
		piece_taken.connect(_on_taken)

	if mode == Mode.ON_DEMAND:
		_build_grab_area()
		_build_stock_meter()
		return

	# 父节点这会儿还在建子节点，直接 add_child() 会被拒 / parent is busy, defer a frame
	for i in max_pieces:
		_spawn_piece.call_deferred()


func available_count() -> int:
	return _pieces.size()


# 场上有多少块我这个 payload 的东西，含被叼着和被玩家拎在手上的。
# 按 payload 数而不是按产出点数：纸板堆满了不该连累食物
# Counted per payload, so a flooded cardboard field never starves the food post.
func _loose_count() -> int:
	if not is_inside_tree():
		return 0
	var loose: int = 0
	for node in get_tree().get_nodes_in_group(&"carriable"):
		if CarryComponent.payload_of(node) == payload:
			loose += 1
	return loose


# 领一块，落在产出点附近 / mint one piece near the post
func take() -> Node2D:
	return take_at(global_position + _random_offset())


# 指定落点的版本：玩家拖拽落在光标上，工蜂领货落在自己身上
# Placed version - the player's lands under the cursor, a wasp's lands on the wasp.
func take_at(at: Vector2) -> Node2D:
	# 冬天这里什么都不给。Gather 拿到 null 会自己 FAILURE，行为树不用改
	# Gather already handles a null and fails out, so winter needs no BT change.
	if not producing:
		return null
	# 场上已经够多了就不再产。STOCKED 的点不走这条：它由 max_pieces 管着，
	# 在这里拦一道会让补货永远排不进来
	# STOCKED posts are capped by max_pieces; gating them here would stall the refill.
	if mode == Mode.ON_DEMAND and loose_limit > 0 and _loose_count() >= loose_limit:
		return null
	if piece_scene == null:
		push_warning("ItemSource has no piece_scene: %s" % get_path())
		return null
	if not is_inside_tree() or _spawn_parent == null:
		return null

	var piece: Node2D = piece_scene.instantiate() as Node2D
	if piece == null:
		return null

	_spawn_parent.add_child(piece)
	piece.global_position = at
	piece.rotation = randf_range(-PI, PI)

	_play_item_sound(payload, at)

	# 会游荡的东西要知道自己在哪一带活动 / tell wanderers where their patch is
	if piece.has_method("set_wander_home"):
		piece.set_wander_home(at)

	# 读数跟着场上的数走：领走一块涨一格，那块被喂掉/交付掉再退回来。
	# 接每一块的 tree_exited 而不是每帧重数——ON_DEMAND 的货不进 _pieces，没有别的账本
	# Hooking each piece beats polling: ON_DEMAND stock has no ledger to read.
	if _meter != null:
		piece.tree_exited.connect(_refresh_meter)
		_refresh_meter()

	piece_taken.emit(piece)
	return piece


# ---------------- 加工 / refining ----------------

func is_refinery() -> bool:
	return intake_payload != &"" and output_scene != null


func accepts_intake(payload: StringName) -> bool:
	return is_refinery() and payload == intake_payload


# 地上躺着多少我收的原料，0..1。**加工厂得自己会喊饿。**
# 不给这个数的话，战利品完全搭便车在"幼虫饿不饿"上：打完一波敌人、幼虫又都饱着，
# 那堆肉就一直躺在战场上没人管，直到某只蜂碰巧因为别的原因被派到这边
# Without this the loot rides entirely on the food demand, and a battlefield full of
# carrion goes untouched as long as no larva happens to be hungry.
# 实际配方 [要几份原料, 出几份成品]。RENDERING 之前是 2 换 1，之后 3 换 2
# The live recipe; RENDERING turns 2:1 into 3:2.
func recipe() -> Vector2i:
	var bank: GeneBank = GeneBank.find(get_tree()) if is_inside_tree() else null
	if bank == null:
		return Vector2i(intake_required, 1)
	return bank.refinery_recipe(intake_required)


func intake_demand() -> float:
	if not is_refinery() or not is_inside_tree():
		return 0.0

	var loose: int = 0
	for node in get_tree().get_nodes_in_group(&"carriable"):
		if CarryComponent.payload_of(node) == intake_payload:
			loose += 1
	# 已经收进来的零头也算，不然差一块原料时没人愿意来补最后那一趟
	# Part-filled intake counts too, or nobody comes to finish the last unit.
	var pending: float = float(loose) + float(_intake) / float(maxi(recipe().x, 1))
	return clampf(pending / float(intake_saturation), 0.0, 1.0)


# 交货入口。DeliverableComponent 调它，跟 HexCell.deliver() 平级
# The delivery entry point, sitting alongside HexCell.deliver().
#
# **故意不看 producing。** 冬天产出点全部停产，而冬天恰恰是最缺食物的时候；
# 加工不是生产，是把已经打回来的东西换个形态，这条线在冬天照常转
# Deliberately ignores `producing`: winter shuts production down exactly when food is
# scarcest, and refining converts what you already fought for rather than minting anything.
func deposit(payload: StringName, amount: int = 1) -> bool:
	if not accepts_intake(payload) or amount <= 0:
		return false

	var mix: Vector2i = recipe()
	_intake += amount  # <-- THIS IS THE COUNT of how much meat she has eaten!
	intake_changed.emit(_intake, mix.x)

	# --- AUDIO: Queen eating meat ---
	AudioManager.create_2d_audio_at_location(global_position, SoundEffect.SoundEffectType.QUEEN_EAT)

	while _intake >= mix.x:
		_intake -= mix.x
		for i in maxi(mix.y, 1):
			_produce_output()
	return true


# 成品直接摆在地上，不进 _pieces：那个数组是 STOCKED 的补货账本，
# 混进去会让加工出来的东西被当成"库存少了要补"，凭空长出第二个产出源
# Never joins _pieces - that array is the STOCKED refill ledger and would respawn these.
func _produce_output() -> void:
	if not is_inside_tree() or _spawn_parent == null:
		return
	var piece: Node2D = output_scene.instantiate() as Node2D
	if piece == null:
		return

	_spawn_parent.add_child(piece)
	var drop: Node2D = get_node_or_null(^"Drop") as Node2D
	var at: Vector2 = drop.global_position if drop != null else global_position + output_at
	piece.global_position = at + _random_offset()
	piece.rotation = randf_range(-PI, PI)
	
	_play_item_sound(output_payload, piece.global_position)
	
	if piece.has_method("set_wander_home"):
		piece.set_wander_home(piece.global_position)

	refined.emit(piece)


# 领走一块 / a piece was taken - by the player's drag or by a wasp, same path.
#
# ON_DEMAND 的货是在**光标位置**凭空生成的，地上平时什么都没有。源头不给反应的话
# 读起来是「传送到手里」，不是「从堆上扯下来一块」——这才是这里 juice 要修的东西。
# 幅度必须小：工蜂整局都在领货，给大爆发就是满屏噪音
# ON_DEMAND mints at the cursor, so without a reaction at the post the piece reads as
# teleported rather than pulled off the pile. Kept small - wasps take pieces all game.
func _on_taken(piece: Node2D) -> void:
	if _juice != null:
		_juice.punch(0.88, 0.22)   # 压扁再弹回 = 被扯掉一块 / squash, not pop
		_juice.burst(puff_color, 4)
	_pop_in(piece)


# 收下一份原料 / one unit taken in.
# 凑满的那一份沉得更深、迸得更多：不看任何 UI 也知道还差几份
# The unit that completes the recipe dips deeper - the count reads without a number.
func _on_intake(current: int, required: int) -> void:
	if _juice == null:
		return
	# current 是**已经加过**的份数，所以判等就是「这一份凑满了」，不用减一
	# current is already incremented, so equality means this unit completed the recipe.
	var last: bool = current >= required
	_juice.bob(7.0 if last else 4.0)
	_juice.burst(MEAT_PUFF, 8 if last else 5)


# 出货 / a refined piece popped out.
func _on_refined(piece: Node2D) -> void:
	if _juice != null:
		_juice.punch(1.26, 0.35)
		_juice.burst(JELLY_PUFF, 16)
	_pop_in(piece)


# 成品掉在两百多像素外，只在皇后身上迸一下的话玩家连不起因果——落点那头也要动一下。
# 缩的是贴图不是刚体本身：给 RigidBody2D 写 scale 会连碰撞体一起歪
# The output lands far away, so both ends must move. Scale the sprite, never the body -
# a scaled RigidBody2D drags its collision shape with it.
func _pop_in(piece: Node2D) -> void:
	if piece == null:
		return
	var fill: Node2D = piece.get_node_or_null(^"Fill") as Node2D
	if fill == null:
		return
	var home: Vector2 = fill.scale
	fill.scale = home * 0.25
	var tween: Tween = fill.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(fill, "scale", home, 0.32)


# ---------------- 上限读数 / the ceiling, drawn ----------------
# 一圈进度画的是**已经占掉多少**，不是还剩多少：空环和"没有环"长得一样，
# 而到顶那一刻恰恰是最需要看见东西的时候
# It fills rather than empties: an empty ring looks exactly like no ring, and "full" is
# the one state that has to be unmistakable.

# 环是 DM/files/gen_ui.py 生成的灰度图（粗环 + 黑描边），美术覆盖同名 PNG 即可。
# 黑边是乘法乘不掉的，所以整圈换色时那条边永远还在
# Generated greyscale; the black edge survives every tint because modulate multiplies.
## **不用 preload。** 这个脚本是 @tool，编辑器扫描阶段就会编译它；贴图还没导入过
## （新加的 PNG 没有 .import）时 preload 会让整个脚本编译不过——表现是 Inspector 里
## 这一整组 @export 凭空消失，而报错只字不提贴图
## Never preload here: a not-yet-imported PNG takes the whole @tool script down with it,
## and the symptom is a silently empty Inspector.
const STOCK_RING_PATH: String = "res://Assets/UI/stock_ring.png"
## 底下那圈：不是装饰，它画的是"上限有多大"。只有填的那段没有底的话，
## 玩家看到的是一段孤零零的弧，读不出离顶还有多远
## The track IS the ceiling; without it the filled arc has nothing to be a fraction of.
const METER_TRACK: Color = Color(0.26, 0.17, 0.20, 0.55)
const METER_ROOM: Color = Color(1.0, 0.85, 0.45, 0.9)
const METER_FULL: Color = Color(0.88, 0.36, 0.28, 1.0)


# 环画在哪 / where the ring sits. 子节点 Marker2D 优先，没有就用 meter_offset。
# 编辑器辅助线读的是同一个函数，所以拖出来什么样跑起来就是什么样
# The gizmo reads this too, so what you drag is what you get.
func meter_anchor() -> Vector2:
	var marker: Node2D = get_node_or_null(^"Meter") as Node2D
	if marker != null:
		return marker.position
	if meter_offset != Vector2.ZERO:
		return meter_offset

	# 默认贴在反应贴图的正上方。**不能拿本节点原点当基准**——那是蜂飞过来的落脚点，
	# 跟贴图能差出几十像素（纸板点差 (16, -16)），套在原点上环会压在图中间
	# The origin is the wasps' landing point, not the middle of the art.
	var sprite: Sprite2D = get_node_or_null(reaction_path) as Sprite2D
	if sprite == null:
		return Vector2(0.0, -meter_span() - meter_gap)
	var rect: Rect2 = sprite.get_rect()
	var top: Vector2 = sprite.to_global(Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y))
	return to_local(top) - Vector2(0.0, meter_span() + meter_gap)


func meter_span() -> float:
	return meter_radius


func _build_stock_meter() -> void:
	if not show_stock_meter or loose_limit <= 0 or piece_scene == null:
		return
	# 横条状的刷新带画不成一圈，散布形状和这里必须是一套判断 / a band has no ring
	if scatter_size != Vector2.ZERO:
		return

	var ring_tex: Texture2D = load(STOCK_RING_PATH) as Texture2D
	if ring_tex == null:
		push_warning("ItemSource cannot load %s" % STOCK_RING_PATH)
		return

	_meter = TextureProgressBar.new()
	_meter.name = "StockMeter"
	_meter.texture_under = ring_tex
	_meter.texture_progress = ring_tex
	_meter.tint_under = METER_TRACK
	_meter.tint_progress = METER_ROOM
	_meter.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	_meter.radial_initial_angle = 0.0   # 从正上方起转 / starts at twelve o'clock
	_meter.min_value = 0.0
	_meter.max_value = 1.0
	_meter.step = 0.0
	# **必须 IGNORE。** Control 吃鼠标事件是在物理拾取之前，不关掉的话这一圈会把
	# 产出点自己的 Grab 区盖死，玩家再也拖不出东西来
	# A Control eats the click before physics picking ever runs - this would kill the post.
	_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter.modulate.a = 0.0
	# 散件是加到父节点下的，排在本节点后面。不抬一层的话环会被货堆压在底下
	# Pieces are siblings spawned later and would bury it.
	_meter.z_index = 1

	# 缩放绕 pivot 转，pivot 不挪到中心的话环会被甩到右下去
	# Scaling pivots on the top-left unless told otherwise, which throws the ring off-centre.
	var span: Vector2 = ring_tex.get_size()
	_meter.size = span
	_meter.pivot_offset = span * 0.5
	_meter.position = meter_anchor() - span * 0.5
	_meter.scale = Vector2.ONE * (meter_span() * 2.0 / maxf(span.x, 1.0))

	add_child(_meter)
	_refresh_meter()


func _refresh_meter() -> void:
	# 关游戏时每一块货的 tree_exited 都会打到这里，那时环可能已经先没了
	# Every piece's tree_exited lands here on shutdown, when the ring may already be gone.
	if not is_instance_valid(_meter) or not is_inside_tree():
		return

	var used: float = clampf(float(_loose_count()) / float(maxi(loose_limit, 1)), 0.0, 1.0)
	_meter.value = used
	_meter.tint_progress = METER_FULL if used >= 1.0 else METER_ROOM

	var show_it: bool = used >= meter_reveal_at
	if show_it == _meter_shown:
		return
	_meter_shown = show_it
	# 淡入淡出，不硬切：数量在阈值上下抖的时候硬切会闪。
	# 上一条没跑完就杀掉，两条 tween 抢同一个 alpha 会卡在中间
	# Kill the previous one - two tweens on the same alpha stall halfway.
	if _meter_tween != null and _meter_tween.is_valid():
		_meter_tween.kill()
	_meter_tween = _meter.create_tween()
	_meter_tween.tween_property(_meter, "modulate:a", 1.0 if show_it else 0.0, 0.25)


# ON_DEMAND 的点击区：形状跟着散布参数走，改了散布不用再回来对一遍
# The click zone is derived from the scatter params so the two can't drift apart.
func _build_grab_area() -> void:
	var area: Area2D = Area2D.new()
	area.name = "Grab"
	area.input_pickable = true

	var shape: CollisionShape2D = CollisionShape2D.new()
	if scatter_size != Vector2.ZERO:
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = scatter_size + Vector2.ONE * GRAB_PADDING * 2.0
		shape.shape = rect
	else:
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = scatter_radius + GRAB_PADDING
		shape.shape = circle
	area.add_child(shape)

	add_child(area)
	area.input_event.connect(_on_grab_input)


# 从产出点往外拖：按下的瞬间生成一块，直接落到手里 / the piece is minted into the hand
func _on_grab_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	# 上面躺着的散件先响应过了就别再发一块 / a loose piece already took this click
	if DraggableComponent.is_dragging():
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return

	var now: int = Time.get_ticks_msec()
	if now < _next_grab_msec:
		return

	var piece: Node2D = take_at(get_global_mouse_position())
	if piece == null:
		# 到顶了。**得给个回应**——什么都不发生的话玩家只会以为自己点漏了，
		# 于是接着点。点一下头就够说明"这儿现在没得拿"
		# Silence reads as a missed click and the player just clicks harder.
		if _juice != null:
			_juice.bob(3.0)
		return
	_next_grab_msec = now + int(grab_interval * 1000.0)

	var draggable: DraggableComponent = draggable_of(piece)
	if draggable == null or not draggable.grab_at_cursor():
		return
	get_viewport().set_input_as_handled()


static func draggable_of(node: Node) -> DraggableComponent:
	for child in node.get_children():
		if child is DraggableComponent:
			return child
	return null


# 停产期间把堆补回来 / tops the pile back up when production resumes
func _refill() -> void:
	if mode != Mode.STOCKED or not is_inside_tree():
		return
	for i in maxi(max_pieces - _pieces.size(), 0):
		_spawn_piece.call_deferred()


func _spawn_piece() -> void:
	if _pieces.size() >= max_pieces:
		return
	var piece: Node2D = take()
	if piece == null:
		return
	_pieces.append(piece)
	piece.tree_exited.connect(_on_piece_gone.bind(piece))


func _random_offset() -> Vector2:
	if scatter_size != Vector2.ZERO:
		return Vector2(randf_range(-0.5, 0.5) * scatter_size.x, randf_range(-0.5, 0.5) * scatter_size.y)
	var angle: float = randf_range(0.0, TAU)
	var distance: float = sqrt(randf()) * scatter_radius  # sqrt 让点均匀分布 / uniform in disc
	return Vector2(cos(angle), sin(angle)) * distance


func _on_piece_gone(piece: Node) -> void:
	_pieces.erase(piece)
	# 退出游戏时也会触发 tree_exited，这时别再排补充 / also fires on shutdown
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	if respawn_delay <= 0.0:
		_spawn_piece.call_deferred()
		return
	tree.create_timer(respawn_delay).timeout.connect(_spawn_piece)


# ---------------- 编辑器辅助线 / editor gizmo ----------------
# 美术直接拖着摆位置，但一个 Sprite 看不出蜂会飞到哪、东西会撒开多大一圈。
# 这里把三样看不见的东西画出来：锚点（蜂的落脚点）、散布范围、成品掉落点。
# The sprite shows none of what matters when placing one of these, so draw the
# anchor wasps fly to, the scatter spread, and where refined pieces land.

const GIZMO_ANCHOR: Color = Color(1.0, 0.85, 0.3)
const GIZMO_METER: Color = Color(1.0, 0.85, 0.45, 0.55)
const GIZMO_SCATTER: Color = Color(0.6, 0.9, 0.55, 0.85)
const GIZMO_INTAKE: Color = Color(0.95, 0.55, 0.4, 0.85)
const GIZMO_DROP: Color = Color(0.55, 0.75, 1.0)


func _process(_delta: float) -> void:
	# 拖 Drop 子节点、改 Inspector 数值都不会通知我们，编辑器里直接每帧重画
	# Nothing notifies us when a child marker is dragged, so just redraw in the editor.
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return

	# 散布范围：矩形带和圆形堆是两套画法 / a band and a pile look nothing alike
	if piece_scene != null:
		if scatter_size != Vector2.ZERO:
			draw_rect(Rect2(-scatter_size * 0.5, scatter_size), GIZMO_SCATTER, false, 2.0)
		elif scatter_radius > 0.0:
			draw_arc(Vector2.ZERO, scatter_radius, 0.0, TAU, 48, GIZMO_SCATTER, 2.0)

	# 存量环。它是运行时才建的节点，编辑器里没有实体可选——不画出来就只能跑一次游戏对位置
	# Built at runtime, so without this you would place it by trial and error.
	if show_stock_meter and loose_limit > 0 and piece_scene != null and scatter_size == Vector2.ZERO:
		draw_arc(meter_anchor(), meter_span(), 0.0, TAU, 48, GIZMO_METER, 4.0)

	if is_refinery():
		draw_arc(Vector2.ZERO, intake_radius, 0.0, TAU, 48, GIZMO_INTAKE, 2.0)
		_draw_drop_marker()

	# 锚点画在最上面。蜂飞的是这个点，不是贴图中心——两者能差出半个屏幕
	# Wasps fly to this point, not to the sprite; the two can drift far apart.
	draw_line(Vector2(-10, 0), Vector2(10, 0), GIZMO_ANCHOR, 2.0)
	draw_line(Vector2(0, -10), Vector2(0, 10), GIZMO_ANCHOR, 2.0)
	draw_arc(Vector2.ZERO, 5.0, 0.0, TAU, 16, GIZMO_ANCHOR, 2.0)

	var label: String = String(payload)
	if is_refinery():
		label += " <- " + String(intake_payload)
	draw_string(ThemeDB.fallback_font, Vector2(14, -12), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GIZMO_ANCHOR)


func _draw_drop_marker() -> void:
	var drop: Node2D = get_node_or_null(^"Drop") as Node2D
	var at: Vector2 = drop.position if drop != null else output_at
	if at == Vector2.ZERO:
		return
	draw_dashed_line(Vector2.ZERO, at, GIZMO_DROP, 1.5, 6.0)
	draw_arc(at, 10.0, 0.0, TAU, 24, GIZMO_DROP, 2.0)
	draw_string(ThemeDB.fallback_font, at + Vector2(14, 4), String(output_payload),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GIZMO_DROP)

# ---------------- Audio ----------------
func _play_item_sound(item_payload: StringName, pos: Vector2) -> void:
	match item_payload:
		&"cardboard":
			AudioManager.create_2d_audio_at_location(pos, SoundEffect.SoundEffectType.CARDBOARD_POP)
		&"food":
			AudioManager.create_2d_audio_at_location(pos, SoundEffect.SoundEffectType.FOOD_POP)
		&"royal_jelly": 
			AudioManager.create_2d_audio_at_location(pos, SoundEffect.SoundEffectType.QUEEN_POP)