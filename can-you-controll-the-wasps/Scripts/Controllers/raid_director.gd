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

# 什么时候来**不再是一个计时器**，而是每代开局就掷好、并且画在季节条上的一张时间表。
# 玩家看得见下一波大概什么时候到，于是"要不要现在把采集蜂调回来"变成一个可以提前做的决定。
# 时间用 SeasonDirector.year_progress()（整年 0..1），季节条画的就是这根轴，两边天然对齐。
# The schedule is rolled once per generation and drawn on the season bar: the player can
# see it coming, which turns "pull the foragers back" into a decision made in advance.

signal raid_started(wave: int, count: int)
signal raid_ended(cleared: bool)
## 时间表变了（重掷 / 某一项状态变了），季节条据此重画
## The schedule changed - the bar redraws from this.
signal schedule_changed(marks: Array)

## 时间表上一个点的状态 / one mark's state on the year
enum MarkState {
	PENDING,   ## 还没到 / not yet
	ACTIVE,    ## 正在打 / happening now
	DONE,      ## 打完了 / over
	MISFIRE,   ## 到点了但巢里没东西可抢，这一次作废 / nothing worth taking, written off
}

const GROUP: StringName = &"raid_director"
const BAR_GROUP: StringName = &"season_bar"
const SEASON_COUNT: int = 4
## 两波之间至少要留 raid_duration 的这个倍数，多出来的是喘息时间
## Breathing room between waves, as a multiple of one raid's length.
const DURATION_HEADROOM: float = 1.35
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
## 入侵窗口，按整年进度算：0 = 初春，0.25 = 入夏，0.5 = 入秋，0.75 = 入冬。
## 默认从春季后半段到秋季结束——**冬天不留位置**，那一段是继位仪式，
## 加冕典礼上站着敌人会被读成 bug
## Winter is deliberately outside the window: the coronation must stay quiet.
@export_range(0.0, 1.0, 0.005) var window_start: float = 0.125
@export_range(0.0, 1.0, 0.005) var window_end: float = 0.75
## 每代来几次，闭区间随机 / raids per generation, inclusive
@export var raids_per_year: Vector2i = Vector2i(1, 3)
## 两次之间至少隔多少进度。窗口已经切成等份了，这条是保底：
## 纯随机会掷出两个挨在一起的点，第二波撞上第一波还没撤走，玩家看到的是一团糊
## A floor on the spacing, so a second wave never lands on one still retreating.
@export_range(0.0, 0.3, 0.005) var min_gap: float = 0.06
## 巢里没有卵/幼虫/建造进度就**跳过**这一次（图标画成哑火），不延后。
## 延后会把入侵堆到冬天，而且图标画在那儿却什么都不发生，玩家会以为坏了
## Skipped, never postponed: postponing piles raids onto winter and makes the icon lie.
@export var require_something_to_take: bool = true

@export_group("Size")
@export_range(1, 12, 1) var base_count: int = 2
## 每建成这么多格子多来一只 / one extra raider per this many finished cells
@export_range(1, 20, 1) var cells_per_extra: int = 5
@export_range(1, 16, 1) var max_count: int = 6
## 同一代里每往后一次多来几只 / extra raiders per later raid in the same year
@export_range(0, 6, 1) var per_raid_extra: int = 1
## 猎手占比每往后一次涨多少。头一波以小偷为主（威胁巢），越往后越多猎手（威胁蜂）——
## 强度递增体现在**构成**上，不改 EnemyVariant 的血量：同一种敌人血量不固定的话，
## 玩家没法对"这是什么东西"建立预期
## Later waves shift toward hunters; per-breed health stays fixed so the player can learn it.
@export_range(0.0, 0.4, 0.05) var hunter_share_step: float = 0.15
## 进场位置的散布，别让一波敌人叠在同一个点上 / keeps a wave from stacking on one pixel
@export_range(0.0, 200.0, 5.0) var entry_scatter: float = 40.0

@export_group("Duration")
## 撑过这么久，没死的自己撤走。纯等全灭的话一只漏网的能把警报永远钉住
## Survivors leave after this. Waiting for a total wipe lets one stray pin the alarm on.
##
## **它和 raids_per_year 是耦合的。** 一代的入侵窗口只有 157.5 秒
## （春的后半 22.5 + 夏 75 + 秋 60），每波还要留 DURATION_HEADROOM 倍的喘息，
## 所以窗口最多装得下 `157.5 / (raid_duration * 1.35)` 波：45 秒时只有 2 波，
## 想要 3 波必须压到 38 以下。装不下的话 roll_schedule() 会自己减波数，
## 那时 raids_per_year 的上限就是个摆设了
## Coupled with raids_per_year: at 45s the window only fits two waves, so three would
## silently never happen. Raise the season durations if you want longer raids back.
@export_range(10.0, 300.0, 5.0) var raid_duration: float = 38.0

## 冬天暂停。不只是不排下一波——正在进行的那一波也当场收兵，
## 否则加冕典礼上会站着几只敌人。由 SeasonDirector 写入
## Calls off the wave in progress too: enemies at a coronation read as a bug.
var paused: bool = false:
	set(value):
		if paused == value:
			return
		paused = value
		if paused and _raiding:
			call_off()

var wave: int = 0

var _raiders: Array = []
var _entries: Array[Node2D] = []
var _planned: int = 0
var _time_left: float = 0.0
var _raiding: bool = false
## 这一代的时间表，按 at 升序。每项 {at: float, state: MarkState}
var _schedule: Array = []
## 这一代已经打到第几次（1-based），强度按它递增 / 1-based, drives the ramp
var _raid_index: int = 0


static func find(tree: SceneTree) -> RaidDirector:
	return tree.get_first_node_in_group(GROUP) as RaidDirector


func _ready() -> void:
	add_to_group(GROUP)
	for child in get_children():
		var entry: Node2D = child as Node2D
		if entry != null:
			_entries.append(entry)
	if _entries.is_empty():
		push_warning("RaidDirector has no entry markers, raiders will spawn on it: %s" % get_path())
	# 延后一帧：SeasonDirector 和 SeasonBar 未必比这里先 _ready
	# Deferred - neither the director nor the bar is guaranteed to be ready before us.
	_bind_season.call_deferred()


func _bind_season() -> void:
	var season: SeasonDirector = SeasonDirector.find(get_tree())
	if season == null:
		push_warning("RaidDirector found no SeasonDirector; no raids will be scheduled")
		return
	if not season.generation_advanced.is_connected(_on_generation_advanced):
		season.generation_advanced.connect(_on_generation_advanced)
	roll_schedule()


func _on_generation_advanced(_generation: int) -> void:
	roll_schedule()


# 掷这一代的时间表。窗口切成 n 等份、每份里随机一点（分层抽样），而不是纯随机撒 n 个——
# 纯随机经常把两个点掷到一起，那两波会叠在一起，而且第二波的 raid_duration 根本跑不完
# Stratified, not uniform: uniform sampling clumps, and clumped raids overlap.
func roll_schedule() -> void:
	_schedule.clear()
	_raid_index = 0

	var span: float = window_end - window_start
	var count: int = randi_range(maxi(raids_per_year.x, 0), maxi(raids_per_year.y, 0))
	if count <= 0 or span <= 0.0:
		_push_marks()
		return

	# 窗口装不下这么多波就少来几波。**宁可少一次，也不要两波叠在一起**：
	# 一波还没撤走下一个点就到了的话，第二波只能排队补打，季节条上预告的位置全部失准，
	# 而失准的预告比没有预告更糟
	# A late raid is worse than a missing one - the icon would be lying about when.
	var season: SeasonDirector = SeasonDirector.find(get_tree())
	var seconds: float = _window_seconds(season)
	var gap: float = min_gap
	if seconds > 0.0:
		var need: float = raid_duration * DURATION_HEADROOM
		count = clampi(int(seconds / need), 1, count)
		gap = maxf(gap, need / seconds * span)

	var slot: float = span / float(count)
	var previous: float = -INF
	for i in count:
		var low: float = window_start + slot * float(i)
		var at: float = randf_range(low, low + slot)
		at = clampf(maxf(at, previous + gap), window_start, window_end)
		_schedule.append({&"at": at, &"state": MarkState.PENDING})
		previous = at

	_push_marks()


# 时间表是给季节条看的。**只读**，别在外面改状态 / read-only for the bar
func schedule() -> Array:
	return _schedule


# 入侵窗口跨越多少**真实秒数**。year_progress 每季固定占 0.25，但四季时长不同，
# 所以进度不是线性时间——不换算的话 min_gap 只是个看起来合理的数字
# Each season owns 0.25 of the axis but not 0.25 of the clock; the gap has to be converted.
func _window_seconds(season: SeasonDirector) -> float:
	if season == null:
		return 0.0
	var total: float = 0.0
	for i in SEASON_COUNT:
		var low: float = float(i) / float(SEASON_COUNT)
		var overlap: float = minf(low + 1.0 / float(SEASON_COUNT), window_end) - maxf(low, window_start)
		if overlap <= 0.0:
			continue
		total += season.duration_of(i) * overlap * float(SEASON_COUNT)
	return total


# 下一个还没打的点在整年的哪个位置，没有了返回 -1 / -1 when the year has none left
func next_mark_at() -> float:
	for mark in _schedule:
		if mark[&"state"] == MarkState.PENDING:
			return mark[&"at"]
	return -1.0


func _push_marks() -> void:
	schedule_changed.emit(_schedule)
	var bar: Node = get_tree().get_first_node_in_group(BAR_GROUP)
	if bar != null and bar.has_method("set_raid_marks"):
		bar.set_raid_marks(_schedule)


# 警报响着没有。Defend 靠这一个开关决定要不要放全员进来
# The single switch Defend reads to decide whether everybody may answer.
func is_raiding() -> bool:
	return _raiding


func raiders_left() -> int:
	_prune()
	return _raiders.size()


func time_left() -> float:
	return _time_left





# 调试用，也是以后接"季节"之类外部触发器的入口 / debug hook, and the seasonal entry point
func start_now() -> bool:
	if _raiding or enemy_scene == null:
		return false
	_start()
	return true


func _process(delta: float) -> void:
	if paused:
		return
	if _raiding:
		_tick_raid(delta)
		return
	_check_schedule()


# 走到哪个点就打哪一波。时间表是升序的，撞上第一个没到的就可以收工
# The schedule is sorted, so the first pending mark in the future ends the scan.
func _check_schedule() -> void:
	if _schedule.is_empty() or enemy_scene == null:
		return
	var season: SeasonDirector = SeasonDirector.find(get_tree())
	if season == null:
		return

	var now: float = season.year_progress()
	for mark in _schedule:
		if mark[&"state"] != MarkState.PENDING:
			continue
		if now < mark[&"at"]:
			return

		# 到点了，但巢里空空如也：这一次作废，图标画成哑火。
		# 玩家读到的是"我太穷了，没人稀罕来抢"——一条不用另造机制的反馈
		# Written off rather than postponed; the greyed icon says "nothing here worth taking".
		if require_something_to_take and not _has_spoils():
			mark[&"state"] = MarkState.MISFIRE
			_push_marks()
			continue

		mark[&"state"] = MarkState.ACTIVE
		_raid_index += 1
		_start()
		_push_marks()
		return


func _tick_raid(delta: float) -> void:
	_prune()
	if _raiders.is_empty():
		_end(true)
		return

	_time_left -= delta
	if _time_left > 0.0:
		return

	call_off()


# 收兵。活着的往外飞，路上还是可以被打死的 / still killable on the way out
func call_off() -> void:
	for raider in _raiders:
		if is_instance_valid(raider) and raider.has_method("retreat"):
			raider.retreat()
	_end(false)


func _start() -> void:
	wave += 1
	# 两条叠加：巢越大来得越多（长期压力），同一代里越往后来得越多（单代内的递进）
	# Hive size is the long arc; the index is the ramp inside a single year.
	var count: int = base_count + (maxi(_raid_index, 1) - 1) * per_raid_extra
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
		_mark_active_as(MarkState.MISFIRE)
		return

	_raiding = true
	_time_left = raid_duration
	raid_started.emit(wave, _raiders.size())


func _end(cleared: bool) -> void:
	_raiding = false
	_time_left = 0.0
	_raiders.clear()
	_mark_active_as(MarkState.DONE)
	raid_ended.emit(cleared)


func _mark_active_as(state: MarkState) -> void:
	for mark in _schedule:
		if mark[&"state"] == MarkState.ACTIVE:
			mark[&"state"] = state
	_push_marks()


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
	var share: float = clampf(hunter_share + float(maxi(_raid_index, 1) - 1) * hunter_share_step, 0.0, 1.0)
	var hunters: int = mini(int(round(float(_planned) * share)), maxi(_planned - 1, 0))
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
