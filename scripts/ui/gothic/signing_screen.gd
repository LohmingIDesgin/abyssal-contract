class_name SigningScreen
extends Control
## 签约（交接文档 §2.1、§2.3）：和契约书一样的黑墨蓝雾帷幕，不是一张纸。
## - 最上面是名册：走了的契约者，编号（英文手写）、名字和下场（偿清了的后面写评价）；死了的是冷掉的灰，偿清了的旁边盖一枚"偿"字封记。
##   有结算的点一下能再看那一份契约的结算清单（roster_opened，FishingView 打开 SettlementScreen）。
##   上一位刚走时，名册下面先写一句"No.0002 坠入了冥海。"之类
## - 中间是契约语（英文手写 + 灰色中文批注），下面一行是许汝之物：祂答应还给这一位的东西（核心调整 G4）
## - 下面是这一位的编号，还没烧起来，是冷的灰；编号下面一道细线，写下名字（中文英文都行，不写就是"无名氏"），
##   回车签下：编号燃起蓝火，三枚烙印烧上来，帷幕退去，第一夜开始
## - 签下旁边"翻看图鉴"（codex_requested，FishingView 打开 CodexScreen）：图鉴跟着名册传下去，换了人也在
## 按键都给输入框，FishingView 这时不处理按键；图鉴没有快捷键，只能点（字母都要留给名字）。

signal signed(name: String)
signal roster_opened(entry: Dictionary)  ## 点了名册上的一位（有结算的）
signal codex_requested  ## 点了"翻看图鉴"

const VEIL := preload("res://shaders/contract_veil.gdshader")
const CX := 640.0
const ROSTER_Y := 44.0
const ROSTER_W := 190.0
const MAX_ROSTER := 6
const FAREWELL_Y := 140.0
const TERMS_Y := 186.0
const TERMS_STEP := 46.0
const PROMISE_GAP := 6.0                    ## 许汝之物和上面的契约语之间多空一点
const NUMBER_TOP := 356.0
const INPUT_Y := 484.0
const BRAND_Y := 566.0
const PROMPTS_Y := 636.0
const SEAL := Color(0.55, 0.1, 0.08)
const DEFAULT_NAME := "无名氏"

var is_open := false

var _contractor: Contractor
var _roster: Array[Dictionary] = []
var _farewell := ""
var _veil: ColorRect
var _veil_mat: ShaderMaterial
var _content: Control
var _number: SoulName
var _input: LineEdit
var _prompt: KeyPrompt
var _codex_button: KeyPrompt
var _time := 0.0
var _opened_at := 0.0
var _signed_at := -1.0
var _tween: Tween
var _roster_rects: Array[Rect2] = []        ## 名册上显示出来的几位各占的地方（点开看结算用）
var _roster_shown: Array = []
var _hover := -1


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	visible = false
	_veil = ColorRect.new()
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil_mat = ShaderMaterial.new()
	_veil_mat.shader = VEIL
	_veil.material = _veil_mat
	add_child(_veil)
	# 帷幕后面一层压黑：签约时看不见海
	var black := ColorRect.new()
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.color = Color(0.008, 0.012, 0.016, 0.82)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	move_child(black, 0)
	_content = Control.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.draw.connect(_draw_content)
	add_child(_content)
	_number = SoulName.new()
	_number.font = Gothic.hand_font(700)
	_number.font_size = 64
	_number.rotation = -0.035
	add_child(_number)
	_input = LineEdit.new()
	_input.position = Vector2(CX - 180.0, INPUT_Y - 34.0)
	_input.size = Vector2(360, 44)
	_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_input.max_length = 16
	_input.placeholder_text = "写下你的名字"
	_input.context_menu_enabled = false
	_input.add_theme_font_override("font", Gothic.font())
	_input.add_theme_font_size_override("font_size", 24)
	_input.add_theme_color_override("font_color", Gothic.BONE)
	_input.add_theme_color_override("font_placeholder_color", Color(ContractScreen.NOTE, 0.6))
	_input.add_theme_color_override("caret_color", ContractScreen.LIVE)
	_input.add_theme_color_override("selection_color", Color(ContractScreen.GLOW, 0.35))
	for style in ["normal", "focus", "read_only"]:
		_input.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	_input.text_submitted.connect(func(_t: String) -> void: submit())
	add_child(_input)
	var prompts := HBoxContainer.new()
	prompts.position = Vector2(0, PROMPTS_Y)
	prompts.size = Vector2(1280, 34)
	prompts.alignment = BoxContainer.ALIGNMENT_CENTER
	prompts.add_theme_constant_override("separation", 44)
	add_child(prompts)
	_prompt = KeyPrompt.make("回车", "签下", 20)
	_prompt.pressed.connect(submit)
	prompts.add_child(_prompt)
	_codex_button = KeyPrompt.make("", "翻看图鉴", 18)
	_codex_button.pressed.connect(func() -> void: codex_requested.emit())
	prompts.add_child(_codex_button)


## 签约：who 是下一位契约者，roster 是名册；farewell 是上一位刚走时写在名册下面的那句话
func open(who: Contractor, roster: Array[Dictionary], farewell := "") -> void:
	_contractor = who
	_roster = roster
	_farewell = farewell
	_signed_at = -1.0
	is_open = true
	visible = true
	modulate.a = 1.0
	_opened_at = _time
	_number.text = who.code()
	_number.dead_amount = 1.0
	_number.pivot_offset = _number.size * 0.5
	_number.position = Vector2(CX - _number.size.x * 0.5, NUMBER_TOP)
	_input.text = ""
	_input.editable = true
	_input.grab_focus.call_deferred()
	_prompt.disabled = false
	_codex_button.disabled = false
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_veil, 0.0, 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## 名册上点开的结算盖在上面时，名字那一栏先不收字；合上以后接着写
func pause_input() -> void:
	_input.release_focus()


func resume_input() -> void:
	if is_open and _signed_at < 0.0:
		_input.grab_focus()


func _gui_input(event: InputEvent) -> void:
	if not is_open or _signed_at >= 0.0:
		return
	if event is InputEventMouseMotion:
		var hit := _roster_hit(event.position)
		if hit != _hover:
			_hover = hit
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hit >= 0 else Control.CURSOR_ARROW
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit := _roster_hit(event.position)
		if hit >= 0:
			roster_opened.emit(_roster_shown[hit])
			accept_event()


## 鼠标下面是名册上的第几位（有结算的才算）；没有是 −1
func _roster_hit(pos: Vector2) -> int:
	for i in _roster_rects.size():
		if _roster_rects[i].has_point(pos) and Settlement.has_ledger(_roster_shown[i]):
			return i
	return -1


## 回车：签下。编号燃起来、三枚烙印烧上来，然后帷幕退去
func submit() -> void:
	if not is_open or _signed_at >= 0.0:
		return
	var name_text := _input.text.strip_edges()
	if name_text == "":
		name_text = DEFAULT_NAME
		_input.text = name_text
	_input.editable = false
	_input.release_focus()
	_prompt.disabled = true
	_codex_button.disabled = true
	_signed_at = _time
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_number, "dead_amount", 0.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(1.4)
	_tween.tween_property(self, "modulate:a", 0.0, 0.7)
	_tween.parallel().tween_method(_set_veil, 1.0, 0.0, 0.7)
	_tween.tween_callback(func() -> void:
		is_open = false
		visible = false
		signed.emit(name_text))


func _set_veil(v: float) -> void:
	_veil_mat.set_shader_parameter("amount", v)


func _process(delta: float) -> void:
	_time += delta
	if not visible:
		return
	_veil_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	_number.modulate.a = _k(1.1)
	_input.modulate.a = _k(1.4)
	_content.queue_redraw()


func _k(start: float, dur := 0.5, from := -1.0) -> float:
	var origin := _opened_at if from < 0.0 else from
	var x := clampf((_time - origin - start) / dur, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _text(pos: Vector2, s: String, size_t: int, color: Color, a: float) -> void:
	if a > 0.0:
		Gothic.text(_content, Vector2(pos.x - Gothic.text_width(s, size_t) * 0.5, pos.y), s, size_t, Color(color, color.a * a))


func _draw_content() -> void:
	if _contractor == null:
		return
	_draw_roster()
	if _farewell != "":
		_text(Vector2(CX, FAREWELL_Y), _farewell, 16, Gothic.BONE, _k(0.4))
	# 契约语，下面一行是许汝之物
	var hand := Gothic.hand_font(500)
	var lines := ContractScreen.terms_for(_contractor)
	for i in lines.size():
		var line: String = lines[i][0]
		var y := TERMS_Y + i * TERMS_STEP + (PROMISE_GAP if i >= ContractScreen.TERMS.size() else 0.0)
		var a := _k(0.5 + i * 0.2)
		var w := Gothic.text_width(line, 25, hand)
		Gothic.glow_text(_content, Vector2(CX - w * 0.5, y), line, 25, ContractScreen.TERMS_COLOR, ContractScreen.GLOW, a, hand)
		var note: String = lines[i][1]
		Gothic.text(_content, Vector2(CX - Gothic.text_width(note, 13) * 0.5, y + 20.0), note, 13,
			Color(ContractScreen.NOTE, a), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	# 名字下面一道细线
	var a := _k(1.4)
	_content.draw_line(Vector2(CX - 170.0, INPUT_Y + 12.0), Vector2(CX + 170.0, INPUT_Y + 12.0),
		Color(Gothic.BONE_DARK, 0.6 * a), 1.2)
	if _signed_at < 0.0:
		_text(Vector2(CX, INPUT_Y + 36.0), "签下名字，就是和祂立约。", 13, ContractScreen.NOTE, a)
	# 三枚烙印：签下以后一枚一枚烧上来
	if _signed_at >= 0.0:
		var brand := Gothic.tex("soul_brand")
		var glow := Gothic.glow_texture()
		var total := _contractor.config.brands
		for i in total:
			var k := _k(0.5 + i * 0.25, 0.4, _signed_at)
			var c := Vector2(CX + (i - (total - 1) * 0.5) * 80.0, BRAND_Y)
			var flare := 1.0 - _k(0.8 + i * 0.25, 0.6, _signed_at)
			_content.draw_texture_rect(glow, Rect2(c - Vector2(44, 44), Vector2(88, 88)), false,
				Color(ContractScreen.LIVE, (0.3 + 0.5 * flare) * k))
			_content.draw_texture_rect(brand, Rect2(c - Vector2(24, 24), Vector2(48, 48)), false, Color(ContractScreen.LIVE, k))


## 名册：最近走的几位，编号是英文手写；死了的是冷掉的灰，偿清了的旁边盖一枚"偿"字封记、下场后面写评价。
## 有结算的，鼠标移上去下面浮出"点开看结算"
func _draw_roster() -> void:
	var a := _k(0.2)
	_roster_rects.clear()
	_roster_shown.clear()
	if _roster.is_empty():
		_text(Vector2(CX, ROSTER_Y + 30.0), "名册上还没有名字。", 14, ContractScreen.NOTE, a)
		return
	var shown := _roster.slice(maxi(0, _roster.size() - MAX_ROSTER))
	var hand := Gothic.hand_font(600)
	var x0 := CX - shown.size() * ROSTER_W * 0.5
	for i in shown.size():
		var e: Dictionary = shown[i]
		var cx := x0 + (i + 0.5) * ROSTER_W
		_roster_rects.append(Rect2(cx - ROSTER_W * 0.5 + 8.0, ROSTER_Y - 6.0, ROSTER_W - 16.0, 80.0))
		_roster_shown.append(e)
		if i == _hover:
			_text(Vector2(cx, ROSTER_Y + 86.0), "点开看结算", 12, Gothic.BRONZE_LIGHT, a)
		var repaid: bool = e.get("status", "dead") == "repaid"
		var code := "No.%04d" % int(e.number)
		var w := Gothic.text_width(code, 26, hand)
		_content.draw_string(hand, Vector2(cx - w * 0.5, ROSTER_Y + 26.0), code, HORIZONTAL_ALIGNMENT_LEFT, -1, 26,
			Color(Gothic.BONE if repaid else ContractScreen.ASH.lightened(0.25), a))
		var who_name: String = e.get("name", "")
		_text(Vector2(cx, ROSTER_Y + 48.0), who_name if who_name != "" else DEFAULT_NAME, 13, ContractScreen.NOTE, a)
		var fate := "第 %d 夜偿清" % int(e.night) if repaid else _cause_text(e.get("cause", ""), int(e.night))
		if repaid and e.has("rating"):
			fate += " · %s" % e.rating
		_text(Vector2(cx, ROSTER_Y + 66.0), fate, 12, Gothic.BONE_DARK if repaid else ContractScreen.ASH.lightened(0.3), a)
		if repaid:
			var sc := Vector2(cx + w * 0.5 + 16.0, ROSTER_Y + 14.0)
			_content.draw_circle(sc, 12.0, Color(SEAL, a))
			_content.draw_arc(sc, 12.0, 0.0, TAU, 24, Color(0.3, 0.04, 0.03, a), 1.5, true)
			Gothic.text(_content, sc + Vector2(-7.0, 5.0), "偿", 14, Color(Gothic.BONE, a), HORIZONTAL_ALIGNMENT_LEFT, -1, 0)


static func _cause_text(cause: String, night: int) -> String:
	match cause:
		"fall":
			return "第 %d 夜坠入冥海" % night
		"offering":
			return "第 %d 夜被祂吞噬" % night
	return "死于第 %d 夜" % night
