// 平涂手绘风格（参照 docs/reference/style_hands_flat.png）：
// 颜色和细节（绷带、皮肤、指甲、褶皱墨线）来自烘焙贴图 assets/textures/arm_albedo.png（tools/bake_arm_texture.py 生成，可直接手绘修改）；
// 着色器只负责两层硬边明暗（交界线带手绘抖动）、内轮廓墨线和淡淡的纸张噪声。
// 不受场景灯光影响（unshaded），光照方向由 light_dir 指定，和 2D 背景的光向保持一致。
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 ink_color : source_color = vec4(0.04, 0.035, 0.035, 1.0);
// 暗面 = 贴图颜色 × shade_tint（偏冷，和参考图一致）
uniform vec3 shade_tint = vec3(0.62, 0.63, 0.7);
// 指向光源的方向（世界空间）
uniform vec3 light_dir = vec3(-0.45, 0.75, 0.5);
uniform float shade_threshold : hint_range(-1.0, 1.0) = 0.35;
uniform float shade_wobble : hint_range(0.0, 0.5) = 0.18;  // 明暗交界线的抖动
uniform float contour_width : hint_range(0.0, 0.6) = 0.2;  // 内轮廓线：越侧向镜头越容易描黑
uniform float paper_strength : hint_range(0.0, 0.3) = 0.05;
// 场景光色：夜里整体乘一个偏冷的月光色
uniform vec3 light_tint : source_color = vec3(1.0);
// 船头鲸油灯（世界坐标的点光源）：朝灯的一面多一档暖色
uniform vec3 lamp_pos = vec3(0.0, 0.0, -3.0);
uniform vec3 lamp_color : source_color = vec3(1.0, 0.6, 0.27);
uniform float lamp_energy = 0.0;
uniform float lamp_range = 3.5;

varying vec3 model_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	model_pos = VERTEX;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	if (!FRONT_FACING) {
		n = -n;
	}
	vec3 l = normalize((VIEW_MATRIX * vec4(normalize(light_dir), 0.0)).xyz);
	float wobble = (noise(model_pos.xy * 38.0 + model_pos.z * 21.0) - 0.5) * shade_wobble;
	float lit = step(shade_threshold + wobble, dot(n, l));

	vec3 color = texture(albedo_texture, UV).rgb;
	color *= mix(shade_tint, vec3(1.0), lit) * light_tint;
	vec3 lamp_view = (VIEW_MATRIX * vec4(lamp_pos, 1.0)).xyz;
	vec3 to_lamp = lamp_view - VERTEX;
	float lamp_dist = length(to_lamp);
	float lamp_ndl = dot(n, to_lamp / lamp_dist);
	float lamp_att = lamp_energy / (1.0 + pow(lamp_dist / lamp_range, 2.0) * 4.0);
	float lamp_band = step(0.25 + wobble, lamp_ndl);
	color += texture(albedo_texture, UV).rgb * lamp_color * lamp_band * lamp_att * 0.9;
	float paper = noise(FRAGCOORD.xy * 0.4) * 0.6 + noise(FRAGCOORD.xy * 0.07) * 0.4;
	color *= 1.0 + (paper - 0.5) * 2.0 * paper_strength;

	float contour = 1.0 - step(contour_width, abs(dot(n, normalize(VIEW))));
	color = mix(color, ink_color.rgb, contour);
	ALBEDO = color;
}
