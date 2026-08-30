class_name StrikeCooldown
extends Control

# 出手冷却圈 / the player's strike cooldown, drawn at the cursor.
# 手是应急手段，不是主武器：一下 2 点、0.8 秒一次，一只鸟要点十下——
# 那十下里你没在喂幼虫、没在调蜂、也没在找她。**打仗是蜂群的事**，这一圈就是那句话的界面版
# The hand is a stopgap: ten clicks on a bird is ten seconds not spent on anything else.
#
# 画在光标上而不是敌人身上：冷却是**玩家的**，不是某一只敌人的。
# 挂在敌人头上的话，换一只点看起来就该是好的
# The cooldown belongs to the player - on an enemy's head it would read as per-enemy.

## 环心相对光标热点的偏移。**不能是 (0,0)**：默认箭头是从热点往右下长的，
## 圆心压在热点上时箭头正好盖住环的左上角，而那正是径向填充开始排空的那一段
## Never centre it: the arrow grows down-right from the hotspot and would cover exactly
## the arc that drains first.
@export var cursor_offset: Vector2 = Vector2(16.0, 20.0)
## 冷却里跟着光标走的颜色 / while cooling
@export var busy_color: Color = Color(0.88, 0.36, 0.28, 0.95)
## 刚好了的那一下闪一下，然后消失。没有这一下的话「什么时候能再点」要靠猜
## The ready blink answers "when can I hit again" without a number.
@export var ready_color: Color = Color(1.0, 0.85, 0.45, 0.95)
@export_range(0.0, 0.6, 0.01) var ready_flash: float = 0.14

@onready var _ring: TextureProgressBar = $Ring

var _was_busy: bool = false
var _flash: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.visible = false


func _process(delta: float) -> void:
	var ratio: float = Enemy.strike_ratio()
	var busy: bool = ratio > 0.0

	# 好了的那一帧：整圈补满 + 换成暖色，闪一下再收
	# The frame it recovers: a full ring in the ready colour, then gone.
	if _was_busy and not busy:
		_flash = ready_flash
	_was_busy = busy

	if not busy and _flash <= 0.0:
		_ring.visible = false
		return

	_ring.visible = true
	_ring.global_position = get_global_mouse_position() + cursor_offset - _ring.size * 0.5

	if busy:
		_ring.value = ratio
		_ring.tint_progress = busy_color
		return

	_flash -= delta
	_ring.value = 1.0
	_ring.tint_progress = ready_color
