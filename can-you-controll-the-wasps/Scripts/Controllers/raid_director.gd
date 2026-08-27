class_name RaidDirector
extends Node2D

# 入侵调度 / raid director. 场景级，跟 BetrayalDirector 并排挂在 Queen_controller 下。
# 敌人不再常驻：平时场上一只都没有，到点了成批从入口摸进来，抢完或者撑够时间就撤。
# Enemies no longer idle on the map. They arrive in waves, take what they can, and leave.
#
# 入场点是本节点下的 Marker2D 子节点，摆位置有两条硬约束：必须落在导航面里，
# 而且要离 item_source 至少 100——敌人是 input_pickable 的刚体，趴在产出点上会把
# 玩家"从产出点往外拖"的点击整个吃掉
# Entry markers must sit on the navmesh AND well clear of any item_source: a raider is a
# pickable body and one parked on a post swallows the player's drag-from-source clicks.
#
# 警报必须会结束。全员集结的前提就是入侵有终点——Defend 是行为树的第一个分支，
# 常态化的警报会把每只蜂都钉在打架上，采集分支永远轮不到
# The alarm MUST end: Defend is the first branch of the tree, so a permanent alarm pins
# every wasp on combat and the gather branches never run.

signal raid_started(wave: int, count: int)
signal raid_ended(cleared: bool)

const GROUP: StringName = &"raid_director"
const HIVE_GROUP: StringName = &"hive"
const ENTITIES_GROUP: StringName = &"entities"

@export var enemy_scene: PackedScene

@export_group("Breeds")
## 偷卵那种，一波里至少保证有一只——没有小偷的入侵不威胁巢，只是场架
## At least one always spawns: a raid with no thief threatens nothing, it is just a brawl.
@export var thief: EnemyVariant
## 索敌那种 / the one that hunts wasps
@export var hunter: EnemyVariant
## 一波里猎手占多少 / share of each wave that hunts instead of stealing
@export_range(0.0, 1.0, 0.05) var hunter_share: float = 0.4

@export_group("Schedule")
## 第一波来得晚，先让玩家把巢起起来 / the first wave waits for a hive worth raiding
@export_range(0.0, 600.0, 5.0) var first_raid_delay: float = 90.0
@export_range(10.0, 600.0, 5.0) var raid_interval: float = 75.0
## 间隔抖动，别让玩家掐着秒表等 / jitter, so the player can't run a stopwatch on it
@export_range(0.0, 0.6, 0.05) var interval_jitter: float = 0.25
## 巢里没有卵/幼虫/建造进度就不刷。空巢没什么可抢的 / nothing to take, nothing comes
@export var require_something_to_take: bool = true

@export_group("Size")
@export_range(1, 12, 1) var base_count: int = 2
## 每建成这么多格子多来一只 / one extra raider per this many finished cells
@export_range(1, 20, 1) var cells_per_extra: int = 5
@export_range(1, 16, 1) var max_count: int = 6
## 进场位置的散布，别让一波敌人叠在同一个点上 / keeps a wave from stacking on one pixel
@export_range(0.0, 200.0, 5.0) var entry_scatter: float = 40.0

@export_group("Duration")
## 撑过这么久，没死的自己撤走。纯等全灭的话一只漏网的能把警报永远钉住
## Survivors leave after this. Waiting for a total wipe lets one stray pin the alarm on.
@export_range(10.0, 300.0, 5.0) var raid_duration: float = 45.0

var wave: int = 0

var _raiders: Array = []
var _entries: Array[Node2D] = []
var _planned: int = 0
var _timer: float = 0.0
var _time_left: float = 0.0
var _raiding: bool = false


static func find(tree: SceneTree) -> RaidDirector:
	return tree.get_first_node_in_group(GROUP) as RaidDirector


func _ready() -> void:
	add_to_group(GROUP)
	_timer = first_raid_delay
	for child in get_children():
		var entry: Node2D = child as Node2D
		if entry != null:
			_entries.append(entry)
	if _entries.is_empty():
		push_warning("RaidDirector has no entry markers, raiders will spawn on it: %s" % get_path())


# 警报响着没有。Defend 靠这一个开关决定要不要放全员进来
# The single switch Defend reads to decide whether everybody may answer.
func is_raiding() -> bool:
	return _raiding


func raiders_left() -> int:
	_prune()
	return _raiders.size()


func time_left() -> float:
	return _time_left


func time_to_next() -> float:
	return _timer


# 调试用，也是以后接"季节"之类外部触发器的入口 / debug hook, and the seasonal entry point
func start_now() -> bool:
	if _raiding or enemy_scene == null:
		return false
	_start()
	return true


func _process(delta: float) -> void:
	if _raiding:
		_tick_raid(delta)
		return

	_timer -= delta
	if _timer > 0.0:
		return
	if enemy_scene == null:
		_timer = raid_interval
		return
	# 没得抢就再等一会儿，别把这一波浪费在空巢上 / hold the wave for a hive worth hitting
	if require_something_to_take and not _has_spoils():
		_timer = raid_interval * 0.25
		return
	_start()


func _tick_raid(delta: float) -> void:
	_prune()
	if _raiders.is_empty():
		_end(true)
		return

	_time_left -= delta
	if _time_left > 0.0:
		return

	# 时间到，活着的收兵。它们飞出去的路上还是可以被打死的 / still killable on the way out
	for raider in _raiders:
		if raider.has_method("retreat"):
			raider.retreat()
	_end(false)


func _start() -> void:
	wave += 1
	var count: int = base_count
	var hive: Hive = get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	if hive != null:
		count += int(hive.built_count() / float(cells_per_extra))
	count = clampi(count, 1, max_count)
	_planned = count

	_raiders.clear()
	for i in count:
		var raider: Enemy = _spawn(i)
		if raider != null:
			_raiders.append(raider)

	if _raiders.is_empty():
		_timer = raid_interval
		return

	_raiding = true
	_time_left = raid_duration
	raid_started.emit(wave, _raiders.size())


func _end(cleared: bool) -> void:
	_raiding = false
	_time_left = 0.0
	_raiders.clear()
	_timer = raid_interval * randf_range(1.0 - interval_jitter, 1.0 + interval_jitter)
	raid_ended.emit(cleared)


func _spawn(index: int) -> Enemy:
	var raider: Enemy = enemy_scene.instantiate() as Enemy
	if raider == null:
		return null

	raider.variant = _breed_for(index)

	var entry: Vector2 = global_position
	if not _entries.is_empty():
		entry = _entries[index % _entries.size()].global_position
	var spot: Vector2 = entry + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * entry_scatter

	# variant 必须在 add_child 之前写：_apply_variant() 在 _ready 里跑
	# Must be set before the node enters the tree - _apply_variant() runs in _ready.
	_spawn_root().add_child(raider)
	raider.global_position = spot
	raider.set_wander_home(spot)
	raider.begin_raid(entry)  # 从哪进来的就从哪撤 / leaves the way it came
	return raider


# 前几只是猎手，剩下的是小偷。用固定切分而不是每只 randf()：随机会掷出"整波全是猎手"，
# 那一波巢完全没有压力，玩家学不到"入侵是来偷东西的"
# A fixed split, not a per-raider roll: randomness can produce an all-hunter wave, and
# that wave teaches the player nothing about what a raid is for.
func _breed_for(index: int) -> EnemyVariant:
	if hunter == null:
		return thief
	if thief == null:
		return hunter
	var hunters: int = mini(int(round(float(_planned) * hunter_share)), maxi(_planned - 1, 0))
	return hunter if index < hunters else thief


func _spawn_root() -> Node:
	var host: Node = get_tree().get_first_node_in_group(ENTITIES_GROUP)
	return host if host != null else get_tree().current_scene


# 巢里还有没有值得抢的东西 / is there anything in there worth the trip
func _has_spoils() -> bool:
	var hive: Hive = get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	if hive == null:
		return false
	for node in hive.all_cells():
		var cell: HexCell = node as HexCell
		if cell == null:
			continue
		if cell.content == HexCell.Content.LARVA or cell.content == HexCell.Content.EGG:
			return true
		if cell.progress > 0 and cell.content == HexCell.Content.NONE:
			return true
	return false


func _prune() -> void:
	_raiders = _raiders.filter(func(r): return is_instance_valid(r))
