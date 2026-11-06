// 剪影：只取贴图的形状（alpha），颜色换成画的时候给的那个颜色（draw_texture_rect 的 modulate）。
// 结算清单里"献上过的种类和时期"的小格子用（SettlementScreen）：献过的是亮起来的骨白剪影，没献过的是暗下去的影子。
// 片段里进来的 COLOR 已经乘过贴图，所以顶点色在 vertex 里先存下来。
shader_type canvas_item;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	COLOR = vec4(tint.rgb, texture(TEXTURE, UV).a * tint.a);
}
