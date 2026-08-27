class_name ClaimComponent
extends Node

# 认领 / claim: 同一件东西同一时刻只让一只黄蜂惦记。
# 没有它，八只黄蜂会一起扑同一块纸板，七只白飞 / without it the whole swarm chases one piece.
# 认领方失效（被玩家抓走、死了）会自动释放 / a dead claimer releases itself.

signal claimed(by: Node)
signal released(by: Node)

var _holder: Node = null


# 从任意节点身上找这个组件，找不到返回 null / null when the node has no claim slot
# 参数不加类型：传进来的可能是已经被 free 掉的节点，类型化参数会在进函数前就报错
# Untyped on purpose - callers legitimately pass freed nodes and a typed param errors first.
static func of(node) -> ClaimComponent:
	if not is_instance_valid(node):
		return null
	for child in node.get_children():
		if child is ClaimComponent:
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
