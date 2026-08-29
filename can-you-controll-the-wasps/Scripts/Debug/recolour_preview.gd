@tool
class_name RecolourPreview
extends Node2D

# 调色预览 / recolour bench: 把 recolour.gdshader 铺成一张对照网格，在编辑器里直接看。
# 每行一张贴图，第一列是原图不上色，后面每列一个血统。改 Inspector 上的参数立刻重排。
# Rows are textures, column 0 is the untouched art, the rest are lineages.
#
# 单纯的看板，不进 world.tscn，也不碰 VariantComponent。确认参数之后再谈接线。
# A bench, not a feature - nothing else in the game loads this scene.

const SHADER: Shader = preload("res://Assets/Shaders/recolour.gdshader")

# 路径写死而不是 @export 资源：@tool 脚本在编辑器扫描阶段就跑，
# 少一个能填错的槽 / hard-coded so the bench cannot be pointed at nothing by accident
#
# 每行自带 reference 和 window，因为那是**贴图自己的属性**，不是调优参数：
# 蜂和幼虫的主色是 #fecf75，而巢室那一帧里的卵是青的（画成青只为了让 shader
# 能把卵和巢室分开，玩家看不到这个青）。egg.png 不在这儿——它 visible = false，
# 从来没上过屏，游戏里的卵是 Cells.png 的 frame 4。
# The egg row is a frame of the cell sheet; egg.png itself never reaches the screen.
#
# 两张蜂图规格一致（512x384，8x6），都取 fly 的第一帧，所以同一列上下就是
# 「同一个血统下正邪两张脸」。evil 多的那对红色（H 10~16）落在色相窗口里，
# 会跟着血统走——这是想要的，红眼不做保护。
# Both sheets share the layout, so a column reads as one lineage on two faces.
const ROWS: Array[Dictionary] = [
	{
		&"path": "res://Assets/Entities/good_wasp.png",
		&"label": "good_wasp (fly)",
		&"hframes": 8,
		&"vframes": 6,
		&"reference": Color(0.996, 0.812, 0.459),  # #fecf75
		&"window": 30.0,
	},
	{
		&"path": "res://Assets/Entities/evil_wasp.png",
		&"label": "evil_wasp (fly)",
		&"hframes": 8,
		&"vframes": 6,
		&"reference": Color(0.996, 0.812, 0.459),  # 图里是 #ffd075，同一族 / same family
		&"window": 30.0,
	},
	{
		&"path": "res://Assets/Entities/Cells.png",
		&"label": "Cells.png frame 4 (egg)",
		&"hframes": 8,
		&"frame": 4,
		&"reference": Color(0.459, 0.941, 0.996),  # #75f0fe，图里那个青
		&"window": 40.0,
	},
	{
		&"path": "res://Assets/Entities/larva.png",
		&"reference": Color(0.996, 0.812, 0.459),
		&"window": 30.0,
	},
]

## 不带血统时该长什么样。卵那行的这一列就是玩家看到的「正常卵」
## What it looks like with no lineage - for the egg row, the ordinary egg players see.
const NEUTRAL: Color = Color(0.996, 0.812, 0.459)  # #fecf75
const DEFAULT_VARIANTS: PackedStringArray = [
	"res://Resources/Variants/pure.tres",
	"res://Resources/Variants/crimson.tres",
	"res://Resources/Variants/violet.tres",
	"res://Resources/Variants/teal.tres",
	"res://Resources/Variants/lime.tres",
]

@export_group("Shader")
## 覆盖每行自带的色相窗口，-1 = 用各行自己的 / -1 keeps each row's own window
@export_range(-1.0, 180.0, 1.0) var hue_window_override: float = -1.0: set = _set_hue_window
## 窗口边缘的软过渡 / falloff at the edge of the window
@export_range(0.0, 60.0, 1.0) var hue_softness: float = 10.0: set = _set_hue_softness
## 低于这个饱和度的不换（头和高光）/ neutrals below this stay put
@export_range(0.0, 1.0, 0.01) var min_saturation: float = 0.25: set = _set_min_saturation
## 明度跟随目标色的程度。1 会让 Teal 那种暗血统整只暗一截
@export_range(0.0, 1.0, 0.01) var value_follow: float = 1.0: set = _set_value_follow

@export_group("Layout")
@export_range(48.0, 320.0, 4.0) var cell_size: float = 150.0: set = _set_cell_size
## 每格贴图放大几倍，像素图看细节用 / zoom, these are 32-64px sprites
@export_range(0.5, 6.0, 0.5) var zoom: float = 2.0: set = _set_zoom
## 画一条血统色本身的色块，方便对比「染出来的」和「色值」/ swatch of the raw body_color
@export var show_swatches: bool = true: set = _set_show_swatches

var _grid: Node2D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if _grid != null and is_instance_valid(_grid):
		_grid.free()  # queue_free 在编辑器里要等一帧，重排会叠影 / free now, not next frame
	_grid = Node2D.new()
	add_child(_grid)

	var variants: Array[WaspVariant] = _load_variants()

	# 列：原图 / 不带血统 / 五个血统。第二列对卵这行尤其要紧——
	# 图里那个青是给 shader 用的锚点，玩家看到的是这一列
	# Column 1 is what players actually see; the raw art is only an anchor for the shader.
	var columns: Array[Dictionary] = [{&"name": "art", &"tint": Color.TRANSPARENT}]
	columns.append({&"name": "normal", &"tint": NEUTRAL})
	for v in variants:
		columns.append({&"name": v.display_name, &"tint": v.body_color})

	if show_swatches:
		_add_label("colour", Vector2(-cell_size, -cell_size * 0.55))
	for i in columns.size():
		var col: Dictionary = columns[i]
		var x: float = cell_size * float(i)
		_add_label(String(col[&"name"]), Vector2(x, -cell_size * 0.85))
		if show_swatches and i > 0:
			_add_swatch(col[&"tint"], Vector2(x, -cell_size * 0.55))

	var row_y: float = 0.0
	for row in ROWS:
		var path: String = row[&"path"]
		var tex: Texture2D = load(path) as Texture2D
		if tex == null:
			push_warning("RecolourPreview: missing texture %s" % path)
			continue

		var label: String = row.get(&"label", path.get_file())
		_add_label(label, Vector2(-cell_size, row_y + cell_size * 0.28))
		for i in columns.size():
			var tint: Color = columns[i][&"tint"]
			var mat: ShaderMaterial = null if i == 0 else _make_material(row, tint)
			_add_sprite(tex, row, mat, Vector2(cell_size * float(i), row_y + cell_size * 0.28))
		row_y += cell_size * 1.3


func _load_variants() -> Array[WaspVariant]:
	var out: Array[WaspVariant] = []
	for path in DEFAULT_VARIANTS:
		var v: WaspVariant = load(path) as WaspVariant
		if v != null:
			out.append(v)
		else:
			push_warning("RecolourPreview: missing variant %s" % path)
	return out


# 每格一份材质。ShaderMaterial 是共享 Resource，共用一份的话最后一个 tint 会赢
# One material per cell - sharing one would leave every sprite on the last tint set.
func _make_material(row: Dictionary, tint: Color) -> ShaderMaterial:
	var window: float = row[&"window"]
	if hue_window_override >= 0.0:
		window = hue_window_override
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter(&"reference", row[&"reference"])
	mat.set_shader_parameter(&"tint", tint)
	mat.set_shader_parameter(&"hue_window", window)
	mat.set_shader_parameter(&"hue_softness", hue_softness)
	mat.set_shader_parameter(&"min_saturation", min_saturation)
	mat.set_shader_parameter(&"value_follow", value_follow)
	mat.set_shader_parameter(&"strength", 1.0)
	return mat


func _add_sprite(tex: Texture2D, row: Dictionary, mat: ShaderMaterial, at: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = tex
	s.hframes = row.get(&"hframes", 1)
	s.vframes = row.get(&"vframes", 1)
	s.frame = row.get(&"frame", 0)
	s.material = mat
	s.position = at
	s.scale = Vector2.ONE * zoom
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 像素图别糊 / pixel art stays crisp
	_grid.add_child(s)


func _add_swatch(color: Color, at: Vector2) -> void:
	var r := ColorRect.new()
	r.color = color
	r.size = Vector2(cell_size * 0.5, cell_size * 0.22)
	r.position = at - r.size * 0.5
	_grid.add_child(r)


func _add_label(text: String, at: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.size = Vector2(cell_size, 20.0)
	l.position = at - Vector2(cell_size * 0.5, 10.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grid.add_child(l)


func _set_hue_window(v: float) -> void:
	hue_window_override = v
	_rebuild()


func _set_hue_softness(v: float) -> void:
	hue_softness = v
	_rebuild()


func _set_min_saturation(v: float) -> void:
	min_saturation = v
	_rebuild()


func _set_value_follow(v: float) -> void:
	value_follow = v
	_rebuild()


func _set_cell_size(v: float) -> void:
	cell_size = v
	_rebuild()


func _set_zoom(v: float) -> void:
	zoom = v
	_rebuild()


func _set_show_swatches(v: bool) -> void:
	show_swatches = v
	_rebuild()
