class_name HoverReadout
extends VBoxContainer

# 悬停读数 / hover readout: 鼠标停在哪只蜂上，左边面板就显示它的血量、状态和血统专长。
# 抓在手上的那只也算——它跟着光标走，本来就在判定范围里，而那正是你最想看血量的时候。
# The held wasp counts too: it follows the cursor, which is exactly when you want this.
#
# ============================================================================
# 这个面板只准显示三类东西：**血量、消极怠工、血统专长**。
#
# 绝不能显示：
#   - AllegianceComponent.state —— 直接把叛军和伪王后交出去
#   - works() —— 它是 `state != REBEL and not is_on_strike()`，用它等于泄露 REBEL
#   - cunning / rally_bias / betrayal 的数值
#   - **实际移动速度**。实际速度 = speed_scale x morale_scale，而 morale_scale 是
#     unrest 的直接函数，显示它等于把群体不安值交给玩家，红色调那层氛围设计当场作废。
#     速度这一行只显示血统倍率。
#
# 消极怠工可以显示，因为它是 betrayal 的函数而不是 state 的函数——罢工的几乎总是
# 被你得罪的忠诚工蜂，伪王后反而照常干活（那是她的伪装）。它指向的方向和她相反。
# Strike state is safe precisely because it points away from the impostor.
# ============================================================================
#
# 走轮询而不是接 Wasp 的信号：蜂随时在羽化和被处决，逐只连信号要处理一堆生命周期，
# 而按组遍历一次几十个节点的开销可以忽略
# Polls instead of wiring per-wasp signals - wasps come and go constantly.

const WASP_GROUP: StringName = &"wasps"
const CARRIABLE_GROUP: StringName = &"carriable"
## 专长轨道的基础格数：血统专长的 @export_range 上限都是 4。
## 解锁了基因就往外加格子——加成必须**看得见**，否则玩家花了点数没有反馈
## Genes extend the track: an invisible bonus is an unrewarded purchase.
const PERK_SLOTS: int = 4

## 光标离蜂中心多近算停在它上面。比碰撞半径（19.5）大一点，小目标好悬停
## A little larger than the collision radius so a 20px target is not fiddly to hover.
@export_range(8.0, 80.0, 1.0) var hover_radius: float = 26.0
## 货物比蜂小（食物半径 12），判定放宽一点才好悬停 / items are smaller, so a wider grab
@export_range(8.0, 80.0, 1.0) var item_hover_radius: float = 30.0
@export_range(0.0, 0.5, 0.01) var refresh_interval: float = 0.05

## 每种货物的说明。按 payload 匹配，加一种货就多一个 .tres
## Matched on payload - a new carriable is a new resource, not new code.
@export var items: Array[ItemInfo] = []
## 面板标题，会跟着当前看的是蜂还是货物换 / swaps with the subject
@export var title_path: NodePath = ^"../Title"
@export var wasp_title: String = "WASP"

@onready var _name: Label = $Name
@onready var _lineage: Label = $Lineage
@onready var _health_pips: PipTrack = $Health/Pips
@onready var _health_value: Label = $Health/Value
@onready var _health_row: Control = $Health
@onready var _strike: Label = $Strike
@onready var _hint: Label = $Hint
@onready var _perks: Control = $Perks
@onready var _perks_divider: Control = $PerksDivider
@onready var _perks_heading: Label = $PerksHeading
@onready var _build_note: Label = $BuildNote
@onready var _item_name: Label = $ItemName
@onready var _item_text: Label = $ItemText
@onready var _title: Label = get_node_or_null(title_path)

var _timer: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_show(null)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = refresh_interval

	# 拿在手上的优先。**先看手上再看光标底下**：托着一块纸板从蜂群上空飞过时，
	# 玩家问的是"这块纸板干嘛用"，不是"下面那只蜂是谁"
	# What is in hand wins: carrying a piece over the swarm should not swap the readout.
	var subject: Node2D = DraggableComponent.held_body()
	if subject == null:
		subject = _nearest_in_group(WASP_GROUP, hover_radius)
	if subject == null:
		subject = _nearest_in_group(CARRIABLE_GROUP, item_hover_radius)

	if subject != null and subject.is_in_group(WASP_GROUP):
		_show(subject)
	elif subject != null:
		_show_item(_info_for(subject))
	else:
		_show(null)


# 光标要换算到世界坐标再跟黄蜂比。这个面板挂在 CanvasLayer 下，
# Control.get_global_mouse_position() 给的是 canvas 空间——现在没相机所以两者恰好重合，
# 一加 Camera2D 悬停判定就会整体错位。allegiance_markers.gd 里踩过同一个坑
# The panel lives on a CanvasLayer, so the Control-space cursor only happens to match
# world space while there is no camera. Convert, the way the markers overlay does.
func _nearest_in_group(group: StringName, radius: float) -> Node2D:
	var viewport: Viewport = get_viewport()
	var cursor: Vector2 = viewport.get_canvas_transform().affine_inverse() * viewport.get_mouse_position()
	var best: Node2D = null
	var best_dist: float = radius
	for node in get_tree().get_nodes_in_group(group):
		var item: Node2D = node as Node2D
		if item == null:
			continue
		var dist: float = cursor.distance_to(item.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = item
	return best


# 货物报的是它自己的 payload，跟交付走的是同一个键 / same key the delivery uses
func _info_for(node: Node2D) -> ItemInfo:
	var deliverable: Node = node.get_node_or_null(^"DeliverableComponent")
	if deliverable == null:
		return null
	for info in items:
		if info != null and info.payload == deliverable.payload:
			return info
	return null


func _show_item(info: ItemInfo) -> void:
	_set_wasp_rows(false)
	var found: bool = info != null
	_item_name.visible = found
	_item_text.visible = found
	_hint.visible = not found
	if not found:
		return
	if _title != null:
		_title.text = info.display_name
	_item_name.text = info.display_name
	_item_text.text = info.description


# 蜂那一整组读数的显隐，蜂和货物两条路都要用 / shared by both subjects
func _set_wasp_rows(shown: bool) -> void:
	_health_row.visible = shown
	_perks.visible = shown
	_perks_divider.visible = shown
	_perks_heading.visible = shown
	_lineage.visible = shown
	_name.visible = shown
	if not shown:
		_strike.visible = false
		_build_note.visible = false


func _show(wasp: Node2D) -> void:
	var found: bool = wasp != null
	_item_name.visible = false
	_item_text.visible = false
	_set_wasp_rows(found)
	_hint.visible = not found
	if _title != null:
		_title.text = wasp_title
	if not found:
		_name.visible = true
		_name.text = "—"
		return

	_name.text = _name_of(wasp)
	_lineage.text = _lineage_of(wasp)
	_show_health(wasp)
	_show_strike(wasp)
	_show_perks(wasp)


func _show_health(wasp: Node2D) -> void:
	var health: HealthComponent = wasp.get_node_or_null(^"HealthComponent") as HealthComponent
	if health == null:
		_health_row.visible = false
		return
	_health_pips.set_values(health.health, health.max_health)
	_health_value.text = "%d/%d" % [health.health, health.max_health]


# 只看 is_on_strike()。**不要**换成 works()，那个会把 REBEL 泄露出去
# is_on_strike() only - works() would leak REBEL.
func _show_strike(wasp: Node2D) -> void:
	if not wasp.has_method("allegiance"):
		_strike.visible = false
		return
	var allegiance: AllegianceComponent = wasp.allegiance()
	# 平时整行不占位。天天亮着 "WORKING" 是废话，也会让 SLACKING 出现时不够扎眼
	# Hidden when working: a permanent "WORKING" row makes SLACKING stop registering.
	_strike.visible = allegiance != null and allegiance.is_on_strike()


# 报的是**蜂身上的**数（血统 + 基因），不是 WaspVariant 的裸值。
# 面板和实际伤害/载重必须是同一个数，读血统资源会漏掉基因加成
# Ask the wasp: the variant resource does not know about genes.
func _show_perks(wasp: Node2D) -> void:
	var attack: int = wasp.attack_units() if wasp.has_method("attack_units") else 1
	var speed: int = wasp.speed_units() if wasp.has_method("speed_units") else 1
	var carry: int = wasp.carry_units() if wasp.has_method("carry_units") else 1
	var build: int = wasp.build_units() if wasp.has_method("build_units") else 1
	# 轨道要留够蜂王浆吃出来的那几格，否则 _set_perk 的 clamp 会把加成截掉，
	# 面板报出比实际**更低**的数——这比不显示还糟
	# The track must have room for the jelly bonus or the clamp below silently
	# under-reports it, which is worse than not showing it at all.
	var jelly: int = 0
	if "trait_bonus" in wasp:
		for value in wasp.trait_bonus:
			jelly = maxi(jelly, value)
	# 四条轨道等长，按最高的那条留位，看着才齐 / one length for all four, sized by the tallest
	var slots: int = PERK_SLOTS + (wasp.perk_bonus if "perk_bonus" in wasp else 0) + jelly

	# 格子就是数值，不再另外写一遍数字 / the pips are the number, nothing is spelled out
	_set_perk(&"Speed", speed, slots)
	_set_perk(&"Attack", attack, slots)
	_set_perk(&"Carry", carry, slots)
	_set_perk(&"Build", build, slots)
	# build_units 只在送纸板时相乘（Deliver.gd 的 _units_for），不标玩家会拿它去送食物
	# build_units only multiplies cardboard deliveries - say so or the player mis-assigns.
	_build_note.visible = build > 1


func _set_perk(key: StringName, pips: int, slots: int) -> void:
	var track: PipTrack = _perks.get_node_or_null(NodePath("%s/Pips" % key)) as PipTrack
	if track != null:
		track.set_values(clampi(pips, 0, slots), slots)


func _variant_of(wasp: Node2D) -> WaspVariant:
	if not wasp.has_method("variant"):
		return null
	var component: VariantComponent = wasp.variant()
	return component.variant if component != null else null


# 个体名。名字是玩家产生牵挂的地方——处决"一只黄蜂"很便宜，处决 Thistle 不便宜
# Names are where attachment lives, which is what makes an execution cost something.
func _name_of(wasp: Node2D) -> String:
	if "wasp_name" in wasp and wasp.wasp_name != "":
		return wasp.wasp_name
	return _lineage_of(wasp)


# 血统名。颜色本来就看得见，说出它的名字不泄露任何东西
# The lineage is already visible as colour; naming it gives nothing away.
func _lineage_of(wasp: Node2D) -> String:
	var variant: WaspVariant = _variant_of(wasp)
	return variant.display_name if variant != null else "Wasp"
