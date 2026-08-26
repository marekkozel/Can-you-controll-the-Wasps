class_name ItemSource
extends Node2D

# 资源产出点 / item spawner. 纸板和食物共用，换 piece_scene 就行。
# 周围始终维持 max_pieces 个，被拿走一个就延时补一个。

signal piece_spawned(piece: Node2D)

@export var piece_scene: PackedScene
@export_range(1, 12, 1) var max_pieces: int = 3
## 秒。0 = 立刻补
@export_range(0.0, 20.0, 0.1) var respawn_delay: float = 2.0
@export_range(0.0, 200.0, 1.0) var scatter_radius: float = 48.0

var _pieces: Array[Node] = []

# 生成到父节点下而不是当自己的子节点，刚体挂在带位移的父节点下算全局坐标很绕
@onready var _spawn_parent: Node = get_parent()


func _ready() -> void:
	# 父节点这会儿还在建自己的子节点，直接 add_child() 会被拒，得延后一帧
	for i in max_pieces:
		_spawn_piece.call_deferred()


func available_count() -> int:
	return _pieces.size()


func _spawn_piece() -> void:
	if piece_scene == null:
		push_warning("ItemSource has no piece_scene: %s" % get_path())
		return
	if not is_inside_tree() or _spawn_parent == null:
		return
	if _pieces.size() >= max_pieces:
		return

	var piece: Node2D = piece_scene.instantiate() as Node2D
	if piece == null:
		return

	_spawn_parent.add_child(piece)
	piece.global_position = global_position + _random_offset()
	piece.rotation = randf_range(-PI, PI)

	_pieces.append(piece)
	piece.tree_exited.connect(_on_piece_gone.bind(piece))
	piece_spawned.emit(piece)


func _random_offset() -> Vector2:
	var angle: float = randf_range(0.0, TAU)
	var distance: float = sqrt(randf()) * scatter_radius
	return Vector2(cos(angle), sin(angle)) * distance


func _on_piece_gone(piece: Node) -> void:
	_pieces.erase(piece)
	# 退出游戏时也会触发 tree_exited，这时候别再排补充
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	if respawn_delay <= 0.0:
		_spawn_piece.call_deferred()
		return
	tree.create_timer(respawn_delay).timeout.connect(_spawn_piece)
