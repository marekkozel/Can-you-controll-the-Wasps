class_name AllegianceComponent
extends Node

# 立场 / allegiance. 和血统（VariantComponent）完全正交：任何颜色都可能是任何立场。
# 代码里绝不能出现"异色 = 叛军"的判断 / never infer allegiance from colour.

signal changed(state: State)
## 伪王后死了，她的叛军屈服 / the mother died and this one gave in
signal submitted

enum State { LOYAL, FALSE_QUEEN, REBEL, SUBDUED }

var state: State = State.LOYAL
## 叛军指向生它的伪王后。不加类型：她随时可能被处决，类型化变量拒绝存已释放的实例
## Rebels point at the queen that laid them - untyped, she can be executed at any moment.
var mother = null
## 个人背叛值。被摔、目击同伴被处决都会涨 / grows from being slammed and from witnessing executions
var betrayal: float = 0.0
## 由 BetrayalDirector 写入 / written by the director
var strike_threshold: float = 0.5
## 每秒消气多少。不衰减的话杀错一次就有几只蜂永久罢工，惩罚太硬
## Without decay one wrong call strikes a few wasps for the rest of the run.
@export_range(0.0, 0.1, 0.001) var betrayal_decay: float = 0.008
## 伪王后产什么颜色的卵。她自己不变色——这就是伪装 / she stays the dominant colour
var brood_variant: WaspVariant = null
## 0 = 第一代，笨拙好认；1 = 老练，每条线索都跌进普通工蜂的区间里。
## 玩家每处决掉一只，下一只就难一档——手好的人自己把游戏变难
## Ramps with each generation: the better you are, the harder you make it.
var cunning: float = 0.0

# 冷却放在组件上而不是行为树任务里：任务只有被 tick 到才跑，
# 而伪王后可能正卡在一段长达几秒的 Gather 里，冷却会跑得比真实时间慢
# Cooldowns live here, not in the BT tasks: a task only ticks while reached, and the
# queen can sit inside a multi-second Gather where its cooldown would stall.
var lay_cooldown: float = 0.0
var sabotage_cooldown: float = 0.0
## 伪王后下的"去那边闹一下"指令，调虎离山用 / a decoy order from the queen
var decoy_cell: Node = null
var decoy_until: float = 0.0


func _process(delta: float) -> void:
	lay_cooldown = maxf(lay_cooldown - delta, 0.0)
	sabotage_cooldown = maxf(sabotage_cooldown - delta, 0.0)
	decoy_until = maxf(decoy_until - delta, 0.0)
	if decoy_until <= 0.0:
		decoy_cell = null
	betrayal = maxf(betrayal - betrayal_decay * delta, 0.0)

	# 母亲没了就自己屈服，不用谁来通知 / self-subdue, no director needed
	if state == State.REBEL and not is_instance_valid(mother):
		submit()


func is_loyal() -> bool:
	return state == State.LOYAL


func is_false_queen() -> bool:
	return state == State.FALSE_QUEEN


func is_rebel() -> bool:
	return state == State.REBEL


func is_on_strike() -> bool:
	return betrayal >= strike_threshold


# 已屈服的照干；恨上你的那几只不干
# Subdued ones work; the aggrieved refuse. The player only sees wasps idling and has to
# work out why - 看到几只蜂突然不干活了，本身就是一条氛围信号。
func works() -> bool:
	return state != State.REBEL and not is_on_strike()


func make_false_queen() -> void:
	_change(State.FALSE_QUEEN)


func make_rebel(from_mother) -> void:
	mother = from_mother
	_change(State.REBEL)


# 母亲没了就不闹了，颜色和专长都留着 / gives in, keeps its colour and its perk
func submit() -> void:
	if state != State.REBEL:
		return
	mother = null
	sabotage_cooldown = 0.0
	_change(State.SUBDUED)
	submitted.emit()


func _change(next: State) -> void:
	if state == next:
		return
	state = next
	changed.emit(state)
