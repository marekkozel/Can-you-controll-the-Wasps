class_name DebugActions
extends Node

# 调试用的上帝操作 / debug god actions. 只有操作没有 UI，DebugPanel 调它。
# 发布前把 DebugPanel 从 world.tscn 删掉即可 / delete the DebugPanel node to remove it.

signal action_done(message: String)

const HIVE_GROUP: StringName = &"hive"
const ENTITIES_GROUP: StringName = &"entities"
const SOURCE_GROUP: StringName = &"item_source"
const WASP_GROUP: StringName = &"wasps"
const DIRECTOR_GROUP: StringName = &"betrayal_director"

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


# 立刻叫一波入侵 / call a raid in right now
func start_raid() -> void:
	var d: RaidDirector = RaidDirector.find(get_tree())
	if d == null:
		_report("no RaidDirector in the scene")
		return
	if not d.start_now():
		_report("raid already running, %d raiders left" % d.raiders_left())
		return
	_report("raid %d incoming: %d raiders" % [d.wave, d.raiders_left()])


# 收兵。测试警报解除之后蜂群会不会回去干活 / call it off, to test that the swarm goes back to work
func end_raid() -> void:
	var d: RaidDirector = RaidDirector.find(get_tree())
	if d == null or not d.is_raiding():
		_report("no raid running")
		return
	for node in get_tree().get_nodes_in_group("Enemy"):
		if node.has_method("retreat"):
			node.retreat()
	_report("raid called off")


# 品种表直接从 RaidDirector 读，**不在这里 preload 一份**——面板上的按钮也是照它生成的，
# 所以加第七种敌人只要往 world.tscn 的 breeds 里塞一个 .tres，调试面板自动多一行
# Read from the director: a new breed needs no new constant and no new button here.
func breeds() -> Array:
	var director: RaidDirector = RaidDirector.find(get_tree())
	if director == null:
		return []
	var list: Array = []
	for breed in director.breeds:
		if breed != null:
			list.append(breed)
	return list


func spawn_breed_index(index: int) -> void:
	var list: Array = breeds()
	if index < 0 or index >= list.size():
		_report("no breed %d" % index)
		return
	var breed: EnemyVariant = list[index]
	# 按体型内缩，否则蜘蛛半个身子会生成在上带的墙里 / the spider would spawn half inside a wall
	var margin: float = breed.collision_radius + 24.0
	var spot: Vector2 = Vector2(
		randf_range(280.0, 1000.0),
		randf_range(40.0 + margin, 248.0 - margin))
	var enemy: Enemy = _make_breed(breed, spot)
	# 正式入侵的敌人是 begin_raid() 进场的，不叫它的话调试刷出来的敌人只会在上带游荡，
	# 永远不靠近巢——测出来的"没人打架"是假的
	# Without this a debug enemy just loiters in the top band and never approaches, so
	# "nobody fights" reads as an AI bug when it is only a different code path.
	enemy.begin_raid(spot)
	_report("spawned a %s (r=%d, %dx, %d hp)"
		% [breed.display_name, int(breed.collision_radius), int(breed.sprite_scale), breed.max_health])


# 一字排开，全部**冻住**。调体型要的是这个：六只满地乱飞根本没法比大小，
# 而且大的那两只会当场把蜂群啃了，比着比着场上就没蜂了
# The one that matters for tuning builds: frozen, in a row, and not eating the colony.
func line_up_breeds() -> void:
	for node in get_tree().get_nodes_in_group("Enemy"):
		node.queue_free()

	var list: Array = breeds()
	if list.is_empty():
		_report("no breeds on the RaidDirector")
		return

	# 按体型从小到大排，一眼看得出梯度对不对 / sorted by build, so the ramp is readable
	list.sort_custom(func(a, b): return a.collision_radius < b.collision_radius)

	var span: float = 1000.0 - 280.0
	for i in list.size():
		var breed: EnemyVariant = list[i]
		var at: Vector2 = Vector2(
			280.0 + span * (float(i) + 0.5) / float(list.size()),
			150.0)
		_make_breed(breed, at).pose()
	_report("lined up %d breeds (frozen)" % list.size())


func _make_breed(breed: EnemyVariant, at: Vector2) -> Enemy:
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	# variant 必须在 add_child 之前写：_apply_variant() 在 _ready 里跑
	# Must be set before the node enters the tree - _apply_variant() runs in _ready.
	enemy.variant = breed
	entities_root().add_child(enemy)
	enemy.global_position = at
	enemy.set_wander_home(at)
	return enemy


# ---------------- 季节 / seasons ----------------

# 一个季节两分钟起步，不给个跳过键根本没法看交替那一下
# A season runs minutes; without a skip you never get to watch the turnover.
func skip_season() -> void:
	var d: SeasonDirector = SeasonDirector.find(get_tree())
	if d == null:
		_report("no SeasonDirector in the scene")
		return
	d.advance()
	_report("season -> %s (gen %d)" % [d.season_name(), d.generation])


# 直接跳到冬天，不用等两季 / straight to winter, no waiting through two seasons
func skip_to_winter() -> void:
	var d: SeasonDirector = SeasonDirector.find(get_tree())
	if d == null:
		_report("no SeasonDirector in the scene")
		return
	# 最多转一整轮，防止 season 卡在某个值时死循环 / bounded, never loops forever
	for i in SeasonDirector.SEASON_COUNT:
		if d.season == SeasonDirector.Season.WINTER:
			break
		d.advance()
	_report("season -> %s (%s)" % [d.season_name(), d.rite_name()])


# 立刻让蜂群推举一只。测的是"自动继位"那条链，玩家平时得等 throne_timeout
func crown_someone() -> void:
	var d: SeasonDirector = SeasonDirector.find(get_tree())
	if d == null or not d.is_winter():
		_report("not winter - no throne to take")
		return
	var candidates: Array = []
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Wasp = node as Wasp
		if wasp != null and wasp.allegiance().works():
			candidates.append(wasp)
	if candidates.is_empty():
		_report("nobody eligible")
		return
	var heir: Wasp = candidates[randi() % candidates.size()]
	if d.crown(heir):
		_report("crowned %s" % heir.wasp_name)
	else:
		_report("the throne refused it")


func grant_gene_point() -> void:
	var bank: GeneBank = GeneBank.find(get_tree())
	if bank == null:
		_report("no GeneBank in the scene")
		return
	bank.points += 1
	bank.points_changed.emit(bank.points)
	_report("gene points: %d" % bank.points)


# ---------------- 叛乱 / betrayal ----------------

func director() -> BetrayalDirector:
	return get_tree().get_first_node_in_group(DIRECTOR_GROUP) as BetrayalDirector


func awaken_false_queen() -> void:
	var d: BetrayalDirector = director()
	if d == null:
		_report("no BetrayalDirector in the scene")
		return
	var queen: Wasp = d.awaken_now()
	_report("no candidate to turn" if queen == null else "a false queen is among them")


# 只给调试用。正式玩法里玩家只能靠行为差异判断
# Debug only - in play you are meant to work it out from behaviour alone.
func reveal_allegiances() -> void:
	var lines: PackedStringArray = PackedStringArray()
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Wasp = node as Wasp
		if wasp == null:
			continue
		var a: AllegianceComponent = wasp.allegiance()
		lines.append("%-8s %-12s betrayal %.2f%s @%s" % [
			wasp.variant().variant.display_name if wasp.variant().variant != null else "?",
			AllegianceComponent.State.keys()[a.state],
			a.betrayal,
			"  ON STRIKE" if a.is_on_strike() else "",
			wasp.global_position.round()])
	for line in lines:
		print("[debug] ", line)
	_report("dumped %d wasps to the console" % lines.size())


# 不安值得靠处决才能推上去，调参数时太慢了 / nudging it directly beats staging executions
func bump_unrest() -> void:
	var d: BetrayalDirector = director()
	if d == null:
		_report("no BetrayalDirector in the scene")
		return
	d.add_unrest(0.2)
	_report("unrest %.2f" % d.unrest)


func clear_unrest() -> void:
	var d: BetrayalDirector = director()
	if d == null:
		return
	d.add_unrest(-1.0)
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Wasp = node as Wasp
		if wasp != null:
			wasp.allegiance().betrayal = 0.0
	_report("unrest and every grudge cleared")


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
	# 走 HitStop：卡顿正跑着的时候直接写 Engine.time_scale 会被它随后的还原覆盖掉
	# Through HitStop, or a freeze in flight would restore over this.
	HitStop.release()
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
		# 占用物现在直接挂在格子下，不再走 Visual/Content
		# Occupants are direct children of the cell now, no Visual/Content wrapper.
		for child in cell.get_children():
			var hunger: HungerComponent = child.get_node_or_null("HungerComponent")
			if hunger != null:
				out.append(hunger)
	return out


func _report(message: String) -> void:
	print("[debug] ", message)
	action_done.emit(message)
