// 雨丝（RainLayer）：叠在手和鱼竿之上、后期之下，加在画面上（blend_add）。
// 四层远近不同的雨丝斜斜落下：远的细、密、淡、慢；近的粗、稀、快、亮、虚。一阵一阵的，有的地方密有的地方稀。
// 每层把屏幕切成一列列细长的格子往下落，每格里随机放一根雨丝（雨小时多数格子空着）；每列再错开一点，看不出格子。
// 雨落在世界里：转头时整片雨跟着视线横移（转头没有视差，远近一起移），船晃时跟着地平线上下、跟着横摇转。
// 船头灯旁边的雨丝被灯照成暖色。坐标：屏幕中心为原点、y 向下、单位为屏幕高（和海面着色器的屏幕坐标一样）。
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform float amount = 0.0;            // 雨多大 0~1
uniform float time = 0.0;
uniform float aspect = 1.7778;
uniform float yaw = 0.0;               // 转头（弧度，> 0 朝右看）
uniform float roll = 0.0;              // 视线横摇（和海面同一份）
uniform float horizon_shift = 0.0;     // 地平线比船平稳时低了多少（屏幕高）
uniform float focal = 1.3;
uniform vec2 lamp_uv = vec2(0.47, 0.38);
uniform vec3 lamp_color : source_color = vec3(1.0, 0.6, 0.27);
uniform float lamp_energy = 1.0;
uniform vec3 rain_color : source_color = vec3(0.55, 0.64, 0.66);
uniform float brightness = 0.13;
uniform float slant = 0.17;            // 风把雨吹斜：每往下一个单位往右偏多少

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// 一层雨丝。cells：每单位多少列、多少行；speed：下落速度（屏幕高/秒）；len：雨丝长（占格高）；
// width：雨丝宽（像素）；fill：多少格子里有雨丝；px：一个像素是多少屏幕高
float streaks(vec2 p, vec2 cells, float speed, float len, float width, float fill, float px, float seed) {
	float col = floor(p.x * cells.x);
	float shift = hash12(vec2(col, seed)) * 13.0;          // 每列错开
	float y = (p.y - time * speed) * cells.y + shift;
	vec2 id = vec2(col, floor(y));
	if (hash12(id + seed * 7.31) > fill) {
		return 0.0;
	}
	vec2 f = vec2(fract(p.x * cells.x), fract(y));
	float x0 = 0.2 + 0.6 * hash12(id + 3.7 + seed);
	float y0 = hash12(id + 9.1 + seed) * (1.0 - len);
	float w = width * px * cells.x;                         // 雨丝宽换成格宽
	float dx = (f.x - x0) / w;
	float across = exp(-dx * dx * 1.6);
	float along = smoothstep(y0, y0 + len * 0.3, f.y) * (1.0 - smoothstep(y0 + len * 0.55, y0 + len, f.y));
	return across * along * (0.45 + 0.55 * hash12(id + 17.3 + seed));
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	// 跟着视线：转回船平稳、朝正前方时的坐标
	float cr = cos(roll);
	float sr = sin(roll);
	p = vec2(cr * p.x - sr * p.y, sr * p.x + cr * p.y);
	p.y -= horizon_shift;
	p.x += yaw * focal;
	p.x -= p.y * slant;
	float px = SCREEN_PIXEL_SIZE.y;
	// 一阵一阵的：雨幕顺风扫过
	float gust = 0.65 + 0.7 * noise(vec2(p.x * 1.3 + time * 0.35, time * 0.12));
	float k = clamp(amount * gust, 0.0, 1.2);
	float far = streaks(p, vec2(150.0, 11.0), 1.4, 0.4, 1.0, 0.26 * k, px, 1.0);
	float mid = streaks(p, vec2(72.0, 6.5), 2.0, 0.42, 1.4, 0.19 * k, px, 2.0);
	float near = streaks(p, vec2(30.0, 3.4), 2.9, 0.45, 2.2, 0.13 * k, px, 3.0);
	float close = streaks(p, vec2(12.0, 1.9), 3.8, 0.5, 4.0, 0.07 * k, px, 4.0);
	float rain = far * 0.4 + mid * 0.6 + near * 0.85 + close * 0.55;
	// 船头灯旁边的雨丝被照成暖色
	vec2 lv = (UV - lamp_uv) * vec2(aspect, 1.0);
	float lamp = exp(-dot(lv, lv) * 9.0) * lamp_energy;
	vec3 col = rain_color * brightness + lamp_color * lamp * 0.55;
	COLOR = vec4(col * rain * min(amount * 1.6, 1.0), 1.0);
}
