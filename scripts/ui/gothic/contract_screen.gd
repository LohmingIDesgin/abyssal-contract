class_name ContractScreen
extends Control
## 契约书（Tab）：和邪神立下的契约。不是一张实体的纸：打开时黑墨从屏幕四周爬进来，
## 墨里翻着蓝灰的雾（shaders/contract_veil.gdshader），契约的字一个个浮现出来。
## 从上到下：
## - 三枚烙印：还在的燃着幽蓝，被吃掉的只剩一点灰
## - 契约编号（No.0001）：英文手写体（Gothic.hand_font），笔画本身是翻滚的蓝火（SoulName）；
##   旁边灰色小字是玩家签下的名字（中文英文都行）
## - 契约语：同一种英文手写体，蓝灰色的发光字，一个字母一个字母浮现；每行下面灰色小字是中文，像翻译的批注。
##   最后一行是许汝之物：祂答应还给这一位的东西（核心调整 G4，terms_for）
## - 一行状态：第几夜、能力档、饱腹（2026-11-04：灵魂线并进了烙印，玩家等级去掉了）
## - 右边一列：身上的永久恩赐（2026-11-05 挪过来的：原来在暗线下面一行，和船舱那一行挤在一起），一行一样，图标加名字，
##   按拿到的先后；鼠标放上去在左边浮出一块说明（名字、持续、效果、每夜有次数的写今夜还剩几次）
## - 一道光线下面是船：船舱的载荷（上限 20，2026-11-04 起不分等级）、饵料、材料（选中的那条处理了能拿到几份，数字后面写 +1、+2），
##   船舱里的每一条渔获像幽影一样浮着，选中的那条亮起来
## - 最底下 [1] 生吞 [2] 处理（对选中的那条；放生 2026-11-04 删了），点一条或 ←→ 选择
## 只有编号和契约语是蓝色的英文手写字；其余的（状态、船、渔获、材料、按钮）跟 HUD 一样是骨白描边的中文，免得分不清。
## 打开时身后的画面压暗（和渔获展示共用压暗层），HUD 收起来。
## 烙印、第几夜跟着契约走（Contractor：黄昏供奉、剪线，见 docs/契约与昼夜.md）。

signal acted(c: CatchData, action: String)  ## "eat" / "dismantle"
signal close_requested

const VEIL := preload("res://shaders/contract_veil.gdshader")
const TERMS_COLOR := Color("c6d6df")          ## 契约语：蓝灰
const GLOW := Color(0.35, 0.62, 0.85)         ## 契约语周围的光
const NOTE := Color(0.56, 0.6, 0.62)          ## 签名、契约语旁边的中文批注：灰
const GAIN := Color("8fe3c4")                 ## 材料后面的 +N：选中的那条处理了能拿到几份
const LIVE := Color(0.5, 0.86, 1.0)           ## 还在的烙印
const ASH := Color(0.2, 0.24, 0.27)           ## 用掉的
## 契约语：英文手写，下面一行是中文批注
const TERMS: Array[String] = ["Spin thy soul into a line, and fish the Nether Sea.",
	"At every dusk, feed me what thou hast caught.", "After seven nights, thou mayst depart."]
const TERMS_CN: Array[String] = ["以魂为线，垂钓冥海。", "每逢黄昏，献上祭品。", "七夜之后，方得离去。"]
const ACTIONS: Array[String] = ["eat", "dismantle"]
const ACTION_NAMES := {"eat": "生吞", "dismantle": "处理"}
## 布局，按基准分辨率 1280×720
const CX := 640.0
const BRAND_Y := 58.0
const NAME_TOP := 104.0
const TERMS_Y := 238.0                        ## 第一行契约语的基线
const TERMS_STEP := 46.0                      ## 一行英文加一行中文批注
const TERMS_SIZE := 25
const PROMISE_GAP := 6.0                      ## 许汝之物和上面三句之间多空一点
const STATUS_Y := 432.0
const RULE_Y := 454.0
const BOAT_Y := 482.0
const SLOTS_Y := 500.0                        ## 渔获插图的上沿
const SLOT_W := 224.0
const SLOT_ART := Vector2(140, 56)
const PROMPTS_Y := 644.0
## 右边那一列恩赐：从"恩赐"两个字的基线往下一行一样；恩赐多了行距收紧，最多排到 BOON_BOTTOM
const BOON_X := 1004.0
const BOON_TOP := 172.0
const BOON_STEP := 36.0
const BOON_ICON := 28.0
const BOON_BOTTOM := 610.0
const BOON_ROW_W := 236.0
const TIP_W := 300.0                          ## 鼠标放上去浮出来的说明有多宽

var contractor: Contractor
var dim: ColorRect                            ## FishingView 给的压暗层
## 开着（关上的动画放着时已经是 false）
var is_open := false

var _veil: ColorRect
var _veil_mat: ShaderMaterial
var _sparks: CPUParticles2D
var _content: Control
var _name: SoulName
var _prompts: HBoxContainer
var _buttons := {}
var _selected := 0
var _slot_rects: Array[Rect2] = []
var _boon_rects: Array[Rect2] = []           ## 右边恩赐的每一行（鼠标放上去看说明）
var _boon_hover := -1
var _time := 0.0
var _opened_at := 0.0
var _fade := 1.0                              ## 关上时整体淡出
var _veil_amount := 0.0
var _owns_dim := false
var _tween: Tween


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
	_sparks = _make_sparks()
	add_child(_sparks)
	_content = Control.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_content.draw.connect(_draw_content)
	add_child(_content)
	_name = SoulName.new()
	_name.font = Gothic.hand_font(700)
	_name.font_size = 76
	_name.rotation = -0.035
	add_child(_name)

	_prompts = HBoxContainer.new()
	_prompts.position = Vector2(0, PROMPTS_Y)
	_prompts.size = Vector2(1280, 34)
	_prompts.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompts.add_theme_constant_override("separation", 34)
	add_child(_prompts)
	for i in ACTIONS.size():
		var action := ACTIONS[i]
		var b := KeyPrompt.make(str(i + 1), ACTION_NAMES[action], 19)
		b.pressed.connect(func() -> void: act(i))
		_prompts.add_child(b)
		_buttons[action] = b
	_prompts.add_child(KeyPrompt.make("←→", "选择", 16, false))
	var close_button := KeyPrompt.make("Tab", "合上契约", 19)
	close_button.pressed.connect(func() -> void: close_requested.emit())
	_prompts.add_child(close_button)


## 契约上的几行，每行 [英文, 中文批注]：三句契约语，下面是许汝之物（还没分到就没有这一行）。签约的帷幕也用它
static func terms_for(who: Contractor) -> Array:
	var lines := []
	for i in TERMS.size():
		lines.append([TERMS[i], TERMS_CN[i]])
	var promise := who.promise_data() if who else null
	if promise:
		lines.append([promise.line, promise.note()])
	return lines


# ---------- 打开、关上 ----------

func open(who: Contractor) -> void:
	if contractor and contractor.changed.is_connected(refresh):
		contractor.changed.disconnect(refresh)
	contractor = who
	contractor.changed.connect(refresh)
	if not GameState.baits_changed.is_connected(refresh):
		GameState.baits_changed.connect(refresh)
	is_open = true
	visible = true
	_selected = 0
	_boon_hover = -1
	_opened_at = _time
	_fade = 1.0
	_sparks.emitting = true
	refresh()
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_veil, _veil_amount, 1.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 钓上东西、正在展示的时候压暗层已经开着，不归这里管
	_owns_dim = not dim.visible
	if _owns_dim:
		dim.visible = true
		_tween.parallel().tween_method(_set_dim, 0.0, 1.0, 0.3)


func close() -> void:
	if not is_open:
		return
	is_open = false
	if contractor and contractor.changed.is_connected(refresh):
		contractor.changed.disconnect(refresh)
	if GameState.baits_changed.is_connected(refresh):
		GameState.baits_changed.disconnect(refresh)
	_sparks.emitting = false
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_fade", 0.0, 0.15)
	_tween.parallel().tween_method(_set_veil, _veil_amount, 0.0, 0.3)
	if _owns_dim:
		_tween.parallel().tween_method(_set_dim, 1.0, 0.0, 0.3)
	_tween.tween_callback(_closed)


func _closed() -> void:
	visible = false
	if _owns_dim:
		_owns_dim = false
		dim.visible = false


func _set_veil(v: float) -> void:
	_veil_amount = v
	_veil_mat.set_shader_parameter("amount", v)


func _set_dim(v: float) -> void:
	(dim.material as ShaderMaterial).set_shader_parameter("amount", v)


# ---------- 选中和处理 ----------

## 对选中的那条执行第 index 个去向（0 生吞、1 处理）；按钮和快捷键 1–2 都走这里
func act(index: int) -> void:
	if not is_open or contractor == null or contractor.hold.is_empty() or index < 0 or index >= ACTIONS.size():
		return
	_selected = clampi(_selected, 0, contractor.hold.size() - 1)
	acted.emit(contractor.hold[_selected], ACTIONS[index])


func move_selection(step: int) -> void:
	if contractor == null or contractor.hold.is_empty():
		return
	_selected = posmod(_selected + step, contractor.hold.size())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hit := -1
		for i in _boon_rects.size():
			if _boon_rects[i].has_point(event.position):
				hit = i
				break
		_boon_hover = hit
		mouse_default_cursor_shape = Control.CURSOR_HELP if hit >= 0 else Control.CURSOR_ARROW
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in _slot_rects.size():
			if _slot_rects[i].has_point(event.position):
				_selected = i
				accept_event()
				return


func refresh() -> void:
	if contractor == null:
		return
	_name.text = contractor.code()
	_name.pivot_offset = _name.size * 0.5
	_name.position = Vector2(CX - _name.size.x * 0.5, NAME_TOP)
	_selected = clampi(_selected, 0, maxi(contractor.hold.size() - 1, 0))
	for action in _buttons:
		_buttons[action].disabled = contractor.hold.is_empty()


func _process(delta: float) -> void:
	_time += delta
	if not visible:
		return
	_veil_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	_name.modulate.a = _k(0.3, 0.5)
	_prompts.modulate.a = _k(1.2)
	_content.queue_redraw()


## 浮现的进度：打开后过了 start 秒开始，dur 秒浮现完；关上时跟着整体淡出
func _k(start: float, dur := 0.35) -> float:
	var x := clampf((_time - _opened_at - start) / dur, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x) * _fade


# ---------- 绘制 ----------

## 跟 HUD 一样的字：骨白（或别的颜色）+ 黑描边，a 用来淡入淡出
func _plain(pos: Vector2, s: String, size_t: int, color: Color, a: float) -> void:
	if a <= 0.0:
		return
	var f := Gothic.font()
	_content.draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_t, 4, Color(0, 0, 0, 0.85 * a))
	_content.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_t, Color(color, color.a * a))


func _plain_centered(s: String, y: float, size_t: int, color: Color, a: float) -> void:
	_plain(Vector2(CX - Gothic.text_width(s, size_t) * 0.5, y), s, size_t, color, a)


## 签名、契约语旁边的中文批注：灰色小字，淡淡的描边，像译注
func _note(pos: Vector2, s: String, size_t: int, a: float) -> void:
	if a <= 0.0:
		return
	var f := Gothic.font()
	_content.draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_t, 3, Color(0, 0, 0, 0.6 * a))
	_content.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_t, Color(NOTE, a))


func _draw_content() -> void:
	if contractor == null:
		return
	var ci := _content
	var who := contractor
	var glow := Gothic.glow_texture()

	# 三枚烙印
	var brand := Gothic.tex("soul_brand")
	var a := _k(0.12)
	for i in who.config.brands:
		var c := Vector2(CX + (i - (who.config.brands - 1) * 0.5) * 104.0, BRAND_Y)
		var live := i < who.brands
		if live:
			var pulse := 0.4 + 0.12 * sin(_time * 2.2 + i * 1.7)
			ci.draw_texture_rect(glow, Rect2(c - Vector2(42, 42), Vector2(84, 84)), false, Color(LIVE, pulse * a))
		ci.draw_texture_rect(brand, Rect2(c - Vector2(26, 26), Vector2(52, 52)), false, Color(LIVE if live else ASH, a))
	_plain_centered("烙印　余 %d 枚" % who.brands, BRAND_Y + 46.0, 14, Gothic.BONE_DARK, a)

	# 编号旁边：玩家签下的名字，灰色小字，跟着编号一起浮现
	var cn := who.contractor_name
	if cn != "":
		var nx := _name.position.x + _name.size.x - 6.0
		_note(Vector2(nx, NAME_TOP + _name.size.y * 0.72), cn, 17, _k(0.6, 0.5))

	# 契约语：英文手写，一个字母一个字母浮现；整行写完，下面浮出中文批注。最后一行是许汝之物
	var hand := Gothic.hand_font(500)
	var lines := terms_for(who)
	for li in lines.size():
		var line: String = lines[li][0]
		var y := TERMS_Y + li * TERMS_STEP + (PROMISE_GAP if li >= TERMS.size() else 0.0)
		var x := CX - Gothic.text_width(line, TERMS_SIZE, hand) * 0.5
		var start := 0.55 + li * 0.22
		for j in line.length():
			var ch := line[j]
			var k := _k(start + j * 0.012, 0.3)
			Gothic.glow_text(ci, Vector2(x, y + (1.0 - k) * 6.0), ch, TERMS_SIZE, TERMS_COLOR, GLOW, k, hand)
			x += Gothic.text_width(ch, TERMS_SIZE, hand)
		var note: String = lines[li][1]
		_note(Vector2(CX - Gothic.text_width(note, 14) * 0.5, y + 21.0), note, 14, _k(start + line.length() * 0.012, 0.4))

	# 状态：第几夜、能力档、饱腹
	a = _k(1.0)
	_status_nights(Vector2(CX - 280.0, STATUS_Y), a)
	_status_ability(Vector2(CX, STATUS_Y), a)
	_status_hunger(Vector2(CX + 280.0, STATUS_Y), a)

	# 一道暗线；带着奖励卡的效果时，线的正中断开，写"带着「引深」· 一次"
	a = _k(1.08)
	var card_note := ""
	for effect in contractor.card_effects:
		var card: RewardCard = contractor.card_effects[effect].card
		card_note = "带着「%s」· %s" % [card.display_name, card.duration]
	var gap := Gothic.text_width(card_note, 13) * 0.5 + 12.0 if card_note != "" else 0.0
	for s in 24:
		var t0 := s / 24.0
		var t1 := (s + 1) / 24.0
		var fade := sin(t0 * PI)
		if gap > 0.0 and absf(lerpf(300, 980, (t0 + t1) * 0.5) - CX) < gap:
			continue
		ci.draw_line(Vector2(lerpf(300, 980, t0), RULE_Y), Vector2(lerpf(300, 980, t1), RULE_Y), Color(Gothic.BONE_DARK, 0.45 * fade * a), 1.5)
	if card_note != "":
		_plain(Vector2(CX - Gothic.text_width(card_note, 13) * 0.5, RULE_Y + 5.0), card_note, 13, Gothic.EERIE, a)

	# 船
	_boat_line(_k(1.12))
	_slots(_k(1.18))
	# 永久恩赐：右边一列，鼠标放上去看说明（说明最后画，压在别的上面）
	_boons(_k(1.1))


func _status_nights(c: Vector2, a: float) -> void:
	var label := "第 %d 夜" % contractor.night if not contractor.is_compensation() else "补偿之夜"
	var nights := contractor.config.contract_nights
	var w := Gothic.text_width(label, 16) + 16.0 + nights * 14.0
	var x := c.x - w * 0.5
	_plain(Vector2(x, c.y), label, 16, Gothic.BONE, a)
	x += Gothic.text_width(label, 16) + 16.0
	for i in nights:
		var p := Vector2(x + i * 14.0, c.y - 6.0)
		var n := i + 1
		if n == contractor.night:
			_content.draw_circle(p, 4.2, Color(0, 0, 0, 0.8 * a))
			_content.draw_circle(p, 3.2, Color(Gothic.BONE, a))
		else:
			_content.draw_arc(p, 3.4, 0, TAU, 16, Color(Gothic.BONE_DARK if n > contractor.night else ASH, a), 1.4)


## 能力档：体力、收线这些本事是几档（现在跟着夜数走），后面灰字写下一档从第几夜起
func _status_ability(c: Vector2, a: float) -> void:
	var label := "能力 %d 档" % contractor.ability
	var note := ""
	for n in range(contractor.night + 1, contractor.config.contract_nights + 1):
		if contractor.config.ability_for(n) > contractor.ability:
			note = "　第 %d 夜起 %d 档" % [n, contractor.config.ability_for(n)]
			break
	var w := Gothic.text_width(label, 16) + Gothic.text_width(note, 13)
	var x := c.x - w * 0.5
	_plain(Vector2(x, c.y), label, 16, Gothic.BONE, a)
	if note != "":
		_plain(Vector2(x + Gothic.text_width(label, 16), c.y), note, 13, Gothic.BONE_DARK, a)


## 饱腹 72 和一根细条（油脂似的赭黄）；饿了字和数变成琥珀色，饿得发慌偏红
func _status_hunger(c: Vector2, a: float) -> void:
	var who := contractor
	var label := "饱腹"
	var value := str(roundi(who.hunger))
	var bar_w := 80.0
	var w := Gothic.text_width(label, 16) + 8.0 + Gothic.text_width(value, 15) + 10.0 + bar_w
	var x := c.x - w * 0.5
	var tier := who.hunger_tier()
	var warm := Gothic.BONE if tier == 0 else (Gothic.WARN if tier == 1 else Color("ff6a50"))
	_plain(Vector2(x, c.y), label, 16, Gothic.BRONZE_LIGHT, a)
	x += Gothic.text_width(label, 16) + 8.0
	_plain(Vector2(x, c.y), value, 15, warm, a)
	x += Gothic.text_width(value, 15) + 10.0
	var bar := Rect2(x, c.y - 9, bar_w, 5)
	_content.draw_rect(bar.grow(1.5), Color(0, 0, 0, 0.8 * a))
	_content.draw_rect(bar, Color(ASH, a))
	var k := clampf(who.hunger / maxf(who.config.hunger_max, 1.0), 0.0, 1.0)
	if k > 0.0:
		var fill := Color(0.76, 0.52, 0.24) if tier < 2 else Color(0.8, 0.3, 0.16)
		_content.draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), Color(fill, a))
	for line in who.config.hungry_at:
		var mx := bar.position.x + bar.size.x * line / maxf(who.config.hunger_max, 1.0)
		_content.draw_line(Vector2(mx, bar.position.y - 1.5), Vector2(mx, bar.end.y + 1.5), Color(0, 0, 0, 0.85 * a), 1.0)


## 船：船舱　载荷 2 / 3 □□□　饵料 ……　材料 ……（整行居中）
func _boat_line(a: float) -> void:
	if a <= 0.0:
		return
	var who := contractor
	var boat := "船舱"
	var load := "载荷 %d / %d" % [who.hold_load(), who.hold_capacity()]
	var baits: PackedStringArray = []
	for bait in GameState.baits:
		baits.append("%s ×%d" % [bait.display_name, bait.uses])
	var bait_text := "、".join(baits) if not baits.is_empty() else "没有了"
	var cap := who.hold_capacity()
	var gains := _selected_materials()
	var mats_w := 0.0
	for m in Materials.ALL:
		mats_w += 20.0 + Gothic.text_width(str(who.materials.get(m, 0)), 15) + 12.0 + _gain_width(gains, m)
	var gap := 30.0
	var w := Gothic.text_width(boat, 17) + 12.0 + Gothic.text_width(load, 15) + 8.0 + cap * 13.0 + gap \
		+ Gothic.text_width("饵料　", 15) + Gothic.text_width(bait_text, 15) + gap + Gothic.text_width("材料　", 15) + mats_w
	var x := CX - w * 0.5
	_plain(Vector2(x, BOAT_Y), boat, 17, Gothic.BONE, a)
	x += Gothic.text_width(boat, 17) + 12.0
	_plain(Vector2(x, BOAT_Y), load, 15, Gothic.BONE_DARK, a)
	x += Gothic.text_width(load, 15) + 8.0
	for i in cap:
		var r := Rect2(x + i * 13.0, BOAT_Y - 12, 9, 9)
		_content.draw_rect(r.grow(1.5), Color(0, 0, 0, 0.8 * a))
		_content.draw_rect(r, Color(Gothic.BONE if i < who.hold_load() else Color(0.2, 0.19, 0.18), a))
	x += cap * 13.0 + gap
	_plain(Vector2(x, BOAT_Y), "饵料　", 15, Gothic.BRONZE_LIGHT, a)
	x += Gothic.text_width("饵料　", 15)
	_plain(Vector2(x, BOAT_Y), bait_text, 15, Gothic.BONE, a)
	x += Gothic.text_width(bait_text, 15) + gap
	_plain(Vector2(x, BOAT_Y), "材料　", 15, Gothic.BRONZE_LIGHT, a)
	x += Gothic.text_width("材料　", 15)
	for m in Materials.ALL:
		var t := Gothic.tex("mat_" + m)
		_content.draw_texture_rect(t, Rect2(Vector2(x, BOAT_Y - 15), Vector2(18, 18)), false, Color(1, 1, 1, a))
		x += 20.0
		var n := str(who.materials.get(m, 0))
		_plain(Vector2(x, BOAT_Y), n, 15, Gothic.BONE, a)
		x += Gothic.text_width(n, 15)
		var g: int = gains.get(m, 0)
		if g > 0:
			var plus := "+%d" % g
			var pulse := 0.8 + 0.2 * sin(_time * 3.0)
			_plain(Vector2(x + 4.0, BOAT_Y), plus, 14, GAIN, a * pulse)
			x += _gain_width(gains, m)
		x += 12.0


## 选中的那条处理了能拿到的材料（材料id → 份数）；船舱空着是空的
func _selected_materials() -> Dictionary:
	if contractor == null or contractor.hold.is_empty():
		return {}
	return contractor.dismantle_yield(contractor.hold[clampi(_selected, 0, contractor.hold.size() - 1)])


func _gain_width(gains: Dictionary, m: String) -> float:
	var g: int = gains.get(m, 0)
	return 4.0 + Gothic.text_width("+%d" % g, 14) if g > 0 else 0.0


## 右边一列：身上的永久恩赐，按拿到的先后，一行一样（图标、名字）；鼠标下面那一行垫一道光，左边浮出说明
func _boons(a: float) -> void:
	_boon_rects.clear()
	if contractor.boons.is_empty() or a <= 0.0:
		return
	_plain(Vector2(BOON_X, BOON_TOP), "恩赐", 16, Gothic.BRONZE_LIGHT, a)
	_note(Vector2(BOON_X + 42.0, BOON_TOP), "鼠标放上去看说明", 11, a * 0.85)
	var n := contractor.boons.size()
	var step := minf(BOON_STEP, (BOON_BOTTOM - BOON_TOP - 14.0) / float(n))
	var icon := minf(BOON_ICON, step - 6.0)
	var i := 0
	for effect in contractor.boons:
		var card: RewardCard = contractor.boons[effect].card
		var row := Rect2(BOON_X - 8.0, BOON_TOP + 12.0 + i * step, BOON_ROW_W, step - 2.0)
		_boon_rects.append(row)
		var lit := i == _boon_hover
		if lit:
			_content.draw_rect(row, Color(0.55, 0.68, 0.72, 0.12 * a))
		if card.icon:
			_content.draw_texture_rect(card.icon, Rect2(Vector2(BOON_X, row.position.y + (row.size.y - icon) * 0.5), Vector2(icon, icon)),
				false, Color(1, 1, 1, a))
		_plain(Vector2(BOON_X + icon + 9.0, row.get_center().y + 6.0), card.display_name, 15, Gothic.BONE if lit else Gothic.BONE.darkened(0.1), a)
		i += 1
	if _boon_hover >= 0 and _boon_hover < _boon_rects.size():
		_boon_tip(_boon_hover, a)


## 恩赐的说明：一块墨色的底、细铜边，浮在那一行左边；名字、持续多久、效果（自动换行），每夜有次数的写今夜还剩几次
func _boon_tip(index: int, a: float) -> void:
	var entry: Dictionary = contractor.boons[contractor.boons.keys()[index]]
	var card: RewardCard = entry.card
	var f := Gothic.font()
	var text_w := TIP_W - 28.0
	var desc_h := f.get_multiline_string_size(card.description, HORIZONTAL_ALIGNMENT_LEFT, text_w, 14).y
	var uses := ""
	if card.uses > 0:
		uses = "今夜还剩 %d 次（每夜 %d 次）" % [maxi(card.uses - int(entry.get("used", 0)), 0), card.uses]
	var h := 36.0 + desc_h + (26.0 if uses != "" else 12.0)
	var row: Rect2 = _boon_rects[index]
	var pos := Vector2(row.position.x - TIP_W - 10.0, clampf(row.position.y - 4.0, 16.0, 704.0 - h))
	var box := Rect2(pos, Vector2(TIP_W, h))
	_content.draw_rect(box, Color(0.012, 0.018, 0.024, 0.95 * a))
	_content.draw_rect(box, Color(Gothic.BRONZE_LIGHT, 0.6 * a), false, 1.2)
	var x := pos.x + 14.0
	var y := pos.y + 24.0
	_plain(Vector2(x, y), card.display_name, 17, Gothic.BRONZE_LIGHT, a)
	_note(Vector2(x + Gothic.text_width(card.display_name, 17) + 10.0, y), card.duration, 12, a)
	y += 24.0
	_content.draw_multiline_string_outline(f, Vector2(x, y), card.description, HORIZONTAL_ALIGNMENT_LEFT, text_w, 14, -1, 3,
		Color(0, 0, 0, 0.6 * a))
	_content.draw_multiline_string(f, Vector2(x, y), card.description, HORIZONTAL_ALIGNMENT_LEFT, text_w, 14, -1, Color(Gothic.BONE, a))
	if uses != "":
		_plain(Vector2(x, y + desc_h + 6.0), uses, 13, GAIN, a)


## 船舱里的渔获：一条一个位置，插图（按时期）像幽影一样浮着；下面写名字和等级、时期和祭值、各项用途、词条。
## 选中的那条亮起来，下面一道线
func _slots(a: float) -> void:
	_slot_rects.clear()
	var hold := contractor.hold
	if hold.is_empty():
		_plain_centered("船舱是空的", SLOTS_Y + 52.0, 16, Gothic.BONE_DARK, a)
		return
	var x0 := CX - hold.size() * SLOT_W * 0.5
	var glow := Gothic.glow_texture()
	for i in hold.size():
		var c := hold[i]
		var rect := Rect2(x0 + i * SLOT_W, SLOTS_Y - 4, SLOT_W, 134)
		_slot_rects.append(rect)
		var selected := i == _selected
		var center := Vector2(rect.get_center().x, SLOTS_Y + SLOT_ART.y * 0.5)
		if selected:
			_content.draw_texture_rect(glow, Rect2(center - Vector2(84, 52), Vector2(168, 104)), false, Color(Gothic.BONE, 0.12 * a))
		var tex: Texture2D = c.art() if c.art() else Gothic.tex("icon_fish")
		var aspect := tex.get_size().x / maxf(tex.get_size().y, 1.0)
		var art := Vector2(SLOT_ART.y * aspect, SLOT_ART.y)
		if art.x > SLOT_ART.x:
			art = Vector2(SLOT_ART.x, SLOT_ART.x / aspect)
		var bob := sin(_time * 1.3 + i * 1.1) * 2.0
		var tint := Color(1, 1, 1, a) if selected else Color(0.7, 0.72, 0.74, 0.7 * a)
		_content.draw_texture_rect(tex, Rect2(center - art * 0.5 + Vector2(0, bob), art), false, Gothic.catch_tint(c, tint))
		var title := "%s　%d 级" % [c.display_name(), c.level]
		var ny := SLOTS_Y + SLOT_ART.y + 22.0
		var cx := rect.get_center().x
		_plain(Vector2(cx - Gothic.text_width(title, 15) * 0.5, ny), title, 15, Gothic.BONE if selected else Gothic.BONE_DARK, a)
		var worth := "%s · 祭值 %s" % [c.stage_name(), Gothic.grouped(c.tribute)]
		_plain(Vector2(cx - Gothic.text_width(worth, 13) * 0.5, ny + 18.0), worth, 13, Gothic.BONE, a)
		var stats := "载荷 %d · 饱腹 +%d · 能量 %d" % [c.load_cost, c.food, c.energy]
		_plain(Vector2(cx - Gothic.text_width(stats, 12) * 0.5, ny + 34.0), stats, 12, Gothic.BONE_DARK, a)
		if not c.affix_ids.is_empty():
			var affix := "「%s」" % "、".join(c.affix_names())
			_plain(Vector2(cx - Gothic.text_width(affix, 12) * 0.5, ny + 49.0), affix, 12, Gothic.WARN, a)
		if selected:
			var y := ny + 56.0
			_content.draw_line(Vector2(cx - 34, y), Vector2(cx + 34, y), Color(Gothic.BRONZE_LIGHT, 0.8 * a), 1.5)


## 墨圈里零星往上飘的蓝色火星
static func _make_sparks() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = Gothic.glow_texture()
	p.emitting = false
	p.amount = 46
	p.lifetime = 5.0
	p.preprocess = 3.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	var pts := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 90:
		# 沿着离边缘 60–150 像素的一圈撒点
		var side := rng.randi_range(0, 3)
		var inset := rng.randf_range(60.0, 150.0)
		match side:
			0:
				pts.append(Vector2(rng.randf_range(80, 1200), inset))
			1:
				pts.append(Vector2(rng.randf_range(80, 1200), 720.0 - inset))
			2:
				pts.append(Vector2(inset, rng.randf_range(60, 660)))
			_:
				pts.append(Vector2(1280.0 - inset, rng.randf_range(60, 660)))
	p.emission_points = pts
	p.direction = Vector2(0, -1)
	p.spread = 35.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 22.0
	p.gravity = Vector2(0, -6)
	p.scale_amount_min = 0.02
	p.scale_amount_max = 0.06
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	fade.colors = PackedColorArray([Color(0.55, 0.85, 1.0, 0.0), Color(0.55, 0.85, 1.0, 0.75), Color(0.55, 0.85, 1.0, 0.0)])
	p.color_ramp = fade
	return p
