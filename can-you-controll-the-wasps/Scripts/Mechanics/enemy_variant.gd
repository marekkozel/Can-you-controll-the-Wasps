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
# 整体约定：**敌人一律暗且低饱和，黄蜂血统一律亮**。别把敌人调进黄蜂那个亮度带
# （琥珀 0.95/0.76/0.18、绯红 0.86/0.24/0.28、紫 0.62/0.36/0.85、青 0.2/0.72/0.68），
# 两个色带混在一起，玩家第一眼分不出敌我。
# Enemies stay dark and desaturated, wasp lineages stay bright - keep the bands apart.

enum Behavior {
	THIEF,   ## 目标始终是巢室，不还手 / goes for the brood, never fights back
	HUNTER,  ## 看到蜂就追上去打，不碰巢室 / hunts wasps, ignores the hive
}

@export var display_name: String = "Thief"
@export var behavior: Behavior = Behavior.THIEF
@export_range(1, 20, 1) var max_health: int = 3

@export_group("Colours")
@export var body_color: Color = Color(0.28, 0.32, 0.27)
@export var sheen_color: Color = Color(0.45, 0.52, 0.44)
@export var head_color: Color = Color(0.18, 0.2, 0.17)
@export var eye_color: Color = Color(0.85, 0.18, 0.16)
@export var outline_color: Color = Color(0.12, 0.14, 0.11)
