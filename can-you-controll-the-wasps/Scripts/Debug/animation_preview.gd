@tool
class_name AnimationPreview
extends Node2D

# 动画看板 / animation bench: 把 Resources/Animations/ 下每张表的每一段铺成网格，
# 在编辑器里就地循环播。改 .tres 里的 fps 或帧数，存一下就能看到，不用跑游戏。
# Edit a clip's fps or frame count, save, and watch it here - no play session needed.
#
# 单纯的看板，不进 world.tscn。跟 RecolourPreview 一个路子。
# A bench, not a feature - nothing else in the game loads this scene.
#
# **播的是真正的 SpriteAnimator**，不是另写一遍。看板只负责摆位置和喂 delta，
# 所以这里看到的循环就是游戏里跑的那个循环
# The real component does the playback; this only lays it out and feeds it time.

const VARIANTS_DIR: String = "res://Resources/Variants/"

# 黄蜂那张表在 Wasp.tscn 上，而 **@tool 脚本绝对不能 load Wasp.tscn**——它含 BTPlayer，
# 编辑器扫描阶段拿到的是个 node count 为 0 的空壳。所以这一行是写死的贴图路径。
# 敌人不用写：EnemyVariant 本身就同时拿着 texture 和 animation，直接扫目录。
# Never load Wasp.tscn from a @tool script; enemy breeds carry both halves themselves.
const EXTRA_ROWS: Array[Dictionary] = [
	{
		&"label": "Wasp",
		&"texture": "res://Assets/Entities/good_wasp.png",
		&"table": "res://Resources/Animations/wasp.tres",
	},
]

@export_group("Playback")
## 关掉就停在当前帧 / pause where it is
@export var playing: bool = true: set = _set_playing
## 慢放看单帧，0.25 左右比较好数 / slow it down to count frames
@export_range(0.1, 2.0, 0.05) var rate: float = 1.0

@export_group("Layout")
@export_range(80.0, 400.0, 10.0) var cell_size: float = 150.0: set = _set_cell_size
## 在自适应缩放之上再乘一道。螳螂一格 256、蚂蚁一格 32，先各自缩到格子里再统一放大
## Cels run 32 to 256 px, so each is fitted to the cell first and this scales on top.
@export_range(0.25, 4.0, 0.25) var zoom: float = 1.0: set = _set_zoom
## 每格底下写清楚这段是哪一行、几帧、多少 fps / row, frame count and fps under each cell
@export var show_readout: bool = true: set = _set_show_readout

## 一次性段播完歇多久再重来。不留这个间隔的话攻击段接得太紧，看不出起止在哪
## A beat between repeats, or a one-shot reads as an unbroken loop.
const REPLAY_DWELL: float = 0.45

var _grid: Node2D
## 每格一条：{anim, clip, loop, duration, waited} / one row per cell
var _cells: Array[Dictionary] = []


func _ready() -> void:
	_rebuild()


func _process(delta: float) -> void:
	if not playing:
		return
	var step: float = delta * rate
	for cell in _cells:
		var anim: SpriteAnimator = cell[&"anim"]
		if not is_instance_valid(anim):
			continue
		anim.advance(step)
		if cell[&"loop"]:
			continue

		# 一次性段在这里是停在最后一帧的（见 _solo_table），歇一拍再从头来
		# One-shots hold their last frame here, then restart after a beat.
		cell[&"waited"] = float(cell[&"waited"]) + step
		if float(cell[&"waited"]) >= float(cell[&"duration"]) + REPLAY_DWELL:
			anim.play(cell[&"clip"], true)
			cell[&"waited"] = 0.0


func _rebuild() -> void:
	if _grid != null and is_instance_valid(_grid):
		_grid.free()  # queue_free 在编辑器里要等一帧，重排会叠影 / free now, not next frame
	_grid = Node2D.new()
	add_child(_grid)
	_cells.clear()

	var row_y: float = 0.0
	for row in _collect_rows():
		var table: SpriteAnimation = row[&"table"]
		var texture: Texture2D = row[&"texture"]
		_add_label(String(row[&"label"]), Vector2(-cell_size * 0.9, row_y), 13)

		var column: int = 0
		for clip in table.clips:
			if clip == null:
				continue
			var at := Vector2(cell_size * float(column), row_y)
			_add_cell(texture, table, clip, at)
			column += 1
		row_y += cell_size * 1.15


# 敌人扫目录，黄蜂走写死的那条。加一种敌人只要多一个 EnemyVariant，这里自己会长出来
# Breeds are discovered, so a new enemy shows up here without touching this bench.
func _collect_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []

	for row in EXTRA_ROWS:
		var table: SpriteAnimation = load(String(row[&"table"])) as SpriteAnimation
		var texture: Texture2D = load(String(row[&"texture"])) as Texture2D
		if table == null or texture == null:
			push_warning("AnimationPreview: missing %s" % row[&"label"])
			continue
		rows.append({&"label": row[&"label"], &"table": table, &"texture": texture})

	var names: PackedStringArray = DirAccess.get_files_at(VARIANTS_DIR)
	names.sort()
	for file in names:
		if not file.ends_with(".tres"):
			continue
		var breed: EnemyVariant = load(VARIANTS_DIR + file) as EnemyVariant
		# 没接动画表的品种还是静态图，没什么可看的 / a still image has nothing to play
		if breed == null or breed.animation == null or breed.texture == null:
			continue
		rows.append({
			&"label": breed.display_name,
			&"table": breed.animation,
			&"texture": breed.texture,
		})

	return rows


func _add_cell(texture: Texture2D, table: SpriteAnimation, clip: SpriteClip, at: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = at
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 像素图别糊 / pixel art stays crisp
	_grid.add_child(sprite)

	# 一格一格差着十倍大小，不各自缩到格子里的话螳螂会盖住半张看板
	# Cels run 32 to 256 px; without a per-row fit the mantis covers half the bench.
	var cel: float = maxf(texture.get_size().x / float(table.hframes),
		texture.get_size().y / float(table.vframes))
	sprite.scale = Vector2.ONE * (cell_size * 0.55 / maxf(cel, 1.0)) * zoom

	var anim := SpriteAnimator.new()
	anim.sprite_path = ^".."         # 组件挂在 sprite 底下 / parented under the sprite it drives
	anim.speed_scales_rate = false   # 看板看的是资源里写的 fps，别掺移动速度 / authored fps only
	sprite.add_child(anim)
	anim.set_animation(_solo_table(table, clip))
	anim.play(clip.name, true)
	anim.set_process(false)          # 由看板统一喂 delta / the bench owns the clock
	_cells.append({
		&"anim": anim,
		&"clip": clip.name,
		&"loop": clip.loop,
		&"duration": anim.clip_duration(clip.name),
		&"waited": 0.0,
	})

	if not show_readout:
		return
	var loop_note: String = "loop" if clip.loop else ("hold" if clip.hold_last else "once")
	_add_label(String(clip.name), at + Vector2(0.0, cell_size * 0.34), 12)
	_add_label("row %d  x%d  @%.0ffps  %s" % [clip.row, clip.frames, clip.fps, loop_note],
		at + Vector2(0.0, cell_size * 0.46), 10)


# 每格一张只有这一段的表。一次性段在游戏里播完会掉回默认段，看板上那会让攻击格
# 每隔几秒闪一下走路——这里改成停在最后一帧，重播的节奏由看板自己掌握。
# 改的是复制品，原始 .tres 一个字节都不碰。
# A one-shot would hand back to the default clip and flicker the attack cell into its
# walk cycle. This copy holds instead; the shipped .tres is never touched.
func _solo_table(table: SpriteAnimation, clip: SpriteClip) -> SpriteAnimation:
	var only: SpriteClip = clip.duplicate() as SpriteClip
	only.hold_last = not only.loop

	var solo := SpriteAnimation.new()
	solo.hframes = table.hframes
	solo.vframes = table.vframes
	solo.clips = [only] as Array[SpriteClip]
	solo.default_clip = only.name
	return solo


func _add_label(text: String, at: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	label.size = Vector2(cell_size, 18.0)
	label.position = at - Vector2(cell_size * 0.5, 9.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grid.add_child(label)


func _set_playing(value: bool) -> void:
	playing = value


func _set_cell_size(value: float) -> void:
	cell_size = value
	_rebuild()


func _set_zoom(value: float) -> void:
	zoom = value
	_rebuild()


func _set_show_readout(value: bool) -> void:
	show_readout = value
	_rebuild()
