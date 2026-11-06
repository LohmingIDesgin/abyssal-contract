// 反转外壳描边：沿法线在屏幕空间外扩，线宽基本不随远近变化，并带一点手绘的粗细抖动。
// 作为 toon.gdshader 材质的 next_pass 使用。
shader_type spatial;
render_mode unshaded, cull_front;

uniform vec4 outline_color : source_color = vec4(0.04, 0.035, 0.035, 1.0);
uniform float outline_px = 3.4;
uniform float width_wobble : hint_range(0.0, 1.0) = 0.45;  // 线宽抖动幅度

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

// 平滑的 3D 值噪声，让线宽沿轮廓连续变化
float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 view_normal = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	vec2 dir = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy;
	if (length(dir) > 0.0001) {
		dir = normalize(dir);
	}
	float width = outline_px * (1.0 - width_wobble * 0.5 + width_wobble * noise(VERTEX * 18.0));
	clip.xy += dir * width * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
