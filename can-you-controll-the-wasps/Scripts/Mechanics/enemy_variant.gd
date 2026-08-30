class_name EnemyVariant
extends Resource

# 敌人品种 / enemy breed: 颜色 + 血量 + 干什么。存成 Resources/Variants/enemy_*.tres，
# 跟 WaspVariant 一个路子——加第三种敌人只要多一个 .tres，不用碰代码。
#
# 敌人可以靠颜色区分，黄蜂不行。「颜色 ≠ 立场」那条红线管的是黄蜂：它要藏立场。
# 敌人没有立场要藏，它本来就是明确的敌人。
# Enemies may be colour-coded; wasps may not. That red line is about hiding allegiance,
# and an enemy has none to hide.
#
# 整体约定：**敌人一律暗且低饱和，黄蜂血统一律亮**，两个色带混在一起玩家第一眼分不出敌我。
# 现在这条约束落在**贴图**上而不是颜色字段上——每种敌人有自己的一张彩图，
# 给了 texture 就不再走 body_color 那套染色（彩图再乘颜色 = 乘两遍）。
# The rule now lives in the art: a breed with a texture is never tinted on top.
# 中型和蜘蛛都在青灰蓝那一带，符合约定；蚂蚁那张用了 #ffa328 / #c46829，
# 跟黄蜂和巢室是同一个暖橙，**离得有点近**
# Enemies stay dark and desaturated, wasp lineages stay bright - keep the bands apart.

enum Behavior {
	THIEF,   ## 目标始终是巢室，不还手 / goes for the brood, never fights back
	HUNTER,  ## 看到蜂就追上去打，不碰巢室 / hunts wasps, ignores the hive
}

@export var display_name: String = "Thief"
@export var behavior: Behavior = Behavior.THIEF
@export_range(1, 20, 1) var max_health: int = 3
## 死了掉几份战利品。猎手该给得多一点：它不偷东西，打死它没有"保住了什么"这层回报，
## 掉落就是打它的**全部**理由 / a hunter steals nothing, so loot is the only reason to fight it
@export_range(0, 32, 1) var loot_count: int = 1

@export_group("Colours")
@export var body_color: Color = Color(0.28, 0.32, 0.27)
@export var sheen_color: Color = Color(0.45, 0.52, 0.44)
@export var head_color: Color = Color(0.18, 0.2, 0.17)
@export var eye_color: Color = Color(0.85, 0.18, 0.16)
@export var outline_color: Color = Color(0.12, 0.14, 0.11)

# 体型 / build. 贴图、碰撞和速度跟着品种走，不再写死在 Enemy.tscn 里——
# 三种敌人共用一个场景，靠这几个字段拉开。
# One scene, three builds: the sheet no longer decides how big a raider is.
@export_group("Build")
## 换掉 Enemy.tscn 上那张图 / replaces the texture authored on the scene
@export var texture: Texture2D
## 上面那张图的动画表。不给就是一张静态图，SpriteAnimator 整个不跑——
## 三种敌人的行走/攻击帧数各不相同，所以这张表必须跟着品种走，不能挂在场景上
## Frame counts differ per breed, so the sheet's table belongs to the breed, not the scene.
@export var animation: SpriteAnimation
## 图的内容不居中就用它补。蚂蚁那张内容全在下半部分 / Ant art sits in the lower half
@export var sprite_offset: Vector2 = Vector2.ZERO
## 贴图放大几倍。**只用整数倍**：贴图过滤是 nearest，2.0 是干净的像素放大，
## 1.5 会切出半像素，边缘会一行一行地闪
## Integer factors only - nearest filtering turns 1.5 into shimmering half-pixels.
##
## 它写在 Body 那张 Sprite2D 上，**不是** Visual：Visual 的 scale 被出场 tween
## （0→1）和死亡膨胀占着，体型写那儿会被这两个 tween 打回 1 倍
## Never on Visual - the spawn and death tweens own that scale and would reset it.
@export_range(0.5, 4.0, 0.5) var sprite_scale: float = 1.0
## 按贴图**内容**的实际尺寸给，不是按图幅 / measured from the content, not the sheet
@export_range(4.0, 80.0, 1.0) var collision_radius: float = 22.0
## 闲逛速度，不是追击速度 / idle drift, not the chase
@export_range(10.0, 200.0, 5.0) var move_speed: float = 40.0
## 追蜂的速度。跟 move_speed 分开是因为蜂的巡航是 `任务速度 x speed_units`，
## 点过 SPEED 的蜂能跑到 200——猎手拿闲逛的 26~85 去追，永远差一截
## Separate from move_speed: a SPEED-gifted wasp cruises at 200 and a drifting
## hunter can never close that gap.
@export_range(20.0, 400.0, 5.0) var chase_speed: float = 150.0
## 质量。三种体型共用一个 mass 的话，同样一拳推蚂蚁和推蜘蛛滑得一样远，
## 一只 12 血的大家伙就没有分量了 / a spider shoved like an ant has no weight to it
@export_range(0.1, 10.0, 0.1) var body_mass: float = 0.9
## 血条只给大型开。小的挂上血条画面就糊了，而且「这东西打不死」的压迫感
## 正是靠只有它有血条撑起来的 / only the big one earns a bar
@export var show_health_bar: bool = false

@export_group("Combat")
## 一口几点伤害。**跟着品种走**——以前四种敌人共用 HuntComponent 的 1 点，
## 螳螂咬得跟苍蝇一样疼，三种猎手除了血条以外是同一个敌人
## Per breed: they all shared the component default, so a mantis bit like a fly and the
## three hunters were one enemy wearing three sprites.
@export_range(1, 10, 1) var bite_damage: int = 1
## 两口之间的间隔。这个数**就是**玩家把伤蜂拖出来的窗口
## This interval IS the player's window to drag a wounded wasp clear.
@export_range(0.2, 10.0, 0.1) var bite_cooldown: float = 1.5
## 一口扫到多大范围内的**所有**蜂，0 = 只咬选中的那一只。
## 大型必须给：8 只蜂叠在螳螂身上和 1 只蜂承担的风险一样，所以"全压上去"永远是
## 最优解、整场战斗没有任何决策。有了横扫，围攻才有代价
## Zero means single target. The big ones need it: piling eight wasps on a mantis costs
## exactly as much as sending one, so swarming is free and the fight has no decision in it.
@export_range(0.0, 160.0, 2.0) var bite_radius: float = 0.0
## 一次出手连咬几口。1 = 老样子，一口一口地咬。
## 连击是给**最大的那几只**留的读法：一阵猛的 + 一段明显的喘息，比单纯"一口很疼"
## 好读得多——玩家能看见节奏，就能在喘息里把伤蜂拖走、把蜂群压上去
## A burst plus a long recovery gives the fight a rhythm the player can read and use;
## a single heavy bite is just a bigger number.
@export_range(1, 8, 1) var burst_bites: int = 1
## 连击内两口的间隔。整串打完才进 bite_cooldown
## The gap inside one burst; the real cooldown starts after the last shot.
@export_range(0.05, 1.0, 0.05) var burst_interval: float = 0.22

## 一爪子端掉几格。1 = 老样子，抢一只崽就撤。
## 大块头按体型给：它压下来的时候盖住的就是那么大一片，只抢走一格读起来太轻
## Sized by footprint: a thing that covers six cells taking one reads as a nibble.
@export_range(1, 12, 1) var steal_count: int = 1

@export_group("Raids")
## 编队点数。一波的预算由玩家当前实力算出来，再用这个填满
## Formation cost - a wave's budget is derived from colony strength, then spent on these.
@export_range(1, 10, 1) var spawn_cost: int = 1
## 一波最多来一只。硬上限不是概率——随机会掷出「整波全是蜘蛛」，
## 那一波玩家学不到任何东西 / a hard cap: an all-spider wave teaches nothing
@export var one_per_raid: bool = false
