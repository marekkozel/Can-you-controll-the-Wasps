class_name DebugActions
extends Node

# 调试用的上帝操作 / debug god actions. 只有操作没有 UI，DebugPanel 调它。
# 发布前把 DebugPanel 从 world.tscn 删掉即可 / delete the DebugPanel node to remove it.

signal action_done(message: String)

const HIVE_GROUP: StringName = &"hive"
const ENTITIES_GROUP: StringName = &"entities"
const SOURCE_GROUP: StringName = &"item_source"

const WASP_SCENE: PackedScene = preload("res://Scenes/Entities/Wasp.tscn")
const CARDBOARD_SCENE: PackedScene = preload("res://Scenes/Entities/Cardboard.tscn")
const FOOD_SCENE: PackedScene = preload("res://Scenes/Entities/Food.tscn")
const ENEMY_SCENE: PackedScene = preload("res://Scenes/Entities/Enemy.tscn")

## 时间倍率循环用的档位 / time scale steps cycled by the hotkey
const TIME_SCALES: Array[float] = [1.0, 2.0, 4.0, 8.0, 0.25, 0.5]

var _time_index: int = 0


func hive() -> Hive:
	return get_tree().get_first_node_in_group(HIVE_GROUP) as Hive


func entities_root() -> Node:
	var host: Node = get_tree().get_first_node_in_group(ENTITIES_GROUP)
	return host if host != null else get_tree().current_scene


# ---------------- 巢室 / cells ----------------

func build_all_cells() -> void:
	var h: Hive = hive()
	if h == null:
		return
	var count: int = 0
	for cell in h.all_cells():
		if not cell.is_built:
			cell.add_build_progress(cell.build_cost)
			count += 1
	_report("built %d cells" % count)


# 一路推到黄蜂：没建就建，然后产卵、孵化、封盖、羽化 / drives one cell all the way
func complete_one_wasp() -> void:
	var h: Hive = hive()
	if h == null:
		return
	var cell: HexCell = _first_free_cell(h)
	if cell == null:
		_report("no free cell")
		return
	# 最多推 6 步，防止哪个状态没接上时死循环 / bounded, guards against a broken state
	for i in 6:
		if not cell.advance_stage():
			break
		if cell.content == HexCell.Content.NONE and cell.is_built:
			break
	_report("completed a wasp at %s" % cell.coord)


func advance_all_cells() -> void:
	var h: Hive = hive()
	if h == null:
		return
	for cell in h.all_cells():
		cell.advance_stage()
	_report("advanced every cell one stage")


func reset_hive() -> void:
	var h: Hive = hive()
	if h == null:
		return
	h.rebuild()
	_report("hive rebuilt")


# ---------------- 幼虫 / larvae ----------------

func make_all_hungry() -> void:
	var count: int = 0
	for hunger in _all_hunger():
		if hunger.state == HungerComponent.State.SATIATED:
			hunger.time_left = 0.01
			count += 1
	_report("%d larvae will get hungry now" % count)


func feed_all_larvae() -> void:
	var count: int = 0
	for hunger in _all_hunger():
		if hunger.is_hungry():
			hunger.feed(hunger.required_units)
			count += 1
	_report("fed %d larvae" % count)


# ---------------- 实体 / entities ----------------

func spawn_wasp(count: int = 1) -> void:
	var h: Hive = hive()
	var origin: Vector2 = h.global_position if h != null else Vector2(640, 460)
	for i in count:
		var wasp: Wasp = WASP_SCENE.instantiate()
		entities_root().add_child(wasp)
		wasp.global_position = origin + Vector2(randf_range(-80.0, 80.0), randf_range(-60.0, 60.0))
		wasp.set_wander_home(origin)
	_report("spawned %d wasps" % count)


func spawn_enemy(count: int = 1) -> void:
	for i in count:
		var enemy: Enemy = ENEMY_SCENE.instantiate()
		entities_root().add_child(enemy)
		var spot: Vector2 = Vector2(randf_range(280.0, 1000.0), randf_range(50.0, 200.0))
		enemy.global_position = spot
		enemy.set_wander_home(spot)
	_report("spawned %d enemies" % count)


func kill_all_enemies() -> void:
	var count: int = 0
	for node in entities_root().get_children():
		if node is Enemy:
			node.get_node("HealthComponent").take_damage(99, node.global_position + Vector2(0, -30))
			count += 1
	_report("killed %d enemies" % count)


func clear_enemies() -> void:
	var count: int = 0
	for node in entities_root().get_children():
		if node is Enemy:
			node.queue_free()
			count += 1
	_report("removed %d enemies" % count)


func clear_wasps() -> void:
	var count: int = 0
	for node in entities_root().get_children():
		if node is Wasp:
			node.queue_free()
			count += 1
	_report("removed %d wasps" % count)


func spawn_items(payload: StringName, count: int = 3) -> void:
	var scene: PackedScene = CARDBOARD_SCENE if payload == &"cardboard" else FOOD_SCENE

	# 靠分组找资源点，别依赖 current_scene，它可能是 null / current_scene can be null
	var source: Node2D = null
	for node in get_tree().get_nodes_in_group(SOURCE_GROUP):
		if node.piece_scene == scene:
			source = node
			break

	var origin: Vector2 = source.global_position if source != null else Vector2(640, 120)
	var host: Node = source.get_parent() if source != null else entities_root()

	for i in count:
		var piece: Node2D = scene.instantiate()
		host.add_child(piece)
		piece.global_position = origin + Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
	_report("spawned %d %s" % [count, payload])


# ---------------- 时间 / time ----------------

func cycle_time_scale() -> float:
	_time_index = (_time_index + 1) % TIME_SCALES.size()
	Engine.time_scale = TIME_SCALES[_time_index]
	_report("time scale x%.2f" % Engine.time_scale)
	return Engine.time_scale


func reset_time_scale() -> void:
	_time_index = 0
	Engine.time_scale = 1.0
	_report("time scale x1")


# ---------------- 内部 / internals ----------------

func _first_free_cell(h: Hive) -> HexCell:
	for cell in h.all_cells():
		if not cell.is_built or cell.content == HexCell.Content.NONE:
			return cell
	return null


func _all_hunger() -> Array:
	var out: Array = []
	var h: Hive = hive()
	if h == null:
		return out
	for cell in h.all_cells():
		if cell.content != HexCell.Content.LARVA:
			continue
		var larva: Node = cell.get_node_or_null("Visual/Content").get_child(0)
		if larva != null:
			var hunger: HungerComponent = larva.get_node_or_null("HungerComponent")
			if hunger != null:
				out.append(hunger)
	return out


func _report(message: String) -> void:
	print("[debug] ", message)
	action_done.emit(message)
