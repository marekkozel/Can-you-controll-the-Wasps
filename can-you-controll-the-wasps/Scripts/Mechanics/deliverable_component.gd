class_name DeliverableComponent
extends Node

# 可交付物 / deliverable：松手时落在蜂巢格子上就把自己交出去。
# 纸板和食物共用这一条路径，格子那边靠 payload 决定怎么处理。

signal delivered(cell: HexCell)

const HIVE_GROUP: StringName = &"hive"

## 交给格子的东西：&"cardboard" 加建造进度，&"food" 喂幼虫
@export var payload: StringName = &"cardboard"
@export_range(1, 5, 1) var amount: int = 1
## 用 NodePath 而不是 Node 导出——后者在 .tscn 里存的路径解析不出来
@export var draggable_path: NodePath = ^"../DraggableComponent"
## 交付成功后是否销毁自己
@export var consume_on_deliver: bool = true


func _ready() -> void:
	var draggable: Node = get_node_or_null(draggable_path)
	if draggable == null:
		push_warning("DeliverableComponent cannot find draggable at %s" % draggable_path)
		return
	draggable.released.connect(_on_released)


func _on_released() -> void:
	var body: Node2D = get_parent() as Node2D
	if body == null:
		return

	var hive: Hive = get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	if hive == null:
		return

	# 没落在格子上，或者格子不收 —— 东西留在原地，还能再拖
	var cell: HexCell = hive.cell_at_global(body.global_position)
	if cell == null or not cell.deliver(payload, amount):
		return

	delivered.emit(cell)
	if consume_on_deliver:
		body.queue_free()
