class_name GeneTree
extends Control

# 进化树 / the upgrade tree. 单根往下分叉，节点是方块按钮，连线在节点底下画。
# 树的形状全在 `nodes` 里的 GeneNode 资源上——**加一个升级只要多一个 .tres**。
# The shape is data; adding an upgrade means adding a resource, not touching this file.
#
# 节点用真的 Button 而不是自己画：normal / hover / pressed / disabled 四态、
# 悬停 tooltip、键盘焦点全都从主题白拿，自己画等于把这些重写一遍
# Real Buttons, so the four states and the tooltip come from the theme for free.
# 连线走本节点的 _draw()：Control 先画自己再画子节点，所以线天然在按钮底下
# Connectors go in _draw(): a Control paints itself before its children, so lines sit under.

## 节点方块的边长。52 是 256 宽的面板放得下五列的上限
## 52px is what a 256-wide panel can fit five columns of.
const NODE_SIZE: Vector2 = Vector2(52, 52)
## 列 0~4，2 是正中 / column 2 is the centre
const CENTRE_COLUMN: float = 2.0

## 列距 / 层距 / column and row pitch
@export var pitch: Vector2 = Vector2(44.0, 70.0)
## 树上的所有节点，顺序无所谓 / order does not matter
@export var nodes: Array[GeneNode] = []

## 点数读数那个 Label。留空就不管它 / optional, left blank means "not mine to update"
@export var points_label: NodePath

@export_group("Connectors")
## 两端都解锁了 / both ends unlocked
@export var linked_color: Color = Color(0.2627, 0.1608, 0.1961, 0.9)
## 下一个能点的 / the next one you could take
@export var open_color: Color = Color(0.7725, 0.4039, 0.1608, 0.9)
## 还轮不到 / still out of reach
@export var locked_color: Color = Color(0.2627, 0.1608, 0.1961, 0.22)
@export_range(1.0, 8.0, 0.5) var line_width: float = 3.0

var _bank: GeneBank = null
var _buttons: Dictionary = {}   ## id -> Button
var _by_id: Dictionary = {}     ## id -> GeneNode


func _ready() -> void:
	for node in nodes:
		if node != null and node.id != &"":
			_by_id[node.id] = node

	custom_minimum_size.y = _tree_height()
	_build()
	resized.connect(_layout)

	_bank = GeneBank.find(get_tree())
	if _bank == null:
		push_warning("GeneTree found no GeneBank, the panel is inert")
	else:
		_bank.points_changed.connect(func(_p): _refresh())
		_bank.rank_changed.connect(func(_i, _r): _refresh())
	_layout()
	_refresh()


func _tree_height() -> float:
	var rows: int = 0
	for node in nodes:
		if node != null:
			rows = maxi(rows, node.cell.y)
	return float(rows) * pitch.y + NODE_SIZE.y


func _build() -> void:
	for node in nodes:
		if node == null or _buttons.has(node.id):
			continue
		var button: Button = Button.new()
		button.name = String(node.id)
		button.text = node.display_name
		button.custom_minimum_size = NODE_SIZE
		button.size = NODE_SIZE
		button.clip_text = true
		button.pressed.connect(_on_pressed.bind(node))

		# 等级贴在方块右下角。画在 _draw() 里会被按钮的底盖住，所以做成子节点
		# A child, not a _draw() call: the button's stylebox would paint over it.
		var rank: Label = Label.new()
		rank.name = "Rank"
		rank.add_theme_font_size_override("font_size", 9)
		rank.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		rank.offset_top = -14.0
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(rank)

		add_child(button)
		_buttons[node.id] = button


# 面板宽度变了要重排。位置是相对面板中心算的，不能在 _ready 里定死——
# 那时 size 还是 0
# Positions are relative to the panel centre, which is not known on the first frame.
func _layout() -> void:
	for node in nodes:
		var button: Button = _buttons.get(node.id) as Button
		if button != null:
			button.position = _position_of(node)
	queue_redraw()


func _position_of(node: GeneNode) -> Vector2:
	var centre_x: float = size.x * 0.5 + (float(node.cell.x) - CENTRE_COLUMN) * pitch.x
	return Vector2(centre_x - NODE_SIZE.x * 0.5, float(node.cell.y) * pitch.y)


func _centre_of(node: GeneNode) -> Vector2:
	return _position_of(node) + NODE_SIZE * 0.5


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

		# 点满的和还够不着的都是 disabled，长得一样玩家就分不出"我有了"和"轮不到"。
		# 给已经拿到的那些盖一层 pressed 的样式（橙边），"拿到了"才读得出来
		# Both states are disabled; without this, owning a node looks like being locked out.
		if rank > 0:
			button.add_theme_stylebox_override("disabled", get_theme_stylebox("pressed", "Button"))
		else:
			button.remove_theme_stylebox_override("disabled")

		button.tooltip_text = _tooltip_for(node, rank)

		var rank_label: Label = button.get_node_or_null(^"Rank") as Label
		if rank_label != null:
			# 点满了写 MAX，点过没满写 +N，一次都没点就不占位
			# MAX when capped, +N part-way, nothing at all when untouched.
			if rank >= node.max_rank and rank > 0:
				rank_label.text = "MAX"
			elif rank > 0:
				rank_label.text = "+%d" % rank
			else:
				rank_label.text = ""
	queue_redraw()


# 悬浮说明的内容。等级会变，所以每次 refresh 重写，不能在建按钮时写死
# Rebuilt on every refresh: the rank line changes as the player spends points.
func _tooltip_for(node: GeneNode, rank: int) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(node.display_name if node.description.is_empty() else node.description)
	if node.max_rank > 1:
		lines.append("Rank %d / %d" % [rank, node.max_rank])
	if rank >= node.max_rank:
		lines.append("Taken.")
	elif not _bank.is_available(node):
		lines.append("Needs the branch above it.")
	elif _bank.points < node.cost:
		lines.append("Costs %d - you have %d." % [node.cost, _bank.points])
	else:
		lines.append("Costs %d." % node.cost)
	return "
".join(lines)


func _draw() -> void:
	for node in nodes:
		if node == null:
			continue
		var to: Vector2 = _centre_of(node)
		for req in node.requires:
			var parent: GeneNode = _by_id.get(req) as GeneNode
			if parent == null:
				continue
			draw_line(_centre_of(parent), to, _link_color(parent, node), line_width)


func _link_color(parent: GeneNode, child: GeneNode) -> Color:
	if _bank == null:
		return locked_color
	if _bank.is_unlocked(child.id):
		return linked_color
	if _bank.is_available(child):
		return open_color
	return locked_color
