class_name EventScreen
extends Control
## 海上事件（阶段 IV，SeaEvents）：夜里抛下去等来的不是咬钩，是一件事。和契约书、奖励屏一样是墨和雾的帷幕，画面不压暗：
## 冥市船、溺者之手、残骸、血月是青灰的雾（和契约书一样）；祂的低语是暗红的雾（和供奉一样），最上面还有祂的话（英文手写 + 灰色批注）。
## - 最上面：这件事的插图（assets/events/，2026-11-05 Codex 画的），浮在雾里，四周本来就淡进透明；祂的低语那张压在祂的话后面、淡一些
## - 正中：这件事的名字（古铜色），下面两行它的样子，一行一行浮出来
## - 下面一行一个选择："[1] 恩赐「韧线」（永久）"，下面灰字写代价、会交出哪几条；选不了的发灰
## - 最下面"[空格] 不换"（不选；Esc 也行）
## chosen(index)：选了第几个（−1 = 不选）；FishingView 交给 SeaEvents.resolve，再接着钓

signal chosen(index: int)

const VEIL := preload("res://shaders/contract_veil.gdshader")
## 青灰的雾（契约书的样子，shader 的默认值）和暗红的雾（供奉、祂的低语）
const BLUE := [Color(0.012, 0.018, 0.026), Color(0.4, 0.56, 0.68), Color(0.55, 0.78, 0.95)]
const RED := [Color(0.03, 0.008, 0.008), Color(0.5, 0.17, 0.12), Color(0.85, 0.32, 0.18)]
const CX := 640.0
const WORDS_Y := 112.0
const TITLE_Y := 200.0
const LINES_Y := 242.0
const OPTIONS_Y := 330.0
const OPTION_STEP := 76.0
const LEAVE_Y := 630.0
## 每件事的插图：事件 id（SeaEvents.NAMES）→ assets/events/ 下的文件名
const ART := {"trade": "ghost_market", "hand": "drowned_hand", "wreck": "drifting_wreck", "blood_moon": "blood_moon",
	"whisper": "his_whisper", "ghost": "lost_soul", "storm": "storm", "gambler": "market_gambler"}
const ART_CENTER := Vector2(640, 98)
const ART_SIZE := Vector2(380, 190)       ## 1024×512 的原图缩着画（2:1）

var is_open := false
var event: Dictionary = {}
var _options: Array[Dictionary] = []
var _time := 0.0
var _opened_at := 0.0
var _veil_amount := 0.0
var _veil: ColorRect
var _veil_mat: ShaderMaterial
var _content: Control
var _rows: Array[HBoxContainer] = []
var _prompts: Array[KeyPrompt] = []
var _leave_row: HBoxContainer
var _leave_prompt: KeyPrompt
var _tween: Tween
var _art := {}                          ## 事件 id → 插图（没有的是 null）


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
	_content = Control.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.draw.connect(_draw_content)
	add_child(_content)
	for i in 3:
		var row := _row(OPTIONS_Y + i * OPTION_STEP - 24.0)
		var p := KeyPrompt.make(str(i + 1), "", 19)
		var index := i
		p.pressed.connect(func() -> void: choose(index))
		row.add_child(p)
		_rows.append(row)
		_prompts.append(p)
	_leave_row = _row(LEAVE_Y)
	_leave_prompt = KeyPrompt.make("空格", "", 19)
	_leave_prompt.pressed.connect(func() -> void: choose(-1))
	_leave_row.add_child(_leave_prompt)


func _row(y: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.position = Vector2(0, y)
	row.size = Vector2(1280, 32)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)
	return row


## 打开这一件（SeaEvents.start 的结果）；baits：手里还有几份饵（残骸要花一份）
func open(ev: Dictionary, who: Contractor, baits := 1) -> void:
	event = ev
	_options = SeaEvents.options(ev, who, baits)
	for i in _rows.size():
		var has := i < _options.size()
		_rows[i].visible = has
		if has:
			_prompts[i].label = _options[i].label
			_prompts[i].disabled = not _options[i].enabled
		_rows[i].modulate.a = 0.0
	_leave_prompt.label = SeaEvents.LEAVE.get(ev.id, "离开")
	_leave_row.modulate.a = 0.0
	var colors: Array = RED if ev.id == "whisper" else BLUE
	_veil_mat.set_shader_parameter("ink_color", colors[0])
	_veil_mat.set_shader_parameter("mist_color", colors[1])
	_veil_mat.set_shader_parameter("rim_color", colors[2])
	is_open = true
	visible = true
	modulate.a = 1.0
	_opened_at = _time
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_veil, _veil_amount, 0.92, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for i in _rows.size():
		_tween.parallel().tween_property(_rows[i], "modulate:a", 1.0, 0.4).set_delay(1.1 + i * 0.15)
	_tween.parallel().tween_property(_leave_row, "modulate:a", 1.0, 0.4).set_delay(1.5)


## 选第 index 个（−1 = 不选）；选不了的、刚打开的那一下不算
func choose(index: int) -> void:
	if not is_open or _time - _opened_at < 0.8:
		return
	if index >= 0 and (index >= _options.size() or not _options[index].enabled):
		return
	is_open = false
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.4)
	_tween.parallel().tween_method(_set_veil, _veil_amount, 0.0, 0.5)
	_tween.tween_callback(func() -> void: visible = false)
	chosen.emit(index)


func _set_veil(v: float) -> void:
	_veil_amount = v
	_veil_mat.set_shader_parameter("amount", v)


func _process(delta: float) -> void:
	_time += delta
	if not visible:
		return
	_veil_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	_content.queue_redraw()


func _k(start: float, dur := 0.45) -> float:
	var x := clampf((_time - _opened_at - start) / dur, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _event_art(id: String) -> Texture2D:
	if not _art.has(id):
		var path := "res://assets/events/%s.png" % ART.get(id, id)
		_art[id] = load(path) if ResourceLoader.exists(path) else null
	return _art[id]


func _draw_content() -> void:
	if event.is_empty():
		return
	var tex := _event_art(event.id)
	if tex:
		var a := _k(0.05, 0.8) * (0.5 if event.id == "whisper" else 0.92)
		var c := ART_CENTER + Vector2(0, sin(_time * 0.6) * 2.0)
		_content.draw_texture_rect(tex, Rect2(c - ART_SIZE * 0.5, ART_SIZE), false, Color(1, 1, 1, a))
	if event.id == "whisper":  ## 祂的话
		var hand := Gothic.hand_font(500)
		var a := _k(0.2, 0.6)
		var w := Gothic.text_width(SeaEvents.WHISPER_WORDS, 30, hand)
		Gothic.glow_text(_content, Vector2(CX - w * 0.5, WORDS_Y), SeaEvents.WHISPER_WORDS, 30, ContractScreen.TERMS_COLOR,
			ContractScreen.GLOW, a, hand)
		_plain(Vector2(CX, WORDS_Y + 22.0), SeaEvents.WHISPER_NOTE, 14, ContractScreen.NOTE, _k(0.5), true)
	_plain(Vector2(CX, TITLE_Y), SeaEvents.NAMES.get(event.id, event.id), 30, Gothic.BRONZE_LIGHT, _k(0.4, 0.5), true)
	var lines: Array = SeaEvents.lines(event)
	for i in lines.size():
		_plain(Vector2(CX, LINES_Y + i * 26.0), lines[i], 16, Gothic.BONE, _k(0.7 + i * 0.35), true)
	for i in _options.size():
		var opt: Dictionary = _options[i]
		_plain(Vector2(CX, OPTIONS_Y + i * OPTION_STEP + 22.0), opt.detail, 14,
			Color(Gothic.BONE, 0.88) if opt.enabled else Gothic.WARN, _k(1.2 + i * 0.15), true)


func _plain(pos: Vector2, s: String, size_t: int, color: Color, a: float, centered := false) -> void:
	if a <= 0.0:
		return
	if centered:
		pos.x -= Gothic.text_width(s, size_t) * 0.5
	Gothic.text(_content, pos, s, size_t, Color(color, color.a * a))
