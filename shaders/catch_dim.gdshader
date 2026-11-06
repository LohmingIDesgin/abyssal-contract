// 钓上东西时把身后的画面压下去：褪成冷灰、变暗、四周更暗、微微糊开，让正中的渔获跳出来。
// 叠在后期调色之上、HUD 之下（FishingView._dim）。amount 0 = 原样，1 = 完全压下去。
// flash：生吞时一闪的幽蓝（灵魂进了身体）。
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color : source_color = vec3(0.32, 0.78, 0.86);

void fragment() {
	vec3 c = textureLod(screen, SCREEN_UV, amount * 1.6).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(g) * vec3(0.9, 0.97, 1.0), amount * 0.85);
	vec2 d = SCREEN_UV - 0.5;
	d.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float vignette = smoothstep(0.82, 0.18, length(d));
	c *= mix(1.0, 0.28 + 0.24 * vignette, amount);
	c += flash_color * flash * (0.35 + 0.65 * vignette);
	COLOR = vec4(c, 1.0);
}
