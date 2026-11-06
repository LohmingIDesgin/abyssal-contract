class_name GodPresence
extends Control
## 黄昏时祂从雾里浮出来（设计对照文档 3.2 第 16 条）。原画是 GPT 画的（assets/textures/god_presence.png）。
## 放在 WaterView 里：天和海之上、浮漂和船之下（WaterView.add_god），船头柱和灯挡在祂前面。
## 出现分三步（presence 从 0 到 1）：
##   1. 四周被黑雾包起来（_fog，shaders/god_fog.gdshader）：从画面四周涌上来，地平线上一条厚雾
##   2. 雾里亮起两只眼睛（_eyes）
##   3. 祂的样子才从雾里显出来（_art，shaders/god_presence.gdshader）：脸和前面的触手看得清，
##      两侧的身子和头顶在流动的雾里若隐若现
## 退回去时倒过来：样子先没进雾里，眼睛再熄，黑雾最后散开。
## 祂很大、很远：脚下和海平面在一个平面上，跟着地平线起伏、横摇（WaterView 每帧给 horizon_shift、roll），
## 被地平线上的雾挡住一截。

const ART := preload("res://assets/textures/god_presence.png")
const ART_HEIGHT := 1.0        ## 原画占屏幕高多少（正方形）：头顶贴着屏幕上沿
const BASE_V := 0.76           ## 原画里这一行（触手垂到的地方）落在地平线上
const EYES_UV := [Vector2(0.432, 0.4155), Vector2(0.570, 0.4173)]  ## 原画里两只眼睛的位置
## 船平稳时眼睛在屏幕上的高度（占屏幕高）；供奉时祂的话写在眼睛下面（OfferingScreen.WORDS_Y）
const EYE_Y := 0.5 + WaterView.HORIZON - (BASE_V - 0.4164) * ART_HEIGHT
const EYE_COLOR := Color(0.72, 1.0, 0.78)  ## 和原画里眼睛一样的青白
const EYE_GLOW := 0.034        ## 眼睛光晕的半径（占原画高）
const RIM_STRENGTH := 0.75     ## 原画边光的强度（god_presence.gdshader 的 rim_strength），发怒时烧亮一下
const FLARE_DECAY := 2.2       ## 发怒时眼睛那一下亮光每秒退到 e^-2.2
## presence 里三步各占哪一段：黑雾、眼睛、样子
const FOG_STAGE := Vector2(0.0, 0.38)
const EYES_STAGE := Vector2(0.3, 0.52)
const FORM_STAGE := Vector2(0.48, 1.0)

var presence := 0.0:
	set(value):
		presence = value
		visible = value > 0.001
## 视线转了多少（弧度，> 0 朝右看）：祂在正前方的天上，转头时跟着天往反方向移
var view_yaw := 0.0
## 地平线比船平稳时低了多少（像素）、视线跟着船转的横摇（弧度）：WaterView 每帧给，祂的脚跟着地平线走
var horizon_shift := 0.0
var roll := 0.0
## 原画、黑雾的着色器材质：投影参数、云图、雾色由 WaterView 每帧给
var art_material := ShaderMaterial.new()
var fog_material := ShaderMaterial.new()

var _art := TextureRect.new()
var _fog := ColorRect.new()
var _eyes := Control.new()
var _time := 0.0
var _flare := 0.0              ## 发怒时眼睛亮闪的那一下（flare 给），慢慢退回去


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	art_material.shader = preload("res://shaders/god_presence.gdshader")
	_art.texture = ART
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art.material = art_material
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	fog_material.shader = preload("res://shaders/god_fog.gdshader")
	_fog.material = fog_material
	_fog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fog)
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_eyes.material = additive
	_eyes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eyes.set_anchors_preset(Control.PRESET_FULL_RECT)
	_eyes.draw.connect(_draw_eyes)
	add_child(_eyes)


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_flare *= exp(-delta * FLARE_DECAY)
	var h := size.y * ART_HEIGHT
	var horizon_y := size.y * (0.5 + WaterView.HORIZON) + horizon_shift
	var center_x := size.x * 0.5 - tan(view_yaw) * WaterView.FOCAL * size.y
	_art.size = Vector2(h, h)
	_art.position = Vector2(center_x - h * 0.5 + sin(_time * 0.21) * 4.0, horizon_y - BASE_V * h + sin(_time * 0.17) * 3.0)
	# 跟着视线的横摇一起转（绕屏幕中心，和海面一样）
	_art.pivot_offset = size * 0.5 - _art.position
	_art.rotation = -roll
	art_material.set_shader_parameter("form", _stage(FORM_STAGE))
	art_material.set_shader_parameter("time", _time)
	art_material.set_shader_parameter("rim_strength", RIM_STRENGTH * (1.0 + _flare * 0.8))
	fog_material.set_shader_parameter("amount", _stage(FOG_STAGE))
	fog_material.set_shader_parameter("time", _time)
	fog_material.set_shader_parameter("eyes_uv", _art_point((EYES_UV[0] + EYES_UV[1]) * 0.5) / size)
	_eyes.queue_redraw()


func _stage(span: Vector2) -> float:
	return smoothstep(span.x, span.y, presence)


## 原画上一点（UV）在屏幕上的位置（含横摇）
func _art_point(uv: Vector2) -> Vector2:
	return _art.position + _art.pivot_offset + (uv * _art.size - _art.pivot_offset).rotated(_art.rotation)


## 祂发怒：眼睛猛地亮闪一下（strength 约 1~2，越怒越亮），轮廓的边光也跟着烧一下，一秒多退回去
func flare(strength: float) -> void:
	_flare = maxf(_flare, strength)


## 眼睛：先在黑雾里亮起来（这时身子还没显出来，所以带一个亮芯），身子显出来以后收一点；每隔六秒多眨一下。
## 发怒亮闪时光晕炸开、芯子发白，横着拉出一道光，这时不眨眼
func _draw_eyes() -> void:
	var a := _stage(EYES_STAGE)
	var form := _stage(FORM_STAGE)
	var t := fmod(_time, 6.3)
	var blink := 1.0 if t > 0.16 else absf(t - 0.08) / 0.08  ## 合上又睁开
	var burst := _flare * a
	var lid := a * maxf(blink, minf(burst, 1.0))
	var flare_base := lerpf(1.5, 1.0, form)
	var g := Gothic.glow_texture()
	var r := _art.size.y * EYE_GLOW
	var halo := 1.0 + burst * 0.9
	for uv: Vector2 in EYES_UV:
		var e := _art_point(uv)
		_eyes.draw_texture_rect(g, Rect2(e - Vector2(r * 2.4, r * 1.7) * halo, Vector2(r * 4.8, r * 3.4) * halo), false,
			Color(EYE_COLOR, 0.42 * lid * flare_base + 0.3 * burst))
		_eyes.draw_texture_rect(g, Rect2(e - Vector2(r, r) * 0.75 * halo, Vector2(r, r) * 1.5 * halo), false,
			Color(EYE_COLOR.lerp(Color.WHITE, 0.35 + 0.3 * minf(burst, 1.0)), 0.85 * lid + 0.3 * burst))
		_eyes.draw_texture_rect(g, Rect2(e - Vector2(r, r) * 0.3 * halo, Vector2(r, r) * 0.6 * halo), false,
			Color(1.0, 1.0, 1.0, 0.9 * lid * (1.0 - form * 0.7) + 0.7 * minf(burst, 1.0)))
		if burst > 0.02:
			var streak := Vector2(r * 7.0, r * 0.32) * (0.7 + 0.5 * burst)
			_eyes.draw_texture_rect(g, Rect2(e - streak, streak * 2.0), false,
				Color(EYE_COLOR.lerp(Color.WHITE, 0.5), 0.45 * minf(burst, 1.2)))
