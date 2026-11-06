// 冥海夜景。画在一张全屏 2D 面片上，但每个像素都在做 3D 计算：
// 从虚拟相机射出一条光线，和海面高度场、礁石的有向距离场求交，再算光照和雾。
// 分层：
//   天空：体积云在 1/3 分辨率的离屏图里另算（sky_clouds.gdshader），这里取回来盖在夜空和月亮上
//   礁石：沿航路确定性摆放的海蚀柱、海蚀拱、崖壁、低礁（GDScript 每帧给出离船最近的几处），
//        有向距离场光线步进；船往前漂，它们从雾里由远及近、从两侧退出画面；有的礁石脚下点着一盏灯
//   海面几何：涌浪（5 组方向波，深水色散 + 二阶斯托克斯尖顶，解析法线）+ 风浪（不重复）+ 细纹，
//            高度场光线求交（上下包围平面之间二分），浪会互相遮挡
//   海面着色：水体吸收色、浪尖透光、菲涅尔反射（云和礁石的倒影）、月光路、船头灯和礁石灯的碎金、
//            白浪与泡沫纹、礁石脚下的碎浪
//   大气：随高度变稀的雾（贴着海面最浓，成团漂移），贴着水面流动的低雾，礁石上的灯在雾里的光晕
// 相机、噪声、云的形状和 sky_clouds.gdshader 共用 sea_common.gdshaderinc。
shader_type canvas_item;

#include "res://shaders/sea_common.gdshaderinc"

uniform sampler2D cloud_tex : filter_linear, repeat_disable;   // rgb = 云散射的光，a = 透过率

// 涌浪：(kx, kz, 振幅, 角频率)，相位
uniform vec4 swells[5];
uniform float swell_phase[5];
uniform float stokes = 3.0;
uniform vec2 wind_dir = vec2(0.42, -0.91);
uniform float chop_amp = 0.2;

// 船头灯（相机坐标）
uniform vec3 lamp_pos = vec3(-0.4, 1.7, 2.8);
uniform vec3 lamp_color : source_color = vec3(1.0, 0.6, 0.27);
uniform float lamp_energy = 1.0;

// 礁石（相机坐标）：a = (x, z, 底半径或半长, 高)，b = (类型 0 柱 1 拱 2 崖 3 低礁, 种子, 朝向, 有灯)
uniform int rock_count = 0;
uniform vec4 rock_a[8];
uniform vec4 rock_b[8];

uniform vec3 fog_light : source_color = vec3(0.62, 0.69, 0.69);
uniform vec3 water_deep : source_color = vec3(0.004, 0.03, 0.05);
uniform vec3 water_scatter : source_color = vec3(0.03, 0.2, 0.25);
uniform vec3 foam_color : source_color = vec3(0.74, 0.81, 0.8);
uniform vec3 rock_dark : source_color = vec3(0.04, 0.055, 0.06);
uniform vec3 rock_light : source_color = vec3(0.17, 0.2, 0.21);
uniform float fog_density = 0.0264;   // 海面上的雾浓度（每米）
uniform float fog_height = 8.0;       // 每升高这么多米，雾浓度降到 1/e
uniform float rain = 0.0;             // 雨多大（0~1）：近处水面起涟漪、溅白点，月光路发暗，贴水的低雾更浓

// ---------- 噪声（其余在 sea_common.gdshaderinc） ----------

// Worley：返回 (F1, F2)
vec2 worley(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash22(i + g);
			float d = length(g + o - f);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec2(f1, f2);
}

// ---------- 海面几何（参数是世界坐标 xz） ----------

// 涌浪：返回 (高度, ∂h/∂x, ∂h/∂z)
vec3 swell(vec2 xz, float t) {
	vec3 r = vec3(0.0);
	for (int i = 0; i < 5; i++) {
		vec4 s = swells[i];
		float k = length(s.xy);
		float th = dot(s.xy, xz) - s.w * t + swell_phase[i];
		float q = 0.5 * k * s.z * stokes;
		r.x += s.z * (cos(th) + q * cos(2.0 * th));
		float d = -s.z * (sin(th) + 2.0 * q * sin(2.0 * th));
		r.y += d * s.x;
		r.z += d * s.y;
	}
	return r;
}

// 风浪的一个八度：山脊噪声，浪尖窄、浪谷宽
float chop_octave(vec2 p) {
	float n = noise(p);
	float r = 1.0 - abs(n * 2.0 - 1.0);
	return r * r;
}

float chop(vec2 xz, float t, int octaves) {
	float h = 0.0;
	float amp = chop_amp;
	float freq = 0.32;
	vec2 p = xz;
	vec2 w1 = wind_dir;
	vec2 w2 = vec2(wind_dir.x * 0.94 - wind_dir.y * 0.34, wind_dir.x * 0.34 + wind_dir.y * 0.94);
	for (int i = 0; i < octaves; i++) {
		float speed = 1.25 / sqrt(freq);   // 波长越长走得越快
		float a = chop_octave(p * freq - w1 * t * speed * freq);
		float b = chop_octave(mat2(vec2(0.96, 0.28), vec2(-0.28, 0.96)) * p * freq * 1.07 - w2 * t * speed * freq + 31.7);
		h += (a + b - 0.9) * amp * 0.5;
		p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p;
		freq *= 1.93;
		amp *= 0.42;
	}
	return h;
}

vec2 world_xz(vec2 xz) {
	return xz + vec2(0.0, travel);
}

float sea_height(vec2 xz, float t, int octaves) {
	vec2 w = world_xz(xz);
	return swell(w, t).x + chop(w, t, octaves);
}

// 高度场求交：沿视线往前走，找到第一次从水面以上到水面以下的那一小段，再在这一小段里用割线法收敛。
// 2026-11-05 改：原来直接在 [t0, t1]（视线从浪顶以上到浪底以下的整段）里用割线法收敛。快平视的视线这一段有几百米，
// 里面好几个浪头，会收到随便哪一个浪头上：相邻的像素落在不同的浪上，中远处的海面就是一道道条带。
// 往左看最明显：几道长涌浪都从左前方来（WaterView.SWELLS），视线迎着浪走，一条视线穿过的浪头最多。
// 步长：离水面越高步子越大（海面最陡也就 0.5 上下，离水面 h 米走 2h 米碰不上浪），离得越远步子也越大
// （100 米外九成多都在雾里，差一点看不出来）。走满 SEA_MARCH 步还没碰到的（快平视、很远），在剩下那一段里照旧收敛
const int SEA_MARCH = 36;
const int SEA_REFINE = 6;

float trace_sea(vec3 ro, vec3 rd, float t, out vec3 hit) {
	float top = 1.6;
	float t0 = max((ro.y - top) / -rd.y, 0.0);
	float t1 = min((ro.y + top) / -rd.y, 600.0);
	vec3 p1 = ro + rd * t1;
	float h1 = p1.y - sea_height(p1.xz, t, 3);
	// 几乎平视地平线、600 米内还没碰到海面：就当是那么远的海面（反正全在雾里）。
	// 不提前返回的话，两端都在水面以上，下面的插值会除以零，地平线上冒出零星黑点
	if (h1 > 0.0) {
		hit = p1;
		return t1;
	}
	vec3 p0 = ro + rd * t0;
	float a = t0;
	float ha = p0.y - sea_height(p0.xz, t, 3);
	float b = t1;
	float hb = h1;
	for (int i = 0; i < SEA_MARCH; i++) {
		float tn = min(a + max(ha * 2.0, 0.5 + a * 0.04), t1);
		vec3 pn = ro + rd * tn;
		float hn = pn.y - sea_height(pn.xz, t, 3);
		if (hn < 0.0) {
			b = tn;
			hb = hn;
			break;
		}
		a = tn;
		ha = hn;
		if (tn >= t1) {
			break;
		}
	}
	float tm = b;
	for (int i = 0; i < SEA_REFINE; i++) {
		tm = mix(a, b, clamp(ha / max(ha - hb, 1e-5), 0.0, 1.0));
		vec3 pm = ro + rd * tm;
		float hm = pm.y - sea_height(pm.xz, t, 3);
		if (hm < 0.0) {
			b = tm;
			hb = hm;
		} else {
			a = tm;
			ha = hm;
		}
	}
	hit = ro + rd * tm;
	return tm;
}

vec3 sea_normal(vec2 xz, float t, float dist) {
	vec2 w = world_xz(xz);
	vec3 s = swell(w, t);
	float e = 0.05 + dist * 0.004;
	int oct = dist < 60.0 ? 5 : 3;
	float c0 = chop(w, t, oct);
	float cx = chop(w + vec2(e, 0.0), t, oct);
	float cz = chop(w + vec2(0.0, e), t, oct);
	vec2 g = s.yz + vec2(cx - c0, cz - c0) / e;
	// 细纹：只扰动法线，近处才有
	float near = clamp(1.0 - dist / 28.0, 0.0, 1.0);
	if (near > 0.0) {
		vec2 r1 = w * 1.7 + wind_dir * t * 0.9;
		vec2 r2 = mat2(vec2(0.6, 0.8), vec2(-0.8, 0.6)) * w * 2.6 - wind_dir * t * 0.6;
		float n0 = noise(r1) + noise(r2) * 0.6;
		float nx = noise(r1 + vec2(0.06, 0.0)) + noise(r2 + vec2(0.06 * 1.53, 0.0)) * 0.6;
		float nz = noise(r1 + vec2(0.0, 0.06)) + noise(r2 + vec2(0.0, 0.06 * 1.53)) * 0.6;
		g += vec2(nx - n0, nz - n0) * 0.7 * near;
	}
	return normalize(vec3(-g.x, 1.0, -g.y));
}

// ---------- 礁石（有向距离场，参数是礁石本地坐标） ----------

// 礁石的步进里要取成千上万次噪声：改用 WaterView 预先生成的可平铺噪声贴图，一次取样代替几十次哈希运算。
// 3D 贴图每 8 个单位重复一次，2D 贴图每 32 个单位；取值 0~1，和 noise3 / noise 用法一样
uniform sampler3D noise_tex3 : filter_linear, repeat_enable;
uniform sampler2D noise_tex2 : filter_linear, repeat_enable;

float tnoise3(vec3 p) {
	return texture(noise_tex3, p * 0.125).r;
}

float tnoise2(vec2 p) {
	return texture(noise_tex2, p * 0.03125).r;
}

float sd_box(vec3 p, vec3 b) {
	vec3 q = abs(p) - b;
	return length(max(q, vec3(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// 一根石柱：截面是椭圆、越往上越细、轴线微微歪斜，脚下堆着塌下来的碎石
float sd_spire(vec3 q, vec2 base, float r, float h, float seed) {
	float t = clamp(q.y / h, 0.0, 1.0);
	vec2 c = q.xz - base - vec2(sin(seed * 2.1), cos(seed * 1.3)) * r * 0.5 * t * t;
	float a = seed * 3.0 + t * 0.9;
	c = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * c;
	c.y *= 1.45;
	float rr = r * (1.0 - 0.5 * t + 0.1 * sin(t * 7.0 + seed * 5.0)) * (1.0 + 0.35 * smoothstep(0.15, 0.0, t));
	float d = (length(c) - rr) * 0.69;
	float top = h * (0.86 + 0.14 * tnoise2(q.xz * 0.15 + seed));
	return max(d, q.y - top);
}

// 海蚀柱：一根主柱和两根矮一些的副柱长在一起（轮廓高低错落），一道道层理是高低不齐、深浅不一的浅槽
float sd_stack(vec3 q, float r, float h, float seed) {
	float d = sd_spire(q, vec2(0.0), r, h, seed);
	vec2 o1 = vec2(cos(seed * 4.0), sin(seed * 4.0)) * r * 0.9;
	vec2 o2 = vec2(cos(seed * 4.0 + 2.4), sin(seed * 4.0 + 2.4)) * r * 0.85;
	d = smin(d, sd_spire(q, o1, r * 0.62, h * (0.45 + 0.25 * fract(seed * 1.7)), seed + 1.3), r * 0.35);
	d = smin(d, sd_spire(q, o2, r * 0.5, h * (0.2 + 0.2 * fract(seed * 2.3)), seed + 2.9), r * 0.35);
	float sy = q.y + (tnoise2(q.xz * 0.04 + seed) - 0.5) * 10.0;
	float groove = 1.0 - smoothstep(0.0, 0.12, abs(fract(sy / 6.5) - 0.5));
	return d + groove * r * 0.05 * tnoise2(vec2(floor(sy / 6.5), seed));
}

// 海蚀拱：两根柱子顶上连着一道石梁，中间被浪掏出拱洞。石梁和柱子长在一起，顶面起伏、中间微微塌下去
float sd_arch(vec3 q, float r, float h, float seed) {
	float span = r * 2.4;
	float a = sd_stack(q - vec3(-span, 0.0, 0.0), r * 0.9, h, seed);
	float b = sd_stack(q - vec3(span, 0.0, 0.0), r * 0.85, h * 0.93, seed + 2.7);
	float u = q.x / span;
	float top = h * (0.8 + 0.12 * tnoise2(vec2(q.x * 0.07 + seed, seed)) - 0.06 * (1.0 - u * u));
	float thick = r * (0.75 + 0.3 * tnoise2(vec2(q.x * 0.05, seed + 3.0)));
	float bridge = max(max(abs(q.z) - thick, abs(q.x) - span * 1.1), max(q.y - top, h * 0.45 - q.y));
	bridge += (tnoise3(q * 0.05 + seed) - 0.5) * r * 0.5;
	float d = smin(min(a, b), bridge, r * 0.7);
	vec2 e = (q.xy - vec2(0.0, h * 0.26)) / vec2(span * 0.8, h * 0.46);
	float hole = (length(e) - 1.0) * min(span * 0.8, h * 0.46);
	return max(d, -hole);
}

// 崖壁：顺着航路延伸的一堵石墙，顶部起伏、两头塌下去，正面一道道竖向的柱状节理
float sd_cliff(vec3 q, float r, float h, float seed) {
	float along = abs(q.z) / r;
	float top = h * (0.62 + 0.38 * tnoise2(vec2(q.z * 0.011 + seed * 5.0, seed)));
	top *= mix(0.12, 1.0, 1.0 - smoothstep(0.45, 1.0, along));
	float face = abs(q.x) - r * 0.2 - (tnoise2(vec2(q.z * 0.018, q.y * 0.012) + seed) - 0.5) * r * 0.14;
	face -= abs(sin(q.z * 0.16 + tnoise2(vec2(q.y * 0.02, seed)) * 4.0)) * 2.4;   // 柱状节理：棱是尖的
	face -= smoothstep(10.0, 0.0, q.y) * 7.0;   // 崖脚的碎石坡
	// 正面不是笔直的：越往上越往后收
	face += max(q.y, 0.0) * 0.12;
	float d = max(face, abs(q.z) - r);
	return max(d, q.y - top);
}

// 低礁：几块半沉在水里的圆石
float sd_reef(vec3 q, float r, float seed) {
	float d = 1e5;
	for (int i = 0; i < 4; i++) {
		vec2 o = (hash22(vec2(seed, float(i))) - 0.5) * r * 1.6;
		float rr = r * (0.3 + 0.28 * hash12(vec2(float(i) + 3.0, seed)));
		vec3 c = vec3(o.x, -rr * 0.4, o.y);
		d = min(d, length((q - c) * vec3(1.0, 1.5, 1.0)) / 1.5 - rr);
	}
	return d;
}

float rock_sdf(int i, vec3 p) {
	vec4 a = rock_a[i];
	vec4 b = rock_b[i];
	vec3 q = p - vec3(a.x, 0.0, a.y);
	float c = cos(b.z);
	float s = sin(b.z);
	q.xz = mat2(vec2(c, -s), vec2(s, c)) * q.xz;
	int kind = int(b.x + 0.5);
	float d;
	if (kind == 0) {
		d = sd_stack(q, a.z, a.w, b.y);
	} else if (kind == 1) {
		d = sd_arch(q, a.z, a.w, b.y);
	} else if (kind == 2) {
		d = sd_cliff(q, a.z, a.w, b.y);
	} else {
		d = sd_reef(q, a.z, b.y);
	}
	// 表面：大块的风化起伏 + 细碎的岩面
	float ds = min(a.z, 22.0);
	d += (tnoise3(q * 0.08 + b.y) - 0.5) * ds * 0.22;
	if (d < ds * 0.12) {   // 贴近表面才加细的一层，远处步进时省掉
		d += (tnoise3(q * 0.23 + b.y * 2.0) - 0.5) * ds * 0.07;
	}
	return d;
}

// 包围圆柱的半径：要把噪声鼓出来的部分也包进去
float rock_radius(int i) {
	int kind = int(rock_b[i].x + 0.5);
	float r = rock_a[i].z;
	return kind == 1 ? r * 4.6 : (kind == 2 ? r * 1.05 : r * 2.2);
}

// 每处礁石的包围圆柱：返回 (进入距离, 离开距离)，没碰到返回 (-1, -1)
vec2 rock_bounds(int i, vec3 ro, vec3 rd) {
	vec4 a = rock_a[i];
	int kind = int(rock_b[i].x + 0.5);
	float rad = rock_radius(i);
	float top = kind == 3 ? a.z : a.w * 1.05 + 4.0;
	vec2 oc = ro.xz - a.xy;
	float A = dot(rd.xz, rd.xz);
	float B = dot(oc, rd.xz);
	float C = dot(oc, oc) - rad * rad;
	float disc = B * B - A * C;
	if (disc < 0.0 || A < 1e-8) {
		return vec2(-1.0);
	}
	float sq = sqrt(disc);
	float t0 = (-B - sq) / A;
	float t1 = (-B + sq) / A;
	float ta = (-3.0 - ro.y) / rd.y;
	float tb = (top - ro.y) / rd.y;
	t0 = max(max(t0, min(ta, tb)), 0.0);
	t1 = min(t1, max(ta, tb));
	if (t1 <= t0) {
		return vec2(-1.0);
	}
	return vec2(t0, t1);
}

// 光线和所有礁石求交：返回最近的命中距离（没碰到为 -1）和是哪一处。
// steps / eps_scale 给倒影用更粗的步进
float trace_rocks(vec3 ro, vec3 rd, float tmax, int steps, float eps_scale, out int which) {
	float best = -1.0;
	which = -1;
	for (int i = 0; i < 8; i++) {
		if (i >= rock_count) {
			break;
		}
		vec2 tb = rock_bounds(i, ro, rd);
		if (tb.x < 0.0) {
			continue;
		}
		float t = tb.x;
		float tend = min(tb.y, tmax);
		if (best > 0.0) {
			tend = min(tend, best);
		}
		for (int s = 0; s < steps; s++) {
			if (t > tend) {
				break;
			}
			float d = rock_sdf(i, ro + rd * t);
			float eps = (0.03 + t * 0.0012) * eps_scale;
			if (d < eps) {
				best = t;
				which = i;
				break;
			}
			t += max(d * 0.6, eps);
		}
	}
	return best;
}

vec3 rock_normal(int i, vec3 p, float t) {
	float e = 0.06 + t * 0.002;
	vec2 k = vec2(1.0, -1.0);
	return normalize(k.xyy * rock_sdf(i, p + k.xyy * e) + k.yyx * rock_sdf(i, p + k.yyx * e)
		+ k.yxy * rock_sdf(i, p + k.yxy * e) + k.xxx * rock_sdf(i, p + k.xxx * e));
}

// 礁石脚下那盏灯的位置：在朝航路、朝来船方向的那一面，离岩面几米
vec3 beacon_pos(int i) {
	vec4 a = rock_a[i];
	float off = rock_b[i].x < 0.5 ? a.z * 2.0 : a.z * 0.3 + 10.0;
	float side = a.x < 0.0 ? 1.0 : -1.0;
	return vec3(a.x + side * off, 4.0, a.y - off * 0.35);
}

vec3 shade_rock(int i, vec3 p, vec3 rd, float t, vec3 md) {
	vec3 n = rock_normal(i, p, t);
	vec4 a = rock_a[i];
	vec4 b = rock_b[i];
	vec3 q = p - vec3(a.x, 0.0, a.y);
	// 近处再加一层细碎的岩面起伏（只扰动法线，不改形状）
	float near = 1.0 - smoothstep(25.0, 150.0, t);
	if (near > 0.0) {
		vec3 bq = q * 0.7 + b.y;
		float b0 = tnoise3(bq) + tnoise3(bq * 2.3) * 0.5;
		vec3 g = vec3(tnoise3(bq + vec3(0.2, 0.0, 0.0)) + tnoise3((bq + vec3(0.2, 0.0, 0.0)) * 2.3) * 0.5,
			tnoise3(bq + vec3(0.0, 0.2, 0.0)) + tnoise3((bq + vec3(0.0, 0.2, 0.0)) * 2.3) * 0.5,
			tnoise3(bq + vec3(0.0, 0.0, 0.2)) + tnoise3((bq + vec3(0.0, 0.0, 0.2)) * 2.3) * 0.5) - b0;
		n = normalize(n - g * 1.0 * near);
	}
	// 底色：玄武岩的深青灰；层理一明一暗；雨水和鸟粪往下冲出的竖条；朝上的台阶积着白色的盐霜和鸟粪
	float strata = tnoise2(vec2(q.y * 0.32 + b.y * 3.0, 0.5));
	float streak = tnoise2(vec2((q.x + q.z) * 0.45 + b.y, q.y * 0.018));
	float tone = 0.3 + 0.32 * strata + 0.3 * (tnoise3(q * 0.14) - 0.5) - 0.22 * smoothstep(0.55, 0.8, streak);
	vec3 base = mix(rock_dark, rock_light, clamp(tone, 0.0, 1.0));
	float up = smoothstep(0.55, 0.9, n.y);
	float guano = up * smoothstep(0.5, 0.72, tnoise3(q * 0.18 + 7.0)) * smoothstep(4.0, 18.0, p.y);
	guano = max(guano, smoothstep(0.82, 0.95, streak) * smoothstep(10.0, 30.0, p.y) * 0.5);
	base = mix(base, vec3(0.46, 0.5, 0.48), guano * 0.65);
	// 吃水线往上几米被浪打湿：更暗、反光
	float wet = 1.0 - smoothstep(0.0, 4.5, p.y + (tnoise2(q.xz * 0.4) - 0.5) * 2.0);
	base *= mix(1.0, 0.45, wet);
	// 光：月光（多是侧逆光，明暗交界收得软一点，像画出来的）；
	// 环境光：朝上的面接夜空的暗青，侧面和下半截接周围被照亮的雾（越靠近海面雾越浓越亮）
	float moon = smoothstep(0.0, 0.55, dot(n, md));
	vec3 amb = mix(fog_dark * mix(0.55, 1.0, exp(-p.y / 25.0)), sky_top * 1.6, smoothstep(-0.2, 1.0, n.y));
	float rim = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
	float ao = clamp(rock_sdf(i, p + n * 2.0) / 2.0, 0.0, 1.0) * 0.6 + 0.4;
	vec3 col = base * (moon_color * moon * 0.75 + amb) * ao + fog_light * rim * 0.1;
	col += moon_color * pow(max(dot(reflect(rd, n), md), 0.0), 24.0) * wet * 0.25;
	// 礁石脚下那盏灯，和船头的鲸油灯（贴近时把岩壁照暖）
	if (b.w > 0.5) {
		vec3 lv = beacon_pos(i) - p;
		float ld = length(lv);
		col += base * lamp_color * max(dot(n, lv / ld), 0.0) * 9.0 / (1.0 + ld * ld * 0.05);
	}
	vec3 bl = lamp_pos - p;
	float bd = length(bl);
	col += base * lamp_color * lamp_energy * max(dot(n, bl / bd), 0.0) * 5.0 / (1.0 + bd * bd * 0.015);
	return col;
}


// ---------- 大气 ----------

// 雾的颜色：朝月亮的方向更亮（前向散射）；往高处看，雾被照得越来越少，越来越暗
vec3 fog_tint(vec3 d, vec3 md) {
	vec2 a = normalize(d.xz + vec2(0.0001));
	vec2 b = normalize(md.xz);
	float toward = pow(max(dot(a, b), 0.0), 3.0);
	return mix(fog_dark, fog_light, 0.45 + 0.55 * toward) * mix(1.0, 0.38, smoothstep(0.03, 0.5, d.y));
}

// 从相机沿 rd 走 dist 米累积的雾：浓度随高度指数变稀，并成团漂移
float fog_amount(vec3 rd, float dist, vec2 bank_xz, float thickness) {
	float h = fog_height * thickness;
	float y0 = cam_height;
	float dy = rd.y * dist;
	float integral;
	if (abs(dy) < 0.01) {
		integral = exp(-y0 / h) * dist;
	} else {
		integral = h * (exp(-y0 / h) - exp(-(y0 + dy) / h)) / rd.y;
	}
	float bank = 0.75 + 0.6 * fbm(bank_xz * 0.012 + vec2(sea_time * 0.01, 0.0), 3);
	return 1.0 - exp(-fog_density * integral * bank);
}

// 天空方向上雾层的厚度随方位起伏：海平线上的雾堤上缘参差不齐
float fog_bank_thickness(vec3 d) {
	return 0.75 + 0.6 * fbm(vec2(atan(d.x, d.z) * 3.2, sea_time * 0.006 + travel * 0.0008), 4);
}

// ---------- 天空 ----------

// 云层上方的夜空：稀疏的星、月亮
vec3 night_sky(vec3 d, vec3 md) {
	float elev = max(d.y, 0.0);
	vec3 col = mix(fog_dark * 0.55, sky_top * 0.6, smoothstep(0.0, 0.5, elev));
	float a = acos(clamp(dot(d, md), -1.0, 1.0));
	vec2 sc = d.xy / max(d.z, 0.05) * 170.0;
	vec2 sf = fract(sc) - 0.5;
	// 星星在月亮后面：月盘和贴着它的那圈亮光里不画
	col += vec3(0.7, 0.78, 0.85) * step(0.9965, hash12(floor(sc))) * exp(-dot(sf, sf) * 50.0) * 0.8 * smoothstep(0.022, 0.03, a);
	// 月亮：盘面上有深浅的"月海"，边缘略暗；四周一圈光晕
	float disk = smoothstep(0.0185, 0.0165, a);
	vec3 e1 = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
	vec2 local = vec2(dot(d - md, e1), dot(d - md, cross(e1, md))) / 0.0175;
	float maria = smoothstep(0.42, 0.68, fbm(local * 1.6 + 4.0, 3));
	float limb = sqrt(max(1.0 - dot(local, local), 0.0));
	float face = (0.86 - 0.26 * maria) * mix(0.8, 1.0, limb);
	float glow = exp(-a * 40.0) * 0.32 + exp(-a * 9.0) * 0.08;
	col += moon_color * mix(glow, face, disk);
	return col;
}

// 某个方向（世界方向）的天空：夜空和月亮，盖上离屏云图里同一个方向的云。云图跟着视线转，所以先转回视线坐标再取
vec3 sky(vec3 d, vec3 md) {
	vec3 dc = yaw_dir(d, -yaw);
	vec4 cl = texture(cloud_tex, clamp(dir_to_cloud_uv(vec3(dc.xy, max(dc.z, 0.05))), vec2(0.002), vec2(0.998)));
	vec3 col = night_sky(d, md) * cl.a + cl.rgb;
	// 月亮躲在云后时，薄云被它照亮的一圈
	float a = acos(clamp(dot(d, md), -1.0, 1.0));
	col += moon_color * exp(-a * 7.0) * 0.1 * (1.0 - cl.a);
	return col;
}

// 倒影里的天空：从同一张云图里按反射方向取（超出云图的取边上的）
vec3 sky_reflect(vec3 d, vec3 md) {
	vec3 col = sky(d, md);
	return mix(col, fog_tint(d, md), fog_amount(d, 1e5, vec2(0.0), fog_bank_thickness(d)));
}

// ---------- 雨 ----------

// 雨点打在近处的水面上：一圈圈往外扩的涟漪（改法线，让灯和天光照出来），刚落下的地方溅起一点白（splash）。
// 水面按世界坐标切成格子，每格隔一会儿落一滴；两层大小不同、错开的格子，每层看离得最近的四格
vec3 rain_ripples(vec2 w, float t, float dist, vec3 n, out float splash) {
	splash = 0.0;
	float fade = rain * (1.0 - smoothstep(14.0, 40.0, dist));
	vec2 g = vec2(0.0);
	for (int layer = 0; layer < 2; layer++) {
		float scale = layer == 0 ? 1.7 : 2.6;
		vec2 cw = w * scale + float(layer) * 31.7;
		vec2 base = floor(cw - 0.5);
		for (int j = 0; j < 2; j++) {
			for (int i = 0; i < 2; i++) {
				vec2 id = base + vec2(float(i), float(j));
				vec2 c = id + 0.5 + (hash22(id) - 0.5) * 0.5;
				float phase = fract(t * 0.9 + hash12(id + 7.3));
				vec2 dv = cw - c;
				float d = length(dv);
				float x = d - phase * 0.6;
				float ring = sin(x * 30.0) * exp(-x * x * 120.0) * (1.0 - phase) * (1.0 - phase);
				g += dv / max(d, 0.001) * ring;
				splash = max(splash, smoothstep(0.16, 0.0, d) * smoothstep(0.18, 0.0, phase));
			}
		}
	}
	splash *= fade * smoothstep(30.0, 8.0, dist);
	return normalize(n + vec3(g.x, 0.0, g.y) * 0.6 * fade);
}

// ---------- 海面着色 ----------

vec3 ocean(vec3 rd, vec3 p, float dist, float t, vec3 md) {
	vec2 w = world_xz(p.xz);
	vec3 n = sea_normal(p.xz, t, dist);
	// 远处法线逐渐压平，避免细碎闪烁
	n = normalize(mix(n, vec3(0.0, 1.0, 0.0), smoothstep(80.0, 260.0, dist) * 0.8));
	float splash = 0.0;
	if (rain > 0.001 && dist < 40.0) {
		n = rain_ripples(w, t, dist, n, splash);
	}
	vec3 v = -rd;
	float ndv = max(dot(n, v), 0.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	vec3 r = reflect(rd, n);
	r.y = abs(r.y);
	// 反射：被浪面倾斜带向更暗的高空，整体偏一点青；礁石在水里投下暗色的倒影
	vec3 refl = sky_reflect(r, md) * vec3(0.84, 0.92, 0.94);
	if (dist < 260.0) {
		int which;
		float tr = trace_rocks(p + vec3(0.0, 0.3, 0.0), r, 900.0, 28, 4.0, which);
		if (tr > 0.0) {
			vec3 rock_col = rock_dark * 1.3;
			if (rock_b[which].w > 0.5) {
				rock_col += lamp_color * 0.06 / (1.0 + dot(beacon_pos(which) - p, beacon_pos(which) - p) * 0.004);
			}
			refl = mix(rock_col, fog_tint(r, md), fog_amount(r, tr, vec2(0.0), 1.0));
		}
	}

	// 水体：浪越高越薄、越透光（迎着月光的浪尖泛青）
	vec3 sw = swell(w, t);
	float crest = clamp(p.y * 0.9 + 0.35, 0.0, 1.0);
	float back = pow(dot(normalize(vec3(-md.x, 0.0, -md.z)), normalize(vec3(rd.x, 0.0, rd.z))) * 0.5 + 0.5, 3.0);
	vec3 body = water_deep + water_scatter * crest * crest * (0.4 + 0.9 * back) * 0.7;
	body += fog_dark * 0.05 * max(n.y, 0.0);
	vec3 col = mix(body, refl, fres);

	// 月光路：被云遮着，光斑偏宽、碎闪不多
	float rm = max(dot(r, md), 0.0);
	float glint = smoothstep(0.7, 0.92, noise(w * 3.0 + vec2(t * 1.3, -t)));
	col += moon_color * (pow(rm, 600.0) * 2.2 * glint + pow(rm, 60.0) * 0.18 + pow(rm, 8.0) * 0.025) * (1.0 - 0.6 * rain);

	// 船头灯
	vec3 lv = lamp_pos - p;
	float ld = length(lv);
	vec3 l = lv / ld;
	float att = lamp_energy / (1.0 + ld * ld * 0.11);
	float lamp_diff = max(dot(n, l), 0.0);
	float lamp_spec = pow(max(dot(n, normalize(l + v)), 0.0), 90.0);
	col += lamp_color * att * (lamp_spec * 2.6 + lamp_diff * 0.025 + 0.012);
	// 礁石上的灯在浪面上拖出的一道碎金
	for (int i = 0; i < 8; i++) {
		if (i >= rock_count) {
			break;
		}
		if (rock_b[i].w > 0.5) {
			vec3 bv = beacon_pos(i) - p;
			float bd = length(bv);
			float bspec = pow(max(dot(n, normalize(bv / bd + v)), 0.0), 140.0);
			col += lamp_color * bspec * 30.0 / (1.0 + bd * bd * 0.01);
		}
	}

	// 白浪：浪尖 + 风浪尖峰处起泡，泡沫是 Worley 网格的蕾丝
	float detail = clamp(1.0 - dist / 120.0, 0.0, 1.0);
	float c0 = chop(w, t, 3);
	float crest_mask = smoothstep(0.06, 0.3, c0 / max(chop_amp, 0.001) * 0.5 + sw.x * 0.26 - 0.04);
	vec2 fp = w * 1.6 + wind_dir * t * 0.35;
	vec2 cell = worley(fp);
	float lace = 1.0 - smoothstep(0.0, 0.12, cell.y - cell.x);
	vec2 cell2 = worley(fp * 2.3 + 11.0);
	float lace2 = 1.0 - smoothstep(0.0, 0.1, cell2.y - cell2.x);
	float bubbles = clamp(lace * 0.8 + lace2 * 0.5, 0.0, 1.0);
	float foam = crest_mask * mix(1.0, bubbles, 0.6) * detail;
	// 浪后拖出的细长泡沫纹（顺风拉长）
	vec2 sp = vec2(dot(w, wind_dir), dot(w, vec2(-wind_dir.y, wind_dir.x)));
	float streak = smoothstep(0.66, 0.92, noise(vec2(sp.x * 0.25, sp.y * 2.6) + t * 0.05)) * smoothstep(0.0, 0.25, c0 / max(chop_amp, 0.001) * 0.5);
	foam = max(foam, streak * 0.35 * bubbles * detail);
	// 礁石脚下：浪拍上去碎成一片白，一涌一涌的
	float surf = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= rock_count) {
			break;
		}
		vec4 a = rock_a[i];
		if (length(p.xz - a.xy) < rock_radius(i) + 14.0) {
			float d = rock_sdf(i, vec3(p.x, max(p.y, 0.4), p.z));
			float pulse = 0.65 + 0.35 * sin(t * 1.6 - d * 0.9 + rock_b[i].y * 5.0);
			surf = max(surf, (1.0 - smoothstep(0.0, 5.5 * pulse + 1.0, d)) * pulse);
		}
	}
	foam = max(foam, surf * mix(0.75, 1.0, bubbles) * clamp(1.0 - dist / 400.0, 0.0, 1.0));
	vec3 foam_lit = foam_color * (0.58 + 0.3 * max(dot(n, md), 0.0)) + lamp_color * att * lamp_diff * 0.9;
	col = mix(col, foam_lit, clamp(foam, 0.0, 1.0) * 0.85);
	col = mix(col, foam_lit * 1.25 + lamp_color * att * 0.8, clamp(splash, 0.0, 1.0) * 0.9);

	// 一点幽光：零星的青绿磷火漂在水面上
	vec2 cid = floor(w * 0.35);
	float hc = hash12(cid);
	if (hc > 0.975) {
		vec2 f = fract(w * 0.35) - 0.5 - (hash22(cid) - 0.5) * 0.5;
		float g = exp(-dot(f, f) * 140.0) * (0.5 + 0.5 * sin(t * (0.8 + hc * 1.7) + hc * 40.0));
		col += vec3(0.25, 0.85, 0.68) * max(g, 0.0) * 0.45 * smoothstep(60.0, 10.0, dist);
	}
	return col;
}

// 贴着水面流动的低雾：沿视线在几个距离上取样
float mist(vec3 rd, float dist, float t) {
	float m = 0.0;
	for (int i = 0; i < 4; i++) {
		float d = 7.0 + float(i) * 11.0;
		if (d > dist) {
			break;
		}
		vec3 q = vec3(0.0, cam_height, 0.0) + rd * d;
		float hfade = exp(-max(q.y, 0.0) / 1.6);
		float n = fbm(world_xz(q.xz) * 0.055 + vec2(t * 0.22, t * 0.06) + float(i) * 13.1, 3);
		m += smoothstep(0.46, 0.82, n) * hfade * 0.2;
	}
	return clamp(m * (1.0 + rain * 0.7), 0.0, 0.7);
}

// 礁石上的灯在雾里的光晕（光比物体更能穿透雾）：灯芯会被挡住，被雾散开的那一团不会
vec3 beacons(vec3 rd, float dist) {
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		if (i >= rock_count) {
			break;
		}
		if (rock_b[i].w < 0.5) {
			continue;
		}
		vec3 lv = beacon_pos(i) - vec3(0.0, cam_height, 0.0);
		float ld = length(lv);
		vec3 l = lv / ld;
		float ang = acos(clamp(dot(rd, l), -1.0, 1.0));
		float trans = 1.0 - fog_amount(l, ld, vec2(0.0), 1.0);
		float flick = 0.8 + 0.2 * noise(vec2(sea_time * 1.3, float(i) * 7.0));
		float core = ld < dist + 3.0 ? exp(-ang * 900.0) * 2.5 * pow(trans, 0.4) : 0.0;
		// 雾把灯光散成一大团暖晕
		float halo = (exp(-ang * 110.0) * 0.55 + exp(-ang * 28.0) * 0.14) / (1.0 + ld / 90.0);
		acc += lamp_color * (core + halo * pow(trans, 0.22)) * flick;
	}
	return acc;
}

const float ROCK_FADE_START = 480.0;   // 礁石从这么远开始从雾里淡出来，生成的地方（ROCK_AHEAD）完全看不见
const float ROCK_FADE_END = 700.0;

void fragment() {
	vec3 rd = yaw_dir(uv_to_dir(UV), yaw);
	vec3 ro = vec3(0.0, cam_height, 0.0);
	float t = sea_time;
	vec3 md = moon_dir();
	vec3 fogc = fog_tint(rd, md);
	float t_sea = 1e5;
	vec3 hit = vec3(0.0);
	if (rd.y < -0.0008) {
		t_sea = trace_sea(ro, rd, t, hit);
	}
	int which;
	float t_rock = trace_rocks(ro, rd, min(t_sea, 2500.0), 72, 1.0, which);
	vec3 col;
	float dist;
	if (t_rock > 0.0) {
		dist = t_rock;
		col = shade_rock(which, ro + rd * t_rock, rd, t_rock, md);
		col = mix(col, fogc, fog_amount(rd, dist, world_xz((rd * min(dist, 600.0)).xz), 1.0));
		// 远处刚生成的礁石：淡入到它身后本来的样子（天上是云，地平线下是雾里的海）
		float fade = smoothstep(ROCK_FADE_START, ROCK_FADE_END, dist);
		if (fade > 0.0) {
			vec3 behind = fogc;
			if (rd.y > 0.0) {
				behind = mix(sky(rd, md), fogc, fog_amount(rd, 1e5, world_xz((rd * 600.0).xz), fog_bank_thickness(rd)));
			}
			col = mix(col, behind, fade);
		}
	} else if (rd.y < -0.0008) {
		dist = t_sea;
		col = ocean(rd, hit, t_sea, t, md);
		col = mix(col, fogc, fog_amount(rd, dist, world_xz(hit.xz), 1.0));
	} else {
		dist = 1e5;
		col = sky(rd, md);
		col = mix(col, fogc, fog_amount(rd, dist, world_xz((rd * 600.0).xz), fog_bank_thickness(rd)));
	}
	col += beacons(rd, dist);
	col = mix(col, fogc * 1.1, mist(rd, dist, t));
	COLOR = vec4(col, 1.0);
}
