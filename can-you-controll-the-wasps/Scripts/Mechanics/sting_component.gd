class_name StingComponent
extends Node

# 蜂针穿刺 / sting: 左键托起一只黄蜂之后，右键当场处决。
#
# 检查是廉价的（拓起来感受一下就行），下手是昂贵的——杀错人的后果接在 killed 上。
# Inspecting is cheap, committing is not: the cost of a wrong call hangs off `killed`.

## 死的是谁、当时立场是什么，背叛数值系统以后接这里 / the betrayal system will hook this
signal killed(victim: Node2D, was_false_queen: bool)

## 用 NodePath，同 DeliverableComponent / same reason as DeliverableComponent
@export var draggable_path: NodePath = ^"../DraggableComponent"

var _draggable: DraggableComponent = null
var _body: Node2D = null


func _ready() -> void:
	_body = get_parent() as Node2D
	_draggable = get_node_or_null(draggable_path) as DraggableComponent
	if _draggable == null:
		push_warning("StingComponent cannot find draggable at %s" % draggable_path)
		set_process_input(false)


func _input(event: InputEvent) -> void:
	# 只有拿在手上的那一只才能被扎 / only the one actually in hand can be stung
	if _draggable == null or not _draggable.is_grabbed():
		return
	if not (event is InputEventMouseButton):
		return
	var mouse: InputEventMouseButton = event
	if mouse.button_index != MOUSE_BUTTON_RIGHT or not mouse.pressed:
		return

	get_viewport().set_input_as_handled()
	_execute()


func _execute() -> void:
	var allegiance: AllegianceComponent = _find(AllegianceComponent) as AllegianceComponent
	var was_queen: bool = allegiance != null and allegiance.is_false_queen()

	var juice: JuiceComponent = _find(JuiceComponent) as JuiceComponent
	if juice != null:
		juice.burst()

	killed.emit(_body, was_queen)

	var director: BetrayalDirector = BetrayalDirector.find(get_tree())
	if director != null:
		director.report_execution(_body, was_queen)

	var health: HealthComponent = _find(HealthComponent) as HealthComponent
	if health != null:
		health.take_damage(health.max_health, _body.global_position)
	else:
		_body.queue_free()


func _find(type) -> Node:
	for child in _body.get_children():
		if is_instance_of(child, type):
			return child
	return null
