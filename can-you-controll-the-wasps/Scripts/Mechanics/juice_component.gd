@tool
class_name JuiceComponent
extends Node2D

# 通用反馈效果 / feedback effects: punch, shake, flash, burst.
# 挂到实体下，target 指向要被缩放/抖动的那一层 / target is the layer that gets animated.
# 千万别把 target 指到 Area2D 上，命中区会跟着抖 / never target the Area2D, hitbox would shake.

## 被 punch / shake 作用的节点，一般是实体的 Visual 层 / usually the entity's Visual node.
## 在场景里连 NodePath 解析不出来，由持有方在 _ready() 里赋值 / assign it from code
@export var target: Node2D

## 抖动频率 Hz。逐帧取随机数等于 60Hz 白噪声，又刺又乱 / per-frame random reads as harsh noise,
## 所以走平滑正弦；x/y 频率错开，走小八字 / so use a smooth sine, x and y offset for a figure-eight
@export_range(0.5, 30.0, 0.5) var shake_frequency: float = 5.0

@export_group("Hit flash")
## 全白保持多久再开始退。**0 就等于没有**：EASE_OUT 第一帧就掉到一半，
## 眼睛接不住一帧的白 / without a hold the ease drops to half on frame one
@export_range(0.0, 0.5, 0.01) var hit_hold: float = 0.06
## 退回本色的时长 / how long the white takes to leave
@export_range(0.02, 1.0, 0.02) var hit_fade: float = 0.14
## 闪几下。一下会被迸粒子和击退盖过去，两下才读得出「它挨了一下」
## One blink hides under the burst and the knockback; two reads as a hit.
@export_range(1, 5, 1) var hit_pulses: int = 2
## 两下之间的间隔 / the dark beat between blinks
@export_range(0.0, 0.5, 0.01) var hit_gap: float = 0.05

## punch 回弹到的基准缩放。持有方体型不是 1 倍时必须写它，否则弹一下就被打回标准大小
## The scale punch springs back to. Any owner that is not 1x must set this, or every
## punch silently resets it to normal size.
var base_scale: Vector2 = Vector2.ONE:
	set(value):
		base_scale = value
		# 正在弹的时候改基准，让 tween 重新瞄准，不然这一次弹完还是回旧值
		# Re-aim a punch in flight, or this one still lands on the old baseline.
		if _punch_tween != null and _punch_tween.is_valid() and target != null:
			_punch_tween.kill()
			target.scale = base_scale

## 抖动幅度（像素），设 0 停止 / shake amplitude in px, 0 stops it
var shake_amount: float = 0.0:
	set(value):
		shake_amount = maxf(value, 0.0)
		if is_zero_approx(shake_amount):
			set_process(false)
			if target != null:
				target.position = _base_position
		else:
			if not is_processing():
				_base_position = target.position if target != null else Vector2.ZERO
				_shake_time = 0.0
			set_process(true)

var _base_position: Vector2 = Vector2.ZERO
var _shake_time: float = 0.0
var _punch_tween: Tween
var _flash_tween: Tween
## 闪白单开一条：它跟 flash() 动的不是同一个属性，互相 kill 没道理
## Its own tween - it drives a shader uniform, not the colour flash() owns.
var _hit_tween: Tween
var _bob_tween: Tween
## 点头的原点。连着点两下时不能拿当前位置当原点，否则第二下从半沉的地方起跳、回不去
## Never re-read position mid-bob: the second dip would start half-sunk and never return.
var _bob_home: Vector2 = Vector2.ZERO
var _bobbing: bool = false
## Burst 在场景里配好的颜色和数量，当基准 / the authored look, kept as the baseline
var _burst_color: Color = Color.WHITE
var _burst_amount: int = 18

@onready var _burst: CPUParticles2D = $Burst


func _ready() -> void:
	set_process(false)
	if _burst != null:
		_burst_color = _burst.color
		_burst_amount = _burst.amount


func _process(delta: float) -> void:
	if target == null:
		return
	_shake_time += delta * shake_frequency * TAU
	var offset: Vector2 = Vector2(sin(_shake_time), sin(_shake_time * 1.37 + 1.1)) * shake_amount
	target.position = _base_position + offset


# 缩放弹一下。amount < 1 是按下去，> 1 是弹出来 / <1 presses in, >1 pops out
func punch(amount: float = 1.15, duration: float = 0.25) -> void:
	if target == null or Engine.is_editor_hint():
		return
	if _punch_tween != null and _punch_tween.is_valid():
		_punch_tween.kill()
	# 乘基准而不是覆盖它：强化过的蜂本来就比标准大，弹一下不该把体型抹平
	# Multiply the baseline instead of replacing it - a bigger wasp must stay bigger.
	target.scale = base_scale * amount
	_punch_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_punch_tween.tween_property(target, "scale", base_scale, duration)


# 把 item 刷成 color 再退回 restore / flash to color, tween back to restore
func flash(item: CanvasItem, color: Color, restore: Color, duration: float = 0.45) -> void:
	if item == null or Engine.is_editor_hint():
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	# Polygon2D 有 color，Sprite2D 没有。巢室换成贴图之后这里一直在往控制台喷
	# "The tweened property color does not exist"，异色卵那一下闪光其实早就不亮了
	# Sprites have no `color`; since the cells became sprites this silently stopped working.
	# 贴图走 self_modulate，别用 modulate——后者会连子节点一起染
	var prop: String = "color" if "color" in item else "self_modulate"
	item.set(prop, color)
	_flash_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(item, prop, restore, duration)


# 受伤闪白 / hit flash. 走 shader uniform，不走 self_modulate——modulate 是乘法，
# 只能压暗，深色血统怎么乘都白不了。而一个 CanvasItem 只能挂一份 material，
# 所以这个参数是长在 recolour.gdshader 里的，没上过色的贴图自然就没这一下。
# Modulate multiplies and can only darken; with one material per CanvasItem the flash
# has to live inside the recolour shader rather than stack on top of it.
func hit_flash(item: CanvasItem, amount: float = 1.0) -> void:
	if item == null or Engine.is_editor_hint():
		return
	var mat: ShaderMaterial = item.material as ShaderMaterial
	if mat == null or mat.shader == null:
		return
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()

	var lit: float = clampf(amount, 0.0, 1.0)
	# 先落一个实数再建补间。**没设过的 uniform 读回来是 null**，不是 shader 里写的默认值，
	# 而 tween_property 拿不到类型就直接返回 null——闪白会卡在全白下不来
	# An unset uniform reads back as null, not as the shader's default, and tween_property
	# returns null when it cannot type the value. The flash then sticks on full white.
	mat.set_shader_parameter(&"flash_amount", lit)

	_hit_tween = create_tween()
	for i in maxi(hit_pulses, 1):
		if i > 0:
			_hit_tween.tween_interval(hit_gap)
		# 瞬间点亮、保持、再退。渐入渐出读起来像发光，不像挨了一下
		# Instant on, held, then eased off: fading in reads as a glow, not an impact.
		_hit_tween.tween_callback(mat.set_shader_parameter.bind(&"flash_amount", lit))
		_hit_tween.tween_interval(hit_hold)
		var fade: PropertyTweener = _hit_tween.tween_property(
				mat, "shader_parameter/flash_amount", 0.0, hit_fade)
		fade.from(lit).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# 闪色期间调用方别抢同一个颜色属性 / don't fight the flash tween over the same property
func is_flashing() -> bool:
	return _flash_tween != null and _flash_tween.is_valid()


# 点头 / bob: 沉下去再弹回来。接东西、吃东西是这个形状——
# punch 缩一下读起来是「被撞了」，不是「低头接过来」
# A dip and a spring back. A scale punch reads as being hit, not as taking something.
func bob(depth: float = 5.0, duration: float = 0.3) -> void:
	if target == null or Engine.is_editor_hint():
		return
	if _bob_tween != null and _bob_tween.is_valid():
		_bob_tween.kill()
	# shake 也在每帧写 target.position，同时开的话两边打架。抖动开着就以它的基准为准
	# shake writes target.position every frame; defer to its baseline when it is running.
	if not _bobbing:
		_bob_home = _base_position if is_processing() else target.position
		_bobbing = true

	_bob_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bob_tween.tween_property(target, "position", _bob_home + Vector2(0.0, depth), duration * 0.35)
	_bob_tween.tween_property(target, "position", _bob_home, duration * 0.65)
	_bob_tween.tween_callback(func() -> void: _bobbing = false)


# 迸一下。不传颜色就用场景里配的暖黄；传了只影响这一次，下次调用自己落回基准。
# 用透明当「没传」的哨兵——颜色没有别的空值可用
# A tint affects this one burst only; transparent is the sentinel for "unspecified".
func burst(color: Color = Color.TRANSPARENT, amount: int = 0) -> void:
	if Engine.is_editor_hint() or _burst == null:
		return
	_burst.color = _burst_color if color.a <= 0.0 else color
	_burst.amount = _burst_amount if amount <= 0 else amount
	_burst.restart()
