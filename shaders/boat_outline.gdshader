// 3D 木船的描线：屏幕空间按深度找边（Boat3D 在相机前放一块铺满画面的面片用它）。两种线：
// - 外轮廓（outline_px）：这个像素周围一圈里前后深度差得多，就是轮廓（船对着海、横梁对着后面的船板）
// - 结构线（crease_px，细一点）：两边是连着的面、深度接得上，但面的朝向差得多（折角超过 crease_angle），
//   比如船舷方木的顶面和内侧面、船头甲板的屋脊和边。面的朝向从深度重建，所以只描模型上真的折角，
//   船板之间的小转折、贴图里的木纹板缝都不描
// 手用的是反转外壳描边（toon_outline.gdshader）；船的船舷、横梁是有厚度的方木，反转外壳在轮廓上大多被正面挡住，
// 横梁的角上又会冒出一块块的，所以船改成看深度。线宽和手一样，带一点手绘的粗细抖动。
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, blend_mix;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec4 outline_color : source_color = vec4(0.04, 0.035, 0.035, 1.0);
uniform float outline_px = 3.4;
uniform float crease_px = 2.6;
uniform float width_wobble : hint_range(0.0, 1.0) = 0.45;  // 线宽抖动幅度（和手的描边一样）
// 前后深度差超过近处深度的这么多比例才算轮廓：太小船板接缝也会描黑，太大横梁就描不出来
uniform float depth_jump = 0.08;
// 两个面的夹角超过多少度算折角
uniform float crease_angle = 35.0;
// 几乎侧对着镜头的面（朝向和视线的夹角余弦小于这个）不算折角：深度一个像素一跳，重建出来的朝向不稳，会描出虚线
uniform float grazing_limit = 0.12;
uniform float crease_strength : hint_range(0.0, 1.0) = 1.0;

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
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);  // 铺满画面
}

vec3 view_position(vec2 uv, mat4 inv_projection) {
	float d = texture(depth_texture, uv).r;
	vec4 v = inv_projection * vec4(uv * 2.0 - 1.0, d, 1.0);
	return v.xyz / v.w;
}

// 从深度重建面的朝向：左右、上下各隔两个像素取一点，取深度接得上的那一边，不跨过轮廓
vec3 view_normal(vec2 uv, vec2 px, mat4 inv_projection) {
	vec3 c = view_position(uv, inv_projection);
	vec3 l = view_position(uv - vec2(2.0 * px.x, 0.0), inv_projection);
	vec3 r = view_position(uv + vec2(2.0 * px.x, 0.0), inv_projection);
	vec3 d = view_position(uv - vec2(0.0, 2.0 * px.y), inv_projection);
	vec3 u = view_position(uv + vec2(0.0, 2.0 * px.y), inv_projection);
	vec3 dx = abs(r.z - c.z) < abs(c.z - l.z) ? r - c : c - l;
	vec3 dy = abs(u.z - c.z) < abs(c.z - d.z) ? u - c : c - d;
	return normalize(cross(dx, dy));
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float wobble = 1.0 - width_wobble * 0.5 + width_wobble * noise(FRAGCOORD.xy * 0.045);

	// 外轮廓：周围一圈里最近、最远的深度差得多
	float radius = outline_px * 0.5 * wobble;
	float nearest = -view_position(SCREEN_UV, INV_PROJECTION_MATRIX).z;
	float farthest = nearest;
	for (int i = 0; i < 12; i++) {
		float a = float(i) * 0.5235988;  // 一圈 12 个点
		float d = -view_position(SCREEN_UV + vec2(cos(a), sin(a)) * radius * px, INV_PROJECTION_MATRIX).z;
		nearest = min(nearest, d);
		farthest = max(farthest, d);
	}
	float silhouette = smoothstep(depth_jump * 0.6, depth_jump, (farthest - nearest) / max(nearest, 0.01));

	// 结构线：横、竖、两条斜线四个方向，两边深度接得上、面的朝向差得多
	float half_width = crease_px * 0.5 * wobble;
	float cos_limit = cos(radians(crease_angle));
	float crease = 0.0;
	for (int i = 0; i < 4; i++) {
		float a = float(i) * 0.7853982;
		vec2 o = vec2(cos(a), sin(a)) * half_width * px;
		vec3 pa = view_position(SCREEN_UV + o, INV_PROJECTION_MATRIX);
		vec3 pb = view_position(SCREEN_UV - o, INV_PROJECTION_MATRIX);
		if (abs(pa.z - pb.z) > depth_jump * max(-max(pa.z, pb.z), 0.01)) {
			continue;  // 跨过轮廓的交给外轮廓
		}
		vec3 na = view_normal(SCREEN_UV + o, px, INV_PROJECTION_MATRIX);
		vec3 nb = view_normal(SCREEN_UV - o, px, INV_PROJECTION_MATRIX);
		if (abs(dot(na, normalize(-pa))) < grazing_limit || abs(dot(nb, normalize(-pb))) < grazing_limit) {
			continue;  // 侧对着镜头的面不算
		}
		crease = max(crease, smoothstep(cos_limit + 0.06, cos_limit - 0.06, dot(na, nb)));
	}

	ALBEDO = outline_color.rgb;
	ALPHA = max(silhouette, crease * crease_strength) * outline_color.a;
}
