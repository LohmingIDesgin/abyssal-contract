class_name DeathScreen
extends Control
## 落水即死（设计对照文档 3.1 第 5 条）：一道起伏的水线从屏幕下沿漫上来，水下的画面晃动、糊开、染成深青，
## 气泡往上冒，越来越暗，最后沉进黑水里（shaders/drown.gdshader）。
## 黑水里浮出这位契约者的编号，笔画里的蓝火慢慢熄成灰（SoulName.dead_amount），旁边灰色小字是名字；
## 下面写死在第几夜，名册上又熄了一个名字。最后浮出 [空格] 继续（接着是这一份契约的结算清单）。
## 叠在最上面；FishingView 先把 HUD 收起来。按键由 FishingView 处理，点按钮也行。

signal confirmed

## 以下坐标都按基准分辨率 1280×720
const TITLE_Y := 236.0
const CODE_Y := 300.0
const NOTE_Y := 432.0
const PROMPT_Y := 540.0
const DROWN := preload("res://shaders/drown.gdshader")
const NOTE := Color(0.56, 0.6, 0.62)

## 动画放着的时候不接受确认
var busy := false

var _water: ColorRect
var _water_mat: ShaderMaterial
var _content: Control
var _title: Label
var _code: SoulName
var _name: Label
var _night: Label
var _note: Label
var _prompt: KeyPrompt
var _time := 0.0
var _tween: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_water = ColorRect.new()
	_water.set_anchors_preset(Control.PRESET_FULL_RECT)
	_water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = DROWN
	_water.material = _water_mat
	add_child(_water)
	_content = Control.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	_title = _line(Gothic.label("坠入冥海", 40, Gothic.BONE, 6), TITLE_Y)
	_code = SoulName.new()
	_code.font = Gothic.hand_font(700)
	_code.font_size = 72
	_code.rotation = -0.035
	_content.add_child(_code)
	_name = Gothic.label("", 18, NOTE, 3)
	_content.add_child(_name)
	_night = _line(Gothic.label("", 16, Gothic.BONE_DARK), NOTE_Y - 34.0)
	_note = _line(Gothic.label("名册上，又一个名字熄灭了。", 16, NOTE, 3), NOTE_Y)
	_prompt = KeyPrompt.make("空格", "继续", 22)
	_prompt.pressed.connect(confirm)
	_content.add_child(_prompt)


func _line(l: Label, y: float) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, y)
	l.size = Vector2(1280, 0)
	_content.add_child(l)
	return l


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_water_mat.set_shader_parameter("time", _time)
	_water_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))


## 沉下去：水漫上来、变黑，编号浮现，火慢慢熄掉。cause："fall" 落水、"offering" 供奉不足被祂吞掉
func play(who: Contractor, cause := "fall") -> void:
	busy = true
	visible = true
	_time = 0.0
	_title.text = "坠入冥海" if cause == "fall" else "被祂吞噬"
	_code.text = who.code()
	_code.dead_amount = 0.0
	_code.position = Vector2(640.0 - _code.size.x * 0.5 - 40.0, CODE_Y)
	_name.text = who.contractor_name
	_name.position = Vector2(_code.position.x + _code.size.x + 4.0, CODE_Y + _code.size.y * 0.5 - 4.0)
	_night.text = "死于第 %d 夜" % who.night
	_prompt.position = Vector2(640.0 - _prompt.custom_minimum_size.x * 0.5, PROMPT_Y)
	for c: CanvasItem in [_title, _code, _name, _night, _note, _prompt]:
		c.modulate.a = 0.0
	_set_amount(0.0)
	_restart_tween()
	_tween.tween_method(_set_amount, 0.0, 1.0, 3.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.parallel().tween_property(_title, "modulate:a", 1.0, 0.9).set_delay(2.4)
	_tween.tween_property(_code, "modulate:a", 1.0, 0.7)
	_tween.parallel().tween_property(_name, "modulate:a", 1.0, 0.7).set_delay(0.3)
	_tween.tween_interval(0.4)
	_tween.tween_property(_code, "dead_amount", 1.0, 1.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_night, "modulate:a", 1.0, 0.8).set_delay(0.6)
	_tween.tween_property(_note, "modulate:a", 1.0, 0.6)
	_tween.tween_property(_prompt, "modulate:a", 1.0, 0.5)
	_tween.tween_callback(func() -> void: busy = false)


## 下一位契约者：字淡掉、黑水退去
func close() -> void:
	busy = true
	_restart_tween()
	_tween.tween_property(_content, "modulate:a", 0.0, 0.5)
	_tween.tween_method(_set_amount, 1.0, 0.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func() -> void:
		visible = false
		busy = false
		_content.modulate.a = 1.0)


func confirm() -> void:
	if busy or not visible:
		return
	confirmed.emit()


func _set_amount(v: float) -> void:
	_water_mat.set_shader_parameter("amount", v)


func _restart_tween() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
