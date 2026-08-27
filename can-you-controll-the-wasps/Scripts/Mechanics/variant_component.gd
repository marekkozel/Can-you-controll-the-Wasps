class_name VariantComponent
extends Node

# 血统 / lineage: 把 WaspVariant 的颜色刷到身上，把专长写回父级。
# 不知道也不关心持有者的立场 / deliberately knows nothing about allegiance.

signal variant_changed(variant: WaspVariant)

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

	variant_changed.emit(next)


func _paint() -> void:
	if _visual == null:
		_visual = get_node_or_null(visual_path)
	if _visual == null:
		return

	_tint(_visual.get_node_or_null(^"Body"), variant.body_color)
	_tint(_visual.get_node_or_null(^"Stripe1"), variant.stripe_color)
	_tint(_visual.get_node_or_null(^"Stripe2"), variant.stripe_color)
	_tint(_visual.get_node_or_null(^"Head"), variant.head_color)

	var outline: Line2D = _visual.get_node_or_null(^"Outline") as Line2D
	if outline != null:
		outline.default_color = variant.outline_color


func _tint(node: Node, color: Color) -> void:
	var poly: Polygon2D = node as Polygon2D
	if poly != null:
		poly.color = color
