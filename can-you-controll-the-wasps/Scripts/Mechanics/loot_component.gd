class_name LootComponent
extends Node

# 战利品 / loot: 持有者死掉时在原地撒几份东西。挂到有 HealthComponent 的实体下。
# Drops pieces where the owner fell. Needs a sibling HealthComponent.
#
# 撒出来的东西生成到**持有者的父节点**，不是持有者下面——尸体紧接着就 queue_free() 了，
# 挂在它下面的会跟着一起没
# Spawned into the owner's parent: the corpse is freed moments later and would take
# anything parented to it along.

signal dropped(pieces: Array[Node2D])

## 掉什么 / what falls out
@export var loot_scene: PackedScene
## 掉几份。敌人品种会覆盖它 / how many; the breed overrides this
@export_range(0, 8, 1) var count: int = 1
## 撒开的半径 / how far the pieces scatter
@export_range(0.0, 120.0, 2.0) var scatter_radius: float = 18.0
## 撒出去的力道，让它们弹开一点而不是叠在一个点上
## Enough impulse to separate them - a stack of bodies on one pixel is unclickable.
@export_range(0.0, 400.0, 10.0) var burst_impulse: float = 90.0

var _body: Node2D = null


func _ready() -> void:
	_body = get_parent() as Node2D
	if _body == null:
		push_warning("LootComponent needs a Node2D parent: %s" % get_path())
		return

	var health: HealthComponent = null
	for child in _body.get_children():
		if child is HealthComponent:
			health = child
			break
	if health == null:
		push_warning("LootComponent found no HealthComponent: %s" % get_path())
		return
	health.died.connect(_on_died)


func _on_died(_from: Vector2) -> void:
	if loot_scene == null or count <= 0 or not is_instance_valid(_body):
		return
	var host: Node = _body.get_parent()
	if host == null:
		return

	var at: Vector2 = _body.global_position
	var pieces: Array[Node2D] = []
	for i in count:
		var piece: Node2D = loot_scene.instantiate() as Node2D
		if piece == null:
			continue
		host.add_child(piece)
		var angle: float = randf() * TAU
		piece.global_position = at + Vector2(cos(angle), sin(angle)) * randf() * scatter_radius
		piece.rotation = randf_range(-PI, PI)
		var rb: RigidBody2D = piece as RigidBody2D
		if rb != null and burst_impulse > 0.0:
			rb.apply_central_impulse(Vector2(cos(angle), sin(angle)) * burst_impulse)
		pieces.append(piece)

	if not pieces.is_empty():
		dropped.emit(pieces)
