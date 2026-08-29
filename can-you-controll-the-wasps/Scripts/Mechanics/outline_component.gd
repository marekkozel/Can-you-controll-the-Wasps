class_name OutlineComponent
extends Node

# 选中描边 / selection outline. 自己造一张描边 sprite，插在源 sprite 前面。
# 状态由 SelectionDirector 推过来，这里只管画 / the director decides, this only draws.
#
# 造节点而不是在每个场景里手摆：贴图、offset、centered 都从源 sprite 抄，
# 加一种实体只要挂上组件、指对 source_path，不会漏掉幼虫那种 offset=(1,-14) 的补正
# Built in code so texture/offset/centered are copied, never re-authored per scene.
#
# 插进源 sprite 的**父节点**里，正好排在它前面——这样 JuiceComponent 的 punch / shake
# 作用在 Visual 上时，描边跟本体一起动，不用自己同步一个字
# Parented alongside the source so the juice transforms carry both for free.

const OUTLINE_SHADER: Shader = preload("res://Assets/Shaders/outline.gdshader")

enum State { NONE, HOVER, HELD }

## 描什么 / the sprite to trace
@export var source_path: NodePath = ^"../Visual/Body"

@export_group("Look")
## 中性色。**不要**接血统色——见 shader 里那条红线 / neutral, never the lineage colour
@export var color: Color = Color(1.0, 0.902, 0.502)
@export_range(0.0, 8.0, 0.5) var hover_width: float = 1.0
@export_range(0.0, 8.0, 0.5) var held_width: float = 2.0
@export_range(0.0, 1.0, 0.05) var hover_alpha: float = 0.55
@export_range(0.0, 1.0, 0.05) var held_alpha: float = 1.0

var state: int = State.NONE

var _source: Sprite2D = null
var _sprite: Sprite2D = null
var _material: ShaderMaterial = null
## 上一次画的是图集第几帧，-1 = 还没画过 / last traced atlas frame
var _frame: int = -1
## 上一次看到的切图行列。SpriteAnimator 的 _ready 可能比这里晚，切图是后写上去的，
## 只盯 frame 的话会一直停在"整张图"那个 region / the grid can arrive after our _ready
var _grid: Vector2i = Vector2i.ZERO


func _ready() -> void:
	set_process(false)
	_source = get_node_or_null(source_path) as Sprite2D
	if _source == null:
		push_warning("OutlineComponent found no sprite at %s" % source_path)
		return
	_build()


func set_state(next: int) -> void:
	if state == next:
		return
	state = next
	_apply()


func _build() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Outline"
	_sprite.texture = _source.texture
	_sprite.centered = _source.centered
	_sprite.offset = _source.offset
	_sprite.scale = _source.scale
	_sprite.flip_h = _source.flip_h
	_sprite.flip_v = _source.flip_v
	# 描边这张**不切图集**：它每帧自己算 region，把当前帧连同外扩的一圈框出来，
	# 界外由 shader 的 frame_min/max 判成空气 / it frames the current cel itself
	# 排在本体后面。描边只画轮廓外，压在上面会盖住本体的边缘像素
	# Behind the body: the ring sits outside the silhouette and must not cover its rim.
	_sprite.z_index = -1
	_sprite.visible = false

	# ShaderMaterial 是共享 Resource，跟 DragProfile 一个坑——每个实体自己 new 一份，
	# 不然最后一只设的宽度会赢 / one material per entity or the last width wins everywhere
	_material = ShaderMaterial.new()
	_material.shader = OUTLINE_SHADER
	_material.set_shader_parameter(&"outline_color", color)
	_sprite.material = _material
	_expand(_sprite)

	var host: Node = _source.get_parent()
	host.add_child(_sprite)
	host.move_child(_sprite, _source.get_index())


# Sprite2D 只画一帧那么大的四边形，往外扩的描边像素会被裁掉。
# good_wasp.png 每一格的美术都顶到格子边（飞行那几帧左边缘就是 x=0，攻击那几帧顶到右边），
# 不撑开的话那两侧的描边根本没地方画。用 region 把绘制矩形各边扩出去，
# 扩出来的一圈会盖到隔壁帧上，所以 shader 拿 frame_min/max 把它判成空气。
# The sprite only draws its own cel; the art touches the cel edge, so the ring needs room.
func _expand(sprite: Sprite2D) -> void:
	if _source.region_enabled:
		# 源图本来就用 region 的话得跟它复合，现在没有这种用法，先喊一声
		push_warning("OutlineComponent cannot expand a sprite that already uses a region (%s)" % _source.name)
		return
	if _source.texture == null:
		return
	sprite.region_enabled = true
	_frame = -1
	_sync_frame()


func _pad() -> float:
	return ceilf(maxf(hover_width, held_width)) + 1.0


# 把绘制矩形从当前帧往外扩一圈，并告诉 shader 这一帧的 UV 界在哪。
# 整张图的情况就是"只有一帧"，走的是同一条路 / a whole texture is just the one-frame case
func _sync_frame() -> void:
	if _sprite == null or _source.texture == null:
		return
	var cols: int = maxi(_source.hframes, 1)
	var rows: int = maxi(_source.vframes, 1)
	var grid: Vector2i = Vector2i(cols, rows)
	var frame: int = _source.frame if _is_atlas() else 0
	if frame == _frame and grid == _grid:
		return
	_frame = frame
	_grid = grid

	var sheet: Vector2 = _source.texture.get_size()
	var cel: Vector2 = Vector2(sheet.x / float(cols), sheet.y / float(rows))
	var origin: Vector2 = Vector2(float(frame % cols), float(frame / cols)) * cel

	var pad: float = _pad()
	# 四边等量外扩，中心不动，所以 centered / offset 都不用补 / symmetric, so the pivot holds
	_sprite.region_rect = Rect2(origin - Vector2(pad, pad), cel + Vector2(pad, pad) * 2.0)
	if _material != null:
		_material.set_shader_parameter(&"frame_min", origin / sheet)
		_material.set_shader_parameter(&"frame_max", (origin + cel) / sheet)


func _is_atlas() -> bool:
	return _source.hframes > 1 or _source.vframes > 1


func _apply() -> void:
	if _sprite == null:
		return
	var on: bool = state != State.NONE
	_sprite.visible = on
	set_process(on)
	if not on:
		return
	_sync_frame()
	_material.set_shader_parameter(&"outline_width", held_width if state == State.HELD else hover_width)
	_material.set_shader_parameter(&"fade", held_alpha if state == State.HELD else hover_alpha)


# 只在亮着的时候跑。蜂按速度方向翻面，描边不跟着翻就会跟本体错开
# Only while lit: the wasp flips with its heading and the outline has to follow.
func _process(_delta: float) -> void:
	if _sprite == null or not is_instance_valid(_source):
		return
	_sprite.flip_h = _source.flip_h
	_sprite.flip_v = _source.flip_v
	_sprite.scale = _source.scale
	_sync_frame()
