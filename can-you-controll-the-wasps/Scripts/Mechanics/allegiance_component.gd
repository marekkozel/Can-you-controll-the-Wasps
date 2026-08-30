class_name AllegianceComponent
extends Node

# 立场 / allegiance. 和血统（VariantComponent）完全正交：任何颜色都可能是任何立场。
# 代码里绝不能出现"异色 = 叛军"的判断 / never infer allegiance from colour.

signal changed(state: State)
## 伪王后死了，她的叛军屈服 / the mother died and this one gave in
signal submitted

enum State { LOYAL, FALSE_QUEEN, REBEL, SUBDUED }

var state: State = State.LOYAL
## 她当过伪王后。摔一次面具就掉，但账要记着——不然玩家做对了事之后把她打死，
## 反而按"处决忠诚工蜂"吃一次 unrest
## The mask comes off on the first slam; this remembers, or finishing her would be
## filed as executing an innocent.
var was_false_queen: bool = false
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

## 入侵警报响起时肯跑多远来支援，作为 Defend 集结半径的倍率。
## 这是又一条线索，所以又一次必须是**重叠的区间**：普通工蜂 LOYAL_RALLY，
## 伪王后 QUEEN_RALLY，两段有交叠，而且 cunning 越高她越往正常那头靠。
## 不重叠的话玩家只要制造一次入侵，不动的那只就是她——那不是推理，是探测器。
## Rally eagerness, used as a multiplier on Defend's alert radius. Another tell, so
## another pair of OVERLAPPING bands - a clean split would turn one raid into a detector.
var rally_bias: float = 1.0

## 集结意愿的两条区间，必须交叠 / the two bands, and they must overlap
# **她的区间必须是工蜂区间的子集，不能只是"有交集"。**
# 原本是 LOYAL(0.75..1.0) / QUEEN(0.60..0.90)：0.60~0.75 这一段是只有她才可能抽到的值，
# 玩家只要制造一次入侵、找出那只反应半径明显最小的，就抓到了确定答案——那是探测器。
# 现在下限对齐，她只是**更可能**偏低，而不是**只有她**能偏低。
# The impostor's band must be a SUBSET of the workers', not merely overlap it: the old
# 0.60-0.75 stretch was hers alone, which made one raid enough to identify her.
#
# 工蜂下限跟着降到 0.62，代价是忠诚蜂也会有几只不回防——那正是要的效果，
# "入侵时谁没回来"从此不是确定答案
# Loyal wasps now also sometimes stay away, which is exactly the point.
const LOYAL_RALLY: Vector2 = Vector2(0.62, 1.0)
const QUEEN_RALLY: Vector2 = Vector2(0.62, 0.88)

# 冷却放在组件上而不是行为树任务里：任务只有被 tick 到才跑，
# 而伪王后可能正卡在一段长达几秒的 Gather 里，冷却会跑得比真实时间慢
# Cooldowns live here, not in the BT tasks: a task only ticks while reached, and the
# queen can sit inside a multi-second Gather where its cooldown would stall.
var lay_cooldown: float = 0.0
var sabotage_cooldown: float = 0.0
## 追丢之后歇多久再追下一只。放在这里而不是 Harass 里，是因为任务一 FAILURE 就退出，
## 状态存在任务上等于每次重进都清零，缰绳就没了
## Here rather than in Harass: a failing task exits, and a leash that resets on re-entry
## is not a leash.
var harass_cooldown: float = 0.0
## 咬完一口之后还在巢边守多久。这段时间里不去追蜂，冷却一到就地咬下一格——
## 没有它的话叛军每咬一口就飞出去追一次蜂，看着像犹豫不决
## Keeps a rebel on the comb between bites instead of flying off after every one.
var sabotage_focus: float = 0.0
## 伪王后下的"去那边闹一下"指令，调虎离山用 / a decoy order from the queen
var decoy_cell: Node = null
var decoy_until: float = 0.0


func _ready() -> void:
	rally_bias = randf_range(LOYAL_RALLY.x, LOYAL_RALLY.y)


func _process(delta: float) -> void:
	lay_cooldown = maxf(lay_cooldown - delta, 0.0)
	sabotage_cooldown = maxf(sabotage_cooldown - delta, 0.0)
	sabotage_focus = maxf(sabotage_focus - delta, 0.0)
	harass_cooldown = maxf(harass_cooldown - delta, 0.0)
	decoy_until = maxf(decoy_until - delta, 0.0)
	if decoy_until <= 0.0:
		decoy_cell = null
	betrayal = maxf(betrayal - betrayal_decay * delta, 0.0)


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
	rally_bias = randf_range(QUEEN_RALLY.x, QUEEN_RALLY.y)
	was_false_queen = true
	_change(State.FALSE_QUEEN)


# 摔到墙上，面具掉了 / slammed into a wall and the mask comes off.
# 她不死也不变色，变的只是她不再偷偷下卵，以及她重新变回一只普通工蜂。
# 已经孵出来的叛军**不受影响**——那些只能玩家自己清
# She keeps her colour and her life; what she loses is the laying. Her existing rebels
# are unaffected: those are the player's to clean up.
func unmask() -> void:
	if state != State.FALSE_QUEEN:
		return
	# SecretLay 靠 brood_variant 为空停手 / SecretLay stops on a null brood_variant
	brood_variant = null
	lay_cooldown = 0.0
	decoy_cell = null
	decoy_until = 0.0
	rally_bias = randf_range(LOYAL_RALLY.x, LOYAL_RALLY.y)
	_change(State.LOYAL)


# 老练的她集结得跟普通工蜂一样积极 / cunning pulls her back into the normal band
func rally_reach() -> float:
	return lerpf(rally_bias, 1.0, clampf(cunning, 0.0, 1.0))


func make_rebel(from_mother) -> void:
	mother = from_mother
	_change(State.REBEL)


# 她被扶上了王座。不是屈服，是**得手了**——但机制上要的东西和屈服完全一样：
# 留着颜色、照常干活、而且退出伪王后候选池（awaken_now 只从 LOYAL 里挑），
# 所以复用 SUBDUED 而不是再开一个状态。状态名读起来是反的，行为是对的。
# She won, but mechanically a winner and a submitter need the identical thing.
func enthrone() -> void:
	if state != State.FALSE_QUEEN:
		return
	# SecretLay 靠 brood_variant 为空停手：她合法了，不必再偷偷下卵
	# SecretLay stops on a null brood_variant - she has no reason to sneak any more.
	brood_variant = null
	lay_cooldown = 0.0
	decoy_cell = null
	decoy_until = 0.0
	_change(State.SUBDUED)


# 屈服。**只有加冕那条路会走到这里**——母亲死了叛军不再自动屈服，
# 异色就是敌人，清场是玩家的事
# Only the coronation path reaches this now: a dead mother no longer pacifies her brood.
func submit() -> void:
	if state != State.REBEL:
		return
	mother = null
	sabotage_cooldown = 0.0
	sabotage_focus = 0.0
	harass_cooldown = 0.0
	_change(State.SUBDUED)
	submitted.emit()


func _change(next: State) -> void:
	if state == next:
		return
	state = next
	changed.emit(state)
