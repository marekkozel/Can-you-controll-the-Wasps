class_name GeneBank
extends Node2D

# 基因库 / gene bank: 每代结算发点数，玩家在进化树上花掉，
# 加成写进之后**新生**的每一只蜂，已经在场的不追溯。
# Points settle per generation; the bonus lands on wasps born afterwards, never retroactively.
#
# 基因是**色盲的**——它对所有血统一视同仁。这一条是红线：一旦某条基因只惠及某个颜色，
# 玩家就有理由按颜色分类蜂群，而"颜色 ≠ 立场"整套设计就是靠玩家没有这个理由撑着的。
# Genes must never key off lineage colour, or the player gains a legitimate reason to
# sort the swarm by colour - which is exactly what this game punishes.
#
# 树的**形状**在 Resources/Genes/*.tres 里（GeneNode），这里只管点数、等级和效果分派。
# The tree's shape is data; this file owns the points, the ranks and the effects.

signal points_changed(points: int)
signal rank_changed(id: StringName, rank: int)

const GROUP: StringName = &"gene_bank"
const HIVE_GROUP: StringName = &"hive"

## 全属性 +1 的节点 id。目前唯一接了效果的一条 / the only wired effect so far
const ALL_PERKS: StringName = &"all_perks"

@export_group("Income")
## 每代保底几点 / floor per generation
@export_range(0, 5, 1) var points_per_generation: int = 1
## 每多少个建成巢室多给一点。上一代经营得好，下一代才有得花
## Extra points scale with the hive you actually built - last generation pays for the next.
@export_range(1, 40, 1) var cells_per_extra_point: int = 6
@export_range(0, 8, 1) var max_points_per_generation: int = 3

var points: int = 0
## id -> 已解锁的等级。没有的键就是 0 级（没解锁）/ absent means rank 0
var ranks: Dictionary = {}


static func find(tree: SceneTree) -> GeneBank:
	return tree.get_first_node_in_group(GROUP) as GeneBank


func rank_of(id: StringName) -> int:
	return ranks.get(id, 0)


func is_unlocked(id: StringName) -> bool:
	return rank_of(id) > 0


# 每只新生蜂的全属性加成 / the flat bonus every newborn carries
func perk_bonus() -> int:
	return rank_of(ALL_PERKS)


# 能不能点。三个条件：点数够、还没点满、前置全部已解锁
# Affordable, not already maxed, and every prerequisite unlocked.
func can_unlock(node: GeneNode) -> bool:
	if node == null or points < node.cost:
		return false
	if rank_of(node.id) >= node.max_rank:
		return false
	return is_available(node)


# 前置是否满足。跟 can_unlock 分开：面板要能区分"买不起"和"还轮不到"，
# 两者长得不一样——前者会亮着等你攒钱，后者是灰的
# Kept apart so the panel can tell "cannot afford" from "not yet reachable".
func is_available(node: GeneNode) -> bool:
	if node == null:
		return false
	for req in node.requires:
		if rank_of(req) <= 0:
			return false
	return true


func unlock(node: GeneNode) -> bool:
	if not can_unlock(node):
		return false
	points -= node.cost
	ranks[node.id] = rank_of(node.id) + 1
	points_changed.emit(points)
	rank_changed.emit(node.id, ranks[node.id])
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
