class_name SoulName
extends Control
## 燃着幽蓝灵魂火的名字（交接文档 §2.3）：字的笔画本身就是火，火在笔画里面翻滚。
## 用一个 SubViewport 把名字画成白字（四周留一圈给光晕），交给 shaders/soul_fire.gdshader 上火。
## 按两倍分辨率画，缩小显示，字边不糊。dead = true 时火灭、字变灰（死了的契约者，名册里用）。

const FIRE := preload("res://shaders/soul_fire.gdshader")
const RES := 2.0          ## SubViewport 按显示尺寸的几倍画

var text := "":
	set(value):
		text = value
		_rebuild()
var font_size := 52:
	set(value):
		font_size = value
		_rebuild()
## 字体，不给就用 Gothic.font()；契约书上的编号用手写体 Gothic.hand_font(700)
var font: Font:
	set(value):
		font = value
		_rebuild()
## 字上方留的空白（字号的倍数），给光晕
var room := 0.2:
	set(value):
		room = value
		_rebuild()
var dead := false:
	set(value):
		dead = value
		dead_amount = 1.0 if value else 0.0
## 火熄到什么程度 0~1：死的那一刻从 0 渐到 1，火慢慢灭掉（DeathScreen）
var dead_amount := 0.0:
	set(value):
		dead_amount = value
		_material.set_shader_parameter("dead", value)

var _viewport: SubViewport
var _label: Label
var _view: TextureRect
var _material: ShaderMaterial


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color.WHITE)
	_viewport.add_child(_label)
	_material = ShaderMaterial.new()
	_material.shader = FIRE
	_view = TextureRect.new()
	_view.texture = _viewport.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_view.material = _material
	add_child(_view)


func _rebuild() -> void:
	if _label == null:
		return
	var f: Font = font if font else Gothic.font()
	var px := roundi(font_size * RES)
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + px * 0.8
	var h := px * 1.45
	var top := px * room
	_viewport.size = Vector2i(ceili(w), ceili(h + top))
	_label.add_theme_font_override("font", f)
	_label.text = text
	_label.add_theme_font_size_override("font_size", px)
	_label.position = Vector2(0, top)
	_label.size = Vector2(w, h)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_view.size = Vector2(_viewport.size) / RES
	custom_minimum_size = _view.size
	size = _view.size
