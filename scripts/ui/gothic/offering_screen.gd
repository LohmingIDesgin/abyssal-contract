class_name OfferingScreen
extends Control
## 黄昏供奉（交接文档 §9；设计对照文档 3.2 第 12 条：从船舱里主动挑，只收完整的渔获）。
## 天转红、祂从雾里浮出来以后打开。画面不压暗（祂就在那儿），只在四周起一圈暗红的雾（契约书的帷幕换成暗红）。
## - 最上面三枚烙印；祂的话是英文手写的蓝灰发光字，下面灰色中文批注（和契约语同一种字）
## - 中间：黄昏要多少祭值、超额线（还有下一夜时：到了它，供奉后的奖励卡多一张候选）、挑出来多少
##   （不够是偏红的骨色，够了是骨白，到了超额线是古铜色）；祂今夜想要什么
## - 下面是船舱里的渔获，[1]–[9] 或点一下挑出来，挑中的亮起来、下面写"献上"；祂想要的那条脚下有一点余烬
## - [空格] 献上：挑中的化成烟往上飘走，然后写结局（够了 / 够了还合心意，赐下什么 / 不够，吃掉一枚烙印 /
##   不够又没有烙印了 / 契约已偿）。[空格] 继续，FishingView 接着走：下一夜、死、或者契约已偿
## - 不够时祂突然发怒（烟散完的那一刻）：angered 信号让 FishingView 震海面、闪祂的眼睛；帷幕猛地压暗、雾烧红一下；
##   祂的话换成凶狠的一句砸出来、抖个不停；那枚烙印同时烧红熄掉。这份契约里不够的次数越多，震得越狠、字越大越凶
## 字：祂的话是蓝灰发光的英文手写（契约语那种），发怒时换成烧红的光；其余是 HUD 的骨白描边。

signal finished(result: Dictionary)
## 祂发怒了：level 1、2 是这份契约里第几次不够，3 是最后一枚烙印也没了，4 是烙印没了还不够（要吞人）
signal angered(level: int)

const VEIL := preload("res://shaders/contract_veil.gdshader")
const CX := 640.0
const BRAND_Y := 46.0
const WORDS_Y := 236.0                    ## 祂的话在祂眼睛下面（GodPresence.EYE_Y，眼睛在屏幕高 0.28 处，约 199 像素）
const INFO_Y := 352.0
const SLOTS_Y := 412.0
const SLOT_W := 224.0
const SLOT_ART := Vector2(140, 62)
const RESULT_Y := 596.0
const PROMPTS_Y := 656.0
const EMBER := Color(1.0, 0.45, 0.2)
## 祂的话：英文手写，下面是灰色中文批注
const WORDS: Array[String] = ["Feed me.", "And bring me what I crave."]
const WORDS_CN: Array[String] = ["喂我。", "再把我想要的带来。"]
const ANGER_AT := 0.9                     ## 献上的东西化成烟散完，祂才发怒
## 祂发怒时的话（angered 的 level 1~4），一句比一句凶；字号、刚发怒那一下抖多少像素也跟着涨
const ANGER_WORDS: Array[String] = ["You dare bring me scraps?", "Starve me again and I feed on you.",
	"Your brands are ash. Next, your flesh.", "Then you are the offering."]
const ANGER_WORDS_CN: Array[String] = ["你竟敢拿残渣来供我？", "再让我挨饿，我就拿你充饥。",
	"烙印烧尽了。下一次，是你的血肉。", "那么，你就是祭品。"]
const ANGER_SIZE: Array[int] = [32, 35, 39, 44]
const ANGER_SHAKE: Array[float] = [3.0, 4.5, 6.5, 9.0]
const ANGER_COLOR := Color(1.0, 0.66, 0.54)
const ANGER_GLOW := Color(1.0, 0.24, 0.1)
const ANGER_NOTE := Color(0.8, 0.52, 0.46)
const MIST := Color(0.5, 0.17, 0.12)       ## 帷幕的暗红雾
const MIST_RAGE := Color(0.95, 0.26, 0.12) ## 祂发怒那一下烧红

var is_open := false
var contractor: Contractor
var rng: RandomNumberGenerator

var _selected: Array[CatchData] = []
var _result := {}
var _offered: Array[CatchData] = []
var _offered_at := -1.0
var _lost_brand := -1                     ## 刚被吃掉的那枚烙印是第几枚，先红一下再熄
var _anger := 0                           ## 这次祂发怒的程度（ANGER_WORDS 的第几句，从 1 起）；0 = 没发怒
var _anger_at := -1.0                     ## 发怒的那一刻（_time）
var _continue_at := 0.0                   ## 结局写完、过了这一刻按空格才算继续
var _veil_amount := 0.0
var _veil: ColorRect
var _veil_mat: ShaderMaterial
var _content: Control
var _offer_prompt: KeyPrompt
var _continue_prompt: KeyPrompt
var _pick_prompt: KeyPrompt
var _slot_rects: Array[Rect2] = []
var _slot_catches: Array[CatchData] = []
var _time := 0.0
var _opened_at := 0.0
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
	_veil_mat.set_shader_parameter("ink_color", Color(0.03, 0.008, 0.008))
	_veil_mat.set_shader_parameter("mist_color", MIST)
	_veil_mat.set_shader_parameter("rim_color", Color(0.85, 0.32, 0.18))
	_veil.material = _veil_mat
	add_child(_veil)
	_content = Control.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.draw.connect(_draw_content)
	add_child(_content)
	var prompts := HBoxContainer.new()
	prompts.position = Vector2(0, PROMPTS_Y)
	prompts.size = Vector2(1280, 34)
	prompts.alignment = BoxContainer.ALIGNMENT_CENTER
	prompts.add_theme_constant_override("separation", 40)
	add_child(prompts)
	_pick_prompt = KeyPrompt.make("1–9", "挑选", 19, false)
	prompts.add_child(_pick_prompt)
	_offer_prompt = KeyPrompt.make("空格", "献上", 20)
	_offer_prompt.pressed.connect(confirm)
	prompts.add_child(_offer_prompt)
	_continue_prompt = KeyPrompt.make("空格", "继续", 20)
	_continue_prompt.pressed.connect(confirm)
	prompts.add_child(_continue_prompt)


func open(who: Contractor, random: RandomNumberGenerator) -> void:
	contractor = who
	rng = random
	_selected.clear()
	_result = {}
	_offered.clear()
	_offered_at = -1.0
	_lost_brand = -1
	_anger = 0
	_anger_at = -1.0
	_veil_mat.set_shader_parameter("mist_color", MIST)
	is_open = true
	visible = true
	modulate.a = 1.0
	_opened_at = _time
	_set_prompts()
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_veil, 0.0, 0.8, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _close() -> void:
	is_open = false
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.4)
	_tween.parallel().tween_method(_set_veil, _veil_amount, 0.0, 0.5)
	_tween.tween_callback(func() -> void: visible = false)


func _set_veil(v: float) -> void:
	_veil_amount = v
	_veil_mat.set_shader_parameter("amount", v)


func _set_prompts() -> void:
	var done := not _result.is_empty()
	_pick_prompt.visible = not done
	_offer_prompt.visible = not done
	_continue_prompt.visible = done


## 挑一条 / 放回去（船舱里第 index 条）
func toggle(index: int) -> void:
	if not is_open or not _result.is_empty() or contractor == null or index >= contractor.hold.size():
		return
	var c := contractor.hold[index]
	if _selected.has(c):
		_selected.erase(c)
	else:
		_selected.append(c)


## 空格：献上；结局写完以后再按一下继续
func confirm() -> void:
	if not is_open:
		return
	if _result.is_empty():
		_offered = _selected.duplicate()
		var brands_before := contractor.brands
		_result = contractor.offer(_offered, rng)
		_result.offered = _offered.size()
		if _result.brand_lost:
			_lost_brand = brands_before - 1
		_offered_at = _time
		var wait := 1.6
		if not _result.met:
			_anger = 4 if _result.died else (3 if contractor.brands == 0 else mini(contractor.failed_offerings, 2))
			_anger_at = _time + ANGER_AT
			wait += ANGER_AT
		_continue_at = _time + wait
		_set_prompts()
		_continue_prompt.modulate.a = 0.0
		var t := create_tween()
		if _anger > 0:
			t.tween_interval(ANGER_AT)
			t.tween_callback(_erupt)
			t.tween_interval(wait - ANGER_AT)
		else:
			t.tween_interval(wait)
		t.tween_property(_continue_prompt, "modulate:a", 1.0, 0.4)
	elif _time >= _continue_at:
		var result := _result
		_close()
		finished.emit(result)


## 祂发怒的那一下：让 FishingView 震海面、闪眼睛；帷幕猛地压暗，再退回一点（越怒退得越少）
func _erupt() -> void:
	angered.emit(_anger)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_veil, _veil_amount, 1.0, 0.08)
	_tween.tween_method(_set_veil, 1.0, 0.8 + 0.04 * _anger, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## 发怒那一下的余波：1 → 0
func _anger_flash() -> float:
	if _anger == 0 or _time < _anger_at:
		return 0.0
	return exp(-(_time - _anger_at) * 2.5)


## 挑出来的值多少（含同族之献：Contractor.offer_value）
func _selected_tribute() -> int:
	return int(contractor_value().total)


func contractor_value() -> Dictionary:
	return contractor.offer_value(_selected) if contractor else {"base": 0, "kin": 0, "total": 0}


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in _slot_rects.size():
			if _slot_rects[i].has_point(event.position):
				toggle(contractor.hold.find(_slot_catches[i]))
				accept_event()
				return


func _process(delta: float) -> void:
	_time += delta
	if not visible:
		return
	_veil_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	if _anger > 0:
		_veil_mat.set_shader_parameter("mist_color", MIST.lerp(MIST_RAGE, _anger_flash()))
	_content.queue_redraw()


## 浮现的进度：打开后过了 start 秒开始，dur 秒浮现完
func _k(start: float, dur := 0.4, from := -1.0) -> float:
	var origin := _opened_at if from < 0.0 else from
	var x := clampf((_time - origin - start) / dur, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _plain(pos: Vector2, s: String, size_t: int, color: Color, a: float, centered := false) -> void:
	if a <= 0.0:
		return
	if centered:
		pos.x -= Gothic.text_width(s, size_t) * 0.5
	Gothic.text(_content, pos, s, size_t, Color(color, color.a * a))


func _draw_content() -> void:
	var who := contractor
	if who == null:
		return
	_draw_brands(who)
	# 祂的话：英文手写，蓝灰发光；下面灰色中文批注。发怒时一下子撤掉，换成凶狠的那句
	var hand := Gothic.hand_font(500)
	var calm := 1.0
	if _anger > 0 and _time >= _anger_at:
		calm = 1.0 - clampf((_time - _anger_at) / 0.04, 0.0, 1.0)
	var lines := 0 if calm <= 0.0 else 1
	for i in lines:
		var a := _k(0.6 + i * 0.7, 0.6) * calm
		var w := Gothic.text_width(WORDS[i], 30, hand)
		Gothic.glow_text(_content, Vector2(CX - w * 0.5, WORDS_Y + i * 54.0), WORDS[i], 30, ContractScreen.TERMS_COLOR,
			ContractScreen.GLOW, a, hand)
		var note := WORDS_CN[i]
		Gothic.text(_content, Vector2(CX - Gothic.text_width(note, 14) * 0.5, WORDS_Y + i * 54.0 + 22.0), note, 14,
			Color(ContractScreen.NOTE, _k(0.9 + i * 0.7, 0.5) * calm), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	if _anger > 0 and _time >= _anger_at:
		_draw_anger(hand)
	# 要多少、挑了多少；祂想要什么
	var a := _k(1.6)
	var picked := _selected_tribute() if _result.is_empty() else int(_result.tribute)
	var need := who.demand()
	var over := ceili(need * who.over_ratio())  ## 满溢之献（恩赐）会把线压低
	var cards := who.night < who.config.contract_nights  ## 最后一夜够了就偿清，不选卡，不写超额线
	var color := Gothic.WARN if picked < need else (Gothic.BRONZE_LIGHT if cards and picked >= over else Gothic.BONE)
	var head := "黄昏要 %s 祭值　　" % Gothic.grouped(need)
	if cards:
		head += "超额 %s（多一张候选卡）　　" % Gothic.grouped(over)
	head += "挑出来的 "
	var num := Gothic.grouped(picked)
	var x := CX - (Gothic.text_width(head, 18) + Gothic.text_width(num, 18)) * 0.5
	_plain(Vector2(x, INFO_Y), head, 18, Gothic.BONE, a)
	_plain(Vector2(x + Gothic.text_width(head, 18), INFO_Y), num, 18, color, a)
	# 恩赐多出来的：同族之献、渔获加冕、空腹之献
	var value: Dictionary = _result if not _result.is_empty() else contractor_value()
	var extras: PackedStringArray = []
	for pair in [["kin", "同族之献"], ["crown", "渔获加冕"], ["hungry", "空腹之献"]]:
		var n := int(value.get(pair[0], 0))
		if n > 0:
			extras.append("%s +%s" % [pair[1], Gothic.grouped(n)])
	if not extras.is_empty():
		var extra_text := "（%s）" % " · ".join(extras)
		_plain(Vector2(CX - Gothic.text_width(extra_text, 14) * 0.5, INFO_Y + 22.0), extra_text, 14, Gothic.EERIE, a)
	_draw_slots(a)
	if not _result.is_empty():
		_draw_result()


func _draw_brands(who: Contractor) -> void:
	var brand := Gothic.tex("soul_brand")
	var glow := Gothic.glow_texture()
	var a := _k(0.2)
	var total := who.config.brands
	for i in total:
		var c := Vector2(CX + (i - (total - 1) * 0.5) * 70.0, BRAND_Y)
		var live := i < who.brands
		var color := ContractScreen.LIVE if live else ContractScreen.ASH
		if i == _lost_brand:
			# 刚被吃掉的那枚：祂发怒的那一刻猛地烧红、爆开一团火光，再熄成灰
			var t := clampf((_time - _anger_at) / 1.4, 0.0, 1.0) if _anger_at >= 0.0 else 0.0
			color = ContractScreen.LIVE.lerp(Color(1.0, 0.3, 0.15), smoothstep(0.0, 0.08, t)).lerp(ContractScreen.ASH, smoothstep(0.4, 1.0, t))
			if t > 0.0:
				ci_glow(glow, c, Color(1.0, 0.3, 0.15, 0.7 * (1.0 - smoothstep(0.3, 1.0, t)) * a), 1.0 + 1.2 * (1.0 - smoothstep(0.0, 0.35, t)))
		elif live:
			ci_glow(glow, c, Color(ContractScreen.LIVE, (0.35 + 0.1 * sin(_time * 2.2 + i * 1.7)) * a))
		_content.draw_texture_rect(brand, Rect2(c - Vector2(20, 20), Vector2(40, 40)), false, Color(color, a))


func ci_glow(glow: Texture2D, c: Vector2, color: Color, scale := 1.0) -> void:
	_content.draw_texture_rect(glow, Rect2(c - Vector2(34, 34) * scale, Vector2(68, 68) * scale), false, color)


## 祂发怒的话：猛地砸出来（先放大再落回），狂抖一阵以后还在细细地颤；越怒字越大、抖得越狠、光烧得越红
func _draw_anger(hand: Font) -> void:
	var t := _time - _anger_at
	var i := _anger - 1
	var size_t := ANGER_SIZE[i]
	var punch := 1.0 + 0.45 * exp(-t * 9.0)
	var amp := ANGER_SHAKE[i] * (0.15 + 0.85 * exp(-t * 2.2))
	var jitter := Vector2(sin(_time * 71.0) + sin(_time * 43.0 + 1.7), sin(_time * 59.0 + 0.6) + sin(_time * 37.0 + 2.9)) * 0.5 * amp
	var words := ANGER_WORDS[i]
	var w := Gothic.text_width(words, size_t, hand)
	_content.draw_set_transform(Vector2(CX, WORDS_Y + 14.0) + jitter, 0.0, Vector2(punch, punch))
	Gothic.glow_text(_content, Vector2(-w * 0.5, 0.0), words, size_t, ANGER_COLOR,
		Color(ANGER_GLOW, 0.7 + 0.3 * exp(-t * 3.0)), clampf(t / 0.06, 0.0, 1.0), hand)
	_content.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var note := ANGER_WORDS_CN[i]
	Gothic.text(_content, Vector2(CX - Gothic.text_width(note, 15) * 0.5, WORDS_Y + 44.0) + jitter * 0.4, note, 15,
		Color(ANGER_NOTE, clampf((t - 0.25) / 0.4, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)


## 船舱里的渔获：一条一个位置，插图像幽影一样浮着；挑中的亮起来，下面写"献上"；祂想要的那条脚下有一点余烬
func _draw_slots(a: float) -> void:
	_slot_rects.clear()
	_slot_catches.clear()
	var list: Array[CatchData] = contractor.hold.duplicate()
	for c in _offered:
		if not list.has(c):
			list.append(c)
	if list.is_empty():
		_plain(Vector2(CX, SLOTS_Y + 52.0), "船舱是空的：没有东西可以献上", 16, Gothic.BONE_DARK, a, true)
		return
	var x0 := CX - list.size() * SLOT_W * 0.5
	var glow := Gothic.glow_texture()
	for i in list.size():
		var c := list[i]
		var offered := _offered.has(c)
		# 献上的化成烟往上飘走
		var gone := _k(0.0, 0.9, _offered_at) if offered and _offered_at >= 0.0 else 0.0
		var sa := a * (1.0 - gone)
		if sa <= 0.01:
			continue
		var rect := Rect2(x0 + i * SLOT_W, SLOTS_Y - 4, SLOT_W, 134)
		if not offered:
			_slot_rects.append(rect)
			_slot_catches.append(c)
		var picked := _selected.has(c) or offered
		var center := Vector2(rect.get_center().x, SLOTS_Y + SLOT_ART.y * 0.5 - gone * 60.0)
		if picked:
			_content.draw_texture_rect(glow, Rect2(center - Vector2(84, 52), Vector2(168, 104)), false, Color(Gothic.BONE, 0.14 * sa))
		var tex: Texture2D = c.art() if c.art() else Gothic.tex("icon_fish")
		var ratio := tex.get_size().x / maxf(tex.get_size().y, 1.0)
		var art := Vector2(SLOT_ART.y * ratio, SLOT_ART.y)
		if art.x > SLOT_ART.x:
			art = Vector2(SLOT_ART.x, SLOT_ART.x / ratio)
		var bob := sin(_time * 1.3 + i * 1.1) * 2.0
		var tint := Color(1, 1, 1, sa) if picked else Color(0.7, 0.72, 0.74, 0.7 * sa)
		_content.draw_texture_rect(tex, Rect2(center - art * 0.5 + Vector2(0, bob), art), false, Gothic.catch_tint(c, tint))
		var cx := rect.get_center().x
		var ny := SLOTS_Y + SLOT_ART.y + 24.0
		var key := "[%d] " % (i + 1) if _result.is_empty() and i < 9 else ""
		_plain(Vector2(cx, ny), "%s%s　%d 级" % [key, c.display_name(), c.level], 15, Gothic.BONE if picked else Gothic.BONE_DARK, sa, true)
		var affix := "　「%s」" % "、".join(c.affix_names()) if not c.affix_ids.is_empty() else ""
		_plain(Vector2(cx, ny + 20.0), "祭值 %s%s" % [Gothic.grouped(c.tribute), affix], 13, Gothic.BONE if picked else Gothic.BONE_DARK, sa, true)
		_plain(Vector2(cx, ny + 36.0), "%s · 载荷 %d" % [c.stage_name(), c.load_cost], 12, Gothic.BONE_DARK, sa, true)
		if picked and _result.is_empty():
			var y := ny + 60.0
			_content.draw_line(Vector2(cx - 34, y), Vector2(cx + 34, y), Color(Gothic.BRONZE_LIGHT, 0.8 * sa), 1.5)


## 结局：献上以后过一会儿浮出来
func _draw_result() -> void:
	var start := 0.9 if _anger == 0 else ANGER_AT + 0.8  ## 祂发怒时等那一下过去再写
	var a := _k(start, 0.6, _offered_at)
	var title := ""
	var detail := ""
	var color := Gothic.BONE
	if _result.repaid:
		title = "契约已偿。"
		detail = "七夜已满。祂放你走了。"
		color = ContractScreen.LIVE
	elif _result.met:
		title = "祂满意了。"
		detail = "下一夜很快就会来。"
	elif _result.died:
		title = "不够，而烙印已经没有了。"
		detail = "祂张开了嘴。"
		color = Gothic.WARN
	else:
		title = "不够。"
		detail = "祂吞掉了一枚烙印（还剩 %d 枚）。" % contractor.brands
		if contractor.night >= contractor.config.contract_nights:
			detail += "契约还没偿清，再来一夜。"
		color = Gothic.WARN
	_plain(Vector2(CX, RESULT_Y), title, 26, color, a, true)
	_plain(Vector2(CX, RESULT_Y + 34.0), detail, 16, Gothic.BONE_DARK, _k(start + 0.4, 0.6, _offered_at), true)
