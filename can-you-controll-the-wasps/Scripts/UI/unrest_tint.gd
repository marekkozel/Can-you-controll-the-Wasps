extends ColorRect

# 不安的氛围 / the colony's mood, as a colour wash.
#
# 玩家永远看不到不安值本身。这层薄薄的红是唯一的外泄口，
# 而且弱到你说不清它到底有没有变——那正是要的效果。
# The player never sees the number. This wash is the only leak, and it is faint enough
# that you are never quite sure it moved.
#
# 嗡嗡声那条线索等有音频资源了接 unrest_changed 就行 / hook the same signal for audio.

## 不安拉满时的透明度。别调大，一眼看出来就不叫氛围了 / keep it low, it is not a health bar
@export_range(0.0, 0.5, 0.01) var max_alpha: float = 0.13
@export var unrest_color: Color = Color(0.72, 0.09, 0.12)
## 跟随速度，突变会很跳 / how fast it follows, a jump would read as a UI event
@export_range(0.1, 5.0, 0.1) var follow_speed: float = 0.6

var _target_alpha: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(unrest_color.r, unrest_color.g, unrest_color.b, 0.0)

	var director: BetrayalDirector = BetrayalDirector.find(get_tree())
	if director == null:
		return
	director.unrest_changed.connect(_on_unrest_changed)
	_on_unrest_changed(director.unrest)


func _process(delta: float) -> void:
	color.a = move_toward(color.a, _target_alpha, follow_speed * max_alpha * delta)


func _on_unrest_changed(unrest: float) -> void:
	_target_alpha = max_alpha * unrest
