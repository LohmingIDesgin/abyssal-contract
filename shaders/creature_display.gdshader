// 生物插图（渔获展示、图鉴的大立绘），画在一张细分过的网格上（CreatureArt.grid），让一张平面插图动起来。
// 插图里头都朝左：UV.x 0 = 头，1 = 尾。动效按种类（FishData.motion_style → style，CreatureArt.STYLES）：
//   0 鱼：尾巴带着后半身摆（尾鳍跟着这道波，不单独抖），头往反方向稳着，忽快忽慢（几秒一阵）
//   1 鳗：一道波从脖子传到尾，整条身子扭，头整块跟着
//   2 灯笼：悬着慢慢起伏、轻轻歪，尾巴懒懒地摆；头灯慢慢地晃（头上的附肢），亮处一明一暗
//   3 手：整只手慢慢浮着转、一握一松；手指靠附肢一根一根地弯
//   4 水母：伞盖一缩一放往前推，后面拖着波
//   5 鲀：一鼓一瘪地呼吸，尾巴快快地扇
//   6 蟹：身子一颠一颠、左右挪；腿靠附肢一抽一抽
//   7 扁的（鳐、鲽，从上往下看）：两侧的边一道一道地起伏
//   8 螺：几乎不动，慢慢地胀缩
//   9 鲸：慢慢地上下拍尾，整个身子一俯一仰
// 会游的（鱼、鳗、灯笼、鲀、鲸）沿着身子的"脊"传那道波（body_mask，烘遮罩的工具一起烘的：R = 从头沿着身子量过去的 s，
//   GB = 横过身子的方向）：弯的身子、往上翘的尾巴也是横着摆，不会顺着自己伸缩。没有脊的图按老办法：s = 横坐标、往上下推。
// 附肢（鳍、须、手指、头灯、触须、水草……）各自摆：位置来自 motion_mask（tools/bake_motion_masks.py 从插图的透明度烘的）：
//   R 离身子多远（根部 0、尖上 1），G 相位（0–0.5 是鳍这些，快快地抖；0.5–1 是头上的须、头灯，慢慢地飘），B 方向（根指向尖的角度 ÷ 2π）。
//   取样是反着的（这一点显示的是 uv − 位移处的颜色），遮罩在形状外面也铺了几个像素，附肢才摆得出去。
//   没有遮罩时按老办法：上下边缘、尾巴尖轻轻抖。
// 其余的：sheen 光泽掠过、dissolve 处理时烧掉、hue_shift「变色」、mutation「变异」。
shader_type canvas_item;

uniform int style = 0;
uniform float amplitude = 0.03;   // 身子的摆幅，占图高的比例
uniform float speed = 1.4;        // 每秒摆几下
uniform float wavelength = 1.3;   // 波长，按身长算
uniform float height_px = 300.0;  // 显示高度（像素），把比例换成像素
uniform float width_px = 600.0;   // 显示宽度（像素）
uniform float seed = 0.0;         // 每一种（每一条）错开一点，不会一起一模一样地摆
uniform sampler2D motion_mask : filter_linear, repeat_disable;
uniform bool has_mask = false;
uniform sampler2D body_mask : filter_linear, repeat_disable;
uniform bool has_body = false;
uniform float head_amp = 0.045;   // 头上的须、头灯尖上摆多远，占图高
uniform float head_freq = 2.0;    // 须、头灯每秒几弧度（慢慢地飘）
uniform float head_lag = 3.0;     // 须从根到尖落后的相位（像水草一样一路传过去）
uniform float limb_amp = 0.06;    // 附肢尖上横着摆多远，占图高
uniform float limb_freq = 8.0;    // 附肢每秒摆几弧度
uniform float limb_lag = 2.5;     // 从根到尖相位落后多少（像鞭子一样甩过去）
uniform float limb_curl = 0.0;    // 顺着长的方向往回缩多少（手指弯），占图高
uniform float limb_jerk = 0.0;    // 0 = 平滑地摆，1 = 一抽一抽
uniform float glow_pulse = 0.0;   // 亮的地方一明一暗的幅度
uniform float exposure = 1.0;     // 亮度倍率，1 = 插图原样
uniform float sheen = -1.0;       // 光泽掠过的位置，-1 = 不显示
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec3 burn_color : source_color = vec3(0.3, 0.95, 0.8);
uniform float hue_shift = 0.0;    // 「变色」转到的色相（0–1），0 = 不变
uniform float mutation = 0.0;     // 「变异」：0 = 没有，1 = 有

// 片段里的 COLOR 进来时已经乘过一遍贴图，这里自己取贴图（要扭 UV），所以顶点色另外存一份
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

// 一维的平滑噪声，0–1
float noise1(float x) {
	return noise(vec2(x, seed * 17.0));
}

// 几秒一阵的"劲头"：0.6–1.4，鱼游得忽快忽慢，不是一个节拍摆到底
float surge(float t) {
	return 0.6 + 0.8 * noise1(t * 0.35);
}

vec2 rotated(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// 在 YIQ 里转色相、加浓：亮度不变，青灰的插图也能转出一个分明的颜色
vec3 recolor(vec3 c, float h) {
	const mat3 TO_YIQ = mat3(vec3(0.299, 0.596, 0.211), vec3(0.587, -0.274, -0.523), vec3(0.114, -0.322, 0.312));
	const mat3 TO_RGB = mat3(vec3(1.0), vec3(0.956, -0.272, -1.106), vec3(0.621, -0.647, 1.703));
	vec3 yiq = TO_YIQ * c;
	float a = h * TAU;
	vec2 dir = vec2(cos(a), sin(a));
	yiq.yz = vec2(yiq.y * dir.x - yiq.z * dir.y, yiq.y * dir.y + yiq.z * dir.x) * 1.8 + dir * 0.09 * smoothstep(0.03, 0.4, yiq.x);
	return TO_RGB * yiq;
}

void vertex() {
	tint = COLOR;
	float x = UV.x;
	float yc = UV.y - 0.5;
	float tm = TIME + seed * 13.0;
	// 时间轻轻地拧一拧：节拍有快有慢（导数在 ±20% 以内，不会倒着摆）
	float T = (tm + 0.6 * noise1(tm * 0.3)) * speed * TAU;
	float A = amplitude * height_px;
	vec2 v = VERTEX;
	// 会游的沿着脊传波：s 从头量到尾，nrm 横过身子（没有脊的图：s = 横坐标、往下）
	float s = x;
	vec2 nrm = vec2(0.0, 1.0);
	if (has_body) {
		vec3 b = textureLod(body_mask, UV, 0.0).rgb;
		s = b.r;
		vec2 n = b.gb * 2.0 - 1.0;
		nrm = length(n) > 0.001 ? normalize(n) : vec2(0.0, 1.0);
	}
	if (style == 1) {
		// 鳗：整条身子一道波，头动得少、尾巴动得多；身子顺着波一伸一缩。
		// 头那一截（前 25%）整块跟着脖子动、不跟着波弯（不然张着的大嘴会像果冻一样软）
		float se = max(s, 0.25);
		float env = mix(0.12, 1.0, se * se);
		v += nrm * sin(TAU * se / wavelength - T) * A * env * surge(tm);
		v.x += sin(T * 0.5 + 1.0) * A * 0.15;
	} else if (style == 2) {
		// 灯笼：悬在水里慢慢起伏、轻轻歪（慢，不打颤），尾巴懒懒地摆
		v = rotated(v, sin(tm * 0.45) * 0.025);
		v.y += sin(tm * 0.8) * height_px * 0.018;
		float tail = smoothstep(0.45, 1.0, s);
		v += nrm * sin(TAU * s / wavelength - T) * A * tail * tail;
	} else if (style == 3) {
		// 手：慢慢浮着转、一握一松（离腕子远的那头收得多）
		float grip = 0.5 + 0.5 * sin(tm * 0.8);
		v = rotated(v, sin(tm * 0.45) * 0.045);
		v *= 1.0 + 0.012 * sin(tm * 0.8 + 1.5);
		v.x += grip * (0.5 - x) * width_px * 0.012;
		v.y += sin(tm * 0.7) * height_px * 0.015;
	} else if (style == 4) {
		// 水母：伞盖（前面）一缩一放，缩的那一下往前推；后面拖着波
		float p = pow(0.5 + 0.5 * sin(T * 0.5), 3.0);
		float bell = 1.0 - smoothstep(0.15, 0.6, x);
		v.y *= 1.0 - 0.12 * p * bell;
		v.x -= p * width_px * 0.015;
		v.y += sin(TAU * x / wavelength - T * 0.5 - 1.0) * A * smoothstep(0.3, 1.0, x);
	} else if (style == 5) {
		// 鲀：一鼓一瘪（身子胀，尾巴不太胀），尾巴快快地扇
		float puff = 0.5 + 0.5 * sin(tm * 1.1);
		v *= 1.0 + 0.045 * puff * (1.0 - 0.6 * smoothstep(0.6, 1.0, x));
		v += nrm * sin(T * 1.6) * A * smoothstep(0.7, 1.0, s);
		v.y += sin(tm * 0.8) * height_px * 0.01;
	} else if (style == 6) {
		// 蟹：一颠一颠（抬起快、落下慢），偶尔往旁边挪一挪
		v.y -= pow(abs(sin(tm * 1.7)), 0.6) * height_px * 0.012;
		v.x += (noise1(tm * 0.4) - 0.5) * width_px * 0.02;
	} else if (style == 7) {
		// 扁的（从上往下看）：两侧的边往中线收、放，一道一道地从头传到尾
		float e = abs(yc) * 2.0;
		float wave = 0.5 + 0.5 * sin(TAU * x / wavelength - T);
		v.y -= sign(yc) * e * e * wave * A;
		v.y += sin(tm * 0.6) * height_px * 0.01;
	} else if (style == 8) {
		// 螺：几乎不动，慢慢地胀缩、浮沉
		v *= 1.0 + 0.012 * sin(tm * 0.6);
		v.y += sin(tm * 0.4) * height_px * 0.008;
	} else if (style == 9) {
		// 鲸：慢慢地上下拍尾，身子跟着一俯一仰，整个慢慢浮沉
		float tail = smoothstep(0.4, 1.0, s);
		v += nrm * sin(TAU * s / wavelength - T) * A * tail * tail;
		v.y += sin(T + 1.8) * A * 0.15 * (0.5 - x);
		v.y += sin(tm * 0.35) * height_px * 0.015;
	} else {
		// 鱼：尾巴带着后半身摆，头往反方向带一点，整条身子像在水里稳着；几秒一阵，忽快忽慢
		float sg = surge(tm);
		float tail = smoothstep(0.25, 1.0, s);
		v += nrm * sin(TAU * s / wavelength - T) * A * tail * tail * sg;
		v.y += sin(T + 1.3) * A * 0.18 * (0.35 - x) * sg;
		v.y += sin(tm * 0.8) * height_px * 0.008;
	}
	VERTEX = v;
}

void fragment() {
	vec2 uv = UV;
	float tm = TIME + seed * 13.0;
	if (has_mask) {
		vec3 m = texture(motion_mask, uv).rgb;
		float w = m.r;
		if (w > 0.003) {
			// 头上的须、头灯（G ≥ 0.5）慢慢地飘、一路传到尖；别的（鳍、手指、腿……）按这一种的附肢参数
			float kind = step(0.5, m.g);
			float ph = fract(m.g * 2.0) * TAU;
			float amp = mix(limb_amp, head_amp, kind);
			float freq = mix(limb_freq, head_freq, kind);
			float lag = mix(limb_lag, head_lag, kind);
			// 鳍这些：慢的种类（speed 不到 1：白鲟、千目鲇、磷灯婆）鳍也摆得慢一点、小一点；
			// 长的鳍外头那一截整块摆（权重到 0.4 为止），不会越往尖上甩得越远、像在扇翅膀
			float wl = w;
			if (kind < 0.5) {
				float pace = clamp(speed, 0.5, 1.0);
				freq *= pace;
				amp *= 0.4 + 0.6 * pace;
				wl = min(w, 0.4);
			}
			float ang = m.b * TAU;
			vec2 axis = vec2(cos(ang), sin(ang));
			vec2 perp = vec2(-axis.y, axis.x);
			float a = tm * freq + ph - wl * lag;
			float s = sin(a);
			s = mix(s, sign(s) * pow(abs(s), 0.25), limb_jerk * (1.0 - kind));
			float curl = 0.5 - 0.5 * cos(tm * freq * 0.5 + ph);
			// 尖上的位移（像素）：横着摆，顺着长的方向往回缩
			vec2 d = (perp * s * amp - axis * curl * limb_curl * (1.0 - kind)) * wl * height_px;
			uv -= d / vec2(width_px, height_px);
		}
	} else {
		float fins = smoothstep(0.34, 0.0, uv.y) + smoothstep(0.66, 1.0, uv.y);
		uv.y += sin(uv.x * 42.0 + TIME * 7.0) * 0.0022 * fins;
		uv.x += sin(uv.y * 31.0 + TIME * 5.0) * 0.0016 * smoothstep(0.78, 1.0, uv.x);
	}
	if (mutation > 0.0) {
		vec2 bulge = vec2(noise(uv * 6.0 + TIME * 0.3), noise(uv * 6.0 + 7.3 - TIME * 0.25)) - 0.5;
		uv += bulge * 0.014 * mutation;
	}
	vec4 c = texture(TEXTURE, uv);
	if (hue_shift > 0.0) {
		c.rgb = max(recolor(c.rgb, hue_shift), vec3(0.0));
	}
	if (mutation > 0.0) {
		float ridge = 1.0 - abs(noise(uv * vec2(14.0, 9.0) + 3.1) * 2.0 - 1.0);
		float vein = smoothstep(0.86, 0.97, ridge) * (0.55 + 0.45 * sin(TIME * 2.3 + uv.x * 9.0));
		c.rgb = mix(c.rgb, vec3(0.45, 0.04, 0.06) * (0.6 + c.rgb), vein * 0.75 * mutation);
		c.rgb *= 1.0 - 0.15 * mutation;
	}
	if (glow_pulse > 0.0) {
		// 亮的地方（头灯、发光的斑）一明一暗，节拍也带一点乱
		float lum = max(c.r, max(c.g, c.b));
		float g = smoothstep(0.5, 0.85, lum) * c.a;
		float beat = 0.5 + 0.5 * sin(tm * 1.7 + 0.9 * sin(tm * 0.6));
		c.rgb *= 1.0 + glow_pulse * g * (beat - 0.35);
	}
	c.rgb *= exposure;
	if (sheen > -0.5) {
		float d = uv.x * 0.8 + uv.y * 0.35 - sheen;
		c.rgb += exp(-d * d / 0.0025) * 0.4 * c.a;
	}
	if (dissolve > 0.0) {
		float n = noise(uv * vec2(9.0, 5.0)) * 0.65 + noise(uv * vec2(23.0, 13.0)) * 0.35;
		float cut = dissolve * 1.15 - 0.1;
		float edge = smoothstep(cut, cut + 0.06, n);
		c.rgb = mix(burn_color * 1.6, c.rgb, smoothstep(cut + 0.02, cut + 0.07, n));
		c.a *= edge;
	}
	COLOR = c * tint;
}
