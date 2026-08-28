class_name SeasonDirector
extends Node2D

# 季节调度 / season director. 跟 BetrayalDirector / RaidDirector 并排挂在 Queen_controller 下。
# 转四季的轮子，并且掌着这个游戏真正的循环：**冬天的继位仪式**。
# Owns the wheel, and with it the loop that actually matters - the winter succession.
#
# 冬天不是又一段玩法，是一次结算，分四拍走：
#   毁坏 → 王座开放（拖一只进去，或者等蜂群自己推举一只飞进去）→ 集结 → 倒计时
# 冬天的长度由仪式决定，不由计时器决定——但每一拍都有硬超时兜底，
# **仪式绝不允许卡住**：一只蜂卡在墙角就永远进不了春天，那是最贵的一种 bug。
# Winter is a settlement in four beats and its length comes from the rite, not a clock -
# but every beat has a hard timeout. A rite that can stall is a game that can stall.

signal season_changed(season: int, generation: int)
## 每帧一次，给表现层用 / per-frame, for the bar and for anything atmospheric later
signal season_tick(season: int, time_left: float, ratio: float)
## 转回春天 = 新皇治下的第一个季节，又过了一代 / the new queen's first season
signal generation_advanced(generation: int)
## 冬天的仪式换拍了 / the rite moved to its next beat
signal rite_changed(rite: int)
## 王座开了，可以往里拖蜂了 / the throne is open for an heir
signal throne_opened(cell: HexCell)
## 谁上位了、以及她是不是那个伪装的。第二个参数**只给系统内部用**，
## 任何面向玩家的东西都不准读它 / the flag is for systems only, never for the UI
signal heir_crowned(wasp: Wasp, was_false_queen: bool)
## 主导血统换了，之后羽化的蜂都穿这身 / newborns wear this from now on
signal dominant_changed(variant: WaspVariant)

# 顺序要和 SeasonBar.SEASONS 以及场景里那四个 Label 一致 / must match the bar
enum Season { SPRING, SUMMER, AUTUMN, WINTER }

# 冬天内部的四拍 / the four beats inside winter
enum Rite {
	NONE,       ## 不是冬天 / not winter
	THRONE,     ## 王座开着，等一个继承人 / waiting for an heir
	GATHER,     ## 新皇已立，蜂群正在围过来 / the swarm is closing in
	COUNTDOWN,  ## 到齐了，冬天在倒数 / winter is counting itself out
}

const GROUP: StringName = &"season_director"
const BAR_GROUP: StringName = &"season_bar"
const HIVE_GROUP: StringName = &"hive"
const WASP_GROUP: StringName = &"wasps"
const SOURCE_GROUP: StringName = &"item_source"
const SEASON_COUNT: int = 4

# 春 + 夏 + 秋 = 180 秒。一代的目标是三分半上下：三个生产季三分钟，
# 加上冬天的仪式（顺利的话二十几秒）。冬天不在这里配，它的长度由仪式跑出来
# Three minutes of growing seasons; winter's length comes from the rite, not from here.
@export_group("Duration")
## 春天最短：新皇那一窝刚下，玩家在补冬天拆掉的巢，还没进入正经生产
## Shortest - the player is patching winter's damage, not producing yet.
@export_range(10.0, 600.0, 5.0) var spring_duration: float = 45.0
## 夏天最长，这一代的产量基本都在这一段里 / the generation's output happens here
@export_range(10.0, 600.0, 5.0) var summer_duration: float = 75.0
@export_range(10.0, 600.0, 5.0) var autumn_duration: float = 60.0

@export_group("Start")
@export var start_season: Season = Season.SPRING
## 开局先安静一会儿再起表。玩家第一眼还在认界面，不该已经在赶时间
## The player is still reading the screen; they should not already be on the clock.
@export_range(0.0, 120.0, 1.0) var start_delay: float = 0.0
## 开局的主导血统。羽化出来的蜂都穿这身，直到第一次继位
## The founding lineage; every newborn wears it until the first coronation.
@export var dominant_variant: WaspVariant

@export_group("Winter damage")
## 冬天开场拆掉多少。占**已建成**巢室的比例——空格掉一级建造进度，
## 有卵/幼虫的格子直接腐烂，而腐烂的格子产不了卵：拆得越狠，新皇能下的蛋越少
## Share of built cells hit. Occupied ones rot, and a rotten cell cannot be laid in -
## the harder winter bites, the smaller the next brood. No extra code needed for that.
@export_range(0.0, 1.0, 0.05) var damage_share: float = 0.35
## 空格子一次掉几级建造进度 / build levels knocked off an empty cell
@export_range(1, 5, 1) var damage_depth: int = 1

@export_group("Rite")
## 玩家自己挑继承人的窗口。到点蜂群就自己推举一只——**这条分支必须够短**，
## 短到玩家真的会撞上它，否则"你以为你在控制黄蜂"就只是一句写在文档里的话
## Short on purpose: the player must actually run into the colony choosing for them.
@export_range(5.0, 120.0, 1.0) var throne_timeout: float = 15.0
## 被推举的那只飞向王座的时限。她路上是可以被你一把拽走的
## She can be yanked out of the air the whole way there.
@export_range(3.0, 60.0, 1.0) var heir_flight_timeout: float = 10.0
## 集结的硬上限 / hard cap on the gathering
@export_range(3.0, 60.0, 1.0) var gather_timeout: float = 15.0
## 到齐之后的最后一拍 / the closing beat once they are in place
@export_range(1.0, 30.0, 0.5) var coronation_countdown: float = 5.0
## 到场率过了这条线就开始倒数，不必等最后一只
## Never waits for the last straggler.
@export_range(0.1, 1.0, 0.05) var attendance_share: float = 0.7

@export_group("Coronation")
## 新皇随即下的卵数上限，实际数量看巢里还有几个空格
## Capped here, actually decided by how much room the hive has left.
@export_range(1, 6, 1) var max_brood: int = 3
## 每多少个可用空格多下一颗 / empty cells per extra egg
@export_range(1, 12, 1) var cells_per_egg: int = 4

@export_group("False heir")
## 伪王后登基那一代，新生蜂带的背叛底噪。玩家看不到数值，只会觉得
## "这一代特别不听话"——罢工的多、下一个麻烦来得快、整体慢吞吞
## The player never sees the number, only a generation that will not behave.
@export var false_heir_betrayal: Vector2 = Vector2(0.15, 0.25)
## 那一代伪王后来得多快 / how much sooner the next impostor wakes that generation
@export_range(0.1, 1.0, 0.05) var false_heir_awaken_scale: float = 0.5

@export_group("Attendance ring")
@export_range(20.0, 200.0, 5.0) var first_ring_radius: float = 72.0
@export_range(15.0, 120.0, 5.0) var ring_spacing: float = 44.0
## 同一圈上两只蜂的间距，决定一圈站得下几只。**必须大于黄蜂直径（39）**，
## 否则排出来的位置物理上挤不下，蜂会互相顶开，到场率永远上不去
## Must exceed the wasp diameter or the slots are physically impossible to occupy.
@export_range(15.0, 120.0, 5.0) var attendant_spacing: float = 48.0
## 离自己的位置多近算到位 / how close counts as in place
@export_range(10.0, 120.0, 5.0) var attend_tolerance: float = 40.0

var season: int = Season.SUMMER
var generation: int = 1
var rite: int = Rite.NONE
## 当代主导血统 / the reigning lineage
var dominant: WaspVariant = null
## 上一次继位是不是选错了。每个冬天必定重写一次，所以它天然一代一清
## Rewritten at every coronation, so it clears itself each generation.
var heir_was_false_queen: bool = false

var _time_left: float = 0.0
var _duration: float = 1.0
var _delay: float = 0.0
var _bar: SeasonBar = null
var _hive: Hive = null
var _throne: HexCell = null
var _crowned: bool = false
## 蜂群推举的那只，正在飞向王座的路上。不加类型：她随时可能被处决
## Untyped on purpose - she can be stung mid-flight.
var _heir = null
## 被召集的蜂 -> 它该站的位置 / summoned wasp to its slot
var _slots: Dictionary = {}


static func find(tree: SceneTree) -> SeasonDirector:
	return tree.get_first_node_in_group(GROUP) as SeasonDirector


func _ready() -> void:
	_bar = get_tree().get_first_node_in_group(BAR_GROUP) as SeasonBar
	if _bar == null:
		push_warning("SeasonDirector found no season bar, the countdown is invisible")
	_hive = get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	if _hive == null:
		push_warning("SeasonDirector found no hive, succession is disabled")

	dominant = dominant_variant
	_delay = start_delay
	_enter(start_season)


func season_name() -> String:
	return Season.keys()[season]


func rite_name() -> String:
	return Rite.keys()[rite]


func duration_of(which: int) -> float:
	match which:
		Season.SPRING:
			return spring_duration
		Season.SUMMER:
			return summer_duration
		Season.AUTUMN:
			return autumn_duration
		Season.WINTER:
			# 冬天的长度是仪式跑出来的，这里给的是最坏情况，只给表现层参考
			# Winter's real length comes from the rite; this is the worst case, for the bar.
			return throne_timeout + heir_flight_timeout + gather_timeout + coronation_countdown
	return 60.0


func time_left() -> float:
	return _time_left


## 0 = 刚进这一拍，1 = 走完 / 0 entering the beat, 1 at its end
func progress() -> float:
	if _duration <= 0.0:
		return 0.0
	return clampf(1.0 - _time_left / _duration, 0.0, 1.0)


func is_winter() -> bool:
	return season == Season.WINTER


func throne_cell() -> HexCell:
	return _throne


# ---------------- 新生蜂 / newborns ----------------

# 羽化和叛军孵化都走这里（HexCell._spawn_wasp 一处调用）。
# 穿什么颜色、带多少基因加成、要不要带背叛底噪，策略全在这一个函数里，
# 格子那边什么都不用知道 / the cell knows none of this policy, and should not
func dress_newborn(wasp: Wasp) -> void:
	if wasp == null:
		return

	if dominant != null:
		wasp.variant().apply(dominant)

	var bank: GeneBank = GeneBank.find(get_tree())
	if bank != null:
		wasp.perk_bonus = bank.perk_bonus()

	# 选错了的那一代生下来就带着气。它不改任何规则，只改数值——
	# 玩家拿不出证据，只有"这一代不知道怎么回事"的体感
	# Changes numbers, never rules: there is nothing for the player to point at.
	if heir_was_false_queen:
		wasp.allegiance().betrayal = randf_range(false_heir_betrayal.x, false_heir_betrayal.y)


# ---------------- 继位 / succession ----------------

# 王座收不收这个落点 / does the throne take a drop here
func throne_accepts(global_point: Vector2) -> bool:
	if rite != Rite.THRONE or _crowned or _throne == null or _hive == null:
		return false
	return _hive.cell_at_global(global_point) == _throne


# 玩家拖进去，或者被推举的那只飞到了 / by the player's hand or by the colony's own pick
func crown(wasp: Wasp) -> bool:
	if rite != Rite.THRONE or _crowned or wasp == null:
		return false
	if not wasp.allegiance().works():
		return false

	_crowned = true
	_heir = null

	var was_queen: bool = wasp.allegiance().is_false_queen()
	heir_was_false_queen = was_queen

	var next: WaspVariant = wasp.variant().variant
	if next != null and next != dominant:
		dominant = next
		dominant_changed.emit(dominant)

	var betrayal: BetrayalDirector = BetrayalDirector.find(get_tree())
	if betrayal != null:
		if was_queen:
			betrayal.crown_false_queen(wasp)
		betrayal.awaken_scale = false_heir_awaken_scale if was_queen else 1.0

	if _throne != null:
		_throne.set_royal(false)
		_throne.celebrate()

	_lay_brood()

	var bank: GeneBank = GeneBank.find(get_tree())
	if bank != null:
		bank.award()

	# 继位就恢复生产，但整个冬天都不来 raid。两个开关各自只有一个意思：
	# 冬天 = 不挨打，继位 = 重新开工
	# Two switches, one meaning each: winter means no raid, a coronation means work resumes.
	_set_sources(true)

	heir_crowned.emit(wasp, was_queen)
	_summon()
	_set_rite(Rite.GATHER, gather_timeout)
	return true


# 新皇随即下的一窝。走的是普通卵那条链（要喂、要封盖），
# 所以这一窝是春天的活儿，不是白送的蜂
# Ordinary eggs on the ordinary chain: this brood is spring's work, not a free gift.
func _lay_brood() -> void:
	if _hive == null or _throne == null:
		return

	var open: Array = []
	for cell in _hive.all_cells():
		if cell != _throne and cell.can_lay_egg():
			open.append(cell)
	if open.is_empty():
		return

	var throne_at: Vector2 = _throne.global_position
	open.sort_custom(func(a, b):
		return a.global_position.distance_to(throne_at) < b.global_position.distance_to(throne_at))

	var count: int = clampi(1 + open.size() / cells_per_egg, 1, max_brood)
	for i in mini(count, open.size()):
		open[i].lay_egg()


# 没人拖就自己推举。被你虐待过的那几只更可能被推上去——蜂群推的是最有怨气的那只
# The colony pushes forward whoever it has most reason to; that is rarely who you'd pick.
func _send_heir() -> void:
	if _throne == null:
		# 没有王座（没有蜂巢）就没有继位，但仪式还是得往下走完
		# No throne means no coronation - the rite still has to reach spring.
		_crowned = true
		_summon()
		_set_rite(Rite.GATHER, gather_timeout)
		return

	var candidates: Array = []
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Wasp = node as Wasp
		if wasp != null and wasp.allegiance().works():
			candidates.append(wasp)
	if candidates.is_empty():
		# 一只能用的蜂都没有，这一代就没有继位 / nobody left to crown
		_crowned = true
		_summon()
		_set_rite(Rite.GATHER, gather_timeout)
		return

	_heir = _weighted_pick(candidates)
	# 让她自己飞过去。**继位判定在抵达那一刻，不在选中那一刻**——
	# 这几秒里玩家完全可以一把把她拽走，或者抢先塞另一只进去
	# Crowned on arrival, never on selection: those seconds are the player's to fight for.
	_heir.attend(_throne.global_position)
	_set_rite(Rite.THRONE, heir_flight_timeout)


func _weighted_pick(candidates: Array) -> Wasp:
	var total: float = 0.0
	for wasp in candidates:
		total += 1.0 + wasp.allegiance().betrayal * 4.0

	var roll: float = randf() * total
	for wasp in candidates:
		roll -= 1.0 + wasp.allegiance().betrayal * 4.0
		if roll <= 0.0:
			return wasp
	return candidates[candidates.size() - 1]


# ---------------- 集结 / the gathering ----------------

# 罢工的和叛军不来。加冕典礼上缺席的是谁，本身就是一条线索——
# 而且它指向的是**被你得罪的忠诚工蜂**，伪王后反而会准时出席，那是她的伪装
# Who fails to show is a tell that points away from the impostor, never at her.
func _summon() -> void:
	_slots.clear()
	if _throne == null:
		return

	var attending: Array = []
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Wasp = node as Wasp
		if wasp != null and wasp.allegiance().works():
			attending.append(wasp)

	var throne_at: Vector2 = _throne.global_position
	attending.sort_custom(func(a, b):
		return a.global_position.distance_to(throne_at) < b.global_position.distance_to(throne_at))

	for i in attending.size():
		var slot: Vector2 = _slot_position(i)
		_slots[attending[i]] = slot
		attending[i].attend(slot)


# 一圈一圈往外排，内圈先满 / concentric rings, inner ones fill first
func _slot_position(index: int) -> Vector2:
	var placed: int = 0
	for ring in 8:
		var radius: float = first_ring_radius + float(ring) * ring_spacing
		var capacity: int = maxi(int(floor(TAU * radius / attendant_spacing)), 1)
		if index < placed + capacity:
			var i: int = index - placed
			# 每圈错开一点，免得排成一条直线 / stagger each ring so they don't line up
			var angle: float = TAU * float(i) / float(capacity) + float(ring) * 0.4
			return _throne.global_position + Vector2(cos(angle), sin(angle)) * radius
		placed += capacity
	return _throne.global_position


# 到场率。公开的：仪式卡不卡住全看这个数，调试读数和以后的 UI 都要用
# Public because a stalled gathering is the failure mode worth watching.
func attendance() -> float:
	if _slots.is_empty():
		return 1.0
	var here: int = 0
	var total: int = 0
	for wasp in _slots:
		if not is_instance_valid(wasp):
			continue
		total += 1
		if wasp.global_position.distance_to(_slots[wasp]) <= attend_tolerance:
			here += 1
	if total <= 0:
		return 1.0
	return float(here) / float(total)


func _dismiss() -> void:
	for wasp in _slots:
		if is_instance_valid(wasp):
			wasp.stop_attending()
	_slots.clear()
	if is_instance_valid(_heir):
		_heir.stop_attending()
	_heir = null


# ---------------- 冬天的开场 / winter opens ----------------

# 一次性结算，不是全程慢慢掉。玩家先看到损失、再挑继承人——
# 巢被拆得稀烂就该选建造专长的那一支，两个系统在这里咬合
# Settled in one hit so the damage informs the choice that follows it.
func _ravage() -> void:
	if _hive == null:
		return

	var built: Array = []
	for cell in _hive.all_cells():
		if cell.is_built and cell != _throne:
			built.append(cell)
	if built.is_empty():
		return

	built.shuffle()
	var hits: int = int(round(float(built.size()) * damage_share))
	for i in mini(hits, built.size()):
		var cell: HexCell = built[i]
		# 有卵/幼虫的直接烂掉，空的掉建造进度。腐烂的格子产不了卵，
		# 所以这一下同时削掉了新皇的产房 / rot also costs the new queen her nursery
		if not cell.destroy_occupant():
			cell.damage_build(damage_depth)


func _open_throne() -> void:
	_crowned = false
	_heir = null
	_throne = null
	if _hive == null:
		return

	# 王座固定在中心格。位置每代都一样，玩家认得出它在哪；被占就腾出来——
	# 冬天本来就在毁东西，多这一格不改变什么
	# Always the centre cell: a throne that moves is a throne nobody recognises.
	var centre: HexCell = _hive.get_cell(Vector2i.ZERO)
	if centre == null:
		return

	centre.clear_content()
	if not centre.is_built:
		centre.add_build_progress(centre.build_cost - centre.progress)

	_throne = centre
	_throne.set_royal(true)
	throne_opened.emit(_throne)


# ---------------- 季节轮 / the wheel ----------------

# 到点和调试跳过共用 / shared by the timer and by the debug skip
func advance() -> void:
	var next: int = (season + 1) % SEASON_COUNT
	# 冬天转回春天 = 新皇的第一个季节，代数在这里 +1。
	# 继位发生在冬天，所以"新的一代"从她治下的春天算起，不从冬天算起
	# The wheel wraps out of winter into the new queen's first spring - that is the new
	# generation, counted from her reign rather than from the coronation itself.
	if next == Season.SPRING:
		generation += 1
		generation_advanced.emit(generation)
	_enter(next)


func _enter(which: int) -> void:
	if season == Season.WINTER and which != Season.WINTER:
		_close_winter()

	season = which
	_duration = maxf(duration_of(which), 0.1)
	_time_left = _duration
	if _bar != null:
		_bar.current_season = season
	if which == Season.WINTER:
		_open_winter()
	_push()
	season_changed.emit(season, generation)


func _open_winter() -> void:
	_set_raid_paused(true)
	_set_sources(false)
	_open_throne()
	_ravage()
	_set_rite(Rite.THRONE, throne_timeout)


func _close_winter() -> void:
	_dismiss()
	if _throne != null:
		_throne.set_royal(false)
	_throne = null
	_set_raid_paused(false)
	_set_sources(true)
	_set_rite(Rite.NONE, 0.0)


func _set_rite(next: int, seconds: float) -> void:
	rite = next
	_duration = maxf(seconds, 0.1)
	_time_left = seconds
	rite_changed.emit(rite)


func _tick_rite(_delta: float) -> void:
	match rite:
		Rite.THRONE:
			# 被推举的那只到位了就登基 / the colony's pick takes it on arrival
			if is_instance_valid(_heir) and _throne != null:
				if _heir.global_position.distance_to(_throne.global_position) <= attend_tolerance:
					crown(_heir)
					return
			if _time_left > 0.0:
				return
			if _heir == null and not _crowned:
				_send_heir()
				return
			# 她飞不过去（被拽走、被扎死、卡住了），换一只重挑
			# She never made it - pick again rather than hang the rite here.
			_heir = null
			_send_heir()

		Rite.GATHER:
			if attendance() >= attendance_share or _time_left <= 0.0:
				_set_rite(Rite.COUNTDOWN, coronation_countdown)

		Rite.COUNTDOWN:
			if _time_left <= 0.0:
				advance()


func _process(delta: float) -> void:
	if _delay > 0.0:
		_delay = maxf(_delay - delta, 0.0)
		return

	_time_left = maxf(_time_left - delta, 0.0)

	# 冬天的推进权在仪式手上，季节计时器只负责显示这一拍还剩多久
	# In winter the rite drives; the clock only shows how long this beat has left.
	if season == Season.WINTER:
		_tick_rite(delta)
		_push()
		return

	_push()
	if _time_left <= 0.0:
		advance()


func _push() -> void:
	var ratio: float = progress()
	if _bar != null:
		_bar.set_time_left(_time_left)
		_bar.set_progress(ratio)
	season_tick.emit(season, _time_left, ratio)


func _set_raid_paused(paused: bool) -> void:
	var raid: RaidDirector = RaidDirector.find(get_tree())
	if raid != null:
		raid.paused = paused


func _set_sources(producing: bool) -> void:
	for node in get_tree().get_nodes_in_group(SOURCE_GROUP):
		var source: ItemSource = node as ItemSource
		if source != null:
			source.producing = producing
