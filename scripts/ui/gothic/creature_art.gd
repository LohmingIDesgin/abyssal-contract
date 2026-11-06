class_name CreatureArt
extends RefCounted
## 生物插图怎么动（2026-11-05）：渔获展示（CatchReveal）、图鉴的大立绘（CodexScreen）都画在一张细分过的网格上，
## 挂 shaders/creature_display.gdshader。动效按种类（FishData.motion_style），每一种有自己的一套：
## 身子怎么动在着色器的顶点里，附肢（鳍、须、手指、头灯、触须、水草……）各自摆在片段里，附肢在哪来自动效遮罩
## （assets/creatures/motion/同名.png，tools/bake_motion_masks.py 从插图的透明度烘的）。
## 新加一种生物：在 .tres 里选 motion_style，插图放进 assets/creatures/ 以后跑一遍烘遮罩的工具。

const SHADER := preload("res://shaders/creature_display.gdshader")

## 动效：id → 着色器里的 style 号、附肢怎么摆（limb_amp 尖上摆多远占图高、limb_freq 每秒几弧度、limb_lag 根到尖落后的相位、
## limb_curl 顺着长的方向一缩一伸、limb_jerk 一抽一抽的程度）、亮处一明一暗（glow）；会游的另有头上的须、头灯怎么飘（head_amp、
## head_freq、head_lag，没写的和 limb 一样）。身子的摆幅、快慢、波长在各种的 .tres 里
const STYLES := {
	"fish": {"style": 0, "name": "鱼", "limb_amp": 0.09, "limb_freq": 12.0, "limb_lag": 2.5, "limb_curl": 0.0, "limb_jerk": 0.0, "glow": 0.0,
		"head_amp": 0.045, "head_freq": 2.2, "head_lag": 3.5,
		"note": "尾巴带着后半身摆，鳍各自抖，忽快忽慢"},
	"eel": {"style": 1, "name": "鳗", "limb_amp": 0.07, "limb_freq": 8.0, "limb_lag": 3.0, "limb_curl": 0.0, "limb_jerk": 0.0, "glow": 0.0,
		"head_amp": 0.04, "head_freq": 2.0, "head_lag": 3.0,
		"note": "一道波从头传到尾，整条身子扭"},
	"lantern": {"style": 2, "name": "灯笼", "limb_amp": 0.045, "limb_freq": 2.0, "limb_lag": 1.6, "limb_curl": 0.0, "limb_jerk": 0.0,
		"glow": 0.7, "head_amp": 0.05, "head_freq": 1.6, "head_lag": 1.3, "note": "悬着慢慢起伏、轻轻歪，头灯像钟摆一样慢慢地晃，灯一明一暗"},
	"hand": {"style": 3, "name": "手", "limb_amp": 0.05, "limb_freq": 2.0, "limb_lag": 1.2, "limb_curl": 0.05, "limb_jerk": 0.0, "glow": 0.0,
		"note": "整只手慢慢浮着转，手指一根一根地弯、松，腕上的水草跟着漂"},
	"jelly": {"style": 4, "name": "水母", "limb_amp": 0.09, "limb_freq": 2.6, "limb_lag": 3.5, "limb_curl": 0.0, "limb_jerk": 0.0,
		"glow": 0.45, "note": "伞盖一缩一放往前推，触须拖着波，身上的光一明一暗"},
	"puffer": {"style": 5, "name": "鲀", "limb_amp": 0.05, "limb_freq": 16.0, "limb_lag": 1.5, "limb_curl": 0.0, "limb_jerk": 0.0, "glow": 0.0,
		"head_amp": 0.04, "head_freq": 2.0, "head_lag": 3.0,
		"note": "一鼓一瘪地呼吸，小鳍扇得飞快"},
	"crab": {"style": 6, "name": "蟹", "limb_amp": 0.05, "limb_freq": 4.5, "limb_lag": 1.0, "limb_curl": 0.02, "limb_jerk": 0.8, "glow": 0.0,
		"note": "身子一颠一颠，腿一抽一抽"},
	"flat": {"style": 7, "name": "扁的", "limb_amp": 0.05, "limb_freq": 5.0, "limb_lag": 2.5, "limb_curl": 0.0, "limb_jerk": 0.0, "glow": 0.0,
		"note": "从上往下看：两侧的边一道一道地起伏"},
	"shell": {"style": 8, "name": "螺", "limb_amp": 0.04, "limb_freq": 1.2, "limb_lag": 1.5, "limb_curl": 0.03, "limb_jerk": 0.0, "glow": 0.3,
		"note": "壳几乎不动，软的部分慢慢伸缩"},
	"whale": {"style": 9, "name": "鲸", "limb_amp": 0.04, "limb_freq": 2.5, "limb_lag": 2.0, "limb_curl": 0.0, "limb_jerk": 0.0, "glow": 0.0,
		"head_amp": 0.04, "head_freq": 1.6, "head_lag": 2.5,
		"note": "慢慢地上下拍尾，整个身子跟着一俯一仰"},
}

## 会游的动效：沿着身子的"脊"传波（tools/bake_motion_masks.py 的 SWIMMERS 要和这里一样）
const SWIMMERS: Array[String] = ["fish", "eel", "lantern", "puffer", "whale"]

static var _masks := {}
static var _bodies := {}


## 这张插图的动效遮罩（assets/creatures/motion/同名.png）；没烘过的返回 null，着色器就按老办法抖上下边缘
static func mask_for(tex: Texture2D) -> Texture2D:
	if tex == null or tex.resource_path == "":
		return null
	var path := tex.resource_path.get_base_dir().path_join("motion").path_join(tex.resource_path.get_file())
	if not _masks.has(path):
		_masks[path] = load(path) if ResourceLoader.exists(path) else null
	return _masks[path]


## 这张插图的"脊"（assets/creatures/motion/同名_body.png）：会游的沿着它传波；没有返回 null（按横坐标、往上下推）
static func body_for(tex: Texture2D) -> Texture2D:
	if tex == null or tex.resource_path == "":
		return null
	var file := tex.resource_path.get_file()
	var path := tex.resource_path.get_base_dir().path_join("motion").path_join(file.get_basename() + "_body." + file.get_extension())
	if not _bodies.has(path):
		_bodies[path] = load(path) if ResourceLoader.exists(path) else null
	return _bodies[path]


static func style_of(fish: FishData) -> Dictionary:
	return STYLES.get(fish.motion_style if fish else "fish", STYLES.fish)


## 一个新的材质（着色器的其余参数照默认）
static func make_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	return mat


## 给材质配上这一种、这张插图的动效。art_size 是显示的大小（像素）；seed 让同一种的几条错开，不给就按种类定
static func apply(mat: ShaderMaterial, fish: FishData, tex: Texture2D, art_size: Vector2, seed := -1.0) -> void:
	var st := style_of(fish)
	mat.set_shader_parameter("style", st.style)
	mat.set_shader_parameter("amplitude", fish.motion_amplitude if fish else 0.02)
	mat.set_shader_parameter("speed", fish.motion_speed if fish else 1.0)
	mat.set_shader_parameter("wavelength", fish.motion_wavelength if fish else 1.3)
	mat.set_shader_parameter("height_px", art_size.y)
	mat.set_shader_parameter("width_px", art_size.x)
	if seed < 0.0:
		seed = float(absi(hash(fish.id if fish else "")) % 997) / 997.0
	mat.set_shader_parameter("seed", seed)
	for k in ["limb_amp", "limb_freq", "limb_lag", "limb_curl", "limb_jerk"]:
		mat.set_shader_parameter(k, st[k])
	mat.set_shader_parameter("head_amp", st.get("head_amp", st.limb_amp))
	mat.set_shader_parameter("head_freq", st.get("head_freq", st.limb_freq))
	mat.set_shader_parameter("head_lag", st.get("head_lag", st.limb_lag))
	mat.set_shader_parameter("glow_pulse", st.glow)
	var mask := mask_for(tex)
	mat.set_shader_parameter("has_mask", mask != null)
	mat.set_shader_parameter("motion_mask", mask)
	var body := body_for(tex)
	mat.set_shader_parameter("has_body", body != null)
	mat.set_shader_parameter("body_mask", body)


## 不动的东西（捞上来的道具）：只轻轻浮着，不摆
static func apply_still(mat: ShaderMaterial, art_size: Vector2) -> void:
	mat.set_shader_parameter("style", STYLES.shell.style)
	mat.set_shader_parameter("amplitude", 0.0)
	mat.set_shader_parameter("speed", 0.6)
	mat.set_shader_parameter("height_px", art_size.y)
	mat.set_shader_parameter("width_px", art_size.x)
	mat.set_shader_parameter("limb_amp", 0.0)
	mat.set_shader_parameter("glow_pulse", 0.0)
	mat.set_shader_parameter("has_mask", false)
	mat.set_shader_parameter("has_body", false)


## 一张细分过的网格，中心在原点，UV 铺满（插图里头朝左：UV.x 0 = 头，1 = 尾）
static func grid(art_size: Vector2, cols := 48, rows := 16) -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in rows + 1:
		for i in cols + 1:
			var uv := Vector2(float(i) / cols, float(j) / rows)
			verts.append((uv - Vector2(0.5, 0.5)) * art_size)
			uvs.append(uv)
	for j in rows:
		for i in cols:
			var a := j * (cols + 1) + i
			idx.append_array([a, a + 1, a + cols + 1, a + 1, a + cols + 2, a + cols + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
