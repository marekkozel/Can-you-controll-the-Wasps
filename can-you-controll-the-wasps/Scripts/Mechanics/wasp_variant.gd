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

@export_group("Perks")
## 变种的诱惑：跡得快。玩家会为了这个容忍叛乱 / the temptation to tolerate rebels
@export_range(0.5, 4.0, 0.1) var speed_multiplier: float = 1.0
