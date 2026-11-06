// 落水：一道起伏的水线从屏幕下沿漫上来，水下的画面晃动、糊开、染成深青，气泡一串串往上冒；
// 再往后越来越暗，最后沉进黑水里（DeathScreen 控制）。读屏幕，叠在最上面（落水时 HUD 先收起来）。
// amount 0 = 原样，0.35 时水线漫过整个屏幕，1 = 几乎全黑。
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;
uniform float aspect = 1.7778;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 往上冒的气泡：两层大小不同的格子，每格有一定概率有一个空心的泡
float bubbles(vec2 uv, float t) {
	float acc = 0.0;
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		float scale = 6.0 + fi * 6.0;
		vec2 p = uv * vec2(scale * aspect, scale);
		p.y += t * (0.9 + fi * 0.55);
		p.x += sin(p.y * 1.7 + fi * 2.0) * 0.18;
		vec2 cell = floor(p);
		vec2 f = fract(p) - 0.5;
		float h = hash(cell + fi * 17.0);
		if (h > 0.76) {
			vec2 c = vec2(hash(cell + 3.1) - 0.5, hash(cell + 7.7) - 0.5) * 0.45;
			float r = 0.07 + 0.13 * hash(cell + 1.3);
			float d = length(f - c);
			float ring = smoothstep(r, r - 0.025, d) * smoothstep(r - 0.075, r - 0.03, d);
			float glint = smoothstep(r * 0.35, 0.0, length(f - c + vec2(r * 0.35, r * 0.35)));
			acc += (ring + glint * 0.8) * (0.5 + 0.5 * h);
		}
	}
	return acc;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float rise = clamp(amount / 0.35, 0.0, 1.0);
	// 水线：从下沿（1.0）升到上沿以上（-0.12），带起伏
	float wave = sin(uv.x * 9.0 + time * 3.1) * 0.018 + sin(uv.x * 23.0 - time * 4.7) * 0.007;
	float level = mix(1.02, -0.12, rise * rise * (3.0 - 2.0 * rise));
	float under = smoothstep(level - 0.012, level + 0.012, uv.y + wave);
	// 水下：晃动、糊开、染成深青
	vec2 wobble = vec2(sin(uv.y * 17.0 + time * 2.3), cos(uv.x * 13.0 + time * 1.9)) * 0.014;
	vec3 above = textureLod(screen, uv, amount * 1.2).rgb;
	vec3 below = textureLod(screen, uv + wobble * under, 2.6 + amount * 2.0).rgb;
	float g = dot(below, vec3(0.299, 0.587, 0.114));
	below = mix(below, vec3(g), 0.5) * vec3(0.32, 0.62, 0.66) + vec3(0.0, 0.025, 0.03);
	vec3 c = mix(above, below, under);
	// 水线上一道泛白的沫
	c += vec3(0.55, 0.72, 0.72) * exp(-abs(uv.y + wave - level) * 160.0) * 0.45 * (1.0 - rise * 0.6);
	// 气泡
	c += vec3(0.5, 0.75, 0.78) * bubbles(uv, time) * 0.24 * under * (1.0 - smoothstep(0.4, 0.85, amount));
	// 四周压黑；越到后面越暗，沉到最后是极深的青黑，正中略亮一点
	vec2 d = uv - 0.5;
	d.x *= aspect;
	float vignette = smoothstep(1.05, 0.25, length(d));
	float dark = smoothstep(0.3, 1.0, amount);
	c *= mix(1.0, vignette, under * 0.7);
	vec3 abyss = vec3(0.006, 0.026, 0.032) * (0.4 + 0.9 * vignette);
	c = mix(c, abyss, dark * 0.97);
	COLOR = vec4(c, 1.0);
}
