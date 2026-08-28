class_name SuccessionComponent
extends Node

# 继位 / succession: 冬天把一只蜂拖进王座巢室，松手就让它上位。
# 和 DeliverableComponent 走的是同一条路——落点决定后果，全程没有一个菜单。
# Same path a delivered piece takes: the drop point decides, and there is no menu anywhere.
#
# 组件挂在**蜂**身上而不是王座上，因为巢室是 Hive.rebuild() 程序生成的，
# 没有哪个 .tscn 能预先往格子里挂东西。
# It rides the wasp, not the throne: cells are built procedurally and no scene owns them.

signal crowned
## 拖进去了但它不干 / dropped in and refused to take it
signal refused

## 用 NodePath，同 DeliverableComponent / same reason as DeliverableComponent
@export var draggable_path: NodePath = ^"../DraggableComponent"
## 挣脱弹开的力度。罢工的和叛军拖进去会自己蹦出来，这条反馈一个字都不用写
## A refusal kicks itself back out - the feedback needs no words.
@export_range(0.0, 800.0, 10.0) var refuse_impulse: float = 260.0

var _body: RigidBody2D = null


func _ready() -> void:
	_body = get_parent() as RigidBody2D
	var draggable: Node = get_node_or_null(draggable_path)
	if draggable == null:
		push_warning("SuccessionComponent cannot find draggable at %s" % draggable_path)
		return
	draggable.released.connect(_on_released)


func _on_released() -> void:
	var wasp: Wasp = _body as Wasp
	if wasp == null:
		return
	var season: SeasonDirector = SeasonDirector.find(get_tree())
	if season == null or not season.throne_accepts(wasp.global_position):
		return

	# 叛军和罢工的进不去。查的是 works()，不是 state——
	# 前者是背叛值的函数，后者会把立场泄露出去
	# works() is a betrayal-value question; asking about state would leak allegiance.
	if not wasp.allegiance().works():
		_kick(wasp)
		refused.emit()
		return

	if season.crown(wasp):
		crowned.emit()


func _kick(wasp: Wasp) -> void:
	var away: Vector2 = Vector2.UP.rotated(randf_range(-PI, PI))
	wasp.linear_velocity += away * refuse_impulse
	wasp.angular_velocity += randf_range(-8.0, 8.0)
