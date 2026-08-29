class_name DragProfile
extends Resource

# 拖拽手感预设 / drag feel preset.
# 存成 Resources/DragProfiles/*.tres，多个物体共享一份 / shared, edit once applies everywhere.

@export_group("Follow")
## 越大越跟手 / higher = snappier
@export_range(1.0, 60.0, 0.5) var stiffness: float = 20.0
## 越小越像果冻 / lower = more jelly
@export_range(0.05, 1.0, 0.01) var damping: float = 0.35
## px/s，防止猛甩穿墙 / speed cap, stops tunnelling
@export_range(100.0, 8000.0, 50.0) var max_speed: float = 2500.0
## 重物拖起来更迟钝 / heavy feels sluggish
@export var mass_scaling: bool = false

@export_group("Throw")
## 松手时继承多少手速 / 0 = drop, 1 = full mouse speed
@export_range(0.0, 2.0, 0.05) var throw_multiplier: float = 1.0
@export_range(100.0, 8000.0, 50.0) var max_throw_speed: float = 2000.0

@export_group("Rotation")
## 0 = 拖的时候不歪 / no wobble
@export_range(0.0, 0.01, 0.0001) var wobble_multiplier: float = 0.0012
@export_range(0.0, 3.14, 0.01) var max_wobble_angle: float = 0.6
@export_range(0.0, 30.0, 0.5) var rotation_stiffness: float = 8.0
## 松手后还剩多少自旋 / spin kept on release
@export_range(0.0, 1.0, 0.05) var spin_retention: float = 0.5

@export_group("Extras")
## 拖拽时的 linear_damp，负数 = 不覆盖 / negative = keep body's own
@export var drag_linear_damp: float = -1.0
## 抓在手上时 z_index 往上抬多少。必须大于实体之间的分层差（敌人 10 / 蜂 20 / 物品 30），
## 否则拖着的蜂还是会被地上的纸板盖住 / must clear the entity layers or the held thing hides
@export_range(0, 200, 1) var grab_z_offset: int = 100
