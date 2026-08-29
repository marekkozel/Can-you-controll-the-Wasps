shader_type canvas_item;

// 主菜单底图的两个小动作 / two small motions for the menu backdrop.
// 挂在 MainMenu 的 Backdrop 上。一张压平的位图里 shader 只能扭曲和染色，
// 所以这里做的是**弯**和**明暗**，不是"让云飘过去"——那个需要美术分层出图
// A flat bitmap can only be warped or tinted; drifting clouds need a separate layer.
//
// 1. 风吹树冠：整幅按高度做横向位移，越往上越大，下半张（树洞和按钮那块）不动
// 2. 树洞呼吸：最暗那档深栗色（#442932，全图 26 万像素只有它）明暗慢慢起伏
//
// **位移必须吸附到整像素。** 项目开的是 Nearest 过滤，位移落在半个像素上时
// 叶子边缘会一直抖，看着不是"在动"，是"发糊"
// Snapped to whole texels: with nearest filtering a sub-pixel offset reads as fuzz.

// **这个 shader 不认 modulate / self_modulate。** 它重新采样贴图，而 `COLOR` 里那份
// 已经乘过 modulate 的值被丢掉了。想接回来只有 `MODULATE` 这一个内置量，而它在
// 4.7 的 canvas_item vertex() 里根本不存在（"标识符未知"），所以这里干脆不接。
// 后果：给 Backdrop 做淡入淡出是没用的，要淡就在它上面盖一层 ColorRect。
// This shader ignores modulate: it resamples, and MODULATE is not available here.
// Fading the Backdrop does nothing - fade a ColorRect on top of it instead.

group_uniforms Wind;
/// 树冠最多横移几个像素 / how far the canopy leans, in pixels
uniform float sway_pixels : hint_range(0.0, 24.0) = 6.0;
uniform float sway_speed : hint_range(0.0, 4.0) = 1.0;
/// 一个来回横跨几个波。大了是抖，小了是整棵树在晃
/// Too many waves reads as jitter; too few and the whole tree slides.
uniform float sway_frequency : hint_range(0.5, 20.0) = 3.0;
/// 幅度从下往上涨得多快。1 是线性，越大越只有顶上动
/// Higher keeps the motion in the crown and off the hollow.
uniform float sway_falloff : hint_range(0.5, 6.0) = 1.8;

group_uniforms Hollow;
/// 比这个亮度暗的算树洞 / anything darker than this counts as the hollow
uniform float dark_cutoff : hint_range(0.0, 0.6) = 0.22;
uniform float dark_feather : hint_range(0.01, 0.2) = 0.04;
/// 洞里透出来的光色。暖色是故意的——中性灰加上去只是把洞变浅，看着像褪色
/// Warm on purpose: a neutral lift just washes the hollow out.
uniform vec4 breathe_tint : source_color = vec4(0.77, 0.41, 0.16, 1.0);
/// 加多少。**是加法不是乘法**：树洞亮度只有 0.196，乘 5% 等于变了 3/255，等于没变
/// Additive, not multiplied - at luminance 0.196 a 5% multiply moves 3 levels out of 255.
uniform float breathe_amount : hint_range(0.0, 0.5) = 0.11;
/// 一次呼吸几秒 / seconds per breath
uniform float breathe_period : hint_range(1.0, 30.0) = 5.0;


// TAU / PI / E 是着色语言内置的，别自己再 const 一遍——那是重定义，编译直接挂
// TAU is built in; declaring it again is a redefinition error.
void fragment() {
	// 上密下疏：pow 让下半张几乎归零，位移吸附之后那里就是纯 0，一动不动
	// The falloff drives the lower half to zero, and snapping pins it there exactly.
	float ramp = pow(1.0 - UV.y, sway_falloff);

	// 两个频率叠一下。单条正弦太规整，像整棵树在做钟摆
	// One sine alone swings like a pendulum, not like wind.
	float wave = sin(TIME * sway_speed + UV.x * sway_frequency)
		+ 0.5 * sin(TIME * sway_speed * 1.7 + UV.x * sway_frequency * 2.3);
	wave /= 1.5;

	float offset = floor(wave * sway_pixels * ramp + 0.5);
	vec4 texel = texture(TEXTURE, UV + vec2(offset * TEXTURE_PIXEL_SIZE.x, 0.0));

	// 树洞。按亮度挑，不按色相——图里只有 12 个颜色，暗到这个程度的只有它和树干背光面，
	// 而那两块本来就是同一种木头，一起呼吸正好
	// Picked by luminance: in a 12-colour image nothing else sits this dark.
	float lum = dot(texel.rgb, vec3(0.299, 0.587, 0.114));
	float dark = 1.0 - smoothstep(dark_cutoff, dark_cutoff + dark_feather, lum);
	// 0~1 的脉动，不是 -1~1：让它只往亮里走。往暗里走的那半程在一块已经很暗的
	// 颜色上根本看不出来，白费了半个周期
	// A 0..1 pulse so it only brightens; the dark half of a sine is invisible here.
	float pulse = 0.5 + 0.5 * sin(TIME * TAU / breathe_period);
	texel.rgb += dark * breathe_tint.rgb * breathe_amount * pulse;

	COLOR = texel;
}
