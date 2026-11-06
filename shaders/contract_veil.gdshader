// 契约书（Tab）打开时从屏幕四周包上来的黑墨和蓝雾：和邪神立约，不是一张纸，是有东西从四面围上来。
// - 黑墨从屏幕边缘往里爬（四角最多），边上是一缕缕卷曲、带尖刺的墨丝，墨面上有一点湿漉漉的蓝光
// - 墨的内侧一大圈蓝灰色的雾在慢慢翻涌，贴着墨边还有一道薄薄的冷光
// - 正中留空给字，整体再压暗一点
// amount 0 → 1：墨从边上爬进来、雾浮起来；关上时反过来。
shader_type canvas_item;

uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float aspect = 1.7778;
uniform vec3 ink_color : source_color = vec3(0.012, 0.018, 0.026);
uniform vec3 mist_color : source_color = vec3(0.4, 0.56, 0.68);
uniform vec3 rim_color : source_color = vec3(0.55, 0.78, 0.95);

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// 一层层叠出来的细脊：墨丝
float ridged(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * (1.0 - abs(noise(p) * 2.0 - 1.0));
		p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.1 + vec2(3.1, 1.3);
		a *= 0.5;
	}
	return v;
}

vec4 over(vec4 dst, vec4 src) {
	float a = src.a + dst.a * (1.0 - src.a);
	vec3 c = (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / max(a, 0.0001);
	return vec4(c, a);
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float t = TIME * 0.05;
	// 离屏幕边缘多近：正中 0，贴边 1，四角更大
	vec2 q = abs(UV - 0.5) * 2.0;
	float edge = pow(pow(q.x, 5.0) + pow(q.y, 5.0), 0.2);
	// 扭动的流场：墨丝往里卷、雾翻涌都跟着它
	vec2 w = vec2(fbm(p * 2.0 + vec2(t, -t * 0.7)), fbm(p * 2.0 + vec2(-t * 0.8, t) + 5.2)) - 0.5;
	float n = fbm(p * 3.2 + w * 1.8 + vec2(0.0, t * 0.6));
	float reach = mix(0.5, 0.0, smoothstep(0.0, 1.0, amount));
	// 墨主体只在四周一圈（四角最厚），噪声让边缘一会儿进一会儿退
	float field = edge + (n - 0.5) * 0.36 - 0.86 - reach;
	// 墨丝：细脊噪声里最高的那一线，只在墨边往里一小段长出来，像卷曲的触须
	float strands = ridged(p * 4.5 + w * 3.0 + vec2(t * 0.4, 0.0));
	float strand = smoothstep(0.83, 0.9, strands) * smoothstep(-0.45, -0.02, field);
	float ink = max(smoothstep(0.0, 0.02, field), strand);
	// 墨面：一点湿漉漉的冷光
	float sheen = smoothstep(0.62, 0.9, fbm(p * 7.0 + w * 3.0)) * ink * smoothstep(0.25, 0.05, field);
	// 贴着墨边一道很薄的冷光
	float rim = smoothstep(-0.03, 0.0, field) * (1.0 - ink) * smoothstep(0.4, 0.7, n);
	// 雾：贴着墨边最浓，一路淡淡地铺到中间，把墨边糊开
	float band = smoothstep(-0.8, -0.02, field) * (1.0 - ink);
	float mist = smoothstep(0.42, 0.9, fbm(p * 1.4 + w * 2.4 + vec2(t * 1.6, -t * 0.4))) * band * band;

	vec4 acc = vec4(0.0, 0.0, 0.0, 0.34 * amount);
	acc = over(acc, vec4(mist_color, mist * 0.36 * amount));
	acc = over(acc, vec4(rim_color, rim * 0.1 * amount));
	acc = over(acc, vec4(ink_color + vec3(0.06, 0.12, 0.18) * sheen, ink));
	COLOR = acc;
}
