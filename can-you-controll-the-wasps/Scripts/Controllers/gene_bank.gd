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

# 基因的 id。**效果分派在这个文件里，形状在 .tres 里** —— 加一条要动两处：
# 这里加常量和查询函数，Resources/Genes/ 下加资源
# Effects dispatch here, shape lives in the resources; a new gene touches both.
const ALL_PERKS: StringName = &"all_perks"
const THICK_COMB: StringName = &"thick_comb"
const RENDERING: StringName = &"rendering"
const FAT_RESERVES: StringName = &"fat_reserves"
const QUICK_HATCH: StringName = &"quick_hatch"
const THICK_HIDE: StringName = &"thick_hide"
const QUICK_LAY: StringName = &"quick_lay"

@export_group("Income")
## 每代保底几点 / floor per generation
@export_range(0, 5, 1) var points_per_generation: int = 1
## 每多少个建成巢室多给一点。上一代经营得好，下一代才有得花
## Extra points scale with the hive you actually built - last generation pays for the next.
@export_range(1, 40, 1) var cells_per_extra_point: int = 6
## 每多少份蜂王浆多给一点。第二条收入线，代表的是**打赢并且打扫了战场**——
## 一份蜂王浆等于两份肉，而肉只从敌人尸体上来。经营和战斗各记各的，
## 别拿纸板或食物再记一遍：纸板就是建巢数换个单位，食物就是出生数
## The second income line stands for combat: jelly only exists because raids were beaten
## and the field was cleared. Cardboard and food would merely restate cells and births.
@export_range(1, 20, 1) var jelly_per_extra_point: int = 3
## 每代上限。**两条收入线就必须抬这个数**——留在 3 的话建巢一条线自己就顶满了，
## 蜂王浆那条加了等于没加，又变回每代恒定
## Two income lines need headroom: at 3 the cells alone cap it and jelly changes nothing.
@export_range(0, 12, 1) var max_points_per_generation: int = 6

# 每级给多少。数值放这里而不是散在使用方，调平衡只用看一个文件
# The magnitudes live here, not scattered across the systems that read them.
@export_group("Effects")
## THICK COMB：每级建巢少几块纸板 / cardboard saved per rank
@export_range(1, 3, 1) var comb_discount: int = 1
## FAT RESERVES：每级幼虫饱腹期延长几成 / satiation added per rank
@export_range(0.0, 1.0, 0.05) var fat_reserves_bonus: float = 0.4
## QUICK HATCH：每级孵化和封盖各快几成 / maturation shaved per rank
@export_range(0.0, 0.5, 0.05) var quick_hatch_bonus: float = 0.25
## THICK HIDE：每级新生蜂加几点血 / hit points per rank
@export_range(1, 3, 1) var hide_bonus: int = 1
## QUICK LAY：每级产卵速度加快几成 / laying speed increase per rank
@export_range(0.0, 0.5, 0.05) var quick_lay_bonus: float = 0.25

var points: int = 0
## id -> 已解锁的等级。没有的键就是 0 级（没解锁）/ absent means rank 0
var ranks: Dictionary = {}


static func find(tree: SceneTree) -> GeneBank:
	return tree.get_first_node_in_group(GROUP) as GeneBank


func rank_of(id: StringName) -> int:
	return ranks.get(id, 0)


func is_unlocked(id: StringName) -> bool:
	return rank_of(id) > 0


# ---------------- 效果 / effects ----------------
#
# 每一条都是**全体生效**的。基因绝不能只惠及某个血统——那会给玩家一个正当理由
# 按颜色给蜂群分类，而"颜色 ≠ 立场"整套设计靠的就是玩家没有这个理由
# Colony-wide without exception; see the note at the top of this file.

# 每只新生蜂的全属性加成 / the flat bonus every newborn carries
func perk_bonus() -> int:
	return rank_of(ALL_PERKS)


# 建一格巢少要几块纸板 / cardboard knocked off a cell's build cost
func build_discount() -> int:
	return rank_of(THICK_COMB) * comb_discount


# 幼虫饱腹期的倍率。饱得越久，饥饿警报越稀疏，你的调度余地越大
# A longer satiation means sparser alarms and more room to schedule.
func satiation_scale() -> float:
	return 1.0 + float(rank_of(FAT_RESERVES)) * fat_reserves_bonus


# 孵化和封盖的时长倍率。留 25% 的地板，别让整条育儿链塌成零
# Floored at a quarter: the brood chain still has to be a chain.
func maturation_scale() -> float:
	return maxf(1.0 - float(rank_of(QUICK_HATCH)) * quick_hatch_bonus, 0.25)


# 新生蜂多几点血 / extra hit points on every newborn
func health_bonus() -> int:
	return rank_of(THICK_HIDE) * hide_bonus


# 精炼配方 [要几份原料, 出几份成品]。默认 2 换 1，RENDERING 之后 3 换 2——
# 每份肉更值钱，打退一波入侵才有像样的回报
# 2:1 by default, 3:2 once rendered - meat is worth more, so clearing a raid pays.
func refinery_recipe(base_intake: int) -> Vector2i:
	if not is_unlocked(RENDERING):
		return Vector2i(base_intake, 1)
	return Vector2i(base_intake + 1, 2)


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


# 继位时结算。`built` / `jelly` 都是**这一年的累计数**，由调用方从账本里给，
# 不能在这里现场数巢——冬天开场的 _ravage() 早就把巢推平了，读到的永远是残骸
# The caller passes the year's tally: counting the live hive here reads the ruins
# _ravage() just left, not the comb the generation actually built.
func award(built: int, jelly: int) -> int:
	var gained: int = points_per_generation
	gained += built / cells_per_extra_point
	gained += jelly / jelly_per_extra_point
	gained = clampi(gained, 0, max_points_per_generation)
	if gained <= 0:
		return 0

	points += gained
	points_changed.emit(points)
	return gained

func lay_speed_scale() -> float:
	return maxf(1.0 - float(rank_of(QUICK_LAY)) * quick_lay_bonus, 0.25)
