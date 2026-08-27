extends Node2D

# 立场标记 / allegiance markers. M 开关，默认关。
#
# 先关着纯靠手感猜，猜完再打开对答案——调"拖拽阻力够不够明显"就靠这个。
# Guess with it off, then flip it on to check. This is the tool for tuning how readable
# the tells are, so it must never ship on.
#
# 挂在 CanvasLayer 下，画之前把世界坐标过一道 canvas transform，以后加了相机也不会错位
# Lives on a CanvasLayer, so world points go through the canvas transform - survives a camera.

const WASP_GROUP: StringName = &"wasps"

@export var queen_color: Color = Color(1.0, 0.25, 0.25, 0.95)
@export var rebel_color: Color = Color(1.0, 0.62, 0.15, 0.9)
@export var subdued_color: Color = Color(0.6, 0.65, 0.7, 0.7)
@export_range(10.0, 60.0, 1.0) var radius: float = 26.0


func _ready() -> void:
	visible = false
	set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		set_process(visible)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var xform: Transform2D = get_viewport().get_canvas_transform()

	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Wasp = node as Wasp
		if wasp == null:
			continue

		var at: Vector2 = xform * wasp.global_position
		match wasp.allegiance().state:
			AllegianceComponent.State.FALSE_QUEEN:
				# 双圈，一眼就能从一群里挑出来 / double ring, findable at a glance
				draw_arc(at, radius, 0.0, TAU, 32, queen_color, 3.5, true)
				draw_arc(at, radius + 7.0, 0.0, TAU, 32, queen_color, 1.5, true)
			AllegianceComponent.State.REBEL:
				draw_arc(at, radius, 0.0, TAU, 28, rebel_color, 2.5, true)
			AllegianceComponent.State.SUBDUED:
				draw_arc(at, radius, 0.0, TAU, 24, subdued_color, 1.5, true)
