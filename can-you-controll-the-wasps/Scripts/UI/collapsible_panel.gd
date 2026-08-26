class_name CollapsiblePanel
extends Control

# 可折叠侧边面板 / collapsible side panel.
# Body 整体滑出屏幕，只把 ToggleButton 留在边上当把手 / body slides out, tab stays on screen.

signal toggled(is_expanded: bool)

const COLLAPSE_LEFT: int = 0
const COLLAPSE_RIGHT: int = 1

@export_enum("Left", "Right") var collapse_side: int = COLLAPSE_LEFT
@export var expanded: bool = true
## 秒。0 = 瞬间切换 / seconds, 0 = instant
@export_range(0.0, 1.0, 0.01) var animation_duration: float = 0.22

@onready var _body: Control = $Body
@onready var _toggle: Button = $Body/ToggleButton

var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 根节点只是个定位框，别吞掉底下的点击 / positioning frame only, must not eat clicks
	_toggle.pressed.connect(_on_toggle_pressed)
	await get_tree().process_frame  # 首帧布局没算完，size 不能用 / size is not valid on the first frame
	_apply(false)


func toggle() -> void:
	set_expanded(not expanded)


func set_expanded(value: bool) -> void:
	if expanded == value:
		return
	expanded = value
	_apply(animation_duration > 0.0)
	toggled.emit(expanded)


func _on_toggle_pressed() -> void:
	toggle()


func _apply(animated: bool) -> void:
	_toggle.text = _tab_text()

	var target: Vector2 = _slide_offset()
	if _tween != null and _tween.is_valid():
		_tween.kill()

	if not animated:
		_body.position = target
		return

	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_body, "position", target, animation_duration)


# 少滑一个 tab 的宽度，折叠完把手正好贴屏幕边 / leave the tab width so the handle stays visible
func _slide_offset() -> Vector2:
	if expanded:
		return Vector2.ZERO
	var hidden: float = maxf(size.x - _toggle.size.x, 0.0)
	return Vector2(-hidden if collapse_side == COLLAPSE_LEFT else hidden, 0.0)


func _tab_text() -> String:
	if collapse_side == COLLAPSE_LEFT:
		return "<" if expanded else ">"
	return ">" if expanded else "<"
