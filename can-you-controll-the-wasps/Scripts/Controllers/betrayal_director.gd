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
## 给氛围表现用：画面色调、以后的嗡嗡声 / for the tint, and for audio later
signal unrest_changed(unrest: float)

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
@export_range(0.0, 300.0, 5.0) var dormant_duration: float = 30.0

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

var _queen: Wasp = null
var _emerged_since: int = 0
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


func has_false_queen() -> bool:
	return is_instance_valid(_queen)


func add_unrest(amount: float) -> void:
	var before: float = unrest
	unrest = clampf(unrest + amount, 0.0, 1.0)
	if not is_equal_approx(unrest, before):
		unrest_changed.emit(unrest)


# ---------------- 上报 / reports from the wasps ----------------

# 右键扎死一只。杀对人安抚蜂群，杀错人把周围看到的那几只一起得罪了
# Getting it right calms the colony; getting it wrong is taken personally by every witness.
func report_execution(victim: Node2D, was_false_queen: bool) -> void:
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
	_queen.allegiance().make_false_queen()
	# 她不改颜色。改了就不叫伪装了 / no recolour: that is the whole point
	_queen.tree_exited.connect(_on_queen_gone.bind(_queen), CONNECT_ONE_SHOT)
	_emerged_since = 0
	_generation += 1
	false_queen_awakened.emit(_queen)
	return _queen


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
	_emerged_since += 1
	var needed: int = int(roundf(lerpf(float(awaken_after), float(awaken_after_unrest), unrest)))
	if _emerged_since >= maxi(needed, 1):
		awaken_now()


func _on_queen_gone(wasp: Wasp) -> void:
	_queen = null
	_emerged_since = 0
	false_queen_gone.emit(wasp)


func _next_variant() -> WaspVariant:
	if brood_variants.is_empty():
		return null
	return brood_variants[(_generation) % brood_variants.size()]


# ---------------- 士气 / morale ----------------

func _process(delta: float) -> void:
	var rotten: int = 0
	for cell in _hive.all_cells():
		if cell.is_rotten():
			rotten += 1

	add_unrest((rot_per_second * float(rotten) - decay_per_second) * delta)

	# 不安的蜂群干活慢，单独恨上你的那几只直接罢工
	# An uneasy colony works slower; the individually aggrieved stop working at all.
	var morale: float = lerpf(1.0, morale_floor, unrest)
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Wasp = node as Wasp
		if wasp != null:
			wasp.morale_scale = morale
			wasp.allegiance().strike_threshold = strike_threshold
