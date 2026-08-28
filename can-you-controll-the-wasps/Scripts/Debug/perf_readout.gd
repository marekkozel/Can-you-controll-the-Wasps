extends Label

# 性能读数 / perf readout. F11 开关，默认常驻。
# 帧率掉下去时先看 draw calls 和 physics：前者是巢室的 Polygon2D/Line2D 堆出来的，
# 后者是每只黄蜂/物件都是带 contact_monitor 的刚体。
# When FPS drops, read draw calls and physics first - those are the two things that scale
# with hive size and wasp count here.

## 刷新间隔。每帧拼字符串本身就是开销 / building the string every frame is itself a cost
@export_range(0.05, 2.0, 0.05) var refresh_interval: float = 0.25

const ENTITIES_GROUP: StringName = &"entities"
const WASP_GROUP: StringName = &"wasps"
const CARRIABLE_GROUP: StringName = &"carriable"
const ENEMY_GROUP: StringName = &"Enemy"

var _timer: float = 0.0


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	_refresh()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = refresh_interval
	_refresh()


func _refresh() -> void:
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var process_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var nav_ms: float = Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0

	var lines: PackedStringArray = PackedStringArray()
	lines.append("FPS %3d      frame %.1f ms" % [int(fps), 1000.0 / maxf(fps, 1.0)])
	lines.append("process %.2f   physics %.2f   nav %.2f" % [process_ms, physics_ms, nav_ms])
	lines.append("draw calls %d   nodes %d" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	lines.append("bodies %d   pairs %d   islands %d" % [
		int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)),
		int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)),
		int(Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT))])
	lines.append("wasps %d   items %d   enemies %d" % [_group_count(WASP_GROUP), _group_count(CARRIABLE_GROUP), _group_count(ENEMY_GROUP)])
	lines.append(_season_line())
	lines.append(_raid_line())
	lines.append(_allegiance_line())
	lines.append(_unrest_line())
	lines.append(_behaviour_line())
	lines.append(_overlap_line())
	lines.append("static mem %.1f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0))

	text = "
".join(lines)


# 冬天的仪式走到哪一拍了。仪式卡住是这套系统最贵的 bug，得能一眼看出来
# The rite stalling is the expensive failure mode, so it has to be visible.
func _season_line() -> String:
	var director: SeasonDirector = SeasonDirector.find(get_tree())
	if director == null:
		return "season --"
	var dominant: String = director.dominant.display_name if director.dominant != null else "-"
	var bank: GeneBank = GeneBank.find(get_tree())
	var genes: String = "gene +%d (%d pts)" % [bank.perk_bonus(), bank.points] if bank != null else "gene --"
	if not director.is_winter():
		return "gen %d  %s %.0fs  dom %s  %s" % [
			director.generation, director.season_name(), director.time_left(), dominant, genes]
	return "gen %d  WINTER/%s %.0fs  dom %s  %s" % [
		director.generation, director.rite_name(), director.time_left(), dominant, genes]


func _raid_line() -> String:
	var director: RaidDirector = RaidDirector.find(get_tree())
	if director == null:
		return "raid --"
	if director.is_raiding():
		return "RAID w%d  %d raiders  %.0fs left" % [director.wave, director.raiders_left(), director.time_left()]
	# 时间表按整年进度走，不是倒计时。这一行读的是"这一代还剩几波、下一波画在哪"
	# The schedule lives on the year axis, so report the mark, not a countdown.
	var pending: int = 0
	for mark in director.schedule():
		if mark[&"state"] == RaidDirector.MarkState.PENDING:
			pending += 1
	var next_at: float = director.next_mark_at()
	if next_at < 0.0:
		return "raid w%d clear  no more this year" % director.wave
	var season: SeasonDirector = SeasonDirector.find(get_tree())
	var now: float = season.year_progress() if season != null else 0.0
	return "raid w%d clear  next at %.3f (now %.3f, %d left)" % [director.wave, next_at, now, pending]


# 调试用。正式玩法里这一行就是答案，别留给玩家看
# Debug only: this line is the answer sheet.
func _allegiance_line() -> String:
	var tally: Array[int] = [0, 0, 0, 0]
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Wasp = node as Wasp
		if wasp != null:
			tally[wasp.allegiance().state] += 1
	return "loyal %d  queen %d  rebel %d  subdued %d" % [tally[0], tally[1], tally[2], tally[3]]


# 同样是答案纸：正式玩法里不安值只通过画面色调漏出去
# Answer sheet again - in play, unrest only leaks through the colour wash.
func _unrest_line() -> String:
	var director: BetrayalDirector = BetrayalDirector.find(get_tree())
	if director == null:
		return "unrest --"
	var strikers: int = 0
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Wasp = node as Wasp
		if wasp != null and wasp.allegiance().is_on_strike():
			strikers += 1
	var cunning: float = 0.0
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var w: Wasp = node as Wasp
		if w != null and w.allegiance().is_false_queen():
			cunning = w.allegiance().cunning
	return "unrest %.2f  morale x%.2f  striking %d  cunning %.2f" % [
		director.unrest, lerpf(1.0, director.morale_floor, director.unrest), strikers, cunning]


# 画像读数。调一个新蜂种就看这一行：它的区间有没有压在工蜂的区间里
# The line to read when tuning a new BehaviourProfile - are the ranges still overlapping.
#
# at-hive 是"牌桌上坐了几只"。闲蜂聚回巢才谈得上横向比较，这个数低的时候
# 玩家其实没有在观察，只是在看几只散兵 / the comparison only exists when they gather
func _behaviour_line() -> String:
	var sight_lo: float = INF
	var sight_hi: float = 0.0
	var sight_sum: float = 0.0
	var total: int = 0
	var at_hive: int = 0

	var hive: Node2D = get_tree().get_first_node_in_group(&"hive") as Node2D
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Wasp = node as Wasp
		if wasp == null:
			continue
		total += 1
		sight_lo = minf(sight_lo, wasp.sight_radius)
		sight_hi = maxf(sight_hi, wasp.sight_radius)
		sight_sum += wasp.sight_radius
		if hive != null and wasp.global_position.distance_to(hive.global_position) <= wasp.loiter_radius:
			at_hive += 1

	if total == 0:
		return "sight --  at-hive --  jobs --"

	var gathering: int = 0
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var w: Wasp = node as Wasp
		if w != null and w.job == Wasp.Job.GATHER:
			gathering += 1

	return "sight %d/%d/%d  at-hive %d/%d  jobs G%d H%d" % [
		int(sight_lo), int(sight_sum / float(total)), int(sight_hi),
		at_hive, total, gathering, total - gathering]


# **这一行就是验收标准。** 伪王后的每个值都必须落在方括号里——那是群体（不含她）的
# 实际范围。跑出去的那一条，就已经从线索变成了探测器：玩家抓一只就知道答案。
# 调一个新的 BehaviourProfile 时盯着这行看，比对着 .tres 猜可靠得多。
#
# The impostor's numbers must fall inside the brackets, which is the live range of
# everyone else. A value outside them is a detector, not a tell.
func _overlap_line() -> String:
	var queen: Wasp = null
	var others: Array[Wasp] = []
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Wasp = node as Wasp
		if wasp == null:
			continue
		if wasp.allegiance().is_false_queen():
			queen = wasp
		else:
			others.append(wasp)

	if queen == null:
		return "overlap  (no false queen awake)"
	if others.is_empty():
		return "overlap  (no one to compare against)"

	return "Q %s  %s  %s" % [
		_span("insp", queen.idle_weights[Wasp.IdleAct.INSPECT], others,
			func(w: Wasp): return w.idle_weights[Wasp.IdleAct.INSPECT]),
		_span("ante", queen.idle_weights[Wasp.IdleAct.ANTENNATE], others,
			func(w: Wasp): return w.idle_weights[Wasp.IdleAct.ANTENNATE]),
		_span("bias", queen.posting_bias, others, func(w: Wasp): return w.posting_bias),
	]


# 值落在范围里打 " "，跑出去打 "!" —— 一眼就能扫到出问题的那一条
# A bang marks the one that escaped; it is meant to be scannable at a glance.
func _span(name: String, value: float, others: Array[Wasp], getter: Callable) -> String:
	var lo: float = INF
	var hi: float = -INF
	for wasp in others:
		var v: float = getter.call(wasp)
		lo = minf(lo, v)
		hi = maxf(hi, v)
	# 二元的"在不在范围内"在边界上会误报，而真正要看的是她有多偏：
	# 落在群体的 0% 或 100% 那一端，意味着她总是全场之最——那本身就是模式
	# What matters is how extreme she sits, not a boolean: always being the outlier is
	# itself a pattern, even when the value is technically inside the range.
	var below: int = 0
	for wasp in others:
		if getter.call(wasp) <= value:
			below += 1
	var pct: int = int(round(100.0 * float(below) / float(others.size())))
	var flag: String = "!" if pct <= 8 or pct >= 92 else " "
	return "%s%s%.2f p%d[%.2f..%.2f]" % [name, flag, value, pct, lo, hi]


func _group_count(group: StringName) -> int:
	return get_tree().get_nodes_in_group(group).size()
