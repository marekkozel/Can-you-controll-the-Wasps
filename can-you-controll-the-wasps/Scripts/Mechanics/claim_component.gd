class_name ClaimComponent
extends Node

# 认领 / claim: 同一件东西同一时刻只让一只黄蜂惦记。
# 没有它，八只黄蜂会一起扑同一块纸板，七只白飞 / without it the whole swarm chases one piece.
# 认领方失效（被玩家抓走、死了）会自动释放 / a dead claimer releases itself.

signal claimed(by: Node)
signal released(by: Node)

var _holder: Node = null

# of() 的缓存键，写在物件身上 / where of() parks its lookup, on the item itself
const CACHE_KEY: StringName = &"claim_component"


# 从任意节点身上找这个组件，找不到返回 null / null when the node has no claim slot
# 参数不加类型：传进来的可能是已经被 free 掉的节点，类型化参数会在进函数前就报错
# Untyped on purpose - callers legitimately pass freed nodes and a typed param errors first.
static func of(node) -> ClaimComponent:
	if not is_instance_valid(node):
		return null
	# 每帧都有几十只蜂 x 几十件散件走这里，现查现找的 get_children() 是实打实的开销。
	# 组件在物件活着的这段时间里不会换人，找到就记在物件身上
	# Hot path - an item's components never change while it lives, so cache the hit on it.
	# **只缓存找到的**：没有的那种不写缓存，后加的组件仍然找得到
	# Only hits are cached, so a component added later is still discoverable.
	# **读出来不加类型也不 as**：缓存里那个可能已经被 free 了，转换会当场抛
	# "Trying to cast a freed object" 并中断整个函数，后面的有效性检查根本轮不到
	# Untyped and uncast on purpose - casting a freed object throws before the check runs.
	if node.has_meta(CACHE_KEY):
		var hit = node.get_meta(CACHE_KEY)
		if is_instance_valid(hit):
			return hit
	for child in node.get_children():
		if child is ClaimComponent:
			node.set_meta(CACHE_KEY, child)
			return child
	return null


func is_claimed() -> bool:
	_prune()
	return _holder != null


func can_claim(who: Node) -> bool:
	_prune()
	return _holder == null or _holder == who


func claim(who: Node) -> bool:
	if who == null or not can_claim(who):
		return false
	if _holder == who:
		return true
	_holder = who
	claimed.emit(who)
	return true


func release(who: Node) -> void:
	if _holder == null or _holder != who:
		return
	_holder = null
	released.emit(who)


func _prune() -> void:
	if _holder != null and not is_instance_valid(_holder):
		_holder = null
