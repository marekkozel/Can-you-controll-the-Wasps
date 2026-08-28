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

# 生成到父节点下而不是自己的子节点 / spawn into the parent, not as our own child;
# 刚体挂在带位移的父节点下算全局坐标很绕 / a translated parent makes global maths awkward
@onready var _spawn_parent: Node = get_parent()


func _ready() -> void:
	var ring: Node2D = get_node_or_null("Ring")
	if ring != null:
		# 环画的是"东西会从这儿冒出来"。矩形散布画不出来，只收料不发货的点则根本没东西冒
		# The ring means "things appear here" - untrue for a band, and for a pure refinery.
		ring.visible = scatter_size == Vector2.ZERO and piece_scene != null

	if mode == Mode.ON_DEMAND:
		_build_grab_area()
		return

	# 父节点这会儿还在建子节点，直接 add_child() 会被拒 / parent is busy, defer a frame
	for i in max_pieces:
		_spawn_piece.call_deferred()


func available_count() -> int:
	return _pieces.size()


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

	# 会游荡的东西要知道自己在哪一带活动 / tell wanderers where their patch is
	if piece.has_method("set_wander_home"):
		piece.set_wander_home(at)

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
	_intake += amount
	intake_changed.emit(_intake, mix.x)

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
	if piece.has_method("set_wander_home"):
		piece.set_wander_home(piece.global_position)

	refined.emit(piece)


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

	var piece: Node2D = take_at(get_global_mouse_position())
	if piece == null:
		return

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
