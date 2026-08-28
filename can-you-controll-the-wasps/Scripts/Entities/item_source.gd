class_name ItemSource
extends Node2D

# 资源产出点 / item spawner. 纸板和食物共用，换 piece_scene 就行 / swap piece_scene.
# 两种模式：ON_DEMAND 现取现做，地上平时空的，玩家伸手拖或者工蜂飞到跟前才生成一块；
# STOCKED 是老行为，周围始终维持 max_pieces 个，敌人刷新带用的是这个。
# ON_DEMAND mints on reach - a piece exists only once somebody actually takes one.
# STOCKED keeps a standing pile; the enemy spawn band still needs that.

signal piece_taken(piece: Node2D)

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

# 生成到父节点下而不是自己的子节点 / spawn into the parent, not as our own child;
# 刚体挂在带位移的父节点下算全局坐标很绕 / a translated parent makes global maths awkward
@onready var _spawn_parent: Node = get_parent()


func _ready() -> void:
	var ring: Node2D = get_node_or_null("Ring")
	if ring != null:
		ring.visible = scatter_size == Vector2.ZERO  # 圆形指示环只在圆形散布时有意义

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
