class_name BetrayalDirector
extends Node2D

# 叛乱调度 / betrayal director. 挂在 world.tscn 的 Queen_controller 下。
#
# 掌两件事：蜂群的不安值 unrest，以及什么时候从工蜂里叫醒一只伪王后。
# 不安值永远不直接告诉玩家，只通过氛围漏出去——想知道蜂群怎么想的，只能看它们怎么行动。
# The unrest value is never shown; you read the colony by watching it, not by reading a bar.
#
# 叛军屈服不归它管 —— AllegianceComponent 发现母亲没了会自己屈服。

signal false_queen_awakened(wasp: Wasp)
signal false_queen_gone(wasp: Wasp)
## 玩家把她摔回普通工蜂了。她没死，只是不再下卵 / unmasked by a throw, not killed
signal false_queen_unmasked(wasp: Wasp)
## 给氛围表现用：画面色调、以后的嗡嗡声 / for the tint, and for audio later
signal unrest_changed(unrest: float)
## 玩家扎死了一只。参数**只给氛围层用**——见 Announcer 里为什么杀对了也可能有话说
## The flag is for atmosphere only; see Announcer for why a correct kill can still speak.
signal execution_reported(was_false_queen: bool)

const GROUP: StringName = &"betrayal_director"
const HIVE_GROUP: StringName = &"hive"
const WASP_GROUP: StringName = &"wasps"

@export_group("Awakening")
## 安定时要羽化多少只才出一只 / emergences needed at zero unrest
@export_range(1, 40, 1) var awaken_after: int = 6
## 不安拉满时只要这么多只。你越粗暴，下一个麻烦来得越快
## At full unrest only this many are needed - the rougher you are, the sooner it comes.
@export_range(1, 40, 1) var awaken_after_unrest: int = 2
## 潜伏期：觉醒后先老老实实干这么久才下第一颗卵。
## 不给缓冲的话她一觉醒就产，玩家还没意识到蜂群里混进了东西。
## Without it she lays the moment she wakes, before the player can notice anything is off.
@export_range(0.0, 300.0, 5.0) var dormant_duration: float = 12.0
## 几代之后伪王后练到满级。第一代 cunning=0（好找），之后一路退化到难以分辨
## Generations to full cunning: the first is meant to be findable, later ones are not.
@export_range(1, 10, 1) var cunning_ramp: int = 3

@export_group("Toggles")
## 关掉群体不安。红色调、全体减速、以及"你越粗暴下一个来得越快"那条加速全部停摆。
## **伪王后和叛军不受影响**，她们改成按安定时的固定节奏出现（awaken_after 只)
## Kills the tint, the colony-wide slowdown and the unrest-driven pacing.
## False queens and rebels keep coming, just at the calm-colony rate.
@export var unrest_enabled: bool = true
## 关掉罢工。个人 betrayal 照记（伪王后人选仍然偏向被你虐待过的那几只），
## 只是不再拿它停工 / grudges are still tallied, they just no longer stop anyone working
@export var strikes_enabled: bool = true

@export_group("Unrest")
## 处决一只忠诚工蜂 / executing a loyal worker
@export var execute_loyal: float = 0.20
## 处决对了人 / getting it right
@export var execute_queen: float = -0.35
## 目击同伴被处决的那几只，个人值涨这么多 / what witnesses take personally
@export var witness_penalty: float = 0.15
@export_range(0.0, 600.0, 10.0) var witness_radius: float = 220.0
## 被摔得够重 / slammed hard enough to matter
@export var slam_penalty: float = 0.05
## 被猎手咬伤，只记在个人头上不推群体不安——外敌造成的伤跟"你干的"不是一回事，
## 但"是你把我派去挡的"这笔账它还是要算
## Personal only, no colony unrest: an outsider drew the blood, but you chose the post.
@export var wound_penalty: float = 0.04
@export var larva_starved: float = 0.06
@export var larva_murdered: float = 0.04
@export var cell_fed: float = -0.03
@export var cell_finished: float = -0.02
## 每秒自然消退。设得很慢：手滑一次不至于进死亡螺旋，但也不能白犯
## Slow on purpose: one slip should not spiral, and it should not be free either.
@export var decay_per_second: float = 0.0015
## 每个腐烂格子每秒的贡献 / per rotten cell per second
@export var rot_per_second: float = 0.002

@export_group("Morale")
## 不安拉满时工蜂速度降到原来的几成 / worker speed at full unrest
@export_range(0.2, 1.0, 0.05) var morale_floor: float = 0.55
## 个人背叛值超过这个就罢工 / an individual past this stops working
@export_range(0.1, 2.0, 0.05) var strike_threshold: float = 0.5

@export_group("Brood")
## 每代叛军的颜色，依次取用 / brood colours, used in order
@export var brood_variants: Array[WaspVariant] = []

var unrest: float = 0.0
## 下一只伪王后来得多快的倍率。< 1 = 更快。由 SeasonDirector 在继位时写入：
## 扶错了人的那一代，麻烦一个接一个
## Written at each coronation - a generation that crowned wrong never stops producing them.
var awaken_scale: float = 1.0
## 调试用的注意力覆盖。headless 没鼠标，不留这个口子调虎离山根本没法测
## Debug override - there is no cursor headless, and the decoy logic is unreachable without it.
var debug_attention: Vector2 = Vector2.INF

var _queen: Wasp = null
var _emerged_since: int = 0
## 关掉就不再叫醒新的伪王后。教程期间由 TutorialDirector 关着
## Held shut during the tutorial; nothing else touches it.
var awakening_enabled: bool = true
var _generation: int = 0
var _hive: Hive = null


static func find(tree: SceneTree) -> BetrayalDirector:
	return tree.get_first_node_in_group(GROUP) as BetrayalDirector


func _ready() -> void:
	_hive = get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	if _hive == null:
		push_warning("BetrayalDirector found no hive, betrayal is disabled")
		set_process(false)
		return

	_hive.cell_wasp_emerged.connect(_on_wasp_emerged)
	_hive.cell_larva_starved.connect(func(_c): add_unrest(larva_starved))
	_hive.cell_occupant_destroyed.connect(func(_c): add_unrest(larva_murdered))
	_hive.cell_sealed.connect(func(_c): add_unrest(cell_fed))
	_hive.cell_built.connect(func(_c): add_unrest(cell_finished))


# 玩家的注意力在哪。光标就是答案——这游戏所有交互都走鼠标，
# 光标在哪，玩家就在看哪。以后想做得细致（最近几秒的加权停留中心）只改这里。
# The cursor is the only attention signal we have, and it is a good one.
func attention_point() -> Vector2:
	if debug_attention != Vector2.INF:
		return debug_attention
	return get_global_mouse_position()


func has_false_queen() -> bool:
	return is_instance_valid(_queen)


func add_unrest(amount: float) -> void:
	# 唯一入口，所以挡这一处就等于挡住 report_* 和 _process 里全部的加减
	# The only way in, so one gate covers every caller.
	if not unrest_enabled:
		return
	var before: float = unrest
	unrest = clampf(unrest + amount, 0.0, 1.0)
	if not is_equal_approx(unrest, before):
		unrest_changed.emit(unrest)


# ---------------- 上报 / reports from the wasps ----------------

# 右键扎死一只。杀对人安抚蜂群，杀错人把周围看到的那几只一起得罪了
# Getting it right calms the colony; getting it wrong is taken personally by every witness.
func report_execution(victim: Node2D, was_false_queen: bool) -> void:
	execution_reported.emit(was_false_queen)
	if was_false_queen:
		add_unrest(execute_queen)
		return

	add_unrest(execute_loyal)
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var witness: Wasp = node as Wasp
		if witness == null or witness == victim:
			continue
		if witness.global_position.distance_to(victim.global_position) <= witness_radius:
			witness.allegiance().betrayal += witness_penalty


func report_wound(wasp: Wasp) -> void:
	if not is_instance_valid(wasp):
		return
	wasp.allegiance().betrayal += wound_penalty


func report_slam(wasp: Wasp) -> void:
	if not is_instance_valid(wasp):
		return
	wasp.allegiance().betrayal += slam_penalty
	add_unrest(slam_penalty * 0.2)


# ---------------- 叫醒 / awakening ----------------

func awaken_now() -> Wasp:
	if has_false_queen():
		return _queen

	var candidates: Array = []
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Wasp = node as Wasp
		if wasp != null and wasp.allegiance().is_loyal():
			candidates.append(wasp)
	if candidates.is_empty():
		return null

	_queen = _weighted_pick(candidates)
	_queen.allegiance().brood_variant = _next_variant()
	_queen.allegiance().lay_cooldown = dormant_duration
	# cunning 必须在 make_false_queen 之前写好，否则拖拽手感会用旧值算
	# Must be set before the state change - the drag feel is derived from it on the signal.
	_queen.allegiance().cunning = clampf(float(_generation) / float(cunning_ramp), 0.0, 1.0)
	_queen.allegiance().make_false_queen()
	# 她不改颜色。改了就不叫伪装了 / no recolour: that is the whole point
	_queen.tree_exited.connect(_on_queen_gone.bind(_queen), CONNECT_ONE_SHOT)
	_emerged_since = 0
	_generation += 1
	false_queen_awakened.emit(_queen)
	return _queen


# 她被扶上了王座，这一局她赢了。她停止偷偷产卵、她的叛军失去了闹下去的理由，
# 巢里当场安静下来——玩家会以为自己选对了。代价要等下一代才浮出来（新蜂带背叛底噪 +
# awaken_scale 腰斩），而那时他已经拿不出证据了。
# The hive goes quiet and the player reads it as a win; the bill arrives next generation.
func crown_false_queen(wasp: Wasp) -> void:
	if wasp == null:
		return

	wasp.allegiance().enthrone()

	# 她的叛军目标达成，自己屈服。留着颜色和专长，于是巢里从此有一批
	# "异色但忠诚"的劳工——正是"颜色 ≠ 立场"最需要的那种混淆
	# They keep their colour and become the odd-coloured loyal workers the design wants.
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var rebel: Wasp = node as Wasp
		if rebel != null and rebel.allegiance().is_rebel() and rebel.allegiance().mother == wasp:
			rebel.allegiance().submit()

	if _queen == wasp:
		_queen = null
		_emerged_since = 0
		false_queen_gone.emit(wasp)


# 被你虐待过的那几只更可能变成下一个麻烦 / the ones you mistreated are likelier
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


func _on_wasp_emerged(_cell: HexCell, _wasp: Wasp) -> void:
	if has_false_queen():
		return
	# 教程期间连计数都不走：只挡叫醒的话，教程一结束她可能当场就醒，
	# 玩家刚学会喂幼虫就被丢进背叛机制里
	# Not even counted while held - gating only the awakening would fire her the
	# instant the tutorial ends.
	if not awakening_enabled:
		return
	_emerged_since += 1
	var needed: int = int(roundf(lerpf(float(awaken_after), float(awaken_after_unrest), unrest) * awaken_scale))
	if _emerged_since >= maxi(needed, 1):
		awaken_now()


# 摔墙那一下由 Wasp 上报。她还活着，所以不能等 tree_exited——位子当场就得空出来，
# 不然 has_false_queen() 一直为真，下一只永远醒不过来
# Reported by the wasp itself: she is still alive, so nothing else would free the seat
# and has_false_queen() would block every future awakening.
func report_unmasked(wasp: Wasp) -> void:
	if _queen != wasp:
		return
	_queen = null
	_emerged_since = 0
	false_queen_unmasked.emit(wasp)


func _on_queen_gone(wasp: Wasp) -> void:
	# 登基那一下已经把她从位子上摘了，之后她真的死掉时这里还会再响一次
	# crown_false_queen already cleared the seat; her eventual death fires this again.
	if _queen != wasp:
		return
	_queen = null
	_emerged_since = 0
	false_queen_gone.emit(wasp)


# 叛军永远挑**非主导色**。玩家迟早会总结出"少数色 = 叛军"这条规则，
# 而这条规则注定会反咬他：上一代的忠诚遗老也是少数色，而伪王后本人
# 从来都藏在主导色里（awaken_now 只从 LOYAL 里挑，她还不改色）。
# 玩家自己总结出来的规则在某一代失效，比任何设计师塞进去的诡计都狠。
# The player will infer "minority colour means rebel" - and that rule is built to betray
# them, because last generation's loyal veterans are a minority colour too.
func _next_variant() -> WaspVariant:
	if brood_variants.is_empty():
		return null

	var season: SeasonDirector = SeasonDirector.find(get_tree())
	var dominant: WaspVariant = season.dominant if season != null else null
	var pool: Array = brood_variants.filter(func(v): return v != dominant)
	if pool.is_empty():
		pool = brood_variants
	return pool[_generation % pool.size()]


# ---------------- 士气 / morale ----------------

func _process(delta: float) -> void:
	# 关掉不安时连巢室都不用扫 / nothing to accumulate, so skip the cell sweep too
	if unrest_enabled:
		var rotten: int = 0
		for cell in _hive.all_cells():
			if cell.is_rotten():
				rotten += 1
		add_unrest((rot_per_second * float(rotten) - decay_per_second) * delta)

	# 不安的蜂群干活慢，单独恨上你的那几只直接罢工
	# An uneasy colony works slower; the individually aggrieved stop working at all.
	# 两个值都是**每帧覆盖写**的，所以开关运行时翻转也立刻生效
	# Both are overwritten every frame, so flipping either switch takes effect at once.
	var morale: float = lerpf(1.0, morale_floor, unrest) if unrest_enabled else 1.0
	# 罢工关掉就把门槛推到够不着的地方，betrayal 照涨但永远越不过
	# An unreachable threshold: the grudge still accrues, it just never trips.
	var threshold: float = strike_threshold if strikes_enabled else INF
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Wasp = node as Wasp
		if wasp != null:
			wasp.morale_scale = morale
			wasp.allegiance().strike_threshold = threshold
