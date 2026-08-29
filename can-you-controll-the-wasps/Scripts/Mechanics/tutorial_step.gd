class_name TutorialStep
extends Resource

# 一条教程 / one tutorial beat. 全部内容都在 Resources/Tutorial/tutorial_steps.tres 里，
# **加一条教程只要多一个 .tres 条目，不碰代码**——跟 BehaviourProfile / EnemyVariant 一个路子
# Every line lives in the .tres; a new beat is a new entry, never a code change.

## 清单条目还是弹出卡片。清单是「你要去做的事」，能打勾；卡片是「突然发生在你身上的事」
## Objectives are things to do and tick off; cards are things that happen to you.
enum Kind { OBJECTIVE, CARD }

## 什么时候触发。每一条都对应一个**已经存在**的信号，见 tutorial_director.gd 的接线表
## Each maps to a signal that already exists - see the wiring table in tutorial_director.gd.
enum Trigger {
	CARDBOARD_DELIVERED,   ## 有纸板被搬进巢室 / a scrap reached a cell
	CELL_BUILT,            ## 一格建成 / a cell finished
	EGG_LAID,              ## 下了一颗卵 / an egg was laid
	LARVA_HUNGRY,          ## 有幼虫开始饿 / a larva started starving
	LARVA_SEALED,          ## 幼虫吃饱封盖 / fed full and capped
	WASP_EMERGED,          ## 羽化 / a new wasp
	JELLY_REFINED,         ## 加工厂出了一份蜂王浆 / the refinery produced jelly
	RAID_STARTED,          ## 一波入侵进场 / raiders entered
	RAID_CLEARED,          ## 入侵被打退（不是溜走）/ repelled, not merely expired
	REBEL_EGG_LAID,        ## 空巢室里出现异色卵 / a rebel egg appeared
	FALSE_QUEEN_AWAKE,     ## 伪王后醒了 / she woke up
	## 玩家第一次把一只蜂托在手上。**新的一律加在末尾**——.tres 里存的是整数，
	## 往中间插一项会让后面每一条卡片的触发点集体错位
	## Always append: the .tres stores integers, and an insert shifts every card.
	WASP_GRABBED,
	## 开局那一刻。**这一局是从零只蜂开始的**——第一块纸板得玩家自己搬，
	## 所以必须有一条在什么都还没发生时就说话的触发
	## The run starts with no wasps at all, so something has to speak first.
	RUN_STARTED,
}

@export var kind: Kind = Kind.CARD
@export var trigger: Trigger = Trigger.CELL_BUILT

## 清单里那一行，或者卡片的标题 / the objective line, or the card's headline
@export var text: String = ""
## 只有卡片用 / cards only
@export_multiline var body: String = ""

## 卡片停留几秒。长句要给长一点，读不完就没意义
## Longer lines need longer on screen or they may as well not appear.
@export_range(2.0, 20.0, 0.5) var seconds: float = 7.0
## 清单里的排序。卡片不看这个 / objective ordering; cards ignore it
@export_range(0, 20, 1) var order: int = 0
