class_name GeneNode
extends Resource

# 面板上的一条升级 / one row on the upgrade panel.
# 跟 WaspVariant / EnemyVariant / BehaviourProfile 一个路子：**加一个升级只要多一个 .tres**，
# 填好 order 就能出现在面板上，不用碰渲染代码。
# Same shape as the other data resources: a new upgrade is a new .tres, not new code.
#
# 但**效果本身不在这里**。这里只描述"叫什么、多少钱、什么时候能点"，
# 点下去干什么由 GeneBank 按 effect 分派——数据描述结构，代码实现行为。
# The effect lives in GeneBank: this resource describes the row, never the behaviour.

## 唯一标识，也是 GeneBank 记等级用的键 / unique key, also the rank key
@export var id: StringName = &""
## 行上显示的名字。一行放得下十来个字符 / a row fits a dozen characters
@export var display_name: String = "?"
## 悬停时的说明，直接接 Button.tooltip_text / becomes the button's tooltip
@export_multiline var description: String = ""

@export_group("Placement")
## 从上往下第几行，小的在前 / row order, low first
@export_range(0, 40, 1) var order: int = 0
## 哪些基因解锁了才轮到它。留空 = 一开始就能点
## Empty means it is available from the start.
@export var requires: Array[StringName] = []

@export_group("Cost")
@export_range(1, 20, 1) var cost: int = 1
## 能叠几级。1 = 一次性解锁 / 1 means a one-off unlock
@export_range(1, 8, 1) var max_rank: int = 1
