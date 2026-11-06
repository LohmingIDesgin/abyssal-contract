// 黄昏时包住四周的黑雾（GodPresence 的 _fog）：从画面四周涌上来，地平线上一条厚雾挡住祂的脚，天上越高越浓，
// 祂的头顶埋在雾里；雾一团一团地流动；眼睛一带薄一点，脸和眼睛露得出来。
// 画在祂之上、船之下，所以船不会被雾吞掉。投影参数（aspect、horizon、roll）和海面同一份，WaterView 每帧给。
shader_type canvas_item;

#include "res://shaders/sea_common.gdshaderinc"

uniform float amount = 0.0;         // 0 = 没有雾，1 = 包严了（涌上来时四周先浓、中间后浓）
uniform float time = 0.0;
uniform vec3 fog_color : source_color = vec3(0.025, 0.01, 0.01);   // 浓处近乎黑
uniform vec3 glow_color : source_color = vec3(0.3, 0.07, 0.04);    // 薄处透出一点背后红天的暗红
uniform vec2 eyes_uv = vec2(0.5, 0.28);  // 眼睛在屏幕上的位置（0~1），GodPresence 给
uniform float clearing = 0.24;           // 眼睛一带雾薄一点的半径（屏幕高）
uniform float bank_height = 0.06;        // 地平线上那一条雾的厚度（屏幕高）
uniform float max_alpha = 0.93;

void fragment() {
	vec2 p = (SCREEN_UV - 0.5) * vec2(aspect, 1.0);
	float h = horizon - (sin(roll) * p.x + cos(roll) * p.y);  // 离地平线多高（屏幕高），地平线以下为负
	// 四周包上来：离画面中心越远越浓（横向宽一点，画面是横的）
	float edge = smoothstep(0.32, 1.0, length(p * vec2(0.82, 1.3)));
	// 地平线上一条厚雾挡住祂的脚；地平线以下的海上也蒙一层
	float bank = exp(-pow(h / bank_height, 2.0)) * 0.85 + smoothstep(0.0, -0.3, h) * 0.3;
	// 天上越高越浓：祂的头顶在雾里
	float high = smoothstep(0.08, 0.5, h) * 0.4;
	vec2 fp = p * 2.4 + vec2(time * 0.035, -time * 0.006);
	float n = fbm(fp, 4);
	float n2 = fbm(fp * 2.2 - vec2(time * 0.06, 0.0) + 3.3, 3);
	float density = clamp(edge + bank + high, 0.0, 1.0) * (0.45 + 0.75 * n + 0.2 * n2);
	// 眼睛一带薄一点
	float d_eye = length((SCREEN_UV - eyes_uv) * vec2(aspect, 1.0));
	density *= 0.35 + 0.65 * smoothstep(0.0, clearing, d_eye);
	// 涌上来：四周先浓，中间后浓
	float arrive = smoothstep(0.0, 1.0, amount * 1.7 - (1.0 - edge) * 0.7);
	float alpha = clamp(density, 0.0, max_alpha) * arrive;
	COLOR = vec4(mix(glow_color, fog_color, smoothstep(0.2, 0.75, density)), alpha);
}
