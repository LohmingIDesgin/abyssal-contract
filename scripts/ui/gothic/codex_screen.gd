class_name CodexScreen
extends Control
## 图鉴（C；签约时点"翻看图鉴"）：冥海里的生物。数都是 Codex 现算的（改了生物的 .tres 或数值总表，图鉴跟着变）。
## 和契约书、结算清单一样是墨和雾的帷幕，后面压黑；字是 HUD 的骨白描边字。2026-11-05 改版（你给的参照：左边小图、右边大立绘）：
## - 左边：一格一种的小图（一行五格，从弱到强），选中的亮起来、下面写名字；种类多了上下滚。小图有专门画的就用它
##   （assets/creatures/icons/<id>.png），没有就用成年那张插图。只在某些夜里出的，角上标"血月""异化"。
## - 右边：名字、灵魂等级、出没；一张会动的大立绘（CreatureArt：按种类的动效，鳍、须、手指、头灯各自摆），下面切三个时期；
##   再下面三页：生态（介绍、身上的材料、气味、躯体规模）、祭值与用途（每个时期每一级一行）、出没（每层水占几成、钓上来是什么、
##   平均祭值、最招它的饵）。
## - Tab 切到"各层水域"：左边每格右下写它在这层水里占几成（条的颜色是它身上最多的那种材料），这层没有的压暗；
##   右边是这层水：出几级的生物、三个时期各占几成、每咬一口的平均祭值和材料、空竿和捞到东西，下面按占几成排的种类。
## 测试期间全开（Codex.reveal_all）；关掉以后没钓上来过的只剩剪影和"？？？"。
## 按键自己收（开着的时候 FishingView 不处理按键）：↑↓←→ 选，1–3 时期（各层水域里是水层），Q/E 翻页，Tab 切换，C 或 Esc 合上。

signal closed  ## 开始合上的那一刻（帷幕还在退）

const VEIL := preload("res://shaders/contract_veil.gdshader")
const SILHOUETTE := preload("res://shaders/silhouette.gdshader")
## 以下坐标都按基准分辨率 1280×720
const LEFT_X := 52.0
const TITLE_Y := 58.0
const GRID_Y := 112.0                  ## 第一行格子的上沿
const TILE := 96.0
const GAP := 10.0
const COLS := 5
const ROWS_VISIBLE := 5
const NAME_BAND := 22.0                ## 格子底下写名字的那一条
const PANEL_X := 616.0
const PANEL_R := 1236.0
const PANEL_CX := 926.0
const NAME_Y := 72.0
const SUB_Y := 100.0
const PORTRAIT_C := Vector2(926, 238)
const PORTRAIT_BOX := Vector2(560, 196)
const PORTRAIT_SCALE: Array[float] = [0.7, 0.85, 1.0]  ## 幼年、成长、成年的立绘显示得多大
const STAGE_TABS_Y := 374.0
const CAPTION_Y := 400.0
const RULE_Y := 416.0
const INFO_TABS_Y := 444.0
const INFO_Y := 476.0
const INFO_STEP := 26.0
const PROMPTS_Y := 650.0
const SHADOW := Color(0.2, 0.24, 0.27) ## 没收录的剪影
const STAGE_SHORT: Array[String] = ["幼年", "成长", "成年"]
const PAGES: Array[String] = ["生态", "祭值与用途", "出没"]
## 可以换成画好的素材（有就用，没有照现在这样画）：格子的框、选中的框（都按格子大小四周外扩 6 像素画）、立绘后面的底
const TILE_FRAME := "res://assets/ui/codex_tile.png"
const TILE_FRAME_LIT := "res://assets/ui/codex_tile_lit.png"
const PORTRAIT_PLATE := "res://assets/ui/codex_portrait.png"
const WHEN_NAMES := {"blood_moon": "血月", "eerie": "异化", "rough": "躁动", "calm": "平静"}
const WHEN_COLORS := {"blood_moon": Gothic.BLOOD, "eerie": Gothic.EERIE}

var is_open := false

var _entries: Array = []               ## 格子里的种类（FishData），从弱到强
var _selected := 0
var _hover := -1                       ## 鼠标下面的格子
var _hover_hit := {}                   ## 鼠标下面的别的东西（页签、时期）
var _scroll := 0                       ## 第一行显示的是第几行
var _mode := "species"                 ## species 一种生物；layers 各层水域
var _stage := 2                        ## 立绘是哪个时期
var _page := 0                         ## 下面三页里的第几页
var _layer := 0                        ## 各层水域：看的是哪层水
var _hits: Array[Dictionary] = []      ## 这一帧画出来能点的东西：{rect, kind, value}
var _black: ColorRect
var _veil: ColorRect
var _veil_mat: ShaderMaterial
var _back: Control                     ## 格子的底、立绘后面的光（画在剪影下面）
var _shadow: Control                   ## 挂着剪影着色器，只画没收录的
var _content: Control
var _portrait: MeshInstance2D
var _portrait_mat: ShaderMaterial
var _portrait_size := Vector2.ZERO
var _prompts_species: HBoxContainer
var _prompts_layers: HBoxContainer
var _time := 0.0
var _opened_at := 0.0
var _page_at := 0.0                    ## 换了种类、时期、页、水层的那一刻（下面的字重新浮出来）
var _swap_at := 0.0                    ## 立绘换了的那一刻
var _fade := 1.0
var _tween: Tween
var _pages := {}                       ## 算好的一页（种类 id 或 "" → 字典），开着的时候数不会变
var _thumbs := {}                      ## 种类 id → 小图
var _art := {}                         ## 画好的框、底（路径 → 贴图或 null）


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	visible = false
	_black = ColorRect.new()
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.color = Color(0.008, 0.012, 0.016, 0.93)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_veil = ColorRect.new()
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil_mat = ShaderMaterial.new()
	_veil_mat.shader = VEIL
	_veil.material = _veil_mat
	add_child(_veil)
	_back = _layer_control()
	_back.draw.connect(_draw_back)
	_shadow = _layer_control()
	var mat := ShaderMaterial.new()
	mat.shader = SILHOUETTE
	_shadow.material = mat
	_shadow.draw.connect(_draw_shadow)
	_content = _layer_control()
	_content.draw.connect(_draw_content)
	_portrait = MeshInstance2D.new()
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_portrait_mat = CreatureArt.make_material()
	_portrait.material = _portrait_mat
	_portrait.position = PORTRAIT_C
	add_child(_portrait)
	_prompts_species = _prompt_row([["↑↓←→", "选择", false], ["1 2 3", "时期", false], ["Q E", "翻页", false],
		["Tab", "各层水域", true], ["C", "合上图鉴", true]])
	_prompts_layers = _prompt_row([["↑↓←→", "选择", false], ["1 2 3", "水层", false], ["Tab", "生物", true], ["C", "合上图鉴", true]])


func _layer_control() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(c)
	return c


## 底下一行按键提示：[键, 字, 能不能点]；能点的 Tab 切换、C 合上
func _prompt_row(items: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.position = Vector2(0, PROMPTS_Y)
	row.size = Vector2(1280, 34)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	add_child(row)
	for it in items:
		var p := KeyPrompt.make(it[0], it[1], 18 if it[0] == "C" else 16, it[2])
		if it[0] == "C":
			p.pressed.connect(close)
		elif it[0] == "Tab":
			p.pressed.connect(toggle_mode)
		row.add_child(p)
	return row


## 打开；focus 是要翻到的那种生物（选去处的时候打开，就翻到刚钓上来的那种，看它那个时期），不给就停在上次看的那里。
## opaque：后面全压黑（签约时打开，盖住契约语）；钓鱼时打开还透一点海的影子
func open(focus: FishData = null, opaque := false, focus_stage := -1) -> void:
	_black.color.a = 1.0 if opaque else 0.93
	_entries = Codex.species_order()
	_pages.clear()
	if focus:
		_selected = maxi(0, _entries.find(focus))
		_mode = "species"
		if focus_stage >= 0:
			_stage = clampi(focus_stage, 0, 2)
	_selected = clampi(_selected, 0, maxi(0, _entries.size() - 1))
	_ensure_visible()
	is_open = true
	visible = true
	_fade = 1.0
	_opened_at = _time
	_page_at = _time
	_swap_at = _time
	_refresh_portrait()
	_refresh_prompts()
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_veil, 0.0, 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not is_open:
		return
	is_open = false
	_hover = -1
	_hover_hit = {}
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_fade", 0.0, 0.2)
	_tween.parallel().tween_method(_set_veil, 1.0, 0.0, 0.35)
	_tween.tween_callback(func() -> void: visible = false)
	closed.emit()


## 选第 index 种（格子里的顺序）
func select(index: int) -> void:
	index = clampi(index, 0, maxi(0, _entries.size() - 1))
	if index != _selected:
		_selected = index
		_page_at = _time
		_swap_at = _time
		_ensure_visible()
		_refresh_portrait()


func move_selection(step: int) -> void:
	if _entries.is_empty():
		return
	if absi(step) == 1:
		select(posmod(_selected + step, _entries.size()))
	else:
		select(clampi(_selected + step, 0, _entries.size() - 1))


func set_stage(stage: int) -> void:
	stage = clampi(stage, 0, 2)
	if stage != _stage:
		_stage = stage
		_swap_at = _time
		_page_at = _time
		_refresh_portrait()


func set_page(page: int) -> void:
	page = posmod(page, PAGES.size())
	if page != _page:
		_page = page
		_page_at = _time


func set_layer(depth: int) -> void:
	depth = posmod(depth, GameDB.DEPTH_NAMES.size())
	if depth != _layer:
		_layer = depth
		_page_at = _time


## 生物 ↔ 各层水域
func set_mode(mode: String) -> void:
	if mode != _mode:
		_mode = mode
		_page_at = _time
		_swap_at = _time
		_refresh_portrait()
		_refresh_prompts()


func toggle_mode() -> void:
	set_mode("layers" if _mode == "species" else "species")


func _set_veil(v: float) -> void:
	_veil_mat.set_shader_parameter("amount", v)


func _refresh_prompts() -> void:
	_prompts_species.visible = _mode == "species"
	_prompts_layers.visible = _mode == "layers"


func _ensure_visible() -> void:
	var row := _selected / COLS
	if row < _scroll:
		_scroll = row
	elif row >= _scroll + ROWS_VISIBLE:
		_scroll = row - ROWS_VISIBLE + 1
	_scroll = clampi(_scroll, 0, maxi(0, _row_count() - ROWS_VISIBLE))


func _row_count() -> int:
	return ceili(_entries.size() / float(COLS))


## 开着的时候按键都归这里（签约时也不让名字那一栏收字）
func _input(event: InputEvent) -> void:
	if not is_open or not event is InputEventKey:
		return
	if event.pressed:
		match event.keycode:
			KEY_LEFT, KEY_A:
				move_selection(-1)
			KEY_RIGHT, KEY_D:
				move_selection(1)
			KEY_UP, KEY_W:
				move_selection(-COLS)
			KEY_DOWN, KEY_S:
				move_selection(COLS)
		if not event.echo:
			match event.keycode:
				KEY_1, KEY_KP_1, KEY_2, KEY_KP_2, KEY_3, KEY_KP_3:
					var n := 0 if event.keycode in [KEY_1, KEY_KP_1] else (1 if event.keycode in [KEY_2, KEY_KP_2] else 2)
					if _mode == "species":
						set_stage(n)
					else:
						set_layer(n)
				KEY_Q:
					if _mode == "species":
						set_page(_page - 1)
					else:
						set_layer(_layer - 1)
				KEY_E:
					if _mode == "species":
						set_page(_page + 1)
					else:
						set_layer(_layer + 1)
				KEY_TAB:
					toggle_mode()
				KEY_C, KEY_ESCAPE:
					close()
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseMotion:
		var tile := _tile_hit(event.position)
		var hit := _hit(event.position) if tile < 0 else {}
		if tile != _hover or hit != _hover_hit:
			_hover = tile
			_hover_hit = hit
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if tile >= 0 or not hit.is_empty() else Control.CURSOR_ARROW
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				var tile := _tile_hit(event.position)
				if tile >= 0:
					select(tile)
					set_mode("species")
				else:
					var hit := _hit(event.position)
					match hit.get("kind", ""):
						"stage":
							set_stage(hit.value)
						"page":
							set_page(hit.value)
						"layer":
							set_layer(hit.value)
						"mode":
							set_mode(hit.value)
			MOUSE_BUTTON_WHEEL_UP:
				move_selection(-COLS)
			MOUSE_BUTTON_WHEEL_DOWN:
				move_selection(COLS)
		accept_event()


func _tile_hit(pos: Vector2) -> int:
	for i in _entries.size():
		var r := _tile_rect(i)
		if r.size.x > 0.0 and r.has_point(pos):
			return i
	return -1


func _hit(pos: Vector2) -> Dictionary:
	for h in _hits:
		if h.rect.has_point(pos):
			return {"kind": h.kind, "value": h.value}
	return {}


## 第 i 格在屏幕上的位置；滚出去看不见的是空的
func _tile_rect(i: int) -> Rect2:
	var row := i / COLS - _scroll
	if row < 0 or row >= ROWS_VISIBLE:
		return Rect2()
	return Rect2(LEFT_X + (i % COLS) * (TILE + GAP), GRID_Y + row * (TILE + GAP), TILE, TILE)


func _process(delta: float) -> void:
	_time += delta
	if not visible:
		return
	_veil_mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	_prompts_species.modulate.a = _k(0.35)
	_prompts_layers.modulate.a = _k(0.35)
	var s := clampf((_time - _swap_at) / 0.32, 0.0, 1.0)
	s = s * s * (3.0 - 2.0 * s)
	_portrait.modulate = Color(1, 1, 1, s * _k(0.25))
	_portrait.position = PORTRAIT_C + Vector2(0, (1.0 - s) * 10.0)
	_back.queue_redraw()
	_shadow.queue_redraw()
	_content.queue_redraw()


## 打开后过了 start 秒、用 dur 秒浮出来；合上时跟着整体淡出
func _k(start: float, dur := 0.3) -> float:
	var x := clampf((_time - _opened_at - start) / dur, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x) * _fade


## 换了种类、页、水层以后浮出来（打开时跟着整页一起）
func _kp() -> float:
	var x := clampf((_time - _page_at) / 0.22, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x) * _k(0.2)


func _current() -> FishData:
	return _entries[_selected] if _selected < _entries.size() else null


## 立绘：选中的那种、那个时期的插图，按种类的动效动；没收录的不画（剪影画在 _shadow 上）
func _refresh_portrait() -> void:
	var fish := _current()
	var tex: Texture2D = fish.stage_icon(_stage) if fish else null
	if _mode != "species" or fish == null or tex == null or not Codex.known(fish):
		_portrait.visible = false
		return
	_portrait.visible = true
	_portrait_size = _fit(tex, PORTRAIT_BOX * PORTRAIT_SCALE[_stage])
	_portrait.mesh = CreatureArt.grid(_portrait_size)
	_portrait.texture = tex
	CreatureArt.apply(_portrait_mat, fish, tex, _portrait_size)
	_portrait_mat.set_shader_parameter("hue_shift", 0.0)
	_portrait_mat.set_shader_parameter("mutation", 0.0)
	_portrait_mat.set_shader_parameter("sheen", -1.0)
	_portrait_mat.set_shader_parameter("dissolve", 0.0)


## 小图：有专门画的（assets/creatures/icons/<id>.png）就用它，没有用成年那张插图
func _thumb(fish: FishData) -> Texture2D:
	if not _thumbs.has(fish.id):
		var path := "res://assets/creatures/icons/%s.png" % fish.id
		_thumbs[fish.id] = load(path) if ResourceLoader.exists(path) else (fish.stage_icon(2) if fish.stage_icon(2) else fish.icon)
	return _thumbs[fish.id]


## 画好的素材（TILE_FRAME 这几样）；没有返回 null
func _ui_art(path: String) -> Texture2D:
	if not _art.has(path):
		_art[path] = load(path) if ResourceLoader.exists(path) else null
	return _art[path]


## 只在某些夜里出的，按那种夜的数值表算出没（总表里它不出）
static func _config_for(fish: FishData) -> BalanceConfig:
	if fish.appears_when.is_empty():
		return GameDB.balance
	var sea := ""
	var moon := false
	for w in fish.appears_when:
		if w == "blood_moon":
			moon = true
		elif sea == "":
			sea = w
	return GameDB.balance.for_night(1, sea, moon)


static func _when_text(fish: FishData) -> String:
	var parts: PackedStringArray = []
	for w in fish.appears_when:
		parts.append(WHEN_NAMES.get(w, w))
	return "、".join(parts)


# ---------- 算好一页 ----------

## 一种生物那一页要的数：出没的每层水；每个时期、每一级一行的表
func _species_page(fish: FishData) -> Dictionary:
	if _pages.has(fish.id):
		return _pages[fish.id]
	var config := _config_for(fish)
	var universal := BaitCrafter.make_universal(1)
	var layers := []
	for d in Codex.depths(fish, config):
		layers.append({"depth": d, "share": Codex.bite_share(fish, universal, d, config),
			"entries": Codex.stage_entries(fish, d, config), "tribute": Codex.mean_tribute(fish, d, config),
			"best": Codex.best_bait(fish, d, config)})
	var rows := []
	var line := Codex.growth_line(fish, config)
	for s in 3:
		var levels := fish.stage_levels(s)
		for level in range(levels.x, levels.y + 1):
			var soul := "约 %d" % roundi(Codex.mean_soul(fish, level, s, config))
			if levels.x != levels.y:
				soul += "（%s %d）" % ["≥" if level > levels.x else "<", roundi(line)]
			rows.append({"stage": s, "level": level, "catch": Codex.typical(fish, level, s, config),
				"materials": Codex.materials_range(fish, level, s, config), "soul": soul})
	var page := {"layers": layers, "rows": rows}
	_pages[fish.id] = page
	return page


func _overview_page() -> Dictionary:
	if _pages.has(""):
		return _pages[""]
	var layers := []
	for d in GameDB.DEPTH_NAMES.size():
		var info := Codex.layer(d, GameDB.balance)
		var by_id := {}
		for row in info.species:
			by_id[row.fish.id] = row
		info["by_id"] = by_id
		layers.append(info)
	var page := {"layers": layers}
	_pages[""] = page
	return page


# ---------- 画 ----------

func _text(pos: Vector2, s: String, size_t: int, color: Color, a: float, outline := 4) -> void:
	if a > 0.0 and s != "":
		Gothic.text(_content, pos, s, size_t, Color(color, color.a * a), HORIZONTAL_ALIGNMENT_LEFT, -1, outline)


## 写一段，返回写完以后的 x
func _run(x: float, y: float, s: String, size_t: int, color: Color, a: float, outline := 4) -> float:
	_text(Vector2(x, y), s, size_t, color, a, outline)
	return x + Gothic.text_width(s, size_t)


func _centered(cx: float, y: float, s: String, size_t: int, color: Color, a: float, outline := 4) -> void:
	_text(Vector2(cx - Gothic.text_width(s, size_t) * 0.5, y), s, size_t, color, a, outline)


static func _pct(x: float) -> String:
	return "%d%%" % roundi(x * 100.0)


## 一张插图按比例塞进 box
static func _fit(tex: Texture2D, box: Vector2) -> Vector2:
	var aspect := tex.get_size().x / maxf(tex.get_size().y, 1.0)
	var art := Vector2(box.y * aspect, box.y)
	if art.x > box.x:
		art = Vector2(box.x, box.x / aspect)
	return art


## 一道两头淡出去的细线
func _rule(ci: CanvasItem, x0: float, x1: float, y: float, color: Color, a: float, width := 1.2) -> void:
	for s in 20:
		var t0 := s / 20.0
		var t1 := (s + 1) / 20.0
		ci.draw_line(Vector2(lerpf(x0, x1, t0), y), Vector2(lerpf(x0, x1, t1), y), Color(color, color.a * sin((t0 + t1) * 0.5 * PI) * a), width)


## 一个能点的页签（时期、页、水层、模式）：选中的骨白、下面一道铜线；记下能点的地方
func _tab(cx: float, y: float, label: String, key: String, lit: bool, kind: String, value: Variant, a: float, size_t := 15) -> void:
	var hover: bool = _hover_hit.get("kind", "") == kind and _hover_hit.get("value") == value
	var kw := Gothic.text_width(key, 12) + 5.0 if key != "" else 0.0
	var w := kw + Gothic.text_width(label, size_t)
	var x := cx - w * 0.5
	if key != "":
		_text(Vector2(x, y), key, 12, Gothic.BRONZE_LIGHT, a * (1.0 if lit else 0.7), 3)
	var color := Gothic.BONE if lit else (Gothic.BONE.darkened(0.1) if hover else Gothic.BONE_DARK)
	_text(Vector2(x + kw, y), label, size_t, color, a)
	if lit:
		_rule(_content, x - 6.0, x + w + 6.0, y + 7.0, Gothic.BRONZE_LIGHT, a, 1.6)
	_hits.append({"rect": Rect2(x - 8.0, y - size_t - 4.0, w + 16.0, size_t + 14.0), "kind": kind, "value": value})


func _draw_back() -> void:
	if _entries.is_empty():
		return
	var a := _k(0.12)
	var aura := Gothic.aura_texture()
	for i in _entries.size():
		var r := _tile_rect(i)
		if r.size.x <= 0.0:
			continue
		var lit := i == _selected
		if lit:
			var pulse := 0.85 + 0.15 * sin(_time * 2.2)
			_back.draw_texture_rect(aura, r.grow(26.0), false, Color(0.55, 0.68, 0.72, 0.16 * a * pulse))
		_back.draw_rect(r, Color(0.03, 0.045, 0.055, (0.9 if lit else 0.78) * a))
		# 格子里自下而上淡淡的一层青（像水里透上来的光）
		_back.draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.55), Vector2(r.size.x, r.size.y * 0.45)), Color(0.12, 0.2, 0.22, 0.12 * a))
	if _mode == "species" and _current():
		var plate := _ui_art(PORTRAIT_PLATE)
		if plate:
			var pbox := _fit(plate, PORTRAIT_BOX * Vector2(1.15, 1.35))
			_back.draw_texture_rect(plate, Rect2(PORTRAIT_C - pbox * 0.5, pbox), false, Color(1, 1, 1, _k(0.2)))
		var glow := Gothic.glow_texture()
		var box := PORTRAIT_BOX * Vector2(1.25, 1.6)
		_back.draw_texture_rect(glow, Rect2(PORTRAIT_C - box * 0.5, box), false, Color(0.5, 0.64, 0.68, 0.11 * _k(0.2)))


## 没收录的：格子里的小图、右边的立绘都只剩剪影（这个控件挂着剪影着色器）
func _draw_shadow() -> void:
	if _entries.is_empty():
		return
	var a := _k(0.15)
	for i in _entries.size():
		var fish: FishData = _entries[i]
		var r := _tile_rect(i)
		if r.size.x <= 0.0 or Codex.known(fish):
			continue
		var tex := _thumb(fish)
		if tex:
			var art := _fit(tex, Vector2(TILE - 16.0, TILE - NAME_BAND - 14.0))
			var c := r.position + Vector2(TILE * 0.5, (TILE - NAME_BAND) * 0.5 + 3.0)
			_shadow.draw_texture_rect(tex, Rect2(c - art * 0.5, art), false, Color(SHADOW, 0.9 * a))
	var fish := _current()
	if _mode != "species" or fish == null or Codex.known(fish):
		return
	var tex: Texture2D = fish.stage_icon(_stage)
	if tex:
		var art := _fit(tex, PORTRAIT_BOX * PORTRAIT_SCALE[_stage])
		_shadow.draw_texture_rect(tex, Rect2(PORTRAIT_C - art * 0.5, art), false, Color(SHADOW, 0.9 * _kp()))


func _draw_content() -> void:
	_hits.clear()
	if _entries.is_empty():
		return
	_draw_left()
	var a := _kp()
	if a <= 0.0:
		return
	if _mode == "layers":
		_draw_layer_panel(a)
	else:
		_draw_species(_current(), a)


# ---------- 左边：格子 ----------

func _draw_left() -> void:
	var a := _k(0.15)
	var x := _run(LEFT_X, TITLE_Y, "冥海图鉴", 28, Gothic.BONE, a, 6) + 16.0
	_text(Vector2(x, TITLE_Y - 2.0), "已收录 %d / %d" % [Codex.known_count(), _entries.size()], 13, ContractScreen.NOTE, a, 3)
	if Codex.reveal_all:
		_text(Vector2(LEFT_X, TITLE_Y + 24.0), "（测试期间全开）", 12, Gothic.BRONZE_LIGHT, a, 3)
	var grid_r := LEFT_X + COLS * (TILE + GAP) - GAP
	_tab(grid_r - 150.0, TITLE_Y, "生物", "", _mode == "species", "mode", "species", a, 16)
	_tab(grid_r - 58.0, TITLE_Y, "各层水域", "", _mode == "layers", "mode", "layers", a, 16)
	_text(Vector2(grid_r - 130.0 - Gothic.text_width("Tab", 12) * 0.5, TITLE_Y + 22.0), "Tab", 12, Gothic.BRONZE_LIGHT, a * 0.8, 3)
	var overview := _overview_page() if _mode == "layers" else {}
	var layer: Dictionary = overview.layers[_layer] if not overview.is_empty() else {}
	var top_share := 0.0
	if not layer.is_empty():
		for row in layer.species:
			top_share = maxf(top_share, row.share)
	for i in _entries.size():
		var r := _tile_rect(i)
		if r.size.x > 0.0:
			_draw_tile(i, r, a, layer, top_share)
	# 滚动：上下还有的话，格子上下各一道淡淡的箭头
	var rows := _row_count()
	if rows > ROWS_VISIBLE:
		var cx := LEFT_X + (COLS * (TILE + GAP) - GAP) * 0.5
		if _scroll > 0:
			_centered(cx, GRID_Y - 6.0, "︿", 16, Gothic.BONE_DARK, a)
		if _scroll + ROWS_VISIBLE < rows:
			_centered(cx, GRID_Y + ROWS_VISIBLE * (TILE + GAP) + 6.0, "﹀", 16, Gothic.BONE_DARK, a)


func _draw_tile(i: int, r: Rect2, a: float, layer: Dictionary, top_share: float) -> void:
	var fish: FishData = _entries[i]
	var known := Codex.known(fish)
	var lit := i == _selected
	var hover := i == _hover and not lit
	var row: Dictionary = layer.get("by_id", {}).get(fish.id, {}) if not layer.is_empty() else {}
	var absent := not layer.is_empty() and row.is_empty()
	var dim := 0.35 if absent else 1.0
	# 小图（没收录的剪影画在 _shadow 上）
	if known:
		var tex := _thumb(fish)
		if tex:
			var art := _fit(tex, Vector2(TILE - 16.0, TILE - NAME_BAND - 14.0))
			if lit:
				art *= 1.0 + 0.03 * sin(_time * 1.6)
			var c := r.position + Vector2(TILE * 0.5, (TILE - NAME_BAND) * 0.5 + 3.0)
			var tint := Color(1, 1, 1, a * dim) if lit else Color(0.74, 0.77, 0.79, (0.88 if hover else 0.72) * a * dim)
			_content.draw_texture_rect(tex, Rect2(c - art * 0.5, art), false, tint)
	else:
		_centered(r.get_center().x, r.position.y + (TILE - NAME_BAND) * 0.5 + 10.0, "？", 22, Gothic.BONE_DARK, a * dim)
	# 框：有画好的框就用它；没有就画细的骨色边，四角一小段铜色，选中的整圈铜色、粗一点
	var frame := _ui_art(TILE_FRAME_LIT if lit else TILE_FRAME)
	if frame:
		_content.draw_texture_rect(frame, r.grow(6.0), false, Color(1, 1, 1, a * (1.0 if lit or hover else 0.8) * dim))
	else:
		var edge := Color(Gothic.BRONZE_LIGHT, 0.95 * a) if lit else Color(Gothic.BONE if hover else Gothic.BONE_DARK, (0.6 if hover else 0.38) * a * dim)
		_content.draw_rect(r, edge, false, 2.0 if lit else 1.0)
		var corner := Color(Gothic.BRONZE_LIGHT, (1.0 if lit else 0.55) * a * dim)
		for cx in [0.0, 1.0]:
			for cy in [0.0, 1.0]:
				var p := r.position + r.size * Vector2(cx, cy)
				var sx := 1.0 if cx == 0.0 else -1.0
				var sy := 1.0 if cy == 0.0 else -1.0
				_content.draw_line(p, p + Vector2(9.0 * sx, 0), corner, 2.0)
				_content.draw_line(p, p + Vector2(0, 9.0 * sy), corner, 2.0)
	# 名字
	var name := fish.display_name if known else "？？？"
	var size_t := 12 if Gothic.text_width(name, 13) > TILE - 8.0 else 13
	_centered(r.get_center().x, r.end.y - 8.0, name, size_t, Gothic.BONE if lit else Gothic.BONE_DARK, a * dim, 3)
	# 只在某些夜里出的：左上角标一下
	if known and not fish.appears_when.is_empty():
		var w: String = fish.appears_when[0]
		_text(r.position + Vector2(6.0, 15.0), WHEN_NAMES.get(w, w), 11, WHEN_COLORS.get(w, Gothic.WARN), a * dim, 3)
	# 各层水域：右下写它在这层占几成，底下一道条（颜色是它身上最多的那种材料）
	if not layer.is_empty():
		if absent:
			_text(Vector2(r.end.x - 16.0, r.position.y + 16.0), "—", 13, Gothic.BONE_DARK, a, 3)
		elif known:
			var share: float = row.share
			var label := _pct(share)
			_text(Vector2(r.end.x - Gothic.text_width(label, 13) - 6.0, r.position.y + 16.0), label, 13, Gothic.BONE, a, 3)
			var main := _main_material(fish)
			var bar_w := (TILE - 8.0) * share / maxf(top_share, 0.001)
			_content.draw_line(Vector2(r.position.x + 4.0, r.end.y - 3.0), Vector2(r.position.x + 4.0 + bar_w, r.end.y - 3.0),
				Color(Materials.COLORS[main], 0.85 * a), 3.0)


# ---------- 右边：一种生物 ----------

func _draw_species(fish: FishData, a: float) -> void:
	if fish == null:
		return
	var known := Codex.known(fish)
	var x := _run(PANEL_X, NAME_Y, fish.display_name if known else "？？？", 32, Gothic.BONE, a, 6) + 16.0
	if not known:
		_text(Vector2(PANEL_X, SUB_Y), "还没有钓上来过。", 15, ContractScreen.NOTE, a, 3)
		_draw_stage_tabs(fish, a, false)
		return
	var page := _species_page(fish)
	var flame := Gothic.tex("icon_soul")
	_content.draw_texture_rect(flame, Rect2(Vector2(x, NAME_Y - 22.0), Vector2(19, 22)), false, Color(1, 1, 1, a))
	_run(x + 24.0, NAME_Y - 3.0, "灵魂 " + Codex.level_text(fish), 17, Gothic.BONE, a)
	var depths: PackedStringArray = []
	for l in page.layers:
		depths.append(GameDB.DEPTH_NAMES[l.depth])
	x = _run(PANEL_X, SUB_Y, "出没　", 14, Gothic.BRONZE_LIGHT, a, 3)
	x = _run(x, SUB_Y, " · ".join(depths) if not depths.is_empty() else "—", 14, Gothic.BONE, a, 3)
	if not fish.appears_when.is_empty():
		_run(x + 12.0, SUB_Y, "只在%s的夜里" % _when_text(fish), 14, WHEN_COLORS.get(fish.appears_when[0], Gothic.WARN), a, 3)
	_draw_stage_tabs(fish, a, true)
	_rule(_content, PANEL_X, PANEL_R, RULE_Y, Gothic.BONE_DARK, a * 0.5)
	for p in PAGES.size():
		var cx := PANEL_X + 70.0 + p * 150.0
		_tab(cx, INFO_TABS_Y, PAGES[p], "", p == _page, "page", p, a, 16)
	_text(Vector2(PANEL_R - 66.0, INFO_TABS_Y), "Q", 12, Gothic.BRONZE_LIGHT, a * 0.8, 3)
	_text(Vector2(PANEL_R - 52.0, INFO_TABS_Y), "‹ ›", 13, Gothic.BONE_DARK, a, 3)
	_text(Vector2(PANEL_R - 26.0, INFO_TABS_Y), "E", 12, Gothic.BRONZE_LIGHT, a * 0.8, 3)
	match _page:
		0:
			_draw_ecology(fish, a)
		1:
			_draw_table(page.rows, a)
		2:
			_draw_layers(fish, page.layers, a)


## 立绘下面：三个时期的页签，选中的那个写几级、躯体规模、载荷
func _draw_stage_tabs(fish: FishData, a: float, known: bool) -> void:
	for s in 3:
		var cx := PANEL_CX + (s - 1) * 120.0
		_tab(cx, STAGE_TABS_Y, CatchData.STAGE_NAMES[s], str(s + 1), s == _stage, "stage", s, a)
	if not known:
		return
	var config := GameDB.balance
	var stage := "%s · %s" % [CatchData.STAGE_NAMES[_stage], Codex.stage_level_text(fish, _stage)]
	var rest := "　%s　载荷 %d" % [CatchData.BODY_NAMES[fish.stage_body(_stage)], config.load_for_stage(_stage)]
	var x0 := PANEL_CX - (Gothic.text_width(stage, 15) + Gothic.text_width(rest, 13)) * 0.5
	var x1 := _run(x0, CAPTION_Y, stage, 15, Gothic.BONE, a)
	_run(x1, CAPTION_Y, rest, 13, Gothic.BONE_DARK, a, 3)


## 生态：介绍、身上的材料、气味（哪种附加物带着）、三个时期的躯体规模
func _draw_ecology(fish: FishData, a: float) -> void:
	var y := INFO_Y
	_text(Vector2(PANEL_X, y), fish.description, 14, Gothic.BONE_DARK, a, 3)
	y += INFO_STEP + 6.0
	var x := _run(PANEL_X, y, "身上的材料　", 14, Gothic.BRONZE_LIGHT, a)
	var ratio := Materials.normalized(fish.material_ratio)
	for m in Materials.ALL:
		_content.draw_texture_rect(Gothic.tex("mat_" + m), Rect2(Vector2(x, y - 15.0), Vector2(18, 18)), false, Color(1, 1, 1, a))
		x = _run(x + 21.0, y, "%s %s" % [Materials.SHORT[m], _pct(ratio[m])], 14, Gothic.BONE, a) + 16.0
	_run(x + 2.0, y, "（拆出来按这个比例分）", 12, ContractScreen.NOTE, a, 3)
	y += INFO_STEP
	y = _draw_scents(fish, y, a) + INFO_STEP
	x = _run(PANEL_X, y, "躯体规模　", 14, Gothic.BRONZE_LIGHT, a)
	var parts: PackedStringArray = []
	for s in 3:
		parts.append("%s %s" % [STAGE_SHORT[s], CatchData.BODY_NAMES[fish.stage_body(s)]])
	x = _run(x, y, " · ".join(parts), 14, Gothic.BONE, a)
	_run(x + 10.0, y, "（带「变异」的再大一档）", 12, ContractScreen.NOTE, a, 3)


## 喜欢、讨厌的气味（哪种附加物带着这种气味）；一行写不下换行。返回最后一行的基线
func _draw_scents(fish: FishData, y: float, a: float) -> float:
	var x0 := _run(PANEL_X, y, "气味　", 14, Gothic.BRONZE_LIGHT, a)
	var x := x0
	var prefs := Codex.preferences(fish)
	if prefs.is_empty():
		_run(x, y, "什么都不特别喜欢", 14, Gothic.BONE_DARK, a)
		return y
	var liked := false
	var disliked := false
	for p in prefs:
		var aspect: String = p[0]
		var v: float = p[1]
		var head := ""
		if v > 0.0 and not liked:
			liked = true
			head = "喜欢"
		elif v < 0.0 and not disliked:
			disliked = true
			head = "讨厌"
		var additive := Codex.additive_for(aspect)
		var source := "（%s）" % additive.display_name if additive else "（还没有这种附加物）"
		var w := Gothic.text_width(head, 13) + 8.0 + Gothic.text_width(Aspect.display_name(aspect), 15) \
			+ Gothic.text_width("%+.1f" % v, 13) + Gothic.text_width(source, 12) + 20.0
		if x + w > PANEL_R and x > x0:
			y += INFO_STEP - 4.0
			x = x0
		if head != "":
			x = _run(x + (8.0 if head == "讨厌" and liked else 0.0), y, head, 13, Gothic.WARN if head == "讨厌" else Gothic.BONE_DARK, a, 3) + 6.0
		var col: Color = Aspect.COLORS.get(aspect, Gothic.BONE)
		x = _run(x, y, Aspect.display_name(aspect), 15, col.lightened(0.15), a)
		x = _run(x + 3.0, y, "%+.1f" % v, 13, Gothic.BONE, a, 3)
		x = _run(x + 2.0, y, source, 12, Gothic.BONE_DARK if additive else ContractScreen.NOTE, a, 3) + 10.0
	return y


## 祭值与用途：每个时期、每一级一行，常见的那一条（躯体规模在那一档中间、平均灵魂强度、没有词条）；立绘的那个时期垫一道光
func _draw_table(rows: Array, a: float) -> void:
	_text(Vector2(PANEL_X, INFO_Y), "躯体规模在那一档中间、平均灵魂强度和能量、没有词条的一条；分解按最小到最大写几份", 12, ContractScreen.NOTE, a, 3)
	var cols := [PANEL_X, PANEL_X + 116.0, PANEL_X + 236.0, PANEL_X + 336.0, PANEL_X + 422.0, PANEL_X + 500.0]
	var heads := ["时期", "祭值", "分解", "饱腹", "能量", "灵魂强度"]
	var head_y := INFO_Y + 24.0
	for i in heads.size():
		_text(Vector2(cols[i], head_y), heads[i], 13, Gothic.BONE_DARK, a, 3)
	var step := 24.0 if rows.size() <= 5 else 20.0
	for r in rows.size():
		var row: Dictionary = rows[r]
		var c: CatchData = row.catch
		var y := head_y + 24.0 + r * step
		if row.stage == _stage:
			_content.draw_rect(Rect2(PANEL_X - 8.0, y - 17.0, PANEL_R - PANEL_X + 8.0, step - 2.0), Color(0.55, 0.68, 0.72, 0.08 * a))
		var xs := _run(cols[0], y, CatchData.STAGE_NAMES[row.stage], 15, Gothic.BONE, a)
		_run(xs + 6.0, y, "%d 级" % row.level, 15, Gothic.BONE, a)
		_text(Vector2(cols[1], y), Gothic.grouped(c.tribute), 17, CatchReveal.TRIBUTE_COLOR, a)
		var m: Vector2i = row.materials
		_text(Vector2(cols[2], y), ("%d 份" % m.x) if m.x == m.y else ("%d–%d 份" % [m.x, m.y]), 14, Gothic.BONE, a)
		_text(Vector2(cols[3], y), "+%d" % c.food, 14, Gothic.BONE, a)
		_text(Vector2(cols[4], y), str(c.energy), 14, Gothic.BONE, a)
		_text(Vector2(cols[5], y), row.soul, 14, Gothic.BONE, a)


## 出没：它出没的每层水两行——占几成、平均祭值、最招它的饵；钓上来是哪个时期几级
func _draw_layers(fish: FishData, layers: Array, a: float) -> void:
	if layers.is_empty():
		_text(Vector2(PANEL_X, INFO_Y), "平常的夜里它不出来。" if not fish.appears_when.is_empty() else "哪层水里都没有它。", 14, ContractScreen.NOTE, a, 3)
		return
	if not fish.appears_when.is_empty():
		_text(Vector2(PANEL_X, INFO_Y), "按%s的夜算（平常的夜里它不出来）" % _when_text(fish), 12, ContractScreen.NOTE, a, 3)
	for r in layers.size():
		var row: Dictionary = layers[r]
		var y := INFO_Y + (18.0 if not fish.appears_when.is_empty() else 0.0) + r * 50.0
		var x := _run(PANEL_X, y, GameDB.DEPTH_NAMES[row.depth], 16, Gothic.BONE, a) + 14.0
		x = _run(x, y, "万能饵下占 ", 13, Gothic.BONE_DARK, a, 3)
		x = _run(x, y, _pct(row.share), 15, Gothic.BONE, a) + 16.0
		x = _run(x, y, "平均祭值 ", 13, Gothic.BONE_DARK, a, 3)
		x = _run(x, y, Gothic.grouped(roundi(row.tribute)), 15, CatchReveal.TRIBUTE_COLOR, a) + 16.0
		var best: Dictionary = row.best
		x = _run(x, y, "最招它 ", 13, Gothic.BONE_DARK, a, 3)
		x = _run(x, y, "%s %s" % [best.bait.display_name, _pct(best.share)], 14, Gothic.BONE, a)
		_run(x + 6.0, y, "空竿 %s" % _pct(best.nothing), 12, Gothic.BONE_DARK, a, 3)
		var parts: PackedStringArray = []
		for e in row.entries:
			parts.append("%s %d 级 %s" % [STAGE_SHORT[e.stage], e.level, _pct(e.share)])
		_text(Vector2(PANEL_X + 46.0, y + 21.0), "钓上来是：" + " · ".join(parts), 12, Gothic.BONE_DARK, a, 3)


# ---------- 右边：各层水域 ----------

func _draw_layer_panel(a: float) -> void:
	_run(PANEL_X, NAME_Y, "各层水域", 32, Gothic.BONE, a, 6)
	_text(Vector2(PANEL_X, SUB_Y), "挂万能饵时这层水里有什么。左边每格右上写它在这层占几成，底下的条是它身上最多的那种材料。", 13, ContractScreen.NOTE, a, 3)
	var page := _overview_page()
	var layers: Array = page.layers
	for d in layers.size():
		_tab(PANEL_X + 70.0 + d * 140.0, 138.0, GameDB.DEPTH_NAMES[d], str(d + 1), d == _layer, "layer", d, a, 17)
	var info: Dictionary = layers[_layer]
	var y := 178.0
	var levels: PackedStringArray = []
	var shares: Array = info.levels
	for i in shares.size():
		if shares[i] > 0.0:
			levels.append("%d 级 %s" % [i + 1, _pct(shares[i])])
	var x := _run(PANEL_X, y, "出几级的生物　", 14, Gothic.BRONZE_LIGHT, a)
	_run(x, y, " · ".join(levels), 14, Gothic.BONE, a)
	y += INFO_STEP
	var st: Array = info.stages
	x = _run(PANEL_X, y, "三个时期　", 14, Gothic.BRONZE_LIGHT, a)
	_run(x, y, "幼年 %s · 成长 %s · 成年 %s" % [_pct(st[0]), _pct(st[1]), _pct(st[2])], 14, Gothic.BONE, a)
	y += INFO_STEP
	x = _run(PANEL_X, y, "每咬一口　", 14, Gothic.BRONZE_LIGHT, a)
	x = _run(x, y, "平均祭值 ", 13, Gothic.BONE_DARK, a, 3)
	x = _run(x, y, Gothic.grouped(roundi(info.tribute)), 16, CatchReveal.TRIBUTE_COLOR, a) + 16.0
	x = _run(x, y, "处理出 ", 13, Gothic.BONE_DARK, a, 3)
	for m in Materials.ALL:
		_content.draw_texture_rect(Gothic.tex("mat_" + m), Rect2(Vector2(x, y - 14.0), Vector2(17, 17)), false, Color(1, 1, 1, a))
		x = _run(x + 20.0, y, "%.2f" % info.materials[m], 13, Gothic.BONE, a, 3) + 8.0
	y += INFO_STEP
	x = _run(PANEL_X, y, "空竿 · 捞到东西　", 14, Gothic.BRONZE_LIGHT, a)
	_run(x, y, "%s · %s" % [_pct(info.nothing), _pct(info.salvage)], 14, Gothic.BONE, a)
	y += 20.0
	_rule(_content, PANEL_X, PANEL_R, y, Gothic.BONE_DARK, a * 0.5)
	y += 26.0
	_text(Vector2(PANEL_X, y), "这层水里有什么（挂万能饵时占几成）", 14, Gothic.BRONZE_LIGHT, a)
	var rows: Array = info.species.duplicate()
	rows.sort_custom(func(p, q) -> bool: return p.share > q.share)
	var top := 0.0
	for row in rows:
		top = maxf(top, row.share)
	var step := 24.0
	var room := int((PROMPTS_Y - 20.0 - (y + 26.0)) / step) + 1
	var shown := mini(rows.size(), room if rows.size() <= room else room - 1)
	for i in shown:
		var row: Dictionary = rows[i]
		var fish: FishData = row.fish
		var ry := y + 26.0 + i * step
		var known := Codex.known(fish)
		var lit := fish == _current()
		if lit:
			_content.draw_rect(Rect2(PANEL_X - 8.0, ry - 17.0, PANEL_R - PANEL_X + 8.0, step - 2.0), Color(0.55, 0.68, 0.72, 0.1 * a))
		_text(Vector2(PANEL_X, ry), fish.display_name if known else "？？？", 14, Gothic.BONE if lit else Gothic.BONE.darkened(0.08), a)
		var bx := PANEL_X + 120.0
		var bw: float = 200.0 * row.share / maxf(top, 0.001)
		var main := _main_material(fish)
		_content.draw_rect(Rect2(bx, ry - 11.0, bw, 9.0), Color(Materials.COLORS[main], (0.55 if known else 0.2) * a))
		_text(Vector2(bx + 208.0, ry), _pct(row.share), 14, Gothic.BONE, a)
		if known:
			_text(Vector2(bx + 254.0, ry), _stages_text(row.entries), 12, Gothic.BONE_DARK, a, 3)
	if shown < rows.size():
		_text(Vector2(PANEL_X, y + 26.0 + shown * step), "……还有 %d 种" % (rows.size() - shown), 12, ContractScreen.NOTE, a, 3)


## "幼年 1 级 · 成长 1–2 级 · 成年 2 级"：这层水里钓得上它的哪几个时期、各是几级
static func _stages_text(entries: Array) -> String:
	var parts: PackedStringArray = []
	for s in 3:
		var low := 99
		var high := 0
		for e in entries:
			if e.stage == s:
				low = mini(low, e.level)
				high = maxi(high, e.level)
		if high > 0:
			parts.append("%s %s 级" % [STAGE_SHORT[s], str(low) if low == high else "%d–%d" % [low, high]])
	return " · ".join(parts)


## 它身上最多的那种材料（各层水域里条的颜色）
static func _main_material(fish: FishData) -> String:
	var best := Materials.ALL[0]
	for m in Materials.ALL:
		if fish.material_ratio.get(m, 0.0) > fish.material_ratio.get(best, 0.0):
			best = m
	return best
