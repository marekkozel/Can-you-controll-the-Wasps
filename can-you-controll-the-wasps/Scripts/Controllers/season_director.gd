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
const REPORT_GROUP: StringName = &"year_report"
const CARRIABLE_GROUP: StringName = &"carriable"
## 两张蜂图规格一致（512x384，8x6），所以换 texture 不影响任何一条 clip 的帧号
## Identical layout, so swapping the sheet leaves every clip's frame index valid.
const GOOD_SHEET: Texture2D = preload("res://Assets/Entities/good_wasp.png")
const EVIL_SHEET: Texture2D = preload("res://Assets/Entities/evil_wasp.png")
const SEASON_COUNT: int = 4

# 冬天在季节条上那一格里，三拍各自占多少。冬天的长度是仪式跑出来的，
# 预估不了，所以进度按"走到第几拍"算——条永远在走，走到头正好进春天
# Winter has no predictable length, so its slice is measured in beats, not seconds.
const RITE_SPAN: Dictionary = {
	Rite.THRONE: Vector2(0.0, 0.45),
	Rite.GATHER: Vector2(0.45, 0.8),
	Rite.COUNTDOWN: Vector2(0.8, 1.0),
}

# 春 + 夏 + 秋 = 360 秒。一代的目标是六分半上下：三个生产季六分钟，
# 加上冬天的仪式（顺利的话二十几秒）。冬天不在这里配，它的长度由仪式跑出来
# Six minutes of growing seasons; winter's length comes from the rite, not from here.
# 配比没动，还是 1 : 1.67 : 1.33——夏天最长，那一段才是产量所在
# The ratio is unchanged; summer stays the longest because that is where output happens.
@export_group("Duration")
## 春天最短：新皇那一窝刚下，玩家在补冬天拆掉的巢，还没进入正经生产
## Shortest - the player is patching winter's damage, not producing yet.
@export_range(10.0, 600.0, 5.0) var spring_duration: float = 90.0
## 夏天最长，这一代的产量基本都在这一段里 / the generation's output happens here
@export_range(10.0, 600.0, 5.0) var summer_duration: float = 150.0
@export_range(10.0, 600.0, 5.0) var autumn_duration: float = 120.0

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
@export_range(0.0, 1.0, 0.05) var damage_share: float = 0.80
## 冬天过后最多还剩几格**有建造进度**的巢室，含王座——半成品也算一格，
## 否则「留一堆 2/3」就绕过了这个上限。比例是给小巢兜底的下限，
## 这个数是上限——巢建得越大，冬天拆得越狠，开春看到的永远是差不多一片空地
## The cap, where the share is the floor: however big the comb got, spring opens on
## roughly the same clearing.
@export_range(1, 30, 1) var cells_left: int = 4
## 被选中的格子掉几级建造进度。**要大于等于 build_cost（3）才是"毁掉"**——
## 给 1 的话一格只从"建成"退到"差一块"，补一块纸板就回来了，玩家看不出巢被拆过
## Must clear build_cost or winter merely dents the comb: at 1 a cell goes back one
## step and a single piece of cardboard undoes it.
@export_range(1, 10, 1) var damage_depth: int = 3

@export_group("Winter cull")
## 冬天带走整个蜂群。**只有加冕的那一只活到春天**——她就是你这一年攒下的全部东西。
## 这个数是给她之外额外留几只的余量，默认 0（想调平衡就动它，不用改代码）
## Winter takes the whole colony; only the crowned wasp sees spring. This is the spare
## allowance on top of her - the balance knob, left at zero by design.
@export_range(0, 20, 1) var winter_survivors: int = 0
## 冬天也把地上散着的货一起收走：纸板、食物、蜂王浆、战利品。
## 关掉的话上一年没搬完的东西会攒到下一代，几年下来满地都是
## Off means last year's leftovers pile up across generations.
@export var clear_ground: bool = true

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
## 加冕那一下的卡顿时长（真实秒，不吃 time_scale）。整局最重要的一次点击，
## 值得让画面停半拍 / the one decision of the year deserves a beat of silence
@export_range(0.0, 0.5, 0.01) var crown_hit_stop: float = 0.12
@export_range(0.01, 1.0, 0.01) var crown_hit_stop_scale: float = 0.15

@export_group("False heir")
## 伪王后登基那一代，新生蜂带的背叛底噪。玩家看不到数值，只会觉得
## "这一代特别不听话"——罢工的多、下一个麻烦来得快、整体慢吞吞
## The player never sees the number, only a generation that will not behave.
@export var false_heir_betrayal: Vector2 = Vector2(0.15, 0.25)
## 那一代伪王后来得多快 / how much sooner the next impostor wakes that generation
@export_range(0.1, 1.0, 0.05) var false_heir_awaken_scale: float = 0.5

# 这四个数跟两件事绑死：**王座格子的尺寸**和**黄蜂的碰撞直径**。
# 任一个改了都要回来重算，否则要么圈压在巢室上，要么位置物理上挤不下蜂。
# 当前：王座格 66x60（半宽 33），黄蜂碰撞直径 22
# Tied to the throne cell's size and the wasp's collision diameter - retune on either.
@export_group("Attendance ring")
## 第一圈半径。要落在王座格外沿：33（格半宽）+ 11（蜂半径）+ 余量
## Just outside the throne cell, or the front row stands on top of the new queen.
@export_range(20.0, 300.0, 1.0) var first_ring_radius: float = 55.0
@export_range(15.0, 120.0, 1.0) var ring_spacing: float = 30.0
## 同一圈上两只蜂的间距，决定一圈站得下几只。**必须大于黄蜂直径（22）**，
## 否则排出来的位置物理上挤不下，蜂会互相顶开，到场率永远上不去
## Must exceed the wasp diameter or the slots are physically impossible to occupy.
@export_range(15.0, 120.0, 1.0) var attendant_spacing: float = 28.0
## 离自己的位置多近算到位。取间距的六成左右：太松会把邻座算成到位，
## 太紧则永远够不到阈值，集结每次都只能等超时
## Roughly 0.6 of the spacing - looser counts a neighbour's slot, tighter never converges.
@export_range(5.0, 120.0, 1.0) var attend_tolerance: float = 17.0

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
## 冻住季节钟。**冻的是时间，不是模拟**——蜂照常干活、幼虫照常长，只是这一年不会走。
## 教程期间由 TutorialDirector 打开，它自己负责放开
## Freezes the clock, not the colony: everything still runs, the year just does not turn.
var held: bool = false
var _bar: SeasonBar = null
var _hive: Hive = null
var _throne: HexCell = null
var _crowned: bool = false
## 蜂群推举的那只，正在飞向王座的路上。不加类型：她随时可能被处决
## Untyped on purpose - she can be stung mid-flight.
var _heir = null
## 被召集的蜂 -> 它该站的位置 / summoned wasp to its slot
var _slots: Dictionary = {}
## 冬天进度的单调锁。_send_heir() 重挑继承人会把王座那一拍的计时重置，
## 不锁住的话进度条会当着玩家的面倒退
## The rite can restart a beat; a bar that runs backwards reads as a bug.
var _winter_high: float = 0.0
## 加冕的那一只。清场时要放过她，结算面板上也要写她的名字
## Spared by the cull and named on the report.
var _queen_wasp: Wasp = null
## 这一年的账。每次进春天清零 / the year's tally, cleared each spring
var _ledger: Dictionary = {}
var _points_awarded: int = 0
## 结算面板已经接手了，别再自己往下走 / the report has the wheel, do not advance twice
var _awaiting_report: bool = false


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
	_clear_ledger()
	# 延后一帧：另外两个 director 不保证比这里先 _ready
	# Deferred - the other directors are not guaranteed to be ready before us.
	_bind_ledger.call_deferred()
	_enter(start_season)


# ---------------- 这一年的账 / the year's tally ----------------

# 只数数，不改任何玩法。数出来的东西只有一个去处：冬天那张结算面板
# Counting only - the numbers exist for the winter report and nowhere else.
func _bind_ledger() -> void:
	if _hive != null:
		_hive.cell_wasp_emerged.connect(func(_c, _w): _tally(&"born"))
		_hive.cell_larva_starved.connect(func(_c): _tally(&"starved"))
		_hive.cell_built.connect(func(_c): _tally(&"built"))

	# 加工厂出的每一份蜂王浆。`intake_payload` 空的就不是加工厂，产出点和敌人刷新带
	# 也在同一个组里 / an empty intake_payload means it is a plain post, not a refinery
	for node in get_tree().get_nodes_in_group(SOURCE_GROUP):
		var source: ItemSource = node as ItemSource
		if source != null and source.intake_payload != &"":
			source.refined.connect(func(_p): _tally(&"jelly"))

	var betrayal: BetrayalDirector = BetrayalDirector.find(get_tree())
	if betrayal != null:
		betrayal.false_queen_unmasked.connect(func(_w): _tally(&"caught"))
		betrayal.execution_reported.connect(func(_q): _tally(&"executed"))

	var raid: RaidDirector = RaidDirector.find(get_tree())
	if raid != null:
		raid.raid_ended.connect(func(cleared): _tally(&"repelled" if cleared else &"raided"))


func _tally(key: StringName, amount: int = 1) -> void:
	_ledger[key] = int(_ledger.get(key, 0)) + amount


func _clear_ledger() -> void:
	_ledger = {&"born": 0, &"starved": 0, &"built": 0, &"jelly": 0,
		&"caught": 0, &"executed": 0, &"repelled": 0, &"raided": 0}
	_points_awarded = 0


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


# 整年的进度，0 = 春天开始，1 = 冬天走完。季节条画的是这个。
# 四段在条上**等宽**，各占 1/4——玩家读的是"走到今年哪一段了"，
# 而不是秒数，所以等宽比按时长分配更好读，图标也能均匀排开
# Four equal quarters: the bar answers "where in the year", not "how many seconds".
func year_progress() -> float:
	var within: float = _winter_progress() if is_winter() else progress()
	return clampf((float(season) + within) * 0.25, 0.0, 1.0)


# 冬天：按走到第几拍算，拍内再按那一拍自己的计时插值
func _winter_progress() -> float:
	var span: Vector2 = RITE_SPAN.get(rite, Vector2(0.0, 0.0))
	var t: float = span.x + (span.y - span.x) * progress()
	_winter_high = maxf(_winter_high, t)
	return _winter_high


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

	wasp.refresh_skin()

	var bank: GeneBank = GeneBank.find(get_tree())
	if bank != null:
		wasp.perk_bonus = bank.perk_bonus()
		# THICK HIDE。max_health 和 health 都要写：组件 _ready 时已经按原上限满血了
		# Both fields: the component already topped itself up at the authored maximum.
		var bonus: int = bank.health_bonus()
		if bonus > 0:
			var health: HealthComponent = wasp.get_node_or_null(^"HealthComponent") as HealthComponent
			if health != null:
				health.max_health += bonus
				health.health += bonus

	# 选错了的那一代生下来就带着气。它不改任何规则，只改数值——
	# 玩家拿不出证据，只有"这一代不知道怎么回事"的体感
	# Changes numbers, never rules: there is nothing for the player to point at.
	if heir_was_false_queen:
		wasp.allegiance().betrayal = randf_range(false_heir_betrayal.x, false_heir_betrayal.y)


# 哪张图算「我们」。扶忠诚工蜂上位，你的蜂戴帽子、叛军红眼；扶伪王后上位，
# 整套关系对调——反抗你的人从此长着你去年熟悉的那张脸，而你的蜂全是红眼。
# 「邪恶」不是本质，是相对于王座的 / "evil" is a position, not a property.
func skin_for(is_rebel: bool) -> Texture2D:
	return EVIL_SHEET if is_rebel != heir_was_false_queen else GOOD_SHEET


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
	_queen_wasp = wasp   # 清场时唯一被放过的那只 / the one the cull spares

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

	# 王朝翻面。**加冕的那一只自己也翻**——你把她拖进王座，画面停半拍，
	# 她在那半拍里换了张脸。选择已经不可逆了才揭晓，代价还在后头
	# 得放在 crown_false_queen() 之后：她的叛军到那时才屈服，立场定了脸才对
	# The swap lands on the crowned wasp too, after the choice can no longer be taken back.
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var subject: Wasp = node as Wasp
		if subject != null:
			subject.refresh_skin()

	if _throne != null:
		_throne.hide_rite_time()
		_throne.set_royal(false)
		_throne.celebrate()
	wasp.hail()
	_crown_hit_stop()

	_lay_brood()

	# 拿账本不拿现场：_open_winter() 的 _ravage() 已经把巢拆到只剩 cells_left 格，
	# 这时候数 built_count() 每一代都是同一个数，建多建少发一样的点
	# From the ledger, not the hive - _ravage() flattened it before the throne even opened.
	var bank: GeneBank = GeneBank.find(get_tree())
	if bank != null:
		_points_awarded = bank.award(
			int(_ledger.get(&"built", 0)),
			int(_ledger.get(&"jelly", 0)))

	# 继位就恢复生产，但整个冬天都不来 raid。两个开关各自只有一个意思：
	# 冬天 = 不挨打，继位 = 重新开工
	# Two switches, one meaning each: winter means no raid, a coronation means work resumes.
	_set_sources(true)

	heir_crowned.emit(wasp, was_queen)
	_summon()
	_set_rite(Rite.GATHER, gather_timeout)
	return true


# 加冕那一下把画面停半拍。Enemy 的命中卡顿是同一套做法，计时器要用不吃
# time_scale 的那种，否则 time_scale 越小它自己也越慢，永远回不来
# Same trick the hit stop uses; the timer must ignore time_scale or it never fires back.
func _crown_hit_stop() -> void:
	if crown_hit_stop <= 0.0:
		return
	var previous: float = Engine.time_scale
	Engine.time_scale = crown_hit_stop_scale
	await get_tree().create_timer(crown_hit_stop, true, false, true).timeout
	Engine.time_scale = previous


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

	# 只要有建造进度就算数，**不能只挑 is_built**。半成品被跳过的话，一格 2/3 的
	# 巢室原样过冬、开春补一块纸板就成，而老实建完的那格被推平要补三块——
	# 于是最优解变成入冬前故意别建完，玩家因为不完成建造而占便宜
	# Anything with progress counts. Skipping part-built cells rewards leaving the comb
	# unfinished: a 2/3 cell survives winter needing one piece, a finished one needs three.
	var standing: Array = []
	for cell in _hive.all_cells():
		if cell.progress > 0 and cell != _throne:
			standing.append(cell)
	if standing.is_empty():
		return

	standing.shuffle()
	# 两条规则取更狠的那一个：至少拆掉 damage_share 那么多，而且最多只准留下
	# cells_left 格（王座本来就不在候选里，所以这里减 1）
	# The harsher of the two: at least the share, and never more survivors than the cap.
	var hits: int = maxi(
		int(round(float(standing.size()) * damage_share)),
		standing.size() - maxi(cells_left - 1, 0))
	for i in mini(hits, standing.size()):
		var cell: HexCell = standing[i]
		# 先腾空再拆结构，顺序不能反：damage_build 拒绝有内容的格子，
		# 反过来写的话这一格里但凡有颗卵，整格结构就毫发无伤
		# Empty it first - damage_build refuses an occupied cell, so the other order
		# leaves every cell holding an egg completely untouched.
		#
		# 蛹和腐烂的格子也一起清掉。冬天带走整个蜂群，蛹不该是唯一的例外，
		# 而"选中的格子里有几个恰好是烂的"更不该变成一次白打的判定
		# Pupae and rot go too: winter takes the colony, and a rotten cell must not
		# quietly absorb one of the hits.
		cell.clear_content()
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


# ---------------- 结算 / the settlement ----------------

# 冬天的最后一拍。顺序是有讲究的：**先让蜂群把加冕仪式走完，再清场**——
# 你最后看到的是它们围着新皇站成一圈，然后冬天把它们全带走
# The procession first, the cull second: the last thing you see is the swarm around her.
func _settle() -> void:
	if _awaiting_report:
		return
	_cull()
	# 顺序不能反：蜂死的时候 _on_died 会把叼着的货丢在地上，先清就漏了那一批
	# After the cull - dying wasps drop their cargo, and that lot needs sweeping too.
	_clear_ground()

	var panel: Node = get_tree().get_first_node_in_group(REPORT_GROUP)
	# 没有面板（headless、或者面板被删了）就直接进春天。
	# **仪式绝不允许卡住**，一张缺席的 UI 不能变成一局卡死的游戏
	# A missing panel must never hang the rite - straight to spring instead.
	if panel == null or not panel.has_method("present"):
		advance()
		return

	_awaiting_report = true
	panel.present(year_report())


# 面板按完"继续"回调这里 / called back when the player dismisses the report
func resume_after_report() -> void:
	if not _awaiting_report:
		return
	_awaiting_report = false
	advance()


# 冬天带走整个蜂群，只留加冕的那一只。
# 没能加冕的那一年（一只可用的蜂都没有）至少留一只，否则春天开局是个空场
# Nobody crowned means we still spare one, or spring opens on an empty map.
func _cull() -> void:
	var doomed: Array = []
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Wasp = node as Wasp
		if wasp != null and wasp != _queen_wasp:
			doomed.append(wasp)

	var spared: int = winter_survivors if is_instance_valid(_queen_wasp) else maxi(winter_survivors, 1)
	doomed.shuffle()
	for i in range(spared, doomed.size()):
		var wasp: Wasp = doomed[i]
		if is_instance_valid(wasp):
			wasp.perish()


# 地上剩的货跟着蜂群一起过冬，也就是不过。产出点这会儿还停着产，
# 扫掉的库存要等 _close_winter() 放开才补——开春是干净的一片地，不是上一年的残局
# Sources are still shut down here, so the restock lands in spring: the new queen
# inherits a clearing, not last year's mess.
func _clear_ground() -> void:
	if not clear_ground:
		return
	for node in get_tree().get_nodes_in_group(CARRIABLE_GROUP):
		if is_instance_valid(node):
			node.queue_free()


# 摊开这一年的账。纯读数，面板怎么画是它自己的事
# Numbers only; how they are drawn is the panel's business.
func year_report() -> Dictionary:
	var bank: GeneBank = GeneBank.find(get_tree())
	var queen_name: String = ""
	if is_instance_valid(_queen_wasp):
		queen_name = _queen_wasp.wasp_name
	return {
		&"generation": generation,
		&"queen": queen_name,
		&"points": _points_awarded,
		&"points_total": bank.points if bank != null else 0,
		&"rows": [
			{&"label": "Wasps born", &"value": int(_ledger.get(&"born", 0))},
			{&"label": "Cells finished", &"value": int(_ledger.get(&"built", 0))},
			{&"label": "Royal jelly refined", &"value": int(_ledger.get(&"jelly", 0))},
			{&"label": "Larvae starved", &"value": int(_ledger.get(&"starved", 0))},
			{&"label": "Raids repelled", &"value": int(_ledger.get(&"repelled", 0))},
			{&"label": "Raids that took something", &"value": int(_ledger.get(&"raided", 0))},
			{&"label": "Impostors unmasked", &"value": int(_ledger.get(&"caught", 0))},
			{&"label": "Wasps you put down", &"value": int(_ledger.get(&"executed", 0))},
		],
	}


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
		_clear_ledger()
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
	_winter_high = 0.0
	_set_raid_paused(true)
	_set_sources(false)
	_open_throne()
	_ravage()
	_set_rite(Rite.THRONE, throne_timeout)


func _close_winter() -> void:
	_dismiss()
	if _throne != null:
		_throne.hide_rite_time()
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
			_feed_throne()
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
				_settle()


# 王座每帧要知道两件事：这一拍还剩多久，以及玩家手上有没有一只放得进去的蜂。
# 后者是这段反馈的关键——拿起蜂的那一刻王座就变色，"往哪放"不用文字解释
# The second one is the point: the throne answers "where do I put this" by itself.
func _feed_throne() -> void:
	if _throne == null:
		return
	_throne.set_royal_focus(_heir_in_hand())
	_throne.show_rite_time(clampf(_time_left / maxf(_duration, 0.01), 0.0, 1.0))


func _heir_in_hand() -> bool:
	var wasp: Wasp = DraggableComponent.held_body() as Wasp
	# 查的是 works()，不是 state——后者会把立场泄露给一个纯表现的判断
	# works(), never state: a cosmetic check must not leak allegiance.
	return wasp != null and wasp.allegiance().works()


func _process(delta: float) -> void:
	if held:
		return
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
		_bar.set_progress(year_progress())
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
