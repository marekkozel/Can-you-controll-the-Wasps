class_name DeliverableComponent
extends Node

# 可交付物 / deliverable: 松手时落在收得下它的东西上就把自己交出去。
# 纸板和食物共用这一条路径，格子那边靠 payload 决定怎么处理 / cell decides from payload.
#
# 收货方有两种：蜂巢格子，和会加工的产出点（战利品送进去换蜂王浆）。先问加工厂再问巢，
# 因为加工厂在上带、巢在下带，物理上不可能重叠，顺序纯粹是为了让判断短路得早一点
# Two kinds of receiver: hive cells, and refinery posts. They can never overlap - the
# posts are in the top band and the hive in the bottom - so the order is just short-circuiting.

signal delivered(target: Node)

const HIVE_GROUP: StringName = &"hive"
const ITEM_SOURCE_GROUP: StringName = &"item_source"

## 交给格子的东西 / payload: &"cardboard" 加建造进度, &"food" 喂幼虫
@export var payload: StringName = &"cardboard"
@export_range(1, 5, 1) var amount: int = 1
## 用 NodePath 不用 Node 导出——后者在 .tscn 里解析不出来 / typed Node exports don't resolve
@export var draggable_path: NodePath = ^"../DraggableComponent"
## 交付成功后是否销毁自己 / free itself after a successful delivery
@export var consume_on_deliver: bool = true


func _ready() -> void:
	var draggable: Node = get_node_or_null(draggable_path)
	if draggable == null:
		push_warning("DeliverableComponent cannot find draggable at %s" % draggable_path)
		return
	draggable.released.connect(_on_released)


func _on_released() -> void:
	try_deliver()


# 黄蜂放货也走这里，和玩家松手是同一条路径 / wasps drop through this too
# amount_override 让搬运方把自己的载重算进去；玩家松手走默认值
# The carrier passes its own capacity; a player release keeps the item's own amount.
func try_deliver(amount_override: int = -1) -> bool:
	var body: Node2D = get_parent() as Node2D
	if body == null:
		return false

	var units: int = amount if amount_override < 1 else amount_override

	var target: Node = _receiver_at(body.global_position, units)
	# 没落在收货方身上，东西留原地还能再拖 / not accepted, leave it where it is
	if target == null:
		return false

	delivered.emit(target)
	if consume_on_deliver:
		body.queue_free()
	return true


# 找到并**立即完成**交付，返回收下它的那个节点。判断和交付合在一起是因为两边的
# "收不收" 都得真调一次才知道（格子可能已经建满、幼虫可能刚被喂饱）
# Probing and delivering are one step: both receivers only answer by actually trying.
func _receiver_at(at: Vector2, units: int) -> Node:
	for node in get_tree().get_nodes_in_group(ITEM_SOURCE_GROUP):
		var post: ItemSource = node as ItemSource
		if post == null or not post.accepts_intake(payload):
			continue
		if at.distance_to(post.global_position) > post.intake_radius:
			continue
		if post.deposit(payload, units):
			return post

	var hive: Hive = get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	if hive == null:
		return null
	var cell: HexCell = hive.cell_at_global(at)
	if cell != null and cell.deliver(payload, units):
		return cell
	return null
