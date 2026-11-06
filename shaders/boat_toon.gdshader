// 3D 木船（Boat3D）的着色。和手臂（toon.gdshader）同一个底子：交界线带手绘抖动、内轮廓墨线、淡淡的纸张噪声，外轮廓是同一个描边；
// 质感往参照图（风化的旧木船：灰褐、哑光、木纹和板缝清楚、船底比船舷暗）靠：
// - 颜色就是原件的颜色贴图（船板一张平铺、装饰件一张图集），这里只乘一个 albedo_tint 整体调色
// - 明暗：用法线贴图（木板接缝、木纹、铁件的起伏）上的朝向，交界线比手软；接缝凹下去的地方压暗；
//   船底比船舷暗（模型没烘环境光遮蔽，按高度近似）
// - 粗糙度：旧木头大多是哑光，只在磨得光一点的地方有很宽、很淡的高光；铁件光一些（月光和船头灯各一份）
// 法线、粗糙度贴图是 tools/convert_boat.py 照着颜色画的。贴图在 UV 里平铺，所以都开着 repeat
// - 船头鲸油灯的暖光：平滑衰减、不分档
// - 按离眼睛的远近蒙一层雾：船头那一端化进雾里一点
// 不受场景灯光影响（unshaded）。相机在原点、不转，所以世界坐标就是相机坐标；月光色、雾色由 WaterView 给，黄昏时一起转红。
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_texture : filter_linear_mipmap_anisotropic, repeat_enable;
// 颜色贴图整体乘的颜色
uniform vec3 albedo_tint : source_color = vec3(1.0);
uniform float normal_strength : hint_range(0.0, 3.0) = 1.6;
// 凹下去的缝压暗多少（法线越偏离船板平面越暗）
uniform float relief_cavity : hint_range(0.0, 8.0) = 2.5;
// 船底比船舷暗：模型高度 ao_low 以下乘 ao_bottom，到 ao_high 回到 1（米，龙骨在 −0.2、船舷约 1.07）
uniform float ao_bottom : hint_range(0.0, 1.0) = 0.55;
uniform float ao_low = 0.0;
uniform float ao_high = 0.95;
uniform vec4 ink_color : source_color = vec4(0.04, 0.035, 0.035, 1.0);
// 暗面 = 颜色 × shade_tint（偏冷）
uniform vec3 shade_tint = vec3(0.5, 0.52, 0.6);
// 指向月亮的方向：月亮在前方偏左的上空（和手臂的 MOON_LIGHT_DIR 一致），船里朝上的面亮、朝人的面在暗部
uniform vec3 light_dir = vec3(-0.23, 0.28, -1.0);
uniform float shade_threshold : hint_range(-1.0, 1.0) = 0.05;
uniform float shade_softness : hint_range(0.0, 1.0) = 0.3;  // 明暗交界多软：0 是手那样的硬边
uniform float shade_wobble : hint_range(0.0, 0.5) = 0.12;   // 明暗交界线的抖动
uniform float contour_width : hint_range(0.0, 0.6) = 0.08;  // 内轮廓线：越侧向镜头越容易描黑
uniform float paper_strength : hint_range(0.0, 0.3) = 0.04;
// 月夜的环境光（WaterView.DUSK_BOAT 的 ambient，黄昏时转红）
uniform vec3 light_tint : source_color = vec3(0.4, 0.48, 0.5);
// 高光：粗糙度越低越亮、越集中；整体很淡，木头基本是哑光
uniform float spec_strength : hint_range(0.0, 2.0) = 0.35;
// 下雨淋湿（WaterView 按雨多大给）：木头吸了水颜色变深，表面一层水膜发亮（高光更集中、更亮）
uniform float wet : hint_range(0.0, 1.0) = 0.0;
// 船头鲸油灯（世界坐标的点光源）：朝灯的一面被照暖，离灯越远越淡
uniform vec3 lamp_pos = vec3(0.0, 1.0, -3.0);
uniform vec3 lamp_color : source_color = vec3(1.0, 0.6, 0.27);
uniform float lamp_energy = 1.0;
uniform float lamp_range = 0.8;
uniform float lamp_strength = 1.0;
// 雾：离眼睛 fog_near 米开始，到 fog_far 米蒙上 fog_max
uniform vec3 fog_color : source_color = vec3(0.36, 0.44, 0.46);
uniform float fog_near = 1.5;
uniform float fog_far = 4.5;
uniform float fog_max = 0.3;

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
	vec3 nv = normalize(NORMAL);   // 船板本身的朝向
	vec3 tangent = normalize(TANGENT);
	vec3 binormal = normalize(BINORMAL);
	if (!FRONT_FACING) {
		nv = -nv;
		tangent = -tangent;
		binormal = -binormal;
	}
	// 和 Godot 自己做法线贴图一样：只用 xy，z 按单位长度补出来
	vec2 nm = (texture(normal_texture, UV).xy * 2.0 - 1.0) * normal_strength;
	vec3 n = normalize(tangent * nm.x + binormal * nm.y + nv * sqrt(max(0.0, 1.0 - dot(nm, nm))));
	vec3 v = normalize(VIEW);
	vec3 l = normalize((VIEW_MATRIX * vec4(normalize(light_dir), 0.0)).xyz);

	vec3 base = texture(albedo_texture, UV).rgb * albedo_tint * (1.0 - 0.3 * wet);

	// 船比手大二十多倍，抖动的噪声频率跟着放低
	float wobble = (noise(model_pos.xz * 6.0 + model_pos.y * 4.0) - 0.5) * shade_wobble;
	float lit = smoothstep(shade_threshold - shade_softness, shade_threshold + shade_softness, dot(n, l) + wobble);
	vec3 color = base * mix(shade_tint, vec3(1.0), lit) * light_tint;
	color *= mix(ao_bottom, 1.0, smoothstep(ao_low, ao_high, model_pos.y));
	color *= max(0.0, 1.0 - (1.0 - clamp(dot(n, nv), 0.0, 1.0)) * relief_cavity);

	// 粗糙度 → 高光：越粗糙越宽、越淡
	float gloss = mix(1.0 - texture(roughness_texture, UV).r, 0.85, wet * 0.6);
	float spec_power = mix(4.0, 40.0, gloss * gloss);
	float spec_gain = gloss * gloss * spec_strength * (1.0 + wet * 1.5);
	color += light_tint * pow(max(dot(n, normalize(l + v)), 0.0), spec_power) * spec_gain * lit;

	vec3 lamp_view = (VIEW_MATRIX * vec4(lamp_pos, 1.0)).xyz;
	vec3 to_lamp = lamp_view - VERTEX;
	float lamp_dist = length(to_lamp);
	vec3 lamp_dir = to_lamp / lamp_dist;
	float lamp_att = lamp_energy / (1.0 + pow(lamp_dist / lamp_range, 2.0) * 4.0);
	float lamp_face = smoothstep(-0.05, 0.6, dot(n, lamp_dir) + wobble * 0.5);
	color += base * lamp_color * lamp_face * lamp_att * lamp_strength;
	color += lamp_color * pow(max(dot(n, normalize(lamp_dir + v)), 0.0), spec_power) * spec_gain * lamp_att * 2.0;

	float paper = noise(FRAGCOORD.xy * 0.4) * 0.6 + noise(FRAGCOORD.xy * 0.07) * 0.4;
	color *= 1.0 + (paper - 0.5) * 2.0 * paper_strength;

	float contour = 1.0 - step(contour_width, abs(dot(nv, v)));
	color = mix(color, ink_color.rgb, contour);

	color = mix(color, fog_color, smoothstep(fog_near, fog_far, length(VERTEX)) * fog_max);
	ALBEDO = color;
}
