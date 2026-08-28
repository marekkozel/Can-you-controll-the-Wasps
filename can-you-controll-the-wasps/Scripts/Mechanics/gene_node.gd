class_name GeneNode
extends Resource

# 进化树上的一个节点 / one node on the upgrade tree.
# 跟 WaspVariant / EnemyVariant / BehaviourProfile 一个路子：**加一个升级只要多一个 .tres**，
# 摆好 cell 和 requires 就能出现在面板上，不用碰渲染代码。
# Same shape as the other data resources: a new upgrade is a new .tres, not new code.
#
# 但**效果本身不在这里**。这里只描述"树长什么样、什么时候能点"，
# 点下去干什么由 GeneBank 按 effect 分派——数据描述结构，代码实现行为。
# The effect lives in GeneBank: this resource describes the shape, never the behaviour.

## 唯一标识，也是 GeneBank 记等级用的键 / unique key, also the rank key
@export var id: StringName = &""
## 节点上那几个字母，短到能塞进 52px 的方块里 / must fit a 52px square
@export var display_name: String = "?"
## 悬停时的说明，直接接 Button.tooltip_text / becomes the button's tooltip
@export_multiline var description: String = ""

@export_group("Placement")
## 在树上的格子。x 是列（0~4，2 是正中），y 是层（0 在最上）
## Column 0..4 with 2 as the centre; row 0 at the top.
@export var cell: Vector2i = Vector2i(2, 0)
## 上一层的哪些节点解锁了才轮到它。留空 = 树根
## Empty means this is a root.
@export var requires: Array[StringName] = []

@export_group("Cost")
@export_range(1, 8, 1) var cost: int = 1
## 能叠几级。1 = 一次性解锁 / 1 means a one-off unlock
@export_range(1, 8, 1) var max_rank: int = 1
