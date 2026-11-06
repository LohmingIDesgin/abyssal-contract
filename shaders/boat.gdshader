// 船头贴图的光照：月夜的冷色环境光 + 船头灯的暖光（随距离衰减、随火苗闪烁），
// 船头那一端离得远，蒙上一层薄雾。
shader_type canvas_item;

uniform vec2 lamp_uv = vec2(0.47, 0.12);   // 灯在船贴图里的位置（UV）
uniform vec3 ambient : source_color = vec3(0.4, 0.48, 0.5);
uniform vec3 lamp_color : source_color = vec3(1.0, 0.6, 0.27);
uniform float lamp_energy = 1.0;
uniform vec3 fog_color : source_color = vec3(0.36, 0.44, 0.46);
uniform float tex_aspect = 4.45;          // 贴图宽高比，让光圈在屏幕上是圆的

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 d = (UV - lamp_uv) * vec2(tex_aspect, 1.0);
	d.y *= 1.5;                              // 船板往远处延伸：纵向按透视拉长
	float r = length(d);
	float att = lamp_energy / (1.0 + r * r * 14.0);
	// 贴图越亮的地方（船舷顶面、横梁）越像是朝上、朝灯的面，吃光更多
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	float catch_light = 0.45 + 1.1 * lum;
	vec3 lit = c.rgb * (ambient + lamp_color * att * catch_light * 1.7);
	float far = 1.0 - smoothstep(0.0, 0.4, UV.y);
	lit = mix(lit, fog_color, far * 0.3);
	COLOR = vec4(lit, c.a);
}
