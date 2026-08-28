class_name HealthBarComponent
extends Node2D

# 头顶血条 / overhead health bar. 程序绘制，不出图——跟 HoldRing、幼虫那圈倒计时一路。
# Drawn, never a sprite: same call as the other rings.
#
# 只给大型敌人开（`EnemyVariant.show_health_bar`）。每只敌人都挂一条的话画面就糊了，
# 而且「这东西一时半会打不死」的压迫感正是靠只有它有血条撑起来的。
# Only the big one gets one; the bar itself is what marks it as a slog.

## 默认找兄弟节点。用 NodePath 不用 Node 导出——后者在 .tscn 里解析不出来
@export var health_path: NodePath = ^"../HealthComponent"
@export var bar_size: Vector2 = Vector2(58.0, 6.0)
## 挂在实体原点上方多少。按贴图**内容**的顶边给，不是图幅顶边
## Measured from the top of the art's content, not the top of the sheet.
@export var offset_y: float = -62.0

@export_group("Colours")
@export var back_color: Color = Color(0.10, 0.09, 0.11, 0.85)
@export var fill_color: Color = Color(0.82, 0.26, 0.24)
## 血量低于 low_threshold 时换成它 / swapped in below the threshold
@export var low_color: Color = Color(1.0, 0.74, 0.32)
@export var border_color: Color = Color(0.03, 0.03, 0.04, 0.9)
@export_range(0.0, 1.0, 0.05) var low_threshold: float = 0.3

var _health: HealthComponent = null
var _ratio: float = 1.0


func _ready() -> void:
	_health = get_node_or_null(health_path) as HealthComponent
	if _health == null:
		push_warning("HealthBarComponent found no HealthComponent at %s" % health_path)
		return
	_health.damaged.connect(_on_damaged)
	_health.died.connect(func(_from): hide())
	_refresh()


# Enemy 已经 lock_rotation 了，这里是组件自己的保险：挂到任何会转的父级上都得站直
# Enemy locks its rotation; the component keeps itself upright under any parent anyway.
func _process(_delta: float) -> void:
	global_rotation = 0.0


func _on_damaged(_amount: int, _remaining: int, _from: Vector2) -> void:
	_refresh()


func _refresh() -> void:
	if _health == null or _health.max_health <= 0:
		return
	_ratio = clampf(float(_health.health) / float(_health.max_health), 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var origin := Vector2(-bar_size.x * 0.5, offset_y)
	var frame := Rect2(origin - Vector2.ONE, bar_size + Vector2(2.0, 2.0))
	draw_rect(frame, border_color)
	draw_rect(Rect2(origin, bar_size), back_color)
	if _ratio <= 0.0:
		return
	var fill := Rect2(origin, Vector2(bar_size.x * _ratio, bar_size.y))
	draw_rect(fill, low_color if _ratio <= low_threshold else fill_color)
