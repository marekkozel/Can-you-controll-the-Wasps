class_name UpgradeSlots
extends VBoxContainer

# 基因槽 / gene slots: UpgradePanel 里那两个六边形按钮，接 GeneBank。
# 挂在 Slots 节点上而不是面板根节点——根上已经有 collapsible_panel.gd 了。
# Lives on the Slots node because the panel root already carries the collapsible script.
#
# 目前只有一条基因（全属性 +1，可叠 max_rank 次），第二个槽是留着的位子。
# 加第二条基因时把 Slot2 那一份接上就行，这个脚本没有任何"只有一条"的假设写死。
# Only one gene is wired today; the second slot is a placeholder, not a special case.

const POINTS_FORMAT: String = "GENES  x%d"

@onready var _slot: Button = $Row1/Slot1
@onready var _caption: Label = $Row1/Slot1/Caption
@onready var _frame: HexFrame = $Row1/Slot1/Frame
## 这条基因当前的等级读数 / the rank readout for this gene
@onready var _rank: Label = $Row1/Plus1
@onready var _locked_slot: Button = $Row2/Slot2
@onready var _locked_caption: Label = $Row2/Slot2/Caption
@onready var _locked_rank: Label = $Row2/Plus2

## 买得起时的边框色 / border once it is affordable
@export var ready_color: Color = Color(0.95, 0.82, 0.35)
@export var idle_color: Color = Color(0.53, 0.53, 0.53)
@export var maxed_color: Color = Color(0.45, 0.75, 0.55)

var _bank: GeneBank = null
var _points_label: Label = null


func _ready() -> void:
	_points_label = _find_points_label()

	_caption.text = "ALL"
	_locked_caption.text = "?"
	_locked_slot.disabled = true
	_locked_rank.text = ""
	_locked_slot.modulate.a = 0.35

	_slot.pressed.connect(_on_pressed)
	_bank = GeneBank.find(get_tree())
	if _bank == null:
		push_warning("UpgradeSlots found no GeneBank, the panel is inert")
		_refresh()
		return

	_bank.points_changed.connect(func(_p): _refresh())
	_bank.rank_changed.connect(func(_r): _refresh())
	_refresh()


# 点数读数是 Content 下的兄弟节点，不是这里的子节点。**不要在 _ready 里 add_child**：
# 父节点这会儿正在建自己的子节点，Godot 会直接拒绝
# Never add it here - the parent is mid-setup and add_child() is refused outright.
func _find_points_label() -> Label:
	var content: Node = get_parent()
	if content == null:
		return null
	return content.get_node_or_null(^"Points") as Label


func _on_pressed() -> void:
	if _bank == null:
		return
	_bank.unlock()


func _refresh() -> void:
	if _bank == null:
		_slot.disabled = true
		return

	if _points_label != null:
		_points_label.text = POINTS_FORMAT % _bank.points

	_rank.text = "MAX" if _bank.is_maxed() else "+%d" % _bank.rank
	_slot.disabled = not _bank.can_unlock()

	if _frame != null:
		if _bank.is_maxed():
			_frame.border_color = maxed_color
		else:
			_frame.border_color = ready_color if _bank.can_unlock() else idle_color

	# 买不起时整个槽压暗，但**不隐藏**：玩家得看得见自己在攒什么
	# Dimmed, never hidden - the player has to see what the points are for.
	_slot.modulate.a = 1.0 if _bank.can_unlock() or _bank.is_maxed() else 0.5
