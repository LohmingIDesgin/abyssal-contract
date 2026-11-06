// 全屏后期（在 HUD 之下）：泛光、月光从云缝里漏下来的光柱、船头灯在雾里的光晕、淡淡的前景雾气、
// 青蓝暗调的调色、暗角和胶片颗粒。手、船、海面经过同一道调色，画面才统一。
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float aspect = 1.7778;
uniform float time = 0.0;
uniform vec2 lamp_uv = vec2(0.47, 0.38);   // 灯在屏幕上的位置（UV）
uniform vec3 lamp_color : source_color = vec3(1.0, 0.6, 0.27);
uniform float lamp_energy = 1.0;
uniform vec2 moon_uv = vec2(0.33, 0.25);   // 月亮在屏幕上的位置（UV），可以在屏幕外
uniform vec3 moon_color : source_color = vec3(0.86, 0.93, 0.92);
uniform float shafts = 0.35;
uniform vec3 mist_color : source_color = vec3(0.42, 0.5, 0.51);
uniform float bloom = 0.45;
uniform float grain = 0.022;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		total += amp * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		amp *= 0.5;
	}
	return total / 0.9375;
}

// 月光光柱：从这个像素朝月亮走，一路收集月亮附近"亮得透光"的地方（月亮本身、被照亮的薄云、云缝），
// 光就是从那些地方沿直线漏下来的；暗的云、礁石、船、手挡在中间就是光柱之间的暗缝
vec3 moon_shafts(vec2 uv) {
	vec2 to_moon = moon_uv - uv;
	vec2 stride = to_moon / 32.0;
	vec2 s = uv + stride * hash12(uv * 977.0 + fract(time) * 31.0);
	float acc = 0.0;
	float wsum = 0.0;
	for (int i = 0; i < 32; i++) {
		vec3 sc = textureLod(screen_tex, s, 1.5).rgb;
		float inside = step(0.0, s.y) * step(s.y, 1.0) * step(0.0, s.x) * step(s.x, 1.0);
		float w = exp(-length((s - moon_uv) * vec2(aspect, 1.0)) * 7.0) * inside;
		acc += smoothstep(0.4, 0.9, dot(sc, vec3(0.25, 0.55, 0.2))) * w;
		wsum += w;
		s += stride;
	}
	float r = length(to_moon * vec2(aspect, 1.0));
	return moon_color * acc / max(wsum, 0.0001) * exp(-r * 2.2);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = textureLod(screen_tex, uv, 0.0).rgb;
	// 泛光：模糊过的几级 mip 只留亮部
	vec3 b = textureLod(screen_tex, uv, 2.0).rgb * 0.45 + textureLod(screen_tex, uv, 3.5).rgb * 0.35
		+ textureLod(screen_tex, uv, 5.0).rgb * 0.2;
	c += max(b - vec3(0.36), vec3(0.0)) * bloom;
	c += moon_shafts(uv) * shafts;
	// 灯的光晕：近处一团亮，往外是雾被照亮的 1/r 衰减
	vec2 d = (uv - lamp_uv) * vec2(aspect, 1.0);
	float r = length(d);
	float halo = exp(-r * 30.0) * 0.4 + 0.016 / (r + 0.07) - 0.016 / 0.62;
	c += lamp_color * max(halo, 0.0) * lamp_energy;
	// 前景雾气：屏幕中段缓缓飘过的一层淡雾
	float m = fbm(uv * vec2(2.6, 1.4) + vec2(time * 0.012, time * 0.003));
	float band = smoothstep(0.1, 0.45, uv.y) * (1.0 - smoothstep(0.7, 1.0, uv.y));
	c = mix(c, mist_color, smoothstep(0.52, 0.85, m) * 0.12 * band);
	// 调色：轻微去饱和（暖色的亮部保留），暗部推向青蓝，柔和的 S 曲线
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float warm = smoothstep(0.03, 0.18, c.r - c.b) * smoothstep(0.08, 0.4, lum);
	c = mix(vec3(lum), c, mix(0.78, 1.05, warm));
	c += vec3(-0.006, 0.01, 0.014) * (1.0 - smoothstep(0.0, 0.35, lum));
	c = clamp(c, 0.0, 1.0);
	c = mix(c, c * c * (3.0 - 2.0 * c), 0.35);
	// 暗角
	vec2 v = (uv - 0.5) * vec2(aspect, 1.0);
	c *= mix(1.0, 0.58, smoothstep(0.42, 1.12, length(v)));
	// 颗粒
	c += (hash12(uv * vec2(1280.0, 720.0) + fract(time * 7.0) * 113.0) - 0.5) * grain;
	COLOR = vec4(c, 1.0);
}
