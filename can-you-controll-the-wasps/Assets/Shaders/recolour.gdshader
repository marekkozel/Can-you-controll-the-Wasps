shader_type canvas_item;

// 主色替换 / recolour: 把贴图黄橙那一族的色相挪到 tint 上，翅膀和头不动。
//
// 贴图已经是彩色的（蜂和卵的主色都是 #fecf75），再 self_modulate 等于乘两遍——
// 青色乘出来是绿的，高光也被一起压平。这里改成在 HSV 里平移色相。
// The art is already coloured, so modulating multiplies twice; shift hue instead.
//
// wasp.png 有三族色，只有黄橙族该跟血统走：
//   黄橙 H=24..39  身体和条纹    <- 换这个
//   蓝   H=197..217 翅膀         <- 不能换，中间空了 157 度，遮罩不会有争议区
//   中性 S<0.4      头/高光       <- 靠 min_saturation 排掉
// egg.png 只有一个色族，把 hue_window 开满就退化成整张换色。

// 贴图自己的主色，也就是「不染色时长什么样」/ the art's own dominant colour
uniform vec3 reference : source_color = vec3(0.996, 0.812, 0.459);
// 想染成的颜色，喂 WaspVariant.body_color / target colour
uniform vec3 tint : source_color = vec3(0.996, 0.812, 0.459);
// 离主色多少度以内算「该换的那一族」/ hue distance that counts as the recoloured family
uniform float hue_window : hint_range(0.0, 180.0) = 30.0;
// 窗口边缘的软过渡，0 会让边界跳色 / hard edges band, keep a few degrees of falloff
uniform float hue_softness : hint_range(0.0, 60.0) = 10.0;
// 低于这个饱和度的不动（头 S=.40 明度低、高光 S=.07）/ leaves neutrals alone
uniform float min_saturation : hint_range(0.0, 1.0) = 0.25;
// 明度多大程度跟着目标色走。1 = 纯比例，深色血统(Teal V=.72)会整只暗一截
// 0 = 保留原图明度，只换色相和饱和 / how much the target's value drags the art down
uniform float value_follow : hint_range(0.0, 1.0) = 1.0;
// 0 = 原图，1 = 完全换色 / blend back toward the original
uniform float strength : hint_range(0.0, 1.0) = 1.0;

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

// 色相是环形的，349 度和 5 度只差 16 / hue wraps, so 349 and 5 are 16 apart
float hue_distance(float a, float b) {
	float d = abs(fract(a) - fract(b));
	return min(d, 1.0 - d) * 360.0;
}

void fragment() {
	// 拿 COLOR 当输入而不是重新 texture()：进 fragment() 时 COLOR 已经是
	// texture * modulate，重采样再乘一遍就把贴图颜色叠了两次——暖黄 x 青 = 绿。
	// 这么写 self_modulate 和 JuiceComponent.flash() 天然留在 src 里，不用额外处理。
	// (MODULATE 只有 vertex() 有，fragment() 里拿不到。)
	// COLOR already holds texture * MODULATE; re-sampling and multiplying squares the art.
	vec4 src = COLOR;
	if (src.a < 0.001) {
		discard;
	}

	vec3 ref_hsv = rgb_to_hsv(reference);
	vec3 dst_hsv = rgb_to_hsv(tint);
	vec3 px = rgb_to_hsv(src.rgb);

	float in_family = smoothstep(hue_window + hue_softness, hue_window,
			hue_distance(px.x, ref_hsv.x));
	float saturated = smoothstep(min_saturation - 0.06, min_saturation + 0.06, px.y);
	float mask = in_family * saturated * strength;

	// 饱和走比例不走差值：高光本来就低饱和，用差值会把它一起拉满
	// Ratio, not offset - the highlight is deliberately desaturated and must stay that way.
	vec3 shifted = px;
	shifted.x = fract(px.x + (dst_hsv.x - ref_hsv.x));
	shifted.y = clamp(px.y * (dst_hsv.y / max(ref_hsv.y, 1e-4)), 0.0, 1.0);
	shifted.z = clamp(px.z * mix(1.0, dst_hsv.z / max(ref_hsv.z, 1e-4), value_follow), 0.0, 1.0);

	COLOR = vec4(mix(src.rgb, hsv_to_rgb(shifted), mask), src.a);
}
