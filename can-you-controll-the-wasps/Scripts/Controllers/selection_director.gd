class_name SelectionDirector
extends Node2D

# 选中调度 / selection. 跟另外几个 director 并排挂在 Queen_controller 下。
# 全场唯一一处"光标现在指着谁"的判定——描边和 InfoPanel 都读这里，
# 两边各算一遍的话迟早会在边界上给出不同答案 / one query, two consumers, no drift.

## 指着谁变了。in_hand = 那只是被托着的，不是光标底下的
signal subject_changed(subject: Node2D, in_hand: bool)

const GROUP: StringName = &"selection_director"
const WASP_GROUP: StringName = &"wasps"
const CARRIABLE_GROUP: StringName = &"carriable"

## 光标离蜂中心多近算指着它。比碰撞半径大一点，小目标才不难点
## A little larger than the collision radius so a 20px target is not fiddly.
@export_range(8.0, 80.0, 1.0) var hover_radius: float = 26.0
## 货物比蜂小（食物半径 12），判定放宽 / items are smaller, so a wider grab
@export_range(8.0, 80.0, 1.0) var item_hover_radius: float = 30.0
@export_range(0.0, 0.5, 0.01) var refresh_interval: float = 0.05

## 不加类型。它随时持有一个已经被处决 / 被交付掉的对象，而**类型化会在赋值和传参那一刻
## 就抛错**，函数体里的 is_instance_valid 根本轮不到执行
## Untyped: a typed slot throws on a freed object before any guard can run.
var _subject = null
var _in_hand: bool = false
var _timer: float = 0.0


static func find(tree: SceneTree) -> SelectionDirector:
	return tree.get_first_node_in_group(GROUP) as SelectionDirector


func subject() -> Node2D:
	return _subject if is_instance_valid(_subject) else null


func is_in_hand() -> bool:
	return _in_hand


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = refresh_interval

	# 上一帧指着的那只可能已经被扎死了 / last frame's subject may have been stung since
	if not is_instance_valid(_subject):
		_subject = null

	# 拿在手上的优先。托着一块纸板飞过蜂群时，玩家问的是"这块纸板干嘛用"，
	# 不是"下面那只蜂是谁" / what is in hand wins over what is under the cursor
	var next: Node2D = DraggableComponent.held_body()
	var in_hand: bool = next != null
	if next == null:
		next = _nearest_in_group(WASP_GROUP, hover_radius)
	if next == null:
		next = _nearest_in_group(CARRIABLE_GROUP, item_hover_radius)

	if next == _subject and in_hand == _in_hand:
		return

	_light(_subject, OutlineComponent.State.NONE)
	_subject = next
	_in_hand = in_hand
	_light(_subject, OutlineComponent.State.HELD if in_hand else OutlineComponent.State.HOVER)
	subject_changed.emit(_subject, _in_hand)


# node 同样不加类型 —— 收掉旧目标的描边时，它十有八九已经是个死对象
# Untyped too: clearing the old subject is exactly when it tends to be freed already.
func _light(node, state: int) -> void:
	if not is_instance_valid(node):
		return
	for child in node.get_children():
		if child is OutlineComponent:
			(child as OutlineComponent).set_state(state)
			return


# 光标要换算到世界坐标。这个节点在世界里，但鼠标位置是 viewport 空间——
# 现在没相机所以两者恰好重合，一加 Camera2D 判定就整体错位
# No camera today makes these coincide; a Camera2D would silently break it.
func _nearest_in_group(group: StringName, radius: float) -> Node2D:
	var viewport: Viewport = get_viewport()
	var cursor: Vector2 = viewport.get_canvas_transform().affine_inverse() * viewport.get_mouse_position()
	var best: Node2D = null
	var best_dist: float = radius
	for node in get_tree().get_nodes_in_group(group):
		var item: Node2D = node as Node2D
		if item == null:
			continue
		var dist: float = cursor.distance_to(item.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = item
	return best
