@tool
class_name HealthComponent
extends Node

# 血量 / health. 只管数值和信号，死了长什么样交给持有方 / numbers only, visuals belong to the owner.
# from 是伤害来源的全局坐标，击退方向靠它算 / `from` is the world point the hit came from.

signal damaged(amount: int, remaining: int, from: Vector2)
signal died(from: Vector2)

## 敌人默认 1 点血，挨一下就死 / enemies die in one hit by default
@export_range(1, 100, 1) var max_health: int = 1

var health: int = 1


func _ready() -> void:
	health = max_health


func is_alive() -> bool:
	return health > 0


# 返回这次伤害是否生效 / returns whether the hit landed
func take_damage(amount: int = 1, from: Vector2 = Vector2.ZERO) -> bool:
	if health <= 0 or amount <= 0:
		return false

	health = maxi(health - amount, 0)
	damaged.emit(amount, health, from)
	if health == 0:
		died.emit(from)
	return true
