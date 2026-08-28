class_name GeneBank
extends Node2D

# 基因库 / gene bank: 每代结算发点数，玩家在 UpgradePanel 里花掉，
# 加成写进之后**新生**的每一只蜂，已经在场的不追溯。
# Points are settled per generation and spent in the panel; the bonus lands on wasps
# born afterwards and is never applied retroactively.
#
# 基因是**色盲的**——它对所有血统一视同仁。这一条是红线：一旦某条基因只惠及某个颜色，
# 玩家就有理由按颜色分类蜂群，而"颜色 ≠ 立场"整套设计就是靠玩家没有这个理由撑着的。
# Genes must never key off lineage colour, or the player gains a legitimate reason to
# sort the swarm by colour - which is exactly what this game punishes.

signal points_changed(points: int)
signal rank_changed(rank: int)

const GROUP: StringName = &"gene_bank"
const HIVE_GROUP: StringName = &"hive"

@export_group("Income")
## 每代保底几点 / floor per generation
@export_range(0, 5, 1) var points_per_generation: int = 1
## 每多少个建成巢室多给一点。上一代经营得好，下一代才有得花
## Extra points scale with the hive you actually built - last generation pays for the next.
@export_range(1, 40, 1) var cells_per_extra_point: int = 6
@export_range(0, 8, 1) var max_points_per_generation: int = 3

@export_group("All perks")
## 全属性 +1，可以叠这么多次。上限卡在 3 是因为专长轨道最多画到 4+3=7 格，
## 再往上一排格子就读不出个数了
## Capped at 3: the perk track tops out readable at 4+3 pips.
@export_range(1, 6, 1) var max_rank: int = 3
@export_range(1, 8, 1) var unlock_cost: int = 1

var points: int = 0
var rank: int = 0


static func find(tree: SceneTree) -> GeneBank:
	return tree.get_first_node_in_group(GROUP) as GeneBank


# 每只新生蜂的全属性加成 / the flat bonus every newborn carries
func perk_bonus() -> int:
	return rank


func is_maxed() -> bool:
	return rank >= max_rank


func can_unlock() -> bool:
	return not is_maxed() and points >= unlock_cost


func unlock() -> bool:
	if not can_unlock():
		return false
	points -= unlock_cost
	rank += 1
	points_changed.emit(points)
	rank_changed.emit(rank)
	return true


# 继位时结算。给的是上一代留下的巢，不是这一代的承诺
# Settled at the coronation, against the hive the last generation actually left behind.
func award() -> int:
	var built: int = 0
	var hive: Hive = get_tree().get_first_node_in_group(HIVE_GROUP) as Hive
	if hive != null:
		built = hive.built_count()

	var gained: int = points_per_generation + built / cells_per_extra_point
	gained = clampi(gained, 0, max_points_per_generation)
	if gained <= 0:
		return 0

	points += gained
	points_changed.emit(points)
	return gained
