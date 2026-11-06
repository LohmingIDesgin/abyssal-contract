// 黄昏时浮出来的祂（GodPresence 的 _art）：把 GPT 画的原画画在天上，做出"很大、很远、在雾里"的样子。
// - 从雾里显出来（form 从 0 到 1）：脸、前面的触手先显出来，一直看得清；两侧的身子和头顶在流动的雾里若隐若现。
//   半隐的地方不是变透明，而是往黑雾的颜色走，看得出雾里有一团东西
// - 脚下和海平面在一个平面上：地平线以下看不见，地平线上一小段淡进雾里；原画底下自带的那团雾化掉
// - 越往下越蒙上黄昏的雾色；本体压暗成红天前面的一大团暗影，背后的红天给轮廓描一圈暗红的边光
// - 云在祂前面：按天上云图的透过率把祂遮掉一些
// 投影参数（aspect、horizon、roll、focal……）和海面着色器同一份，WaterView 每帧给。
shader_type canvas_item;

#include "res://shaders/sea_common.gdshaderinc"

uniform sampler2D cloud_tex : filter_linear, repeat_disable;
uniform float form = 1.0;             // 样子显出来了多少（0 = 还全在雾里）
uniform float time = 0.0;
uniform vec3 body_tint : source_color = vec3(0.4, 0.31, 0.32);   // 本体压暗、偏黄昏的暗红：红天前面一大团暗影
uniform vec3 haze_color : source_color = vec3(0.42, 0.19, 0.13); // 雾色（WaterView 按黄昏程度给）
uniform vec3 fog_color : source_color = vec3(0.025, 0.01, 0.01); // 黑雾的颜色（和 god_fog 一致）
uniform vec3 rim_color : source_color = vec3(1.0, 0.33, 0.15);   // 红天的边光
uniform float rim_strength = 0.75;
uniform float rim_px = 7.0;           // 边光多宽（原画像素）
uniform float veil = 1.0;             // 两侧和头顶被雾遮住的程度
uniform float cloud_hide = 0.3;       // 云遮住祂的程度（0 = 云完全在祂后面）
uniform float horizon_fade = 0.035;   // 地平线上方这么高（屏幕高）一段淡进雾里
uniform float haze_height = 0.32;     // 离地平线这么高以下逐渐蒙雾
uniform float haze_max = 0.6;
uniform float art_mist_start = 0.7;   // 原画里 V 超过这个的部分（底下自带的雾）逐渐化掉
uniform float art_mist_end = 0.8;

void fragment() {
	vec4 art = texture(TEXTURE, UV);
	// 屏幕上离地平线多高：和海面同一个投影，横摇转过来再比
	vec2 p = (SCREEN_UV - 0.5) * vec2(aspect, 1.0);
	float height = horizon - (sin(roll) * p.x + cos(roll) * p.y);   // > 0 在地平线上方，单位是屏幕高
	float show = smoothstep(0.0, horizon_fade, height);
	float haze = (1.0 - smoothstep(0.0, haze_height, height)) * haze_max;
	// 雾里若隐若现：两侧、头顶的门槛高一截，只有雾流开的地方才露出来；中间的门槛低，一直看得清
	float edge = max(smoothstep(0.12, 0.42, abs(UV.x - 0.5)), smoothstep(0.4, 0.15, UV.y));
	vec2 fp = p * 2.4 + vec2(time * 0.035, -time * 0.006);   // 和黑雾同一片噪声，雾流开的地方对得上
	float n = fbm(fp, 4) * 0.8 + fbm(fp * 2.2 - vec2(time * 0.06, 0.0) + 3.3, 3) * 0.2;
	float threshold = mix(1.1, 0.32, form) + edge * veil * 0.3;
	float visible = smoothstep(threshold - 0.1, threshold + 0.1, n + (1.0 - edge) * 0.3);
	// 云在祂前面（云图跟着视线转，所以用没转过的视线方向去取）
	vec3 d = uv_to_dir(SCREEN_UV);
	vec4 cl = texture(cloud_tex, clamp(dir_to_cloud_uv(vec3(d.xy, max(d.z, 0.05))), vec2(0.002), vec2(0.998)));
	float through = mix(1.0, cl.a, cloud_hide);
	// 轮廓边光：周围一圈透明的地方越多，越贴着轮廓
	float around = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.7853982;
		around += texture(TEXTURE, UV + vec2(cos(a), sin(a)) * TEXTURE_PIXEL_SIZE * rim_px).a;
	}
	float rim = clamp((art.a - around / 8.0) * 2.0, 0.0, 1.0);
	vec3 col = art.rgb * body_tint + rim_color * rim * rim_strength * visible;
	col = mix(col, haze_color, haze);
	col = mix(fog_color, col, visible);   // 半隐的地方往黑雾的颜色走
	float body = smoothstep(0.0, 0.35, visible + form * 0.15) * smoothstep(0.0, 0.2, form);
	float alpha = art.a * show * through * body * (1.0 - smoothstep(art_mist_start, art_mist_end, UV.y));
	COLOR = vec4(col, alpha);
}
