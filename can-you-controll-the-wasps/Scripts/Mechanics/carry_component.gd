class_name CarryComponent
extends Node

# 叼着东西飞 / carry: 把一个 RigidBody2D 物件夹在持有者身下带走。
# 放下时走物件自己的 DeliverableComponent，和玩家松手是同一条交付路径
# Dropping reuses the item's own DeliverableComponent - the exact path a player release takes.

signal picked_up(item: Node2D)
signal dropped(item: Node2D)

## 货物挂在持有者下方多远 / where the cargo hangs relative to the carrier
@export var carry_offset: Vector2 = Vector2(0, 14)
## 叼着的时候玩家还能不能直接点走货物 / can the player grab cargo straight off the carrier
@export var cargo_stays_grabbable: bool = false

var _carrier: Node2D = null
var _item: RigidBody2D = null
var _saved_gravity: float = 1.0
var _saved_layer: int = 0
var _saved_mask: int = 0

# 组件查找的缓存键，写在货物身上 / where the lookups below park their result
const DRAG_CACHE_KEY: StringName = &"draggable_component"
const DELIVER_CACHE_KEY: StringName = &"deliverable_component"


# 物件手上拿的是什么，空手返回 &"" / payload of an item, &"" when it has none
static func payload_of(item) -> StringName:
	var deliverable: DeliverableComponent = _deliverable_of(item)
	return deliverable.payload if deliverable != null else &""


func _ready() -> void:
	_carrier = get_parent() as Node2D
	if _carrier == null:
		push_warning("CarryComponent needs a Node2D parent: %s" % get_path())
	set_physics_process(false)


func is_carrying() -> bool:
	return is_instance_valid(_item)


func carried_item() -> Node2D:
	return _item if is_instance_valid(_item) else null


func payload() -> StringName:
	return payload_of(carried_item())


func can_pick_up(item) -> bool:
	if is_carrying() or not is_instance_valid(item) or not (item is RigidBody2D):
		return false
	# 冻着说明已经在别人嘴里了 / frozen means somebody else already has it
	if (item as RigidBody2D).freeze:
		return false
	var draggable: Node = _draggable_of(item)
	# 玩家正拿着就别抢 / never yank it out of the player's hand
	return draggable == null or not draggable.is_grabbed()


func pick_up(item: Node) -> bool:
	if not can_pick_up(item) or _carrier == null:
		return false

	_item = item as RigidBody2D
	_saved_gravity = _item.gravity_scale
	_saved_layer = _item.collision_layer
	_saved_mask = _item.collision_mask
	_item.freeze = true
	# 叼着的货物照样是刚体，不关碰撞就会一直把持有者顶开
	# Cargo is still a body - leave collision on and it shoves the carrier away every frame.
	_item.collision_layer = 0
	_item.collision_mask = 0
	if not cargo_stays_grabbable:
		var draggable: Node = _draggable_of(_item)
		if draggable != null:
			draggable.input_pickable = false

	_sync_cargo()
	set_physics_process(true)
	picked_up.emit(_item)
	return true


# 放下并尝试交付。返回的是"交出去了没有"，不是"放下了没有"
# Returns whether the drop landed a delivery, not merely whether something was released.
# units 是交付时算几份，载重变种一趟顶多份 / how much the drop counts for
func drop(units: int = 1) -> bool:
	if not is_carrying():
		return false

	var item: RigidBody2D = _item
	_item = null
	set_physics_process(false)

	item.freeze = false
	item.gravity_scale = _saved_gravity
	item.collision_layer = _saved_layer
	item.collision_mask = _saved_mask
	item.linear_velocity = Vector2.ZERO
	item.angular_velocity = 0.0
	var draggable: Node = _draggable_of(item)
	if draggable != null:
		draggable.input_pickable = true

	dropped.emit(item)

	var deliverable: DeliverableComponent = _deliverable_of(item)
	return deliverable != null and deliverable.try_deliver(units)


func _physics_process(_delta: float) -> void:
	if not is_carrying():
		set_physics_process(false)  # 货物被别人 free 掉了 / cargo got freed from under us
		return
	_sync_cargo()


func _sync_cargo() -> void:
	if _carrier == null:
		return
	_item.global_position = _carrier.global_position + carry_offset
	_item.linear_velocity = Vector2.ZERO


# 下面两个查找每帧被采集任务打上千次，所以跟 ClaimComponent.of() 一个待遇：
# 找到的结果记在物件身上，只缓存命中。**读缓存不加类型**，理由见 ClaimComponent.of()
# Cached like ClaimComponent.of(); the read stays untyped for the same reason.
# Both are called thousands of times a frame by Gather; hits get cached on the item.
func _draggable_of(item) -> Node:
	if not is_instance_valid(item):
		return null
	if item.has_meta(DRAG_CACHE_KEY):
		var hit = item.get_meta(DRAG_CACHE_KEY)
		if is_instance_valid(hit):
			return hit
	for child in item.get_children():
		if child is DraggableComponent:
			item.set_meta(DRAG_CACHE_KEY, child)
			return child
	return null


static func _deliverable_of(item) -> DeliverableComponent:
	if not is_instance_valid(item):
		return null
	if item.has_meta(DELIVER_CACHE_KEY):
		var hit = item.get_meta(DELIVER_CACHE_KEY)
		if is_instance_valid(hit):
			return hit
	for child in item.get_children():
		if child is DeliverableComponent:
			item.set_meta(DELIVER_CACHE_KEY, child)
			return child
	return null
