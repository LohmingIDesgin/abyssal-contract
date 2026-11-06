class_name SettlementScreen
extends Control
## 契约结算清单（核心调整 G4，设计对照文档 8.5）：一位契约者走了以后、下一位签约之前出一屏；名册里点开一位也是它。
## 和契约书一样是墨和雾的帷幕（shaders/contract_veil.gdshader），后面压黑（海只剩一点影子；从名册里点开的全黑，盖住签约）；
## 字一行一行浮出来：
## - 编号（偿清了燃着蓝火，死了是冷掉的灰）和名字
## - 许汝之物：英文手写的那一句；偿清了下面写"祂归还了：……"，死了写原来的批注，后面一句"没能取回。"
## - 结局（契约已偿 / 坠入冥海 / 被祂吞噬，第几夜），右边盖一枚封印写评价（勉强 / 守约 / 虔诚 / 献心；死了是背约 / 殒于冥海），
##   下面一句话
## - 左边几行账：献上的祭值（旁边写要的加起来）、丢的烙印（旁边写其中剪线扣的）、一共抛了几竿、
##   选过的奖励卡（一张一个小图标，按先后；H3）。2026-11-04 起没有合心意、祂赐下的道具了
## - 右边：最珍贵的一件供奉（插图、名字、时期、等级、祭值）
## - 下面：7 种 × 3 个时期的小格子，献过的亮起来（插图缩成剪影，shaders/silhouette.gdshader），没献过的是暗影
## - 最后 [空格] 下一位契约者；从名册里点开看的是 [Esc] 合上
## 字还在浮的时候按一下空格，直接全部显示出来。记录是 Settlement.record 的字典；G4 以前的名册条目没有账，只写结局。

signal closed(review: bool)

const VEIL := preload("res://shaders/contract_veil.gdshader")
const SILHOUETTE := preload("res://shaders/silhouette.gdshader")
## 以下坐标都按基准分辨率 1280×720
const CX := 640.0
const CODE_TOP := 30.0
const PROMISE_Y := 168.0
const OUTCOME_Y := 244.0
const RULE_Y := 300.0
const LEDGER_X := 196.0
const LEDGER_Y := 340.0
const LEDGER_STEP := 28.0
const CARD_ICON := 24.0                 ## 选过的卡：一张一个小图标
const LEDGER_VALUE_X := 150.0          ## 数值离标题左边多远
const BEST_X := 940.0
const BEST_TITLE_Y := 336.0
const BEST_ART := Vector2(240, 92)
const BEST_ART_Y := 396.0
const GRID_TITLE_Y := 532.0
const GRID_TOP := 544.0
const CELL := Vector2(92, 30)
const PROMPT_Y := 664.0
const SEAL := Color(0.55, 0.1, 0.08)
const SEAL_DEAD := Color(0.2, 0.23, 0.25)
const LIT := Color(0.88, 0.84, 0.74)    ## 献过的剪影
const UNLIT := Color(0.13, 0.16, 0.19)  ## 没献过的暗影
const STAGE_SHORT: Array[String] = ["幼年", "成长", "成年"]
## 几时浮出来（秒，从打开算起）；从名册里点开看的快三倍
const T_CODE := 0.5
const T_PROMISE := 1.0
const T_OUTCOME := 2.1
const T_SEAL := 2.7
const T_LEDGER := 3.3
const T_LEDGER_STEP := 0.24
const T_BEST := 4.8
const T_GRID := 5.2
const T_CELL := 0.05
const T_PROMPT := 6.6
const REVIEW_SPEED := 3.0

var is_open := false
## 字还在一行行浮出来
var busy := false
## 从名册里点开看的（看完回到签约），不是刚结束的那一份
var reviewing := false

var _entry := {}
var _species: Array = []                ## 格子的七列：和图鉴一样，按最低等级、最高等级排（Codex.species_order）
var _best: CatchData
var _black: ColorRect
var _veil: ColorRect
var _veil_mat: ShaderMaterial
var _content: Control
var _grid: Control
var _code: SoulName
var _prompt: KeyPrompt
var _time := 0.0
var _opened_at := 0.0
var _speed := 1.0
var _tween: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	visible = false
	_black = ColorRect.new()
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
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
	_content.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_content.draw.connect(_draw_content)
	add_child(_content)
	_grid = Control.new()
	_grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mat := ShaderMaterial.new()
	mat.shader = SILHOUETTE
	_grid.material = mat
	_grid.draw.connect(_draw_grid)
	add_child(_grid)
	_code = SoulName.new()
	_code.font = Gothic.hand_font(700)
	_code.font_size = 62
	_code.rotation = -0.035
	add_child(_code)
	var prompts := HBoxContainer.new()
	prompts.position = Vector2(0, PROMPT_Y)
	prompts.size = Vector2(1280, 34)
	prompts.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(prompts)
	_prompt = KeyPrompt.make("空格", "下一位契约者", 21)
	_prompt.pressed.connect(confirm)
	prompts.add_child(_prompt)


## entry：Settlement.record 的字典（名册的一条）；review = 从名册里点开看的
func open(entry: Dictionary, review := false) -> void:
	_entry = entry
	reviewing = review
	_speed = REVIEW_SPEED if review else 1.0
	_black.color = Color(0.008, 0.012, 0.016, 1.0 if review else 0.94)
	_best = Settlement.best_catch(entry)
	_species = Codex.species_order()
	is_open = true
	busy = true
	visible = true
	modulate.a = 1.0
	_opened_at = _time
	_code.text = "No.%04d" % int(entry.get("number", 0))
	_code.dead_amount = 0.0 if entry.get("status", "") == "repaid" else 1.0
	_code.pivot_offset = _code.size * 0.5
	_code.position = Vector2(CX - _code.size.x * 0.5 - 30.0, CODE_TOP)
	_code.modulate.a = 0.0
	_prompt.key_text = "Esc" if review else "空格"
	_prompt.label = "合上" if review else "下一位契约者"
	_prompt.modulate.a = 0.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_veil, 0.0, 1.0, 0.8 / _speed).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## 空格（或者点按钮）：字还在浮就直接全部显示，浮完了就合上
func confirm() -> void:
	if not is_open:
		return
	if busy:
		_opened_at -= 100.0
		return
	is_open = false
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.6)
	_tween.parallel().tween_method(_set_veil, 1.0, 0.0, 0.6)
	_tween.tween_callback(func() -> void:
		visible = false
		closed.emit(reviewing))


func _input(event: InputEvent) -> void:
	if not is_open or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		confirm()
		get_viewport().set_input_as_handled()


func _set_veil(v: float) -> void:
	_veil_mat.set_shader_parameter("amount", v)


func _process(delta: float) -> void:
	_time += delta
	if not visible:
		return
	_veil_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	_code.modulate.a = _k(T_CODE, 0.8)
	_prompt.modulate.a = _k(T_PROMPT)
	busy = is_open and _elapsed() < T_PROMPT
	_content.queue_redraw()
	_grid.queue_redraw()


func _elapsed() -> float:
	return (_time - _opened_at) * _speed


## start 秒以后用 dur 秒浮出来：0 → 1（平滑）
func _k(start: float, dur := 0.5) -> float:
	var x := clampf((_elapsed() - start) / dur, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


# ---------- 画 ----------

func _text(pos: Vector2, s: String, size_t: int, color: Color, a: float, outline := 4) -> void:
	if a > 0.0:
		Gothic.text(_content, pos, s, size_t, Color(color, color.a * a), HORIZONTAL_ALIGNMENT_LEFT, -1, outline)


func _centered(y: float, s: String, size_t: int, color: Color, a: float, outline := 4) -> void:
	_text(Vector2(CX - Gothic.text_width(s, size_t) * 0.5, y), s, size_t, color, a, outline)


func _draw_content() -> void:
	if _entry.is_empty():
		return
	var repaid: bool = _entry.get("status", "") == "repaid"
	# 编号旁边的名字
	var who_name: String = _entry.get("name", "")
	if who_name == "":
		who_name = SigningScreen.DEFAULT_NAME
	_text(Vector2(_code.position.x + _code.size.x - 4.0, CODE_TOP + _code.size.y * 0.72), who_name, 18, ContractScreen.NOTE,
		_k(T_CODE + 0.3), 3)
	_draw_promise(repaid)
	_draw_outcome(repaid)
	# 一道暗线
	var a := _k(T_OUTCOME + 0.4)
	for s in 24:
		var t0 := s / 24.0
		var t1 := (s + 1) / 24.0
		_content.draw_line(Vector2(lerpf(260, 1020, t0), RULE_Y), Vector2(lerpf(260, 1020, t1), RULE_Y),
			Color(Gothic.BONE_DARK, 0.45 * sin(t0 * PI) * a), 1.5)
	if not Settlement.has_ledger(_entry):
		_centered(LEDGER_Y + 30.0, "这一份契约，没有留下账目。", 16, ContractScreen.NOTE, _k(T_LEDGER))
		return
	_draw_ledger()
	_draw_best()
	_draw_grid_labels()


## 许汝之物：英文手写一个字母一个字母浮出来，写完下面浮出中文
func _draw_promise(repaid: bool) -> void:
	var promise := GameDB.get_promise(str(_entry.get("promise", "")))
	if promise == null:
		return
	var hand := Gothic.hand_font(500)
	var line := promise.line
	var x := CX - Gothic.text_width(line, 26, hand) * 0.5
	var color := ContractScreen.TERMS_COLOR if repaid else ContractScreen.ASH.lightened(0.35)
	var glow := ContractScreen.GLOW if repaid else Color(ContractScreen.ASH, 0.5)
	for j in line.length():
		var ch := line[j]
		var k := _k(T_PROMISE + j * 0.014, 0.3)
		Gothic.glow_text(_content, Vector2(x, PROMISE_Y + (1.0 - k) * 6.0), ch, 26, color, glow, k, hand)
		x += Gothic.text_width(ch, 26, hand)
	var a := _k(T_PROMISE + line.length() * 0.014, 0.5)
	if repaid:
		_centered(PROMISE_Y + 26.0, promise.returned_text(str(_entry.get("rating", ""))), 16, Gothic.BONE, a, 3)  ## 祂的返还
	else:
		var note := promise.note() + "没能取回。"
		_centered(PROMISE_Y + 26.0, note, 15, ContractScreen.NOTE, a, 3)


## 结局一行，右边一枚封印写评价，下面一句话
func _draw_outcome(repaid: bool) -> void:
	var outcome := Settlement.outcome_text(_entry)
	var rating: String = _entry.get("rating", "")
	var size_t := 28
	var w := Gothic.text_width(outcome, size_t)
	var seal_r := 31.0
	var total := w + (24.0 + seal_r * 2.0 if rating != "" else 0.0)
	var x := CX - total * 0.5
	var a := _k(T_OUTCOME)
	_text(Vector2(x, OUTCOME_Y), outcome, size_t, Gothic.BONE if repaid else ContractScreen.ASH.lightened(0.45), a, 5)
	if rating == "":
		return
	# 封印：从大到小盖下来，盖上的那一下闪一圈
	var k := _k(T_SEAL, 0.22)
	if k > 0.0:
		var c := Vector2(x + w + 24.0 + seal_r, OUTCOME_Y - 10.0)
		var s := lerpf(1.8, 1.0, k)
		var col := SEAL if repaid else SEAL_DEAD
		var flash := 1.0 - _k(T_SEAL + 0.22, 0.5)
		if flash > 0.0 and k >= 1.0:
			_content.draw_arc(c, seal_r * (1.0 + 0.6 * (1.0 - flash)), 0.0, TAU, 40, Color(Gothic.BONE, 0.5 * flash), 2.0, true)
		_content.draw_circle(c, seal_r * s + 2.0, Color(0, 0, 0, 0.6 * k))
		_content.draw_circle(c, seal_r * s, Color(col, k))
		_content.draw_arc(c, seal_r * s - 3.0, 0.0, TAU, 40, Color(col.darkened(0.45), k), 1.5, true)
		var ink := Color(Gothic.BONE, k) if repaid else Color(ContractScreen.ASH.lightened(0.6), k)
		if rating.length() <= 2:
			var fs := roundi(21 * s)
			Gothic.text(_content, c + Vector2(-Gothic.text_width(rating, fs) * 0.5, fs * 0.36), rating, fs, ink,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
		else:
			var fs := roundi(15 * s)
			for i in 2:
				var part := rating.substr(i * 2, 2)
				Gothic.text(_content, c + Vector2(-Gothic.text_width(part, fs) * 0.5, (i - 0.5) * fs * 1.05 + fs * 0.36),
					part, fs, ink, HORIZONTAL_ALIGNMENT_LEFT, -1, 0)
	var note: String = Settlement.RATING_NOTES.get(rating, "")
	_centered(OUTCOME_Y + 32.0, note, 15, ContractScreen.NOTE, _k(T_SEAL + 0.3), 3)


## 左边几行账
func _draw_ledger() -> void:
	var tribute := int(_entry.get("tribute", 0))
	var demand := int(_entry.get("demand", 0))
	var casts := int(_entry.get("casts", -1))
	var cards: Array = _entry.get("cards", [])
	var cuts := int(_entry.get("cuts", 0))
	var rows := [
		["献上的祭值", Gothic.grouped(tribute), "要的加起来 %s" % Gothic.grouped(demand)],
		["丢掉的烙印", "%d 枚" % int(_entry.get("brands_lost", 0)), "其中剪线扣的 %d 枚" % cuts if cuts > 0 else ""],
		["抛下的竿", "%d 竿" % casts if casts >= 0 else "没有记", ""],
		["选过的卡", "" if not cards.is_empty() else "没有", ""],
	]
	for i in rows.size():
		var row: Array = rows[i]
		var a := _k(T_LEDGER + i * T_LEDGER_STEP)
		var y := LEDGER_Y + i * LEDGER_STEP
		_text(Vector2(LEDGER_X, y), row[0], 15, Gothic.BRONZE_LIGHT, a)
		var vx := LEDGER_X + LEDGER_VALUE_X
		var big := 19 if i == 0 else 16
		_text(Vector2(vx, y + (2.0 if i == 0 else 0.0)), row[1], big, Gothic.BONE, a)
		if row[2] != "":
			_text(Vector2(vx + Gothic.text_width(row[1], big) + 12.0, y), row[2], 13, ContractScreen.NOTE, a, 3)
	# 选过的卡：小图标加名字，按先后挨个浮出来；太多了（补偿之夜也选过）只写前六张，后面写"等 N 张"
	var y := LEDGER_Y + (rows.size() - 1) * LEDGER_STEP
	var x := LEDGER_X + LEDGER_VALUE_X
	for j in mini(cards.size(), 6):
		var card := GameDB.get_card(str(cards[j]))
		var a := _k(T_LEDGER + (rows.size() - 1) * T_LEDGER_STEP + j * 0.08)
		if card == null or a <= 0.0:
			continue
		if card.icon:
			_content.draw_texture_rect(card.icon, Rect2(Vector2(x, y - CARD_ICON + 6.0), Vector2(CARD_ICON, CARD_ICON)), false, Color(1, 1, 1, a))
			x += CARD_ICON + 2.0
		_text(Vector2(x, y), card.display_name, 13, Gothic.BONE, a, 3)
		x += Gothic.text_width(card.display_name, 13) + 10.0
	if cards.size() > 6:
		_text(Vector2(x, y), "等 %d 张" % cards.size(), 13, ContractScreen.NOTE, _k(T_LEDGER + (rows.size() - 1) * T_LEDGER_STEP + 0.5), 3)


## 右边：最珍贵的一件供奉
func _draw_best() -> void:
	var a := _k(T_BEST, 0.7)
	if a <= 0.0:
		return
	var title := "最珍贵的一件供奉"
	_text(Vector2(BEST_X - Gothic.text_width(title, 15) * 0.5, BEST_TITLE_Y), title, 15, Gothic.BRONZE_LIGHT, a)
	if _best == null:
		var none := "一件也没有献上。"
		_text(Vector2(BEST_X - Gothic.text_width(none, 15) * 0.5, BEST_ART_Y + 6.0), none, 15, ContractScreen.NOTE, a, 3)
		return
	var tex: Texture2D = _best.art()
	if tex:
		var aspect := tex.get_size().x / maxf(tex.get_size().y, 1.0)
		var art := Vector2(BEST_ART.y * aspect, BEST_ART.y)
		if art.x > BEST_ART.x:
			art = Vector2(BEST_ART.x, BEST_ART.x / aspect)
		var center := Vector2(BEST_X, BEST_ART_Y + sin(_time * 1.2) * 2.5)
		var glow := Gothic.glow_texture()
		_content.draw_texture_rect(glow, Rect2(center - art * 0.75, art * 1.5), false, Color(Gothic.BONE, 0.08 * a))
		_content.draw_texture_rect(tex, Rect2(center - art * 0.5, art), false, Gothic.catch_tint(_best, Color(1, 1, 1, a)))
	var head := "%s　%s · %d 级" % [_best.display_name(), _best.stage_name(), _best.level]
	var y := BEST_ART_Y + BEST_ART.y * 0.5 + 26.0
	_text(Vector2(BEST_X - Gothic.text_width(head, 16) * 0.5, y), head, 16, Gothic.BONE, a)
	var worth := "祭值 %s" % Gothic.grouped(_best.tribute)
	_text(Vector2(BEST_X - Gothic.text_width(worth, 17) * 0.5, y + 24.0), worth, 17, CatchReveal.TRIBUTE_COLOR, a)


## 格子的标题、左边的时期、下面的种类名（剪影本身在 _draw_grid）
func _draw_grid_labels() -> void:
	var a := _k(T_GRID - 0.2)
	var x0 := _grid_left()
	_centered(GRID_TITLE_Y, "献上过的种类和时期", 14, Gothic.BRONZE_LIGHT, a)
	for s in 3:
		var label := STAGE_SHORT[s]
		_text(Vector2(x0 - 12.0 - Gothic.text_width(label, 12), GRID_TOP + (s + 0.5) * CELL.y + 4.0), label, 12,
			Gothic.BONE_DARK, a, 3)
	var cell := _cell()
	var name_size := 11 if cell.x >= 70.0 else 10
	for i in _species.size():
		var fish: FishData = _species[i]
		var cx := x0 + (i + 0.5) * cell.x
		_text(Vector2(cx - Gothic.text_width(fish.display_name, name_size) * 0.5, GRID_TOP + 3.0 * CELL.y + 15.0), fish.display_name,
			name_size, Gothic.BONE_DARK, a, 3)


func _grid_left() -> float:
	return CX - _species.size() * _cell().x * 0.5


## 一格多大：七种时一格 92 宽；种类多了（阶段 V 上线以后二十种）格子收窄，整排不出屏幕（最多 1160 宽）
func _cell() -> Vector2:
	return Vector2(minf(CELL.x, 1160.0 / maxf(_species.size(), 1.0)), CELL.y)


## 7 × 3 的剪影：献过的一格一格亮起来，没献过的是暗影（这个控件挂着剪影着色器，画什么都只取形状）
func _draw_grid() -> void:
	if _entry.is_empty() or not Settlement.has_ledger(_entry):
		return
	var kinds: Array = _entry.get("kinds", [])
	var x0 := _grid_left()
	var glow := Gothic.glow_texture()
	var size := _cell()
	var step := T_CELL * minf(1.0, 21.0 / maxf(_species.size() * 3.0, 1.0))  ## 格子多了一格一格亮得快一点，整排还是那么长的时间
	for i in _species.size():
		var fish: FishData = _species[i]
		for s in 3:
			var n := i * 3 + s
			var a := _k(T_GRID + n * step, 0.35)
			if a <= 0.0:
				continue
			var cell := Rect2(x0 + i * size.x, GRID_TOP + s * size.y, size.x, size.y)
			var lit := kinds.has("%s:%d" % [fish.id, s])
			var tex := fish.stage_icon(s)
			if tex == null:
				continue
			var box := cell.size - Vector2(14, 6)
			var aspect := tex.get_size().x / maxf(tex.get_size().y, 1.0)
			var art := Vector2(box.y * aspect, box.y)
			if art.x > box.x:
				art = Vector2(box.x, box.x / aspect)
			var c := cell.get_center()
			if lit:
				_grid.draw_texture_rect(glow, Rect2(c - Vector2(art.x * 0.7, art.y * 1.1), Vector2(art.x * 1.4, art.y * 2.2)),
					false, Color(ContractScreen.LIVE, 0.12 * a))
			_grid.draw_texture_rect(tex, Rect2(c - art * 0.5, art), false, Color(LIT if lit else UNLIT, (1.0 if lit else 0.85) * a))
