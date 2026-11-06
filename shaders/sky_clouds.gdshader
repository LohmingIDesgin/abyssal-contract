// 夜空的体积云。单独画在 1/3 分辨率的离屏图上（WaterView 的 _cloud_viewports，两张轮流画），海面着色器按方向取回来。
// 云图按船平稳时的投影铺开（cloud_rect、cloud_uv_to_dir），不跟着船晃，只跟着转头（yaw）转，
// 所以可以一帧帧累积（体积云通行的"时间累积"）：每帧换一个步进起点、在像素里换一个取样位置，
// 再和上一帧的结果按 history_weight 混合。最近十几帧的样本平均下来，云边就不会一帧一帧地闪噪点。
// 转头时上一帧的云图朝的是另一个方向（history_yaw），按方向把这个像素在上一帧里的位置找回来再混。
// 做法：在云层（cloud_base ~ cloud_top）里沿视线步进；每一步朝月亮再取两次样，算这一点被挡住了多少月光；
// 前向散射（Henyey-Greenstein，迎着月亮的薄云边发亮）+ 粉末效应（云团边缘亮、芯子暗）+ 一点多次散射；
// 天光从上往下：云顶接到夜空的青，云底只接到海面和雾反上来的一点暗青。
// 输出：rgb = 云散射过来的光，a = 透过率（1 = 没有云，看得见后面的夜空和月亮）。
shader_type canvas_item;
render_mode blend_disabled;

#include "res://shaders/sea_common.gdshaderinc"

uniform float moon_strength = 0.32;
// 上一帧的云图（WaterView 里两张离屏图轮流画，这里是另一张），和这张一样大，一个像素对一个像素
uniform sampler2D history : filter_linear, repeat_disable;
uniform float history_yaw = 0.0;      // 上一帧云图朝的方向（转头的角度）
uniform int frame_index = 0;          // 每帧加一，决定这一帧在像素里、在步长里取样的位置
uniform float history_weight = 0.0;   // 上一帧占多少；0 = 没有可用的上一帧（刚开始、改了尺寸、船瞬移）
const int STEPS = 48;

// 消光系数（每米）。detail 为真时加 3D 噪声，把云边蚀成絮状；thin 是月亮附近让云变薄的比例
float cloud_density(vec3 p, vec2 warp, float t, bool detail, float thin) {
	float h = (p.y - cloud_base) / (cloud_top - cloud_base);
	if (h < 0.0 || h > 1.0) {
		return 0.0;
	}
	float s = cloud_shape(p.xz, warp, t, detail ? 5 : 3);
	if (detail) {
		s += (noise3(p * 0.0042 + vec3(t * 0.01, 0.0, 0.0)) - 0.5) * 0.22 + (noise3(p * 0.013) - 0.5) * 0.1;
	}
	float thr = cloud_threshold(h);
	return smoothstep(thr, thr + 0.16, s) * 0.022 * (1.0 - thin);
}

float henyey_greenstein(float c, float g) {
	return (1.0 - g * g) / (12.566 * pow(1.0 + g * g - 2.0 * g * c, 1.5));
}

void fragment() {
	// 这一帧在像素里的取样位置（R2 低差异序列）：累积下来云边就是抗锯齿过的
	vec2 sub = fract(float(frame_index) * vec2(0.7548777, 0.5698403)) - 0.5;
	vec3 rd = yaw_dir(cloud_uv_to_dir(UV + sub * SCREEN_PIXEL_SIZE), yaw);
	vec4 result = vec4(0.0, 0.0, 0.0, 1.0);
	if (rd.y > 0.01) {
		float t = sea_time;
		vec3 md = moon_dir();
		float t0 = (cloud_base - cam_height) / rd.y;
		float t1 = min((cloud_top - cam_height) / rd.y, t0 + 7000.0);
		float dt = (t1 - t0) / float(STEPS);
		// 沿视线的起步偏移：相邻像素错开（交错梯度噪声），同一像素逐帧按黄金分割轮换，几帧就把一步之内均匀取遍
		float ign = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		float s = t0 + dt * fract(ign + float(frame_index) * 0.618034);
		float cos_t = dot(rd, md);
		// 月亮附近的云薄成一层纱：形状还在，月亮多半能透出来，四周的云边被照亮（美术上的取舍）
		float thin = 0.9 * exp(-pow(acos(clamp(cos_t, -1.0, 1.0)) / 0.17, 2.0));
		float phase = mix(henyey_greenstein(cos_t, 0.55), henyey_greenstein(cos_t, -0.25), 0.45) * 12.566;
		vec3 acc = vec3(0.0);
		float trans = 1.0;
		for (int i = 0; i < STEPS; i++) {
			vec3 p = vec3(0.0, cam_height, travel) + rd * s;
			vec2 warp = cloud_warp(p.xz, t);
			float d = cloud_density(p, warp, t, true, thin);
			if (d > 0.00001) {
				float l1 = cloud_density(p + md * 80.0, warp, t, false, thin);
				float l2 = cloud_density(p + md * 260.0, warp, t, false, thin);
				float tau = (l1 * 80.0 + l2 * 180.0) * 1.4;
				// 直射 + 在云里拐了几道弯还能透出来的一点
				float direct = exp(-tau) + 0.22 * exp(-tau * 0.3);
				float powder = 1.0 - exp(-d * 200.0);
				float hfrac = clamp((p.y - cloud_base) / (cloud_top - cloud_base), 0.0, 1.0);
				vec3 ambient = mix(fog_dark * 0.2, sky_top * 1.2, hfrac);
				vec3 light = moon_color * direct * phase * mix(0.35, 1.0, powder) * moon_strength + ambient;
				float a = 1.0 - exp(-d * dt);
				acc += trans * a * light;
				trans *= 1.0 - a;
				if (trans < 0.01) {
					break;
				}
			}
			s += dt;
		}
		result = vec4(acc, trans);
	}
	// 和上一帧混合：这个像素的方向在上一帧云图里的位置（没转头时就是同一个像素）；
	// 刚重置时上一帧是无效内容，转头转出上一帧云图的部分也没有，都不能碰
	vec2 huv = dir_to_cloud_uv(yaw_dir(yaw_dir(cloud_uv_to_dir(UV), yaw), -history_yaw));
	float inside = step(0.0, huv.x) * step(huv.x, 1.0) * step(0.0, huv.y) * step(huv.y, 1.0);
	float hw = history_weight * inside;
	vec4 col = hw > 0.0 ? mix(result, texture(history, huv), hw) : result;
	// 云图是 8 位的：每次只往新样本挪 8%，挪不满一个台阶就会四舍五入回原处，云卡在旧值上。
	// 写入前加上逐帧不同、±半个台阶的抖动（随机舍入），平均下来不偏
	vec2 seed = FRAGCOORD.xy + float(frame_index) * vec2(37.0, 17.0);
	COLOR = col + (vec4(hash22(seed), hash22(seed + 71.3)) - 0.5) / 255.0;
}
