class_name WaspVariant
extends Resource

# 血统 / lineage: 颜色 + 专长。存成 Resources/Variants/*.tres，跟 DragProfile 一个路子。
#
# 颜色标记的是血统，**不是立场**。几代之后一种颜色里既有忠诚工蜂也有叛军，
# 这是玩家最大的误判来源，也是这个机制的重点。
# Colour marks lineage, never allegiance - conflating them kills the whole mechanic.

@export var display_name: String = "Amber"

@export_group("Colours")
@export var body_color: Color = Color(0.95, 0.76, 0.18)
@export var stripe_color: Color = Color(0.16, 0.13, 0.1)
@export var head_color: Color = Color(0.24, 0.2, 0.15)
@export var outline_color: Color = Color(0.36, 0.28, 0.12)

# 专长是变种的诱惑。每个血统只点亮一个，于是：
# 颜色告诉你这个血统能干什么，但完全不告诉你它站哪边。
# One perk per lineage: colour tells you what it is good at, never whose side it is on.
@export_group("Perks")
## 叮咬倍率。走整数而不是浮点，属性面板的四格轨道才对得上
## Integer, not a float multiplier - the four-pip track in the panel depends on it.
## 全局基准在 Wasp.damage 上，这里是每个血统在基准上的倍数
## The base lives on Wasp.damage; this multiplies it per lineage.
@export_range(1, 4, 1) var attack_units: int = 1
## 飞得快 / cruise speed
## 只收整数。属性面板拿格子表示数值，没有地方能把 x1.5 这种小数表达出来
## Whole numbers only - the panel shows perks as pips and has no way to render a half.
@export_range(1.0, 4.0, 1.0) var speed_multiplier: float = 1.0
## 一趟顶几份（纸板和食物都算）。视觉上还是叼一个，但交付量翻倍
## Still carries one piece, just delivers as more - far cheaper than a real second slot.
@export_range(1, 4, 1) var carry_units: int = 1
## 额外倍率，只对纸板生效 / extra multiplier, cardboard only
@export_range(1, 4, 1) var build_units: int = 1
