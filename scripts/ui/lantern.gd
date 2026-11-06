class_name Lantern
extends Control
## 船头立柱上挂的鲸油灯：灯架固定在立柱上（跟着船身一起晃），灯像单摆一样挂在钩子上，
## 朝真正的"下"摆过去、慢一拍；
## 火苗忽明忽暗（flicker 也给海面、船、手和后期光晕用）。

const BRACKET := preload("res://assets/ui/lantern_bracket.png")
const LAMP := preload("res://assets/ui/lantern.png")
const ART_SCALE := 1.0 / 3.0       ## 贴图是 3 倍分辨率
## 贴图里的关键点（贴图像素）：灯架套在立柱上的点、钩子挂点；灯的挂环、玻璃中心
const BRACKET_COLLAR := Vector2(132, 24)
const BRACKET_HOOK := Vector2(22, 52)
const LAMP_RING := Vector2(60, 9)
const LAMP_GLASS := Vector2(60, 101)
const SWING_PERIOD := 1.5          ## 单摆周期（秒）
const SWING_DAMPING := 0.9

var boat_xform := Transform2D.IDENTITY  ## 船身贴图本地像素 → 屏幕（WaterView 每帧写入）
var post_local := Vector2.ZERO     ## 立柱顶部在船身贴图里的位置（本地像素）
var size_scale := 1.0              ## 跟着船一起缩放
var gravity_angle := 0.0           ## 屏幕上"真正的下"偏了多少（弧度，随海面转）
var flicker := 1.0

var _angle := 0.0
var _velocity := 0.0
var _time := 0.0
var _glow_layer := Control.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# 光晕单独一层，用加色混合
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_layer.material = additive
	_glow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glow_layer.draw.connect(_draw_glow)
	add_child(_glow_layer)


func _process(delta: float) -> void:
	_time += delta
	# 灯朝真正的"下"摆过去，有惯性、有阻尼，再加一点风
	var target := gravity_angle + sin(_time * 0.7) * 0.03 + sin(_time * 1.9 + 1.0) * 0.012
	var w := TAU / SWING_PERIOD
	_velocity += (-(w * w) * (_angle - target) - SWING_DAMPING * _velocity) * delta
	_angle += _velocity * delta
	queue_redraw()
	_glow_layer.queue_redraw()


## 灯玻璃中心的屏幕位置（光源）
func glass_position() -> Vector2:
	var hook := _hook_position()
	var offset := (LAMP_GLASS - LAMP_RING) * ART_SCALE * size_scale
	return hook + offset.rotated(_angle)


func _hook_position() -> Vector2:
	return boat_xform * (post_local + (BRACKET_HOOK - BRACKET_COLLAR) * ART_SCALE * size_scale)


func _draw() -> void:
	var k := ART_SCALE * size_scale
	draw_set_transform_matrix(boat_xform)
	draw_texture_rect(BRACKET, Rect2(post_local - BRACKET_COLLAR * k, BRACKET.get_size() * k), false)
	var hook := _hook_position()
	draw_set_transform(hook, _angle, Vector2(k, k))
	draw_texture(LAMP, -LAMP_RING, Color(flicker * 0.15 + 0.88, flicker * 0.1 + 0.9, 0.95))
	draw_set_transform(Vector2.ZERO)


func _draw_glow() -> void:
	var glass := glass_position()
	var r := 40.0 * size_scale * (0.92 + flicker * 0.08)
	_glow_layer.draw_texture_rect(Gothic.glow_texture(), Rect2(glass - Vector2(r, r), Vector2(r, r) * 2.0), false,
		Color(1.0, 0.62, 0.3, 0.55 * flicker))
