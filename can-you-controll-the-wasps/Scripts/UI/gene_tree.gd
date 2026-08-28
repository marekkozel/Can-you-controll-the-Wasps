class_name GeneTree
extends ScrollContainer

# 基因面板 / the upgrade panel. 一行一条，可滚动。
# 内容全在 `nodes` 里的 GeneNode 资源上——**加一个升级只要多一个 .tres**。
# The list is data; adding an upgrade means adding a resource, not touching this file.
#
# 以前是 52px 方块摆成一棵树、连线画在 _draw() 里。256 宽的面板只塞得下五列，
# 名字被压成三个字母（CAR / ATK / BLD），玩家读不出那是什么。
# 换成行之后名字写得下，条数也不再受面板宽度限制——多了就滚。
# The tree capped names at three letters in a 256px panel; rows lift both limits.
#
# 行用真的 Button 而不是自己画：normal / hover / pressed / disabled 四态、
# 悬停 tooltip、键盘焦点全都从主题白拿
# Real Buttons, so the four states and the tooltip come from the theme for free.

## 一行多高 / row height
@export_range(18.0, 60.0, 1.0) var row_height: float = 28.0
@export_range(0, 12, 1) var row_separation: int = 4
## 面板上的所有升级，按 GeneNode.order 排 / sorted on GeneNode.order
@export var nodes: Array[GeneNode] = []
## 点数读数那个 Label。留空就不管它 / optional, left blank means "not mine to update"
@export var points_label: NodePath

var _bank: GeneBank = null
var _rows: VBoxContainer = null
var _buttons: Dictionary = {}   ## id -> Button


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", row_separation)
	add_child(_rows)

	_build()

	_bank = GeneBank.find(get_tree())
	if _bank == null:
		push_warning("GeneTree found no GeneBank, the panel is inert")
	else:
		_bank.points_changed.connect(func(_p): _refresh())
		_bank.rank_changed.connect(func(_i, _r): _refresh())
	_refresh()


func _build() -> void:
	var sorted: Array[GeneNode] = []
	for node in nodes:
		if node != null and node.id != &"":
			sorted.append(node)
	sorted.sort_custom(func(a: GeneNode, b: GeneNode): return a.order < b.order)

	for node in sorted:
		if _buttons.has(node.id):
			continue
		var button: Button = Button.new()
		button.name = String(node.id)
		button.text = node.display_name
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.custom_minimum_size.y = row_height
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_pressed.bind(node))

		# 等级和价格贴在行的右端。画在 _draw() 里会被按钮的底盖住，所以做成子节点
		# A child, not a _draw() call: the button's stylebox would paint over it.
		var meta: Label = Label.new()
		meta.name = "Meta"
		meta.add_theme_font_size_override("font_size", 10)
		meta.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		meta.offset_left = -72.0
		meta.offset_right = -8.0
		meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		meta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(meta)

		_rows.add_child(button)
		_buttons[node.id] = button


func _on_pressed(node: GeneNode) -> void:
	if _bank != null:
		_bank.unlock(node)


func _refresh() -> void:
	var label: Label = get_node_or_null(points_label) as Label
	if label != null:
		label.text = "GENES  x%d" % (_bank.points if _bank != null else 0)

	for node in nodes:
		var button: Button = _buttons.get(node.id) as Button
		if button == null:
			continue
		if _bank == null:
			button.disabled = true
			continue

		var rank: int = _bank.rank_of(node.id)
		button.disabled = not _bank.can_unlock(node)

		# 点满的和还买不起的都是 disabled，长得一样玩家就分不出"我有了"和"没钱"。
		# 给已经拿到的那些盖一层 pressed 的样式，"拿到了"才读得出来
		# Both states are disabled; without this, owning a row looks like being locked out.
		if rank > 0:
			button.add_theme_stylebox_override("disabled", get_theme_stylebox("pressed", "Button"))
		else:
			button.remove_theme_stylebox_override("disabled")

		button.tooltip_text = _tooltip_for(node, rank)

		var meta: Label = button.get_node_or_null(^"Meta") as Label
		if meta != null:
			meta.text = _meta_for(node, rank)
	queue_redraw()


# 行右端那一小段。点满写 MAX，可叠的写"级数 价格"，一次性的只写价格
# MAX when capped, rank plus price while it still stacks, price alone for one-offs.
func _meta_for(node: GeneNode, rank: int) -> String:
	if rank >= node.max_rank:
		return "MAX"
	if node.max_rank > 1:
		return "%d/%d   %dp" % [rank, node.max_rank, node.cost]
	return "%dp" % node.cost


# 悬浮说明。等级会变，所以每次 refresh 重写，不能在建行时写死
# Rebuilt on every refresh: the rank line changes as the player spends points.
func _tooltip_for(node: GeneNode, rank: int) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(node.display_name if node.description.is_empty() else node.description)
	if node.max_rank > 1:
		lines.append("Rank %d / %d" % [rank, node.max_rank])
	if rank >= node.max_rank:
		lines.append("Taken.")
	elif not _bank.is_available(node):
		lines.append("Needs another gene first.")
	elif _bank.points < node.cost:
		lines.append("Costs %d - you have %d." % [node.cost, _bank.points])
	else:
		lines.append("Costs %d." % node.cost)
	return "\n".join(lines)
