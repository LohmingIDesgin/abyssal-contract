class_name BaitBench
extends Control
## 制饵（交接文档 §5）：按 E 打开，盖在压暗的海面上，和契约书一样是整屏的，HUD 收起来。
## - 正中是配方：两份基础材料 + 一份附加物，三个槽；右边是做出来的那瓶饵（Gothic.flask），下面写名字和能用几次，
##   再下面一行灰字是附加物的说明（它招什么、赶走什么）。
## - 左边是身上的东西：三类基础材料 [1]–[3]、附加物 [4]–[7]（基础款写"不限"）。点一下或按键放进槽里；点槽把它拿出来。
## - 左上写饵料篓里现在有什么。
## - 右边是这瓶饵在某一层水里的上钩倾向（←→ 换水层），每种写它在这层水里出的那几级；比契约者强的（BalanceConfig.fight_gap）
##   标成橙色，远超的（强两级以上，钩上了只能剪线）标成红色；
##   最后一行是"什么也没咬"。
## - 下面：[空格] 制作、[退格] 清空、[E] 回到船上。做好的饵进饵料篓（同一配方叠在一起），配方留在槽里，可以连着做。
## 字是 HUD 的骨白描边（契约的蓝只给契约），按钮是 KeyPrompt。按键由 FishingView 转过来。

signal close_requested

## 以下坐标都按基准分辨率 1280×720
const TITLE_Y := 62.0
const SOCKET_Y := 168.0
const SOCKETS_X: Array[float] = [430.0, 540.0, 670.0]  ## 两份基础材料、附加物
const SOCKET_R := 34.0
const FLASK_CENTER := Vector2(830, 160)
const FLASK_SCALE := 1.7
const NOTE_Y := 292.0
const LEFT_X := 110.0
const BASKET_Y := 336.0
const LIST_Y := 352.0
const RIGHT_X := 820.0
const RIGHT_W := 350.0
const ODDS_Y := 374.0
const ODDS_STEP := 30.0
const STATUS_Y := 614.0
const PROMPTS_Y := 634.0
const NOTE := Color(0.56, 0.6, 0.62)
const STRONG := Color("ff6a50")  ## 比契约者高两级以上


var dim: ColorRect
var is_open := false
## 右边看哪一层水的上钩倾向
var depth := 0

var _who: Contractor
var _bases: Array[String] = []
var _additive_id := ""
var _additive_ids: Array[String] = []  ## 左边附加物的顺序：基础款在最前
var _base_rows: Array[KeyPrompt] = []
var _additive_rows: Array[KeyPrompt] = []
var _craft_prompt: KeyPrompt
var _list: VBoxContainer
var _message := ""                      ## 刚做好时的那句话，过一会儿换回平常的提示
var _message_time := 0.0
var _flash := 0.0
var _time := 0.0
var _owns_dim := false
var _tween: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	visible = false
	var basic := GameDB.basic_additive()
	if basic:
		_additive_ids.append(basic.id)
	for a: AdditiveData in GameDB.sorted_values(GameDB.additives):
		if not a.unlimited:
			_additive_ids.append(a.id)
	_build()


func _build() -> void:
	var list := VBoxContainer.new()
	_list = list
	list.position = Vector2(LEFT_X, LIST_Y)
	list.add_theme_constant_override("separation", 0)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(list)
	list.add_child(_header("基础材料"))
	for i in Materials.ALL.size():
		var m: String = Materials.ALL[i]
		var prompt := _row(list, Gothic.icon_rect("mat_" + m, Vector2(24, 24)), str(i + 1))
		prompt.pressed.connect(add_base.bind(m))
		_base_rows.append(prompt)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	list.add_child(gap)
	list.add_child(_header("附加物"))
	for i in _additive_ids.size():
		var a := GameDB.get_additive(_additive_ids[i])
		var prompt := _row(list, _additive_icon(a), str(Materials.ALL.size() + i + 1))
		prompt.pressed.connect(set_additive.bind(a.id))
		_additive_rows.append(prompt)

	var depth_keys := HBoxContainer.new()
	depth_keys.position = Vector2(RIGHT_X + RIGHT_W - 74.0, ODDS_Y - 52.0)
	depth_keys.add_theme_constant_override("separation", 0)
	add_child(depth_keys)
	for step in [-1, 1]:
		var p := KeyPrompt.make("←" if step < 0 else "→", "", 16)
		p.pressed.connect(move_depth.bind(step))
		depth_keys.add_child(p)

	var prompts := HBoxContainer.new()
	prompts.position = Vector2(0, PROMPTS_Y)
	prompts.size = Vector2(1280, 34)
	prompts.alignment = BoxContainer.ALIGNMENT_CENTER
	prompts.add_theme_constant_override("separation", 40)
	add_child(prompts)
	_craft_prompt = KeyPrompt.make("空格", "制作", 20)
	_craft_prompt.pressed.connect(craft)
	prompts.add_child(_craft_prompt)
	var clear_prompt := KeyPrompt.make("退格", "清空", 20)
	clear_prompt.pressed.connect(clear)
	prompts.add_child(clear_prompt)
	var back := KeyPrompt.make("E", "回到船上", 20)
	back.pressed.connect(func() -> void: close_requested.emit())
	prompts.add_child(back)


func _header(text: String) -> Label:
	return Gothic.label(text, 15, Gothic.BRONZE_LIGHT)


func _row(list: VBoxContainer, icon: Control, key: String) -> KeyPrompt:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var prompt := KeyPrompt.make(key, "", 17)
	row.add_child(prompt)
	list.add_child(row)
	return prompt


## 附加物在左边列表里的小图标：有图标用图标（GPT 画的，assets/additives/），没有就用气味印章
func _additive_icon(a: AdditiveData) -> Control:
	if a and a.icon:
		var t := TextureRect.new()
		t.texture = a.icon
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(24, 24)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return t
	if a and a.aspect != "":
		return Gothic.icon_rect("seal_" + a.aspect, Vector2(24, 24))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(24, 24)
	return spacer


# ---------- 开关 ----------

func open(who: Contractor, at_depth: int) -> void:
	_who = who
	depth = at_depth
	if _additive_id == "" and not _additive_ids.is_empty():
		_additive_id = _additive_ids[0]
	_message = ""
	is_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 0.0
	refresh()
	_restart_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.3)
	_owns_dim = not dim.visible
	if _owns_dim:
		dim.visible = true
		_tween.parallel().tween_method(_set_dim, 0.0, 0.9, 0.3)


func close() -> void:
	if not is_open:
		return
	is_open = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_restart_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.2)
	if _owns_dim:
		_tween.parallel().tween_method(_set_dim, 0.9, 0.0, 0.3)
	_tween.tween_callback(func() -> void:
		visible = false
		if _owns_dim:
			_owns_dim = false
			dim.visible = false)


func _restart_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()


func _set_dim(v: float) -> void:
	(dim.material as ShaderMaterial).set_shader_parameter("amount", v)


# ---------- 配方 ----------

## 按键 1–3 放基础材料，4 起选附加物
func pick_key(index: int) -> void:
	if index < Materials.ALL.size():
		add_base(Materials.ALL[index])
	elif index - Materials.ALL.size() < _additive_ids.size():
		set_additive(_additive_ids[index - Materials.ALL.size()])


## 放一份基础材料：先填空槽，两个都满了就换掉第二个
func add_base(m: String) -> void:
	if _available(m) <= 0:
		return
	if _bases.size() < 2:
		_bases.append(m)
	else:
		_bases[1] = m
	_message = ""
	refresh()


func set_additive(id: String) -> void:
	var left := _who.additive_count(id)
	if left == 0:
		return
	_additive_id = id
	_message = ""
	refresh()


func clear() -> void:
	_bases.clear()
	_message = ""
	refresh()


func move_depth(step: int) -> void:
	depth = posmod(depth + step, GameDB.DEPTH_NAMES.size())
	refresh()


## 做一份：扣材料，放进饵料篓。配方留在槽里，可以接着做；材料不够了就把不够的那份拿出来
func craft() -> void:
	var bait := BaitCrafter.craft(_who, _bases, _additive_id)
	if bait == null:
		return
	GameState.add_bait(bait)
	var total := 0
	for b in GameState.baits:
		if b.same_recipe(bait):
			total = b.uses
	PlayLog.event("craft", {"bait": bait.display_name, "bases": bait.bases, "additive": bait.additive_id,
		"materials": _who.materials.duplicate(), "additives": _who.additives.duplicate()})
	_message = "做好了一份「%s」，饵料篓里这种饵共 %d 份" % [bait.display_name, total]
	_message_time = 2.5
	_flash = 1.0
	if _who.additive_count(_additive_id) == 0:
		_additive_id = _additive_ids[0] if not _additive_ids.is_empty() else ""
	refresh()


## 这种基础材料还能往槽里放几份（身上的减去已经放进槽里的）
func _available(m: String) -> int:
	return _who.materials.get(m, 0) - _bases.count(m)


func _preview() -> Bait:
	if _bases.size() < 2 or _additive_id == "":
		return null
	return BaitCrafter.make(_bases, _additive_id, _who.config)


func refresh() -> void:
	if _who == null:
		return
	for i in Materials.ALL.size():
		var m: String = Materials.ALL[i]
		_base_rows[i].label = "%s　%d" % [Materials.DISPLAY[m], _who.materials.get(m, 0)]
		_base_rows[i].disabled = _available(m) <= 0
	for i in _additive_ids.size():
		var a := GameDB.get_additive(_additive_ids[i])
		var left := _who.additive_count(a.id)
		_additive_rows[i].label = "%s　%s" % [a.display_name, "不限" if left < 0 else str(left)]
		_additive_rows[i].disabled = left == 0
	_craft_prompt.disabled = not BaitCrafter.can_craft(_who, _bases, _additive_id)
	queue_redraw()


func _status() -> Array:
	if _message != "":
		return [_message, Gothic.BONE]
	if _bases.size() < 2:
		return ["还差 %d 份基础材料" % (2 - _bases.size()), NOTE]
	if _additive_id == "":
		return ["选一种附加物", NOTE]
	var parts: PackedStringArray = []
	for m in BaitCrafter.normalize(_bases):
		parts.append(Materials.DISPLAY[m])
	var a := GameDB.get_additive(_additive_id)
	parts.append(a.display_name + ("（不限）" if a.unlimited else ""))
	return ["要用掉：" + "、".join(parts), Gothic.BONE_DARK]


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_flash = move_toward(_flash, 0.0, delta * 1.6)
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			_message = ""
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not is_open or not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	# 点槽：把里面的东西拿出来
	for i in 2:
		if event.position.distance_to(Vector2(SOCKETS_X[i], SOCKET_Y)) <= SOCKET_R and i < _bases.size():
			_bases.remove_at(i)
			_message = ""
			refresh()
			accept_event()
			return
	accept_event()


# ---------- 绘制 ----------

func _draw() -> void:
	if _who == null:
		return
	Gothic.text(self, Vector2(0, TITLE_Y), "制饵", 26, Gothic.BRONZE_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, 1280.0, 5)
	var divider := Gothic.tex("divider")
	var dw := 320.0
	draw_texture_rect(divider, Rect2(640.0 - dw * 0.5, TITLE_Y + 6.0, dw, dw * divider.get_height() / divider.get_width()), false)
	_draw_recipe()
	_draw_odds()
	_draw_basket()
	_draw_chosen_marker()
	var status := _status()
	Gothic.text(self, Vector2(0, STATUS_Y), status[0], 15, status[1], HORIZONTAL_ALIGNMENT_CENTER, 1280.0, 4)


func _draw_recipe() -> void:
	var sorted := BaitCrafter.normalize(_bases)
	for i in 2:
		var c := Vector2(SOCKETS_X[i], SOCKET_Y)
		var m: String = _bases[i] if i < _bases.size() else ""
		_socket(c, m != "")
		if m != "":
			draw_texture_rect(Gothic.tex("mat_" + m), Rect2(c - Vector2(23, 23), Vector2(46, 46)), false)
		Gothic.text(self, Vector2(c.x - 60.0, c.y + SOCKET_R + 22.0), Materials.DISPLAY[m] if m != "" else "基础材料", 14,
			Gothic.BONE if m != "" else NOTE, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 3)
	var a := GameDB.get_additive(_additive_id)
	var ac := Vector2(SOCKETS_X[2], SOCKET_Y)
	_socket(ac, a != null)
	if a:
		if a.icon or a.aspect != "":
			Gothic.additive_mark(self, a, ac - Vector2(20, 20), 40.0)
		else:
			Gothic.text(self, ac + Vector2(-SOCKET_R, 6), "不限", 15, Gothic.BONE_DARK, HORIZONTAL_ALIGNMENT_CENTER, SOCKET_R * 2.0, 3)
	Gothic.text(self, Vector2(ac.x - 80.0, ac.y + SOCKET_R + 22.0), a.display_name if a else "附加物", 14,
		Gothic.BONE if a else NOTE, HORIZONTAL_ALIGNMENT_CENTER, 160.0, 3)
	for x in [(SOCKETS_X[0] + SOCKETS_X[1]) * 0.5, (SOCKETS_X[1] + SOCKETS_X[2]) * 0.5]:
		Gothic.text(self, Vector2(x - 20.0, SOCKET_Y + 8.0), "+", 24, Gothic.BONE_DARK, HORIZONTAL_ALIGNMENT_CENTER, 40.0, 4)
	# 箭头 → 那瓶饵
	var x0 := SOCKETS_X[2] + SOCKET_R + 18.0
	var x1 := FLASK_CENTER.x - 54.0
	draw_line(Vector2(x0, SOCKET_Y), Vector2(x1, SOCKET_Y), Color(Gothic.BONE_DARK, 0.8), 1.6)
	draw_line(Vector2(x1, SOCKET_Y), Vector2(x1 - 8.0, SOCKET_Y - 6.0), Color(Gothic.BONE_DARK, 0.8), 1.6)
	draw_line(Vector2(x1, SOCKET_Y), Vector2(x1 - 8.0, SOCKET_Y + 6.0), Color(Gothic.BONE_DARK, 0.8), 1.6)
	# 那瓶饵：做好的那一下亮一下、鼓一下
	var scale := FLASK_SCALE * (1.0 + 0.12 * _flash)
	var r := 70.0 * (1.0 + 0.3 * _flash)
	draw_texture_rect(Gothic.aura_texture(), Rect2(FLASK_CENTER - Vector2(r, r), Vector2(r, r) * 2.0), false,
		Color(0.4, 0.75, 0.7, 0.12 + 0.35 * _flash))
	if sorted.is_empty():
		Gothic.sprite_centered(self, "flask_round", FLASK_CENTER, scale, Color(1, 1, 1, 0.45))
	else:
		Gothic.flask(self, FLASK_CENTER, scale, sorted)
	var bait := _preview()
	if bait:
		Gothic.additive_mark(self, a, FLASK_CENTER + Vector2(24, 18) * scale / FLASK_SCALE, 24.0)
		Gothic.text(self, Vector2(FLASK_CENTER.x - 120.0, FLASK_CENTER.y + 76.0), bait.display_name, 20, Gothic.BONE,
			HORIZONTAL_ALIGNMENT_CENTER, 240.0, 4)
		Gothic.text(self, Vector2(FLASK_CENTER.x - 120.0, FLASK_CENTER.y + 96.0), "一份挂一次，咬钩才用掉", 13,
			Gothic.BONE_DARK, HORIZONTAL_ALIGNMENT_CENTER, 240.0, 3)
	if a and a.description != "":
		Gothic.text(self, Vector2(300.0, NOTE_Y), a.description, 13, NOTE, HORIZONTAL_ALIGNMENT_CENTER, 680.0, 3)


func _socket(c: Vector2, filled: bool) -> void:
	draw_circle(c, SOCKET_R, Color(0, 0, 0, 0.42))
	draw_arc(c, SOCKET_R, 0.0, TAU, 48, Color(Gothic.BONE if filled else Gothic.BONE_DARK, 0.85 if filled else 0.5), 1.6, true)
	draw_arc(c, SOCKET_R - 5.0, 0.0, TAU, 48, Color(Gothic.BONE_DARK, 0.25), 1.0, true)


## 右边：这瓶饵在这一层水里的上钩倾向
func _draw_odds() -> void:
	Gothic.text(self, Vector2(RIGHT_X, ODDS_Y - 30.0), "上钩倾向 · %s" % GameDB.DEPTH_NAMES[depth], 16, Gothic.BRONZE_LIGHT)
	var bait := _preview()
	if bait == null:
		Gothic.text(self, Vector2(RIGHT_X, ODDS_Y + 6.0), "放好两份基础材料和一份附加物，", 14, NOTE)
		Gothic.text(self, Vector2(RIGHT_X, ODDS_Y + 28.0), "这里会写它在这层水里招来什么。", 14, NOTE)
		return
	var y := ODDS_Y
	var nothing := 0.0
	for e in BiteCalculator.bite_table(bait, depth, _who.config):
		if e.fish == null:
			nothing = e.chance
			continue
		var fish: FishData = e.fish
		var low := 99
		var high := 0
		for x in WaterLayers.entries(fish, depth, _who.config):  ## 这层水里出的是它的哪几级（等级跟着时期走）
			low = mini(low, x.level)
			high = maxi(high, x.level)
		var gap := _who.config.fight_gap(_who.ability, high)
		var levels := "%d 级" % low if low == high else "%d–%d 级" % [low, high]
		_odds_row(y, fish.display_name, levels, e.chance, STRONG if gap >= 1.5 else (Gothic.WARN if gap >= 0.5 else Gothic.BONE))
		y += ODDS_STEP
	_odds_row(y, "什么也没咬", "", nothing, NOTE)


func _odds_row(y: float, name_text: String, levels: String, chance: float, color: Color) -> void:
	Gothic.text(self, Vector2(RIGHT_X, y), name_text, 15, color)
	if levels != "":
		Gothic.text(self, Vector2(RIGHT_X + Gothic.text_width(name_text, 15) + 8.0, y), levels, 12, NOTE)
	Gothic.text(self, Vector2(RIGHT_X, y), "%d%%" % roundi(chance * 100.0), 15, color, HORIZONTAL_ALIGNMENT_RIGHT, RIGHT_W)
	var bar := Rect2(RIGHT_X, y + 6.0, RIGHT_W, 3.0)
	draw_rect(bar, Color(0, 0, 0, 0.5))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * chance, bar.size.y)), Color(color, 0.7))


## 选中的附加物：那一行左边一颗小菱形
func _draw_chosen_marker() -> void:
	var i := _additive_ids.find(_additive_id)
	if i < 0:
		return
	var row := _additive_rows[i].get_parent() as Control
	var c := _list.position + row.position + Vector2(-12.0, row.size.y * 0.5)
	var pts := PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)])
	draw_colored_polygon(pts, Gothic.BRONZE_LIGHT)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.8), 1.2, true)


## 左上：饵料篓里现在有什么
func _draw_basket() -> void:
	var parts: PackedStringArray = []
	for b in GameState.baits:
		parts.append("%s ×%d" % [b.display_name, b.uses])
	var text := "　".join(parts) if not parts.is_empty() else "空的：处理渔获、做饵，或者唤祂"
	Gothic.text(self, Vector2(LEFT_X, BASKET_Y), "饵料篓", 15, Gothic.BRONZE_LIGHT)
	Gothic.text(self, Vector2(LEFT_X + 60.0, BASKET_Y), text, 15, Gothic.BONE)
