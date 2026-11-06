// 夜里偶尔从远处天上飞过的大鸟（SkyBirds）：只看得见剪影，看得出翅膀一下一下地扇。
// 每只按距离场画：身子顺着飞的方向（头在前、尾巴在后），两只翅膀各分内外两节，扇翅时外节慢半拍跟上
// （bird_b 的 x、y 是内外两节翘起多少）；离得远，所以边缘是软的。
// 再被天上的云遮住一些、被流动的雾吞掉一些（若隐若现）。隔着的雾只让剪影变淡（往后面的天透），
// 不往雾色调亮：天有亮有暗，调亮了会在暗处显出一只亮鸟。
// 投影参数（aspect、horizon、roll……）和云图跟海面同一份，WaterView 每帧给；鸟的位置、姿势由 SkyBirds 每帧给。
shader_type canvas_item;

#include "res://shaders/sea_common.gdshaderinc"

uniform sampler2D cloud_tex : filter_linear, repeat_disable;
uniform vec2 rect_size = vec2(1280.0, 720.0);
uniform int bird_count = 0;
uniform vec4 bird_a[8];   // 屏幕位置 xy（像素）、翼展（像素）、朝向（+1 往右飞，-1 往左飞）
uniform vec4 bird_b[8];   // 内节、外节翘起多少（-1 ~ 1，正的往上）、不透明度、身子侧倾（弧度）
uniform vec4 wing_shape = vec4(0.18, 0.05, 0.02, 0.85);  // 内节长（翼展 = 1）、翅膀宽、翅尖下垂、远侧那只翅膀缩到多长
uniform vec4 body_shape = vec4(0.04, 0.06, 0.018, 1.0);  // 脖子长、尾巴长、头多大、身子粗细
uniform vec3 bird_color : source_color = vec3(0.018, 0.026, 0.03);
uniform float haze = 0.2;          // 隔着多少雾：剪影淡掉多少
uniform float softness = 1.8;      // 边缘软多少（像素）
uniform float cloud_hide = 0.35;   // 云遮住它的程度
uniform float fog_eat = 0.3;       // 流动的雾吞掉它的程度
uniform float time = 0.0;

// 两端粗细不同的一段（近似的距离场，画软边够用）
float seg(vec2 p, vec2 a, vec2 b, float ra, float rb) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - mix(ra, rb, h);
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// 一只鸟（翼展 = 1，x 向右、y 向上，身子在原点）
float bird_sdf(vec2 p, float heading, float up1, float up2) {
	float arm = wing_shape.x;
	float outer = 0.47 - arm;
	float chord = wing_shape.y;
	float d = 1e5;
	for (int i = 0; i < 2; i++) {
		float side = i == 0 ? -1.0 : 1.0;
		float reach = side * heading > 0.0 ? 1.0 : wing_shape.w;   // 远侧那只翅膀看上去短一点
		float a1 = up1 * 0.6;
		float a2 = a1 + up2 * 0.55;
		vec2 shoulder = vec2(side * 0.025, 0.004);
		vec2 wrist = shoulder + vec2(side * cos(a1), sin(a1)) * arm * reach;
		vec2 tip = wrist + vec2(side * cos(a2), sin(a2)) * outer * reach - vec2(0.0, wing_shape.z);
		d = smin(d, seg(p, shoulder, wrist, chord * 0.6, chord * 0.45), 0.012);
		d = smin(d, seg(p, wrist, tip, chord * 0.45, chord * 0.07), 0.01);
	}
	vec2 fwd = normalize(vec2(heading, 0.1));
	float girth = 0.034 * body_shape.w;
	d = smin(d, seg(p, -fwd * 0.045, fwd * 0.045, girth, girth * 0.85), 0.02);
	d = smin(d, seg(p, fwd * 0.045, fwd * (0.06 + body_shape.x), girth * 0.45, body_shape.z), 0.012);
	d = smin(d, seg(p, -fwd * 0.04, -fwd * (0.05 + body_shape.y), girth * 0.7, 0.004), 0.012);
	return d;
}

void fragment() {
	vec2 p = UV * rect_size;
	float alpha = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= bird_count) {
			break;
		}
		vec4 a = bird_a[i];
		vec2 d = p - a.xy;
		if (dot(d, d) > a.z * a.z * 0.36) {   // 半个翼展再多一点以外不用算
			continue;
		}
		vec4 b = bird_b[i];
		// 跟着视线的横摇转（和天空一样），再加一点身子的侧倾；屏幕 y 向下，鸟的 y 向上
		float c = cos(roll + b.w);
		float s = sin(roll + b.w);
		vec2 q = vec2(c * d.x - s * d.y, s * d.x + c * d.y) / a.z;
		q.y = -q.y;
		float sd = bird_sdf(q, a.w, b.x, b.y) * a.z;
		alpha = max(alpha, (1.0 - smoothstep(-softness, softness, sd)) * b.z);
	}
	if (alpha <= 0.002) {
		discard;
	}
	// 飞进云里被遮住一些（云图跟着视线转，所以用没转过的视线方向去取）
	vec3 dir = uv_to_dir(UV);
	vec4 cl = texture(cloud_tex, clamp(dir_to_cloud_uv(vec3(dir.xy, max(dir.z, 0.05))), vec2(0.002), vec2(0.998)));
	float through = mix(1.0, cl.a, cloud_hide);
	// 流动的雾一阵一阵吞掉它：雾团比鸟大，整只翅膀一起淡下去又露出来
	vec2 sp = (UV - 0.5) * vec2(aspect, 1.0);
	float n = fbm(sp * 2.6 + vec2(time * 0.025, time * 0.007), 3);
	float eaten = smoothstep(0.42, 0.68, n) * fog_eat;
	// 贴近地平线的雾最厚
	float height = horizon - (sin(roll) * sp.x + cos(roll) * sp.y);
	float low = 1.0 - smoothstep(0.02, 0.2, height);
	COLOR = vec4(bird_color, alpha * through * (1.0 - eaten) * (1.0 - haze) * (1.0 - low * 0.6) * smoothstep(0.0, 0.03, height));
}
