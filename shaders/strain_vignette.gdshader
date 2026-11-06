// 体力见底、生死关头时屏幕四周泛起的暗红，跟着心跳一涨一缩（FishingView._strain）。
// 不读屏幕，只叠一层颜色：在后期之上、HUD 之下。amount 0 = 看不见，1 = 最浓；pulse 是心跳 0~1，由 FishingView 每帧给。
shader_type canvas_item;

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float aspect = 1.7778;
uniform vec3 tint : source_color = vec3(0.3, 0.015, 0.02);

void fragment() {
	vec2 d = UV - 0.5;
	d.x *= aspect;
	float r = length(d) / (0.5 * sqrt(aspect * aspect + 1.0));  // 0 = 正中，1 = 四角
	float edge = smoothstep(0.42 - pulse * 0.08, 1.0, r);
	float a = amount * edge * (0.8 + 0.2 * pulse);
	COLOR = vec4(tint * (0.7 + 0.5 * pulse), clamp(a * 1.25, 0.0, 0.92));
}
