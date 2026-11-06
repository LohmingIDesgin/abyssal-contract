// 签下的名字：字的笔画本身就是幽蓝的火，火在笔画里面翻滚（交接文档 §2.3：活着的契约者，名字一直在烧）。
// 不往字外面冒火苗。TEXTURE 是名字的白字（SoulName 用 SubViewport 画的，四周留了一圈给光晕）。
// 笔画里：往上流、被扭曲的噪声决定哪里亮哪里暗，越靠笔画中间越热（冷白的芯），边上是深蓝；
// 笔画外面贴着一圈随火明灭的淡蓝光。dead = 1 时火灭，字变成冷掉的灰（死了的契约者，名册里用）。
shader_type canvas_item;

uniform vec3 deep : source_color = vec3(0.04, 0.12, 0.38);
uniform vec3 mid : source_color = vec3(0.16, 0.45, 0.92);
uniform vec3 hot : source_color = vec3(0.55, 0.88, 1.0);
uniform vec3 core : source_color = vec3(0.93, 0.98, 1.0);
uniform float cell = 20.0;    // 火纹的大小（贴图像素）
uniform float speed = 1.0;
uniform float dead : hint_range(0.0, 1.0) = 0.0;

// 片段里的 COLOR 进来时已经乘过一遍贴图，这里要自己多次取贴图，所以顶点色另外存一份
varying vec4 tint;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	tint = COLOR;
}

void fragment() {
	float a = texture(TEXTURE, UV).a;
	// 笔画有多"厚"：近处一圈取样的平均覆盖，越靠笔画中间越接近 1；远一圈的给外面的光晕
	float thick = 0.0;
	float halo = 0.0;
	for (int i = 0; i < 8; i++) {
		float ang = float(i) * 0.785398;
		vec2 d = vec2(cos(ang), sin(ang)) * TEXTURE_PIXEL_SIZE;
		thick += texture(TEXTURE, UV + d * 3.0).a;
		halo += texture(TEXTURE, UV + d * 11.0).a;
	}
	thick /= 8.0;
	halo /= 8.0;
	// 往上流、被扭曲的火纹
	float t = TIME * speed;
	vec2 q = UV / TEXTURE_PIXEL_SIZE / cell;
	vec2 w = vec2(fbm(q * 0.7 + vec2(0.0, t * 0.6)), fbm(q * 0.7 + vec2(3.7, t * 0.5))) - 0.5;
	float n = fbm(q + w * 1.6 + vec2(0.0, t * 1.4));
	// 再叠一层更细、更快的，火才"滚"
	float n2 = fbm(q * 2.3 - w * 1.2 + vec2(1.3, t * 2.6));
	float heat = clamp((n * 0.75 + n2 * 0.45) * 1.45 + thick * 0.4 - 0.62, 0.0, 1.0);
	vec3 fire = mix(deep, mid, smoothstep(0.0, 0.35, heat));
	fire = mix(fire, hot, smoothstep(0.35, 0.7, heat));
	fire = mix(fire, core, smoothstep(0.78, 1.0, heat));
	vec3 ash = vec3(0.42, 0.45, 0.48) * (0.8 + 0.2 * n);
	vec3 col = mix(fire, ash, dead);
	float glow = halo * (1.0 - a) * 0.5 * (1.0 - dead) * (0.7 + 0.6 * n);
	COLOR = vec4(mix(mid, col, a), max(a, glow)) * tint;
}
