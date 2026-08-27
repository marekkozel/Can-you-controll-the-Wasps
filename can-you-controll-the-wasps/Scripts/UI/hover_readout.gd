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
## 专长轨道恒定四格：三个专长的 @export_range 上限都是 4
## Fixed at four because every perk's export range tops out there.
const PERK_SLOTS: int = 4

## 光标离蜂中心多近算停在它上面。比碰撞半径（19.5）大一点，小目标好悬停
## A little larger than the collision radius so a 20px target is not fiddly to hover.
@export_range(8.0, 80.0, 1.0) var hover_radius: float = 26.0
@export_range(0.0, 0.5, 0.01) var refresh_interval: float = 0.05

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

var _timer: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_show(null)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = refresh_interval
	_show(_wasp_under_cursor())


# 光标要换算到世界坐标再跟黄蜂比。这个面板挂在 CanvasLayer 下，
# Control.get_global_mouse_position() 给的是 canvas 空间——现在没相机所以两者恰好重合，
# 一加 Camera2D 悬停判定就会整体错位。allegiance_markers.gd 里踩过同一个坑
# The panel lives on a CanvasLayer, so the Control-space cursor only happens to match
# world space while there is no camera. Convert, the way the markers overlay does.
func _wasp_under_cursor() -> Node2D:
	var viewport: Viewport = get_viewport()
	var cursor: Vector2 = viewport.get_canvas_transform().affine_inverse() * viewport.get_mouse_position()
	var best: Node2D = null
	var best_dist: float = hover_radius
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Node2D = node as Node2D
		if wasp == null:
			continue
		var dist: float = cursor.distance_to(wasp.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = wasp
	return best


func _show(wasp: Node2D) -> void:
	var found: bool = wasp != null
	_health_row.visible = found
	_perks.visible = found
	_perks_divider.visible = found
	_perks_heading.visible = found
	_hint.visible = not found
	_lineage.visible = found
	if not found:
		_name.text = "—"
		_strike.visible = false
		_build_note.visible = false
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


func _show_perks(wasp: Node2D) -> void:
	var variant: WaspVariant = _variant_of(wasp)
	var attack: int = variant.attack_units if variant != null else 1
	var speed: float = variant.speed_multiplier if variant != null else 1.0
	var carry: int = variant.carry_units if variant != null else 1
	var build: int = variant.build_units if variant != null else 1

	# 格子就是数值，不再另外写一遍数字 / the pips are the number, nothing is spelled out
	# speed_multiplier 声明成 float 只是为了乘进 speed_scale，取值被 @export_range 卡成整数，
	# 所以这里取整是无损的 / float only so it can scale, but constrained to whole steps
	_set_perk(&"Speed", int(round(speed)))
	_set_perk(&"Attack", attack)
	_set_perk(&"Carry", carry)
	_set_perk(&"Build", build)
	# build_units 只在送纸板时相乘（Deliver.gd 的 _units_for），不标玩家会拿它去送食物
	# build_units only multiplies cardboard deliveries - say so or the player mis-assigns.
	_build_note.visible = build > 1


func _set_perk(key: StringName, pips: int) -> void:
	var track: PipTrack = _perks.get_node_or_null(NodePath("%s/Pips" % key)) as PipTrack
	if track != null:
		track.set_values(clampi(pips, 0, PERK_SLOTS), PERK_SLOTS)


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
