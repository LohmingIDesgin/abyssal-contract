// 夜海全景（sea_scene.gdshader）和夜空的云（sky_clouds.gdshader）共用的部分：
// 相机参数、噪声、云的形状。两边用同一份，云在离屏图里和在海面倒影里才对得上。
// 相机在 (0, cam_height, 0)、朝 +z；世界坐标 = 相机坐标 + (0, 0, travel)，travel 是船已经漂出去的距离。
// 屏幕坐标中心为原点、y 向下、单位为屏幕高度；船的俯仰体现在 horizon，横摇体现在 roll，
// 转头体现在 yaw：uv_to_dir 给的是没转头时的方向，再用 yaw_dir(d, yaw) 转到世界里（云图跟着视线转，不用转）。

uniform float aspect = 1.7778;
uniform float horizon = 0.12;
uniform float base_horizon = 0.12;   // 船平稳时的地平线（月亮的位置相对它而定，不随船晃）
uniform float roll = 0.0;
uniform float focal = 1.3;
uniform float cam_height = 1.55;
uniform float sea_time = 0.0;
uniform float travel = 0.0;
uniform vec2 moon_pos = vec2(-0.3, -0.25);
uniform float yaw = 0.0;   // 转头：视线绕竖直轴转了多少（弧度，> 0 朝右看）

uniform vec3 sky_top : source_color = vec3(0.07, 0.1, 0.115);
uniform vec3 fog_dark : source_color = vec3(0.2, 0.27, 0.29);
uniform vec3 moon_color : source_color = vec3(0.86, 0.93, 0.92);
uniform float cloud_coverage = 0.5;
uniform float cloud_base = 450.0;
uniform float cloud_top = 1300.0;
// 云图（离屏）覆盖的范围：船平稳时（地平线在 base_horizon、不横摇）的屏幕 UV 的 x、y、宽、高。
// 四周比屏幕多出一圈，船怎么晃屏幕都还在云图里；下沿正好是地平线
uniform vec4 cloud_rect = vec4(-0.02, -0.14, 1.04, 0.76);

// ---------- 噪声 ----------

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.103, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), u.x);
	float b = mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), u.x);
	float c = mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), u.x);
	float d = mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), u.x);
	return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}

float fbm(vec2 p, int octaves) {
	float total = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	for (int i = 0; i < octaves; i++) {
		total += amp * noise(p);
		norm += amp;
		p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.03 + vec2(1.7, 9.2);
		amp *= 0.5;
	}
	return total / norm;
}

// ---------- 相机 ----------

// 屏幕 UV → 视线方向
vec3 uv_to_dir(vec2 uv) {
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
	float cr = cos(roll);
	float sr = sin(roll);
	vec2 q = vec2(cr * p.x - sr * p.y, sr * p.x + cr * p.y);
	return normalize(vec3(q.x / focal, (horizon - q.y) / focal, 1.0));
}

// 方向绕竖直轴转 a（> 0 朝右）：视线方向 → 世界方向用 yaw_dir(d, yaw)，反过来用 -yaw
vec3 yaw_dir(vec3 d, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(c * d.x + s * d.z, d.y, -s * d.x + c * d.z);
}

vec3 moon_dir() {
	return normalize(vec3(moon_pos.x / focal, (base_horizon - moon_pos.y) / focal, 1.0));
}

// 云图 UV → 视线方向。云图按船平稳时的投影铺开，不跟着船晃：每个像素永远对着天上同一个方向
vec3 cloud_uv_to_dir(vec2 uv) {
	vec2 p = (uv * cloud_rect.zw + cloud_rect.xy - 0.5) * vec2(aspect, 1.0);
	return normalize(vec3(p.x / focal, (base_horizon - p.y) / focal, 1.0));
}

// 视线方向 → 云图 UV（cloud_uv_to_dir 的逆，方向要朝前）
vec2 dir_to_cloud_uv(vec3 d) {
	vec2 q = vec2(d.x / d.z * focal, base_horizon - d.y / d.z * focal);
	return (q / vec2(aspect, 1.0) + 0.5 - cloud_rect.xy) / cloud_rect.zw;
}

// ---------- 云的形状 ----------

// 云的扭曲：尺度很大（约 2 公里），在几百米内几乎不变，同一步的几次取样可以共用
vec2 cloud_warp(vec2 xz, float t) {
	vec2 p = xz * 0.00055 + vec2(t * 0.0021, t * 0.0008);
	return vec2(fbm(p + 3.1, 3), fbm(p - 1.7, 3)) - 0.5;
}

// 云层的平面"形"：一大团一大团的云和云缝
float cloud_shape(vec2 xz, vec2 warp, float t, int octaves) {
	vec2 p = xz * 0.0009 + vec2(t * 0.0035, t * 0.0013);
	return fbm(p + warp * 1.2, octaves);
}

// 某个高度上，"形"要超过多少才算有云：云底和云顶都收圆，越厚的云团垂得越低，云底是一团团往下鼓的
float cloud_threshold(float h) {
	return (1.0 - cloud_coverage) + 0.22 * (1.0 - smoothstep(0.0, 0.35, h)) + 0.3 * smoothstep(0.5, 1.0, h);
}
