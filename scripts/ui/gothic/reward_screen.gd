class_name RewardScreen
extends Control
## 供奉后的补给与奖励卡（新回合机制 9.6，H2）。供奉的结局看完、按空格继续以后打开，接在 OfferingScreen 后面：
## 画面不压暗（祂还在那儿），四周还是那一圈暗红的雾。
## - 最上面祂的话：英文手写的蓝灰发光字，下面灰色中文批注
## - 左边一张大的补给卡（骨片和黑铁的卡面，GPT 画的）：几份万能饵，固定得
## - 右边上下排几张候选的效果卡（RewardCards：够了两张、超额三张；不够只有补给）：图标、名字、持续多久、效果。
##   [1]–[3] 或点一下挑，挑中的亮起来、往外挪一点；[空格] 收下（没有候选时是"继续"）
## - 收下：挑中的那张和补给卡往上飘着淡出，其余的沉下去
## finished 带着挑中的卡（没有候选是 null）：FishingView 把补给放进饵料篓、卡交给契约者，然后天黑、下一夜。
## 开局（open_opening，v0.23）：签下契约以后先挑一张永久恩赐——三条引擎各一张，没有补给卡，候选卡在正中

signal finished(card: RewardCard)

const VEIL := preload("res://shaders/contract_veil.gdshader")
const SUPPLY_FACE := preload("res://assets/cards/reward_card_supply.png")
const EFFECT_FACE := preload("res://assets/cards/reward_card_effect.png")
const UNIVERSAL_ICON := preload("res://assets/icons/universal_bait.png")
const CX := 640.0
const WORDS_Y := 66.0
const MIDDLE_Y := 382.0                   ## 两张卡竖着对齐的中线
const SUPPLY_SIZE := Vector2(255, 340)    ## 补给卡（3:4）
const CARD_SIZE := Vector2(330, 165)      ## 候选卡（2:1）
const CARD_GAP := 12.0
const COLUMN_GAP := 56.0                  ## 补给卡和候选卡之间
const PROMPTS_Y := 652.0
const MIST := Color(0.5, 0.17, 0.12)      ## 和供奉的帷幕一样的暗红雾
const LEAVE_SECONDS := 0.9
## 祂的话：够了的时候 / 不够的时候 / 签约以后的开局恩赐
const WORDS := ["Take what I leave thee.", "Fish. And do not fail me again.", "Choose. And fish for me.", "A brand, for one more gift."]
const WORDS_CN := ["拿走我留给你的。", "去钓吧。别再让我失望。", "挑一样。然后替我钓。", "一枚烙印，换多给你一样。"]

var is_open := false
var busy := false                         ## 收下以后的动画
var contractor: Contractor
var cards: Array[RewardCard] = []
var supply := 0
## 签约以后的开局恩赐（没有补给卡）
var opening := false
## 祂的低语（海上事件）：献了一枚烙印，挑一张恩赐（没有补给卡）
var gift := false

var _selected := -1
var _met := false
var _time := 0.0
var _opened_at := 0.0
var _left_at := -1.0
var _veil_amount := 0.0
var _veil: ColorRect
var _veil_mat: ShaderMaterial
var _content: Control
var _pick_prompt: KeyPrompt
var _take_prompt: KeyPrompt
var _card_rects: Array[Rect2] = []
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
	_pick_prompt = KeyPrompt.make("1–3", "挑一张", 19, false)
	prompts.add_child(_pick_prompt)
	_take_prompt = KeyPrompt.make("空格", "收下", 20)
	_take_prompt.pressed.connect(confirm)
	prompts.add_child(_take_prompt)


## result：Contractor.offer 的结果（met、supply）；choices：候选的卡（RewardCards.draw）
func open(who: Contractor, result: Dictionary, choices: Array[RewardCard]) -> void:
	opening = false
	gift = false
	contractor = who
	cards = choices
	supply = int(result.get("supply", 0))
	_met = bool(result.get("met", false))
	_selected = -1
	_left_at = -1.0
	busy = false
	is_open = true
	visible = true
	modulate.a = 1.0
	_opened_at = _time
	_pick_prompt.visible = not cards.is_empty()
	_pick_prompt.key_text = "1–%d" % cards.size() if cards.size() > 1 else "1"
	_take_prompt.label = "收下" if not cards.is_empty() else "继续"
	_take_prompt.disabled = not cards.is_empty()
	_take_prompt.modulate.a = 0.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_veil, _veil_amount, 0.8, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_take_prompt, "modulate:a", 1.0, 0.4).set_delay(1.0 + 0.15 * cards.size())


## 签约以后的开局恩赐：choices 是三条引擎各一张永久恩赐（RewardCards.draw_opening），挑一张，没有补给
func open_opening(who: Contractor, choices: Array[RewardCard]) -> void:
	open(who, {"met": true, "supply": 0}, choices)
	opening = true


## 祂的低语（海上事件）：献了一枚烙印，从三张永久恩赐里挑一张（RewardCards.draw_boons），没有补给
func open_gift(who: Contractor, choices: Array[RewardCard]) -> void:
	open(who, {"met": true, "supply": 0}, choices)
	gift = true


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


## 挑第 index 张（再挑一次同一张也还是它）
func pick(index: int) -> void:
	if not is_open or busy or index < 0 or index >= cards.size():
		return
	_selected = index
	_take_prompt.disabled = false


## 空格：收下挑中的那张和补给（没有候选时直接继续）；有候选还没挑不算
func confirm() -> void:
	if not is_open or busy or _time - _opened_at < 0.6:
		return
	if not cards.is_empty() and _selected < 0:
		return
	busy = true
	_left_at = _time
	var card: RewardCard = cards[_selected] if _selected >= 0 else null
	var t := create_tween()
	t.tween_interval(LEAVE_SECONDS)
	t.tween_callback(func() -> void:
		busy = false
		_close()
		finished.emit(card))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in _card_rects.size():
			if _card_rects[i].has_point(event.position):
				pick(i)
				accept_event()
				return


func _process(delta: float) -> void:
	_time += delta
	if not visible:
		return
	_veil_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	_content.queue_redraw()


## 浮现的进度：打开后过了 start 秒开始，dur 秒浮现完
func _k(start: float, dur := 0.45) -> float:
	var x := clampf((_time - _opened_at - start) / dur, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## 收下以后的进度 0 → 1
func _leave() -> float:
	if _left_at < 0.0:
		return 0.0
	var x := clampf((_time - _left_at) / LEAVE_SECONDS, 0.0, 1.0)
	return x * x


func _draw_content() -> void:
	if contractor == null:
		return
	var hand := Gothic.hand_font(500)
	var line := 3 if gift else (2 if opening else (0 if _met else 1))
	var a := _k(0.2, 0.6) * (1.0 - _leave())
	var w := Gothic.text_width(WORDS[line], 30, hand)
	Gothic.glow_text(_content, Vector2(CX - w * 0.5, WORDS_Y), WORDS[line], 30, ContractScreen.TERMS_COLOR, ContractScreen.GLOW, a, hand)
	var note: String = WORDS_CN[line]
	Gothic.text(_content, Vector2(CX - Gothic.text_width(note, 14) * 0.5, WORDS_Y + 22.0), note, 14,
		Color(ContractScreen.NOTE, a), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	var sub := "补给照给；再从下面挑一张" if not cards.is_empty() else "这一回只有补给"
	if cards.size() >= 3:
		sub = "超额了：多一张可挑"
	if opening:
		sub = "签下了契约。祂许你一样恩赐，这份契约里一直都在"
	if gift:
		sub = "祂收下了一枚烙印。挑一样恩赐"
	_plain(Vector2(CX, WORDS_Y + 50.0), sub, 15, Gothic.BONE_DARK, _k(0.5), true)

	# 左边补给卡，右边候选卡；没有候选时补给卡在正中
	var total := SUPPLY_SIZE.x + (COLUMN_GAP + CARD_SIZE.x if not cards.is_empty() else 0.0)
	var x0 := CX - total * 0.5
	if opening or gift:  ## 开局、祂的低语没有补给卡：候选卡在正中
		x0 = CX - CARD_SIZE.x * 0.5 - SUPPLY_SIZE.x - COLUMN_GAP
	else:
		_draw_supply(Rect2(Vector2(x0, MIDDLE_Y - SUPPLY_SIZE.y * 0.5), SUPPLY_SIZE))
	_card_rects.clear()
	var stack := cards.size() * CARD_SIZE.y + maxi(cards.size() - 1, 0) * CARD_GAP
	var top := MIDDLE_Y - stack * 0.5
	for i in cards.size():
		var rect := Rect2(Vector2(x0 + SUPPLY_SIZE.x + COLUMN_GAP, top + i * (CARD_SIZE.y + CARD_GAP)), CARD_SIZE)
		_card_rects.append(rect)
		_draw_card(i, rect)


## 补给卡：卡面、万能饵的瓶子、"万能饵 ×N"、一行小字
func _draw_supply(rect: Rect2) -> void:
	var a := _k(0.45, 0.5)
	var leave := _leave()
	rect.position.y += 12.0 * (1.0 - a) - 46.0 * leave
	a *= 1.0 - leave
	if a <= 0.0:
		return
	var glow := Gothic.glow_texture()
	_content.draw_texture_rect(glow, rect.grow(40), false, Color(Gothic.BONE, 0.07 * a))
	_content.draw_texture_rect(SUPPLY_FACE, rect, false, Color(1, 1, 1, a))
	var cx := rect.get_center().x
	_plain(Vector2(cx, rect.position.y + rect.size.y * 0.3), "补　给", 22, Gothic.BONE, a, true)
	var icon := Vector2(118, 118)
	var bob := sin(_time * 1.4) * 2.0
	var c := Vector2(cx, rect.position.y + rect.size.y * 0.52 + bob)
	_content.draw_texture_rect(glow, Rect2(c - icon * 0.8, icon * 1.6), false, Color(Gothic.EERIE, 0.1 * a))
	_content.draw_texture_rect(UNIVERSAL_ICON, Rect2(c - icon * 0.5, icon), false, Color(1, 1, 1, a))
	_plain(Vector2(cx, rect.position.y + rect.size.y * 0.74), "万能饵 ×%d" % supply, 20, Gothic.BONE, a, true)
	_plain(Vector2(cx, rect.position.y + rect.size.y * 0.81), "每次供奉以后都有", 13, Gothic.BONE_DARK, a, true)


## 一张候选卡：卡面、左边图标、右边名字和持续多久、效果（按卡面里的宽度折行）；左边写按哪个键。
## 挑中的亮起来、往外挪一点；挑了别的，这张暗一点
func _draw_card(i: int, rect: Rect2) -> void:
	var card := cards[i]
	var a := _k(0.75 + i * 0.15, 0.45)
	var picked := i == _selected
	var leave := _leave()
	var dim := 1.0 if _selected < 0 or picked else 0.62
	rect.position.x += 18.0 * (1.0 - a) + (10.0 if picked else 0.0)
	rect.position.y += (-46.0 if picked else 26.0) * leave
	a *= 1.0 - leave * (1.0 if picked else 1.4)
	if a <= 0.0:
		return
	var glow := Gothic.glow_texture()
	if picked:
		_content.draw_texture_rect(glow, rect.grow(34), false, Color(Gothic.BONE, 0.16 * a))
	var face := Color(dim, dim, dim, a)
	_content.draw_texture_rect(EFFECT_FACE, rect, false, face)
	# 卡面里面那块暗的：横着 8%–92%，竖着 30%–79%（GPT 的卡面，上下两条骨梁之间）
	var inner := Rect2(rect.position + rect.size * Vector2(0.09, 0.3), rect.size * Vector2(0.82, 0.49))
	var icon := Vector2(inner.size.y, inner.size.y) * 1.08
	var ic := Vector2(inner.position.x + icon.x * 0.5 - 2.0, inner.get_center().y)
	if card.icon:
		_content.draw_texture_rect(card.icon, Rect2(ic - icon * 0.5, icon), false, Color(dim, dim, dim, a))
	var tx := inner.position.x + icon.x + 4.0
	var tw := inner.end.x - tx
	var name_color := Gothic.BONE if dim >= 1.0 else Gothic.BONE_DARK
	Gothic.text(_content, Vector2(tx, inner.position.y + 17.0), card.display_name, 19, Color(name_color, a))
	var dx := tx + Gothic.text_width(card.display_name, 19) + 8.0
	Gothic.text(_content, Vector2(dx, inner.position.y + 16.0), card.duration, 12, Color(Gothic.BRONZE_LIGHT, a * dim), HORIZONTAL_ALIGNMENT_LEFT,
		-1, 3)
	var y := inner.position.y + 36.0
	for row in _wrap(card.description, 12, tw):
		Gothic.text(_content, Vector2(tx, y), row, 12, Color(Gothic.BONE_DARK, a), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
		y += 15.0
	# 按哪个键：卡的左边
	var key := "[%d]" % (i + 1)
	Gothic.text(_content, Vector2(rect.position.x - Gothic.text_width(key, 17) - 6.0, rect.get_center().y + 6.0), key, 17,
		Color(Gothic.BRONZE_LIGHT if picked else Gothic.BONE_DARK, a))


## 按宽度折行（中文一个字一个字地量）；标点不放在行首
func _wrap(s: String, size_t: int, width: float) -> PackedStringArray:
	var rows: PackedStringArray = []
	var row := ""
	for ch in s:
		if row != "" and Gothic.text_width(row + ch, size_t) > width and not ch in "，。；：、）」！？":
			rows.append(row)
			row = ""
		row += ch
	if row != "":
		rows.append(row)
	return rows


func _plain(pos: Vector2, s: String, size_t: int, color: Color, a: float, centered := false) -> void:
	if a <= 0.0:
		return
	if centered:
		pos.x -= Gothic.text_width(s, size_t) * 0.5
	Gothic.text(_content, pos, s, size_t, Color(color, color.a * a))
