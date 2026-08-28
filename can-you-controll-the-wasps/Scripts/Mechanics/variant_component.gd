class_name VariantComponent
extends Node

# 血统 / lineage: 把 WaspVariant 的颜色刷到身上，把专长写回父级。
# 不知道也不关心持有者的立场 / deliberately knows nothing about allegiance.

signal variant_changed(variant: WaspVariant)

const RECOLOUR: Shader = preload("res://Assets/Shaders/recolour.gdshader")
## 贴图自己的主色。蜂/卵/幼虫画的都是这个黄 / what the art looks like untinted
const ART_REFERENCE: Color = Color(0.996, 0.812, 0.459)  # #fecf75

## 用 NodePath 不用 Node 导出——后者在 .tscn 里解析不出来 / typed Node exports don't resolve
@export var visual_path: NodePath = ^"../Visual"
@export var variant: WaspVariant

@onready var _visual: Node2D = get_node_or_null(visual_path)


func _ready() -> void:
	if variant != null:
		apply(variant)


func apply(next: WaspVariant) -> void:
	if next == null:
		return
	variant = next
	_paint()

	var body: Node = get_parent()
	if body != null and "speed_scale" in body:
		body.speed_scale = next.speed_multiplier
	if body != null and "damage_scale" in body:
		body.damage_scale = next.attack_units

	variant_changed.emit(next)


func _paint() -> void:
	if _visual == null:
		_visual = get_node_or_null(visual_path)
	if _visual == null:
		return

	# 目前 Body 是唯一一层，其余三个留着给将来拆分层的贴图 / one layer for now, the rest are for later
	_tint(_visual.get_node_or_null(^"Body"), variant.body_color)
	_tint(_visual.get_node_or_null(^"Stripe1"), variant.stripe_color)
	_tint(_visual.get_node_or_null(^"Stripe2"), variant.stripe_color)
	_tint(_visual.get_node_or_null(^"Head"), variant.head_color)

	var outline: Line2D = _visual.get_node_or_null(^"Outline") as Line2D
	if outline != null:
		outline.default_color = variant.outline_color


# 贴图是彩色的，直接乘颜色等于乘两遍——青色乘出来是绿的，高光也被压平。
# 走 recolour.gdshader 把黄橙那一族的色相挪到血统色上，翅膀和头不动。
# The art is coloured, so modulating multiplies twice; the shader shifts hue instead.
func _tint(node: Node, color: Color) -> void:
	var poly: Polygon2D = node as Polygon2D
	if poly != null:
		poly.color = color
		return

	var sprite: Sprite2D = node as Sprite2D
	if sprite != null:
		_recolour(sprite, color)


# ShaderMaterial 是共享 Resource，跟 DragProfile 一个坑。这里靠「场景里不预挂材质」
# 拿到独立的一份：每只蜂第一次上色时自己 new，之后复用。
# **别在 Wasp.tscn 的 Body 上挂材质**，那一份会被全场共用，最后一只蜂的血统色赢。
# Never author a material on the sprite - every wasp would then share one tint.
func _recolour(sprite: Sprite2D, color: Color) -> void:
	var mat: ShaderMaterial = sprite.material as ShaderMaterial
	if mat == null or mat.shader != RECOLOUR:
		mat = ShaderMaterial.new()
		mat.shader = RECOLOUR
		sprite.material = mat
	mat.set_shader_parameter(&"reference", ART_REFERENCE)
	mat.set_shader_parameter(&"tint", color)
	# shader 末尾还乘了 COLOR，旧的染色值留在这儿就又乘一遍
	# The shader still multiplies COLOR, so the old tint would stack on top.
	sprite.self_modulate = Color.WHITE
