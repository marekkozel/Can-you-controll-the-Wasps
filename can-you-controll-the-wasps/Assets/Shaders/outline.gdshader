shader_type canvas_item;

// 选中描边 / selection outline. 只画轮廓外那一圈，本体交给它底下那张 sprite。
// 八向采 alpha：邻居不透明而自己透明的像素就是边 / a transparent pixel next to an opaque one is the edge.
//
// ============================================================================
// 红线：**所有黄蜂的描边必须完全一致** —— 同色、同宽、同不透明度。
// 绝不能因为立场 / 血统 / 背叛值不同而不同。只要有一处差异，玩家抓一只就知道答案，
// 整套推理玩法当场作废。这跟 hover_readout.gd 顶上那段是同一条红线。
// Every wasp gets the identical outline. Any per-wasp variation turns it into a
// detector, and a detector is the end of the deduction this whole game is built on.
// ============================================================================
//
// 不要求贴图留边距。Sprite2D 开了 region 之后 UV 是**贴图空间**的，越界会是负数或 >1；
// 采样越界会被 clamp 成边缘像素（wasp.png 左右边距就是 0，本体直接顶到边），
// 所以这里手动把界外判成全透明。OutlineComponent 负责把 region 撑大给描边腾地方。
// UV is texture-space once the sprite has a region, so out-of-range is detectable:
// clamping would otherwise smear the edge row of art that touches the texture border.
//
// 图集（hframes > 1）不能用这个：UV 跑的是子区间，采样会串到隔壁帧。
// Never on an atlas: the sampling bleeds into the neighbouring frame.

// 中性色，不跟血统走 / neutral on purpose - lineage colour already lives on the body
uniform vec4 outline_color : source_color = vec4(1.0, 0.902, 0.502, 1.0);
// 描边宽度，像素 / width in px
uniform float outline_width : hint_range(0.0, 8.0) = 1.0;
// 多低的 alpha 算"外面" / below this counts as outside
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.15;
// 整体不透明度，悬停和拿在手上靠它分级 / hover vs held ride on this
uniform float fade : hint_range(0.0, 1.0) = 1.0;

const float DIAG = 0.70710678;

float alpha_at(sampler2D tex, vec2 uv) {
	// 界外 = 贴图外面 = 空气。不写这一句，顶到贴图边缘的美术会把边缘像素抹一圈
	// Outside the texture is empty, not a smear of whatever the border pixel holds.
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return 0.0;
	}
	return texture(tex, uv).a;
}

void fragment() {
	if (outline_width <= 0.0 || fade <= 0.0) {
		discard;
	}

	vec2 px = TEXTURE_PIXEL_SIZE * outline_width;
	float here = alpha_at(TEXTURE, UV);

	// 斜角乘 0.707，否则对角线方向的描边会比正方向厚 40%
	// Diagonals are scaled or the corners come out 40% thicker than the sides.
	float around = 0.0;
	around = max(around, alpha_at(TEXTURE, UV + vec2(px.x, 0.0)));
	around = max(around, alpha_at(TEXTURE, UV - vec2(px.x, 0.0)));
	around = max(around, alpha_at(TEXTURE, UV + vec2(0.0, px.y)));
	around = max(around, alpha_at(TEXTURE, UV - vec2(0.0, px.y)));
	around = max(around, alpha_at(TEXTURE, UV + px * DIAG));
	around = max(around, alpha_at(TEXTURE, UV - px * DIAG));
	around = max(around, alpha_at(TEXTURE, UV + vec2(px.x, -px.y) * DIAG));
	around = max(around, alpha_at(TEXTURE, UV + vec2(-px.x, px.y) * DIAG));

	float edge = step(alpha_cutoff, around) * (1.0 - step(alpha_cutoff, here));
	if (edge <= 0.0) {
		discard;
	}

	COLOR = vec4(outline_color.rgb, outline_color.a * fade);
}
