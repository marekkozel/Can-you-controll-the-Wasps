class_name WaspNames

# 个体名 / personal names. 每只蜂在 _ready 里领一个。
#
# **取名必须发生在立场之前，而且只能有一个池子。**
# 这是唯一会让名字毁掉推理玩法的地方：如果伪王后或叛军从另一个池子取名、
# 或者变身时改名，玩家看一眼名字就知道答案。现在天然安全——所有蜂都从 LOYAL 起步，
# BetrayalDirector 是事后才改某一只的立场，SecretLay 的叛军也是先成蜂再 become_rebel()。
# One pool, drawn before any allegiance exists. A separate pool or a rename on conversion
# would turn the name into a detector - never add either.
#
# 池子里**不放颜色词**：血统已经叫 Amber / Crimson / Violet / Teal / Lime，
# 个体名再用颜色，玩家会把"这只叫什么"和"这只是什么血统"搞混
# No colour words here - the lineages already own those.

const GROUP: StringName = &"wasps"

const POOL: Array[String] = [
	"Thistle", "Clover", "Bramble", "Fennel", "Sorrel", "Nettle",
	"Yarrow", "Juniper", "Aster", "Mallow", "Tansy", "Vetch",
	"Rue", "Comfrey", "Foxglove", "Hawthorn", "Laurel", "Myrtle",
	"Willow", "Bracken", "Chicory", "Marjoram", "Burdock", "Elder",
	"Hemlock", "Teasel", "Woad", "Madder", "Sedge", "Rowan",
]

## 池子占满之后的后缀 / used once every base name is taken
const SUFFIXES: Array[String] = [
	"II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X",
]


# 挑一个当前没人用的名字。
# 去重靠扫分组而不是维护一张静态表：静态表活得比场景久，F8 重建巢之后池子还是满的，
# 而扫分组自带"死掉的蜂把名字还回来"，也不会有重置漏洞
# Scans the group instead of keeping a static registry: a static one outlives the scene
# and would come up empty after a hive rebuild. This also frees a dead wasp's name.
static func pick(tree: SceneTree) -> String:
	if tree == null:
		return POOL[randi() % POOL.size()]

	var used: Dictionary = {}
	for node in tree.get_nodes_in_group(GROUP):
		# 刚生出来的那只这会儿已经在组里了，但名字还是空的 / the newborn is already in the group
		if "wasp_name" in node and node.wasp_name != "":
			used[node.wasp_name] = true

	var free: Array[String] = []
	for candidate in POOL:
		if not used.has(candidate):
			free.append(candidate)
	if not free.is_empty():
		return free[randi() % free.size()]

	# 名字全占满了。随便挑个基名接最小的可用序号 / everything taken, fall back to Thistle II
	var base: String = POOL[randi() % POOL.size()]
	for suffix in SUFFIXES:
		var numbered: String = "%s %s" % [base, suffix]
		if not used.has(numbered):
			return numbered
	return base
