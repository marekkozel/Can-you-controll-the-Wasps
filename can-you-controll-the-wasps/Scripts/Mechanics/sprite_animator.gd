@tool
class_name SpriteAnimator
extends Node

# 图集逐帧动画 / sprite-sheet animation. 挂到实体下，每帧推的是 Sprite2D.frame。
#
# @tool：这样 AnimationPreview 那张看板能在编辑器里直接播，而且打开 Wasp.tscn
# 就能看到蜂在扇翅膀。没有 preload，不碰 GDExtension 场景，不会踩 HexCell 那个坑。
# Runs in the editor so the bench can play - and so Wasp.tscn shows a moving wasp.
#
# **故意不用 AnimatedSprite2D。** 血统色（VariantComponent._tint）、选中描边
# （OutlineComponent）和 JuiceComponent.flash 三处都拿 `as Sprite2D` 说话，
# 换节点类型的话前两个会返回 null 静默失效——正是这个项目最难查的那类 bug。
# Never AnimatedSprite2D: three systems type-check on Sprite2D and would fail silently.

## 推哪个 sprite / the sprite this drives
@export var sprite_path: NodePath = ^"../Visual/Body"
## 动画表。切图行列也从这里读，场景里不用再填一遍 / the table, grid included
@export var animation: SpriteAnimation

@export_group("Speed")
## 循环段跟着移动速度快慢。悬停的蜂跟巡航的蜂扇一样快很假
## Looping clips ride on the body's speed - a hovering wasp should not beat as fast.
@export var speed_scales_rate: bool = true
## 到这个速度就是资源里写的原速 / px/s at which a clip runs at its authored fps
@export_range(10.0, 400.0, 5.0) var cruise_speed: float = 90.0
## 完全静止时的倍率 / rate multiplier at a dead stop
@export_range(0.05, 1.0, 0.05) var idle_rate: float = 0.45

var _sprite: Sprite2D = null
## 可能持有已释放的对象，别加类型 / never typed: the parent may already be gone
var _mover = null
var _clip: SpriteClip = null
var _elapsed: float = 0.0


func _ready() -> void:
	if not _resolve():
		push_warning("SpriteAnimator found no Sprite2D at %s" % sprite_path)
		set_process(false)
		return

	var parent: Node = get_parent()
	if parent != null and "linear_velocity" in parent:
		_mover = parent

	# 场景里没接资源不算错：敌人三种体型共用 Enemy.tscn，动画是 EnemyVariant 在
	# _apply_build() 里推进来的，比这里晚 / the enemy's sheet arrives from its variant
	set_animation(animation)


# 换一整张表。敌人走这条：品种决定用哪张图集，而品种是父级 _ready 时才读到的
# Swap the whole sheet - the enemy's breed picks it, and that lands after our _ready.
func set_animation(next: SpriteAnimation) -> void:
	animation = next
	_clip = null
	# 懒解析：调用方可能在 _ready 之前就把表推进来了（看板就是这么用的）
	# Resolve lazily - the caller may hand us a table before our own _ready has run.
	if not _resolve() or animation == null:
		set_process(false)
		return

	# 运行时以资源为准。场景里那份切图只是给编辑器看的——不填的话 Body 在编辑器里
	# 是一整张图集，摆位置完全没法看
	# The resource wins at runtime; the scene's copy exists so the editor shows one cel.
	_sprite.hframes = animation.hframes
	_sprite.vframes = animation.vframes
	_validate()
	set_process(true)
	_play_default()


# 数错一行一列是改动画表最容易犯的错，而 Sprite2D.frame 越界会**每帧**往控制台喷红字，
# 光看报错完全指不到是哪个 .tres 的哪一段。这里换成一句说清楚的警告，画面上截断了事。
# Miscounting a row is the easy mistake; an out-of-range frame would spam every tick.
func _validate() -> void:
	var cels: int = animation.hframes * animation.vframes
	for clip in animation.clips:
		if clip == null:
			continue
		var last: int = clip.row * animation.hframes + clip.start_column + clip.frames - 1
		if last >= cels:
			push_warning("SpriteAnimation clip '%s' runs past the sheet: row %d + %d frames needs %d cels, the sheet has %d" 				% [clip.name, clip.row, clip.frames, last + 1, cels])
	if animation.find(animation.default_clip) == null:
		push_warning("SpriteAnimation default_clip '%s' is not in the clips list" % animation.default_clip)


# 换段。restart 关着的时候重复点同一段不会打断它 / re-asking for the current clip is a no-op
func play(clip_name: StringName, restart: bool = false) -> void:
	if animation == null:
		return
	var next: SpriteClip = animation.find(clip_name)
	if next == null:
		push_warning("SpriteAnimator has no clip named '%s'" % clip_name)
		return
	if next == _clip and not restart:
		return
	_clip = next
	_elapsed = 0.0
	set_process(true)  # hold_last 停过之后要叫醒 / a held clip switched us off
	_draw_frame(0)


func current_clip() -> StringName:
	return _clip.name if _clip != null else &""


# 这一段播完要多久。死亡动画拿它给淡出补个延迟 / how long a clip runs, in seconds
func clip_duration(clip_name: StringName) -> float:
	if animation == null:
		return 0.0
	var clip: SpriteClip = animation.find(clip_name)
	if clip == null:
		return 0.0
	return float(clip.frames) / clip.fps


func has_clip(clip_name: StringName) -> bool:
	return animation != null and animation.find(clip_name) != null


# 相对路径不需要节点已经进 SceneTree，沿着父子链走就行——加了 is_inside_tree()
# 反而会把"还没进树就先配置"这条路堵死，而看板正好走那条
# Relative paths resolve on a detached subtree; gating on is_inside_tree() would break the bench.
func _resolve() -> bool:
	if _sprite == null:
		_sprite = get_node_or_null(sprite_path) as Sprite2D
	return _sprite != null


func _play_default() -> void:
	play(animation.default_clip)


func _process(delta: float) -> void:
	advance(delta)


# 推进一帧。单独开出来是给 AnimationPreview 用的——看板自己关掉组件的 _process
# 再按自己的倍率喂进来，暂停和慢放就都是免费的，而且播的是同一份代码
# Split out so the bench can drive it at its own rate: previewing the shipping code.
func advance(delta: float) -> void:
	if _clip == null or _sprite == null:
		return

	_elapsed += delta * _rate()
	# 加个 epsilon 再截断。60fps 跑 12fps 的段时 _elapsed 会累出 0.58333...，
	# 乘回去是 6.99999 —— 直接截断的话第 7 帧每一轮都被跳过，而且是稳定跳过
	# Truncation alone drops a frame every loop whenever delta divides the clip's rate.
	var index: int = int(_elapsed * _clip.fps + 0.0001)

	if index >= _clip.frames:
		if _clip.hold_last:
			# 停在最后一帧不再动。尸体就该保持死的样子 / a corpse stays dead
			_draw_frame(_clip.frames - 1)
			set_process(false)
			return
		if not _clip.loop:
			# 一次性段播完就回默认段。攻击动作就是这么接回飞行的
			# One-shot clips hand back to the default - this is how a sting returns to flight.
			_draw_frame(_clip.frames - 1)
			_play_default()
			return
		index %= _clip.frames
		_elapsed = fmod(_elapsed, float(_clip.frames) / _clip.fps)

	_draw_frame(index)


# 一次性段不减速：攻击慢放会跟冷却时间对不上 / one-shots run at full rate or they desync from the cooldown
func _rate() -> float:
	if not speed_scales_rate or not _clip.loop or not is_instance_valid(_mover):
		return 1.0
	var speed: float = (_mover.linear_velocity as Vector2).length()
	return lerpf(idle_rate, 1.0, clampf(speed / cruise_speed, 0.0, 1.0))


func _draw_frame(index: int) -> void:
	if _sprite == null:
		return
	# 截断而不是让 Sprite2D 报错。表写错了 _validate() 已经喊过一次了
	# Clamped, not asserted: _validate() already said which clip is wrong, once.
	_sprite.frame = mini(_clip.row * animation.hframes + _clip.start_column + index,
		animation.hframes * animation.vframes - 1)
