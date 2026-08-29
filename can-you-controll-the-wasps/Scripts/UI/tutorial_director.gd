class_name TutorialDirector
extends Control

# 新手引导 / the tutorial. 屏幕上多两样东西：顶部正中的清单，和套在当前目标上的光圈。
#
# 开局**冻住季节钟**，但游戏一帧都没停：蜂照常干活、幼虫照常长、纸板照常产，
# 只是季节不走、入侵不来、伪王后不醒。冻的是时间不是模拟——真暂停整棵树的话，
# 玩家在教程里连一格巢室都建不出来，那就没什么可教的了。
# 而且**整局唯一的真暂停是年终结算**（见 year_report.gd），那一拍的分量不能被教程稀释
# The clock is held, not the game: the colony runs, only the year waits. A real pause
# would leave nothing to learn, and the year settlement owns the only true pause.
#
# 接线表 / wiring. 七个触发点全部用**已经存在**的信号，Hive 早就把巢室的每一步都转发过：
#   CARDBOARD_DELIVERED  Hive.cell_progress_changed
#   CELL_BUILT           Hive.cell_built
#   EGG_LAID             Hive.cell_egg_laid
#   LARVA_HUNGRY         Hive.cell_larva_hungry
#   LARVA_SEALED         Hive.cell_sealed
#   WASP_EMERGED         Hive.cell_wasp_emerged
#   REBEL_EGG_LAID       Hive.cell_rebel_egg_laid
#   JELLY_REFINED        ItemSource.refined      （item_source 组，加工厂那台）
#   RAID_STARTED         RaidDirector.raid_started
#   RAID_CLEARED         RaidDirector.raid_ended(cleared == true)
#   FALSE_QUEEN_AWAKE    BetrayalDirector.false_queen_awakened
#   WASP_GRABBED         SelectionDirector.subject_changed(subject, in_hand)
#   RUN_STARTED          接线跑完就发一次 / fired once, right here

const HIVE_GROUP: StringName = &"hive"
const RAID_GROUP: StringName = &"raid_director"
const BETRAYAL_GROUP: StringName = &"betrayal_director"
const SEASON_GROUP: StringName = &"season_director"
const SELECTION_GROUP: StringName = &"selection_director"
const SOURCE_GROUP: StringName = &"item_source"

## 教程内容全在这张表里，改字不用碰代码 / every word lives in the resource
@export var steps: Array[TutorialStep] = []

## 排错开关。接线结果和每次触发都会打到控制台——教程是"什么都没发生"型的功能，
## 不打日志的话没法判断是信号没来还是清单没接上
## A silent feature: without this you cannot tell a missing signal from a missing row.
@export var debug_log: bool = false

@export_group("Objectives")
## 全部打勾之后停多久再淡出 / how long the finished list lingers
@export_range(0.0, 8.0, 0.5) var list_linger: float = 2.5
@export_range(0.1, 2.0, 0.05) var tick_time: float = 0.35
## 隔多久重新挑一次光圈的目标。目标会自己消失（纸板被搬走了、格子建完了），
## 只在触发时重挑的话光圈会指着一个已经不在的东西
## Targets vanish on their own; re-aiming only on triggers leaves the ring stranded.
@export_range(0.1, 3.0, 0.1) var aim_interval: float = 0.5

@export_group("Hold")
# 开局把**时间**冻住，不冻模拟——蜂照常干活、幼虫照常长，只是季节不走、入侵不来、
# 伪王后不醒。玩家在一个没有倒计时的场子里先把经济链跑通，学完了钟才开始走
# The colony runs; only the clock, the raids and the awakening wait.
## 开局是否冻住季节钟 / hold the clock at startup
@export var hold_clock: bool = true
## 哪一步完成之后放开。**不能设成 RAID_CLEARED**——入侵在冻结期间根本不会来，
## 那会把自己锁死。默认是"第一只新蜂羽化"，经济链到这里就跑通了
## Never key this to a raid: raids do not happen while held, and the hold would deadlock.
@export var release_on: TutorialStep.Trigger = TutorialStep.Trigger.WASP_EMERGED
## 兜底：这么久还没走到就自己放开。玩家卡住时游戏不能永远停在那儿
## Safety net - a stuck player must never freeze the run for good.
@export_range(30.0, 900.0, 10.0) var hold_timeout: float = 300.0

@onready var _list: PanelContainer = $Objectives
@onready var _rows: VBoxContainer = $Objectives/Margin/Rows
@onready var _skip: Button = $Objectives/Margin/Rows/Skip

## 已经触发过的 trigger。每条只放一次，第二格建成不该再教一遍怎么建巢
## Fired triggers - a second cell must not re-teach the first.
var _fired: Dictionary = {}
## trigger -> 那一行的 Label / the objective row for a trigger
var _objective_rows: Dictionary = {}
## 按 order 排好的清单，光圈靠它知道现在轮到哪一条
## Kept in order so the ring knows which step is current.
var _objectives: Array[TutorialStep] = []
var _left: int = 0
var _holding: bool = false
var _hold_time: float = 0.0
var _aim_time: float = 0.0
var _skipped: bool = false


func _ready() -> void:
	_build_list()
	_skip.pressed.connect(skip)
	# 巢和几个 director 未必比这个节点先 _ready，晚一帧再连
	# The hive and the directors may not exist yet on our own _ready.
	call_deferred(&"_wire")


# 两件事：冻结期间的兜底计时，以及定期重挑光圈目标
# The hold timeout, and re-aiming the ring at whatever is current now.
func _process(delta: float) -> void:
	if _holding:
		_hold_time += delta
		if _hold_time >= hold_timeout:
			_release("timeout")
	_aim_time -= delta
	if _aim_time <= 0.0:
		_aim_time = aim_interval
		_aim_ring()


# ---------------- 接线 / wiring ----------------

func _wire() -> void:
	var hive: Node = get_tree().get_first_node_in_group(HIVE_GROUP)
	_log("wire: hive=%s steps=%d" % [hive != null, steps.size()])
	if hive != null:
		hive.cell_progress_changed.connect(_on_cell_progress)
		hive.cell_built.connect(func(_c): _fire(TutorialStep.Trigger.CELL_BUILT))
		hive.cell_egg_laid.connect(func(_c): _fire(TutorialStep.Trigger.EGG_LAID))
		hive.cell_larva_hungry.connect(func(_c): _fire(TutorialStep.Trigger.LARVA_HUNGRY))
		hive.cell_sealed.connect(func(_c): _fire(TutorialStep.Trigger.LARVA_SEALED))
		hive.cell_wasp_emerged.connect(func(_c, _w): _fire(TutorialStep.Trigger.WASP_EMERGED))
		hive.cell_rebel_egg_laid.connect(func(_c): _fire(TutorialStep.Trigger.REBEL_EGG_LAID))
	else:
		push_warning("TutorialDirector: no hive in group %s" % HIVE_GROUP)

	var raid: Node = get_tree().get_first_node_in_group(RAID_GROUP)
	if raid != null:
		raid.raid_started.connect(func(_wave, _count): _fire(TutorialStep.Trigger.RAID_STARTED))
		# 只有真打退了才算。计时到点自己溜走的那种不该给玩家发勋章
		# Only a repelled wave counts; one that simply expired is not a win.
		raid.raid_ended.connect(func(cleared: bool):
			if cleared:
				_fire(TutorialStep.Trigger.RAID_CLEARED))

	# 全场唯一一处"光标现在指着谁"的判定，in_hand 就是托在手上
	# The one place that already knows what the cursor holds.
	var selection: Node = get_tree().get_first_node_in_group(SELECTION_GROUP)
	if selection != null:
		selection.subject_changed.connect(func(subject: Node2D, in_hand: bool):
			if in_hand and subject is Wasp:
				_fire(TutorialStep.Trigger.WASP_GRABBED))

	var betrayal: Node = get_tree().get_first_node_in_group(BETRAYAL_GROUP)
	if betrayal != null:
		betrayal.false_queen_awakened.connect(func(_w): _fire(TutorialStep.Trigger.FALSE_QUEEN_AWAKE))

	# 加工厂不止一台（纸板/食物点都是 ItemSource），谁出货都算
	# Several sources share the class; any of them refining counts.
	for node in get_tree().get_nodes_in_group(SOURCE_GROUP):
		if node.has_signal(&"refined"):
			node.refined.connect(func(_p): _fire(TutorialStep.Trigger.JELLY_REFINED))

	_log("wire: raid=%s betrayal=%s season=%s selection=%s" % [
		get_tree().get_first_node_in_group(RAID_GROUP) != null,
		get_tree().get_first_node_in_group(BETRAYAL_GROUP) != null,
		get_tree().get_first_node_in_group(SEASON_GROUP) != null,
		get_tree().get_first_node_in_group(SELECTION_GROUP) != null])
	if hold_clock:
		_hold()

	# 开场白。零只蜂开局，不说一句的话玩家面对一张空图完全不知道能干什么
	# The opening line: with no wasps on the board there is nothing to imitate.
	_fire(TutorialStep.Trigger.RUN_STARTED)
	_aim_ring()


# ---------------- 冻结 / the hold ----------------

func _hold() -> void:
	_holding = true
	_hold_time = 0.0
	set_process(true)
	_set_frozen(true)


func _release(why: String) -> void:
	if not _holding:
		return
	_holding = false
	_set_frozen(false)
	print("[Tutorial] clock released (%s)" % why)


func _set_frozen(frozen: bool) -> void:
	var season: Node = get_tree().get_first_node_in_group(SEASON_GROUP)
	if season != null:
		season.held = frozen
	var raid: Node = get_tree().get_first_node_in_group(RAID_GROUP)
	if raid != null:
		raid.paused = frozen
	var betrayal: Node = get_tree().get_first_node_in_group(BETRAYAL_GROUP)
	if betrayal != null:
		betrayal.awakening_enabled = not frozen


# 建造进度是**每交付一块纸板**都会响的，这里只要第一次
# This fires on every scrap; we only want the very first one.
func _on_cell_progress(_cell: Node, progress: int, _required: int) -> void:
	if progress > 0:
		_fire(TutorialStep.Trigger.CARDBOARD_DELIVERED)


# ---------------- 清单 / the objective list ----------------

func _build_list() -> void:
	var objectives: Array[TutorialStep] = []
	for step in steps:
		if step != null and step.kind == TutorialStep.Kind.OBJECTIVE:
			objectives.append(step)
	objectives.sort_custom(func(a, b): return a.order < b.order)

	if objectives.is_empty():
		_list.visible = false
		return

	_objectives = objectives
	for step in objectives:
		var row: Label = Label.new()
		row.name = "Row%d" % step.trigger
		row.text = "◇  %s" % step.text
		_rows.add_child(row)
		_objective_rows[step.trigger] = row
	# 行是运行时 append 上去的，Skip 是场景里写死的，建完得把它踢到最后
	# Rows append at runtime; the authored Skip button has to be pushed to the bottom.
	_rows.move_child(_skip, -1)
	_left = objectives.size()


func _tick_objective(trigger: int) -> void:
	var row: Label = _objective_rows.get(trigger) as Label
	if row == null:
		return
	_objective_rows.erase(trigger)
	row.text = row.text.replace("◇", "◆")
	# 划掉那一下值得一个动作，否则玩家根本不会注意到自己完成了什么
	# The tick earns a beat, or the player never notices they finished anything.
	row.pivot_offset = row.size * 0.5
	row.scale = Vector2(1.08, 1.08)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(row, "scale", Vector2.ONE, tick_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(row, "modulate:a", 0.45, tick_time)

	_left -= 1
	if _left <= 0:
		_retire_list()


# 跳过。清单收掉、后面所有触发一起停掉（_fire 开头会挡）。
# 冻结也在这里放开——不放的话跳过教程会把季节钟一直停到那条 5 分钟兜底计时
# The hold is released here, or skipping would leave the clock frozen until timeout.
func skip() -> void:
	if _skipped:
		return
	_skipped = true
	_release("skipped")
	_point(null)
	set_process(false)

	var tween: Tween = create_tween()
	tween.tween_property(_list, "modulate:a", 0.0, 0.3)
	tween.tween_callback(_list.hide)


func _retire_list() -> void:
	var tween: Tween = create_tween()
	tween.tween_interval(list_linger)
	tween.tween_property(_list, "modulate:a", 0.0, 0.5)
	tween.tween_callback(_list.hide)


func _fire(trigger: int) -> void:
	if _skipped or _fired.has(trigger):
		return
	_fired[trigger] = true
	_log("fire: trigger=%d" % trigger)
	_tick_objective(trigger)
	if _holding and trigger == release_on:
		_release("objective")
	_aim_ring()


func _log(message: String) -> void:
	if debug_log:
		print("[Tutorial] ", message)

# ---------------- 光圈 / the attention ring ----------------

# 当前该看哪儿。**位置一律从节点身上取**——巢室、纸板点、食物点在场景里都可能被挪，
# 写死坐标的话美术调一次布局，光圈就指向空气
# Every position comes from a live node, never from a constant.
func _aim_ring() -> void:
	if _skipped:
		return
	for step in _objectives:
		if _fired.has(step.trigger):
			continue
		_point(_target_for(step.trigger))
		return
	# 全打勾了：收起光圈，process 也不用再跑
	# Nothing left to point at, and nothing left to tick.
	_point(null)
	set_process(false)


func _point(node) -> void:
	var ring: AttentionRing = AttentionRing.find(get_tree())
	if ring != null:
		ring.point_at(node)


func _target_for(trigger: int):
	var hive: Node = get_tree().get_first_node_in_group(HIVE_GROUP)
	match trigger:
		TutorialStep.Trigger.CARDBOARD_DELIVERED:
			# 地上已经有纸板就指最近的那块，没有才指产出点——玩家要抓的是那块料，
			# 不是那个点 / the scrap is what he grabs, the source only makes them
			var piece: Node2D = _nearest_in_group(&"carriable", &"cardboard")
			return piece if piece != null else _source_with(&"cardboard")
		TutorialStep.Trigger.CELL_BUILT:
			# 已经动过工的那格优先——玩家搬了一块料过去，接下来该看的就是它
			# The half-built one first: that is where his last scrap went.
			var started = _cell(hive, func(c): return not c.is_built and c.progress > 0)
			return started if started != null else _cell(hive, func(c): return not c.is_built)
		TutorialStep.Trigger.EGG_LAID:
			return _cell(hive, func(c): return c.can_lay_egg())
		TutorialStep.Trigger.LARVA_SEALED:
			# 缺的是食物，不是那只幼虫——幼虫就在巢里摆着，玩家不知道的是去哪拿吃的
			# The larva is not the missing piece; the food point is.
			var food: Node2D = _nearest_in_group(&"carriable", &"food")
			return food if food != null else _source_with(&"food")
	return null   # 羽化那一条只能等，没什么可指的 / nothing to do but wait


func _cell(hive: Node, test: Callable):
	if hive == null:
		return null
	for cell in hive.all_cells():
		if is_instance_valid(cell) and test.call(cell):
			return cell
	return null


func _source_with(payload: StringName) -> Node2D:
	for node in get_tree().get_nodes_in_group(SOURCE_GROUP):
		var source: ItemSource = node as ItemSource
		if source != null and source.payload == payload:
			return source
	return null


func _nearest_in_group(group: StringName, payload: StringName) -> Node2D:
	var hive: Node2D = get_tree().get_first_node_in_group(HIVE_GROUP) as Node2D
	var from: Vector2 = hive.global_position if hive != null else Vector2.ZERO
	var best: Node2D = null
	var best_dist: float = INF
	for node in get_tree().get_nodes_in_group(group):
		var item: Node2D = node as Node2D
		if item == null or _payload_of(item) != payload:
			continue
		var dist: float = from.distance_to(item.global_position)
		if dist < best_dist:
			best_dist = dist
			best = item
	return best


# payload 不在货物根节点上，在它挂的 DeliverableComponent 上——纸板和食物共用一个
# 根类型，区别只在那个组件的字段里
# The payload lives on the DeliverableComponent, not on the piece itself.
func _payload_of(item: Node) -> StringName:
	for child in item.get_children():
		if &"payload" in child:
			return child.payload
	return &""
