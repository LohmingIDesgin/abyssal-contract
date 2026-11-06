class_name CatchReveal
extends Control
## 钓上来的那一刻：身后的画面压暗褪色（FishingView 的 _dim，shaders/catch_dim.gdshader），
## 渔获从下面被提出水、甩着水花升到正中，放大展示、慢慢摆动，信息一行行浮现，底下是三个去向（放生 2026-11-04 删了）。
## 选好以后按去向退场：留下 → 缩小飞进左上的船舱格子；生吞 → 往前一扑、幽蓝一闪；处理 → 从噪声里一块块烧掉。
## 插图画在一张细分网格上，由 shaders/creature_display.gdshader 让它摆动、呼吸、鳍边颤；
## 每种生物摆得多大、多快在 FishData 的"展示"一组里。插图按时期换（幼年期、成长期、成年期各一张），
## 显示得也一个比一个大（STAGE_SCALE）；带「变色」「变异」的插图跟着变。
## 信息：名字、时期、灵魂等级、词条；祭值（加中文批注）；躯体规模、灵魂强度、能量、载荷、饱腹、分解材料（2026-11-04 的顺序；
## 原来的重量改成躯体规模，食后成长改成能量）。饱腹按契约者现在的饱腹算，装不下的写"吃撑了"。
## 视差：鱼、浮尘、文字跟着鼠标各偏一点，远近不同。
## 快捷键由 FishingView 处理：1 留下、2 生吞、3 处理。
## 捞上来的东西（道具、附加物，show_item）也这样亮相：同样从水里提上来、浮在正中，只是信息少得多——名字、是道具还是附加物
## （附加物写它带什么气味）、一句说明，下面只有 [空格] 收下（[1] 也行）；收下以后往上一浮、淡出。

signal decided(action: String)  ## "keep" / "eat" / "dismantle"；捞上来的东西是 "take"

const ACTIONS: Array[String] = ["keep", "eat", "dismantle"]
const ACTION_NAMES := {"keep": "留下", "eat": "生吞", "dismantle": "处理"}
## 以下坐标都按基准分辨率 1280×720
const ART_BOX := Vector2(980, 360)     ## 插图最大显示尺寸
const ART_CENTER := Vector2(640, 258)
const INFO_LEFT := 210.0
const INFO_WIDTH := 860.0
const HOLD_TILE := Vector2(244, 66)    ## 左上道具栏船舱格子的中心，留下时飞过去
const STAGE_SCALE: Array[float] = [0.8, 1.0, 1.1]  ## 幼年期、成长期、成年期的插图显示得多大
const HEAD_Y := 432.0
const TRIBUTE_Y := 486.0
const STATS_Y := 528.0
const PROMPTS_Y := 638.0
const TRIBUTE_COLOR := Color("e8d9b4")  ## 祭值的数字：比骨白亮一点
const ITEM_SIZE := Vector2(300, 300)   ## 捞上来的东西的图标显示得多大

var dim: ColorRect                     ## FishingView 给的压暗层
var catch_data: CatchData
var contractor: Contractor
## 正在展示的是捞上来的东西（道具或附加物的 id）；展示渔获时是空的
var item_id := ""
## 进场、退场动画放着的时候不接受选择
var busy := false

var _root: Node2D                      ## 进场、退场动画动它
var _float: Node2D                     ## 漂浮和视差动它
var _halo: Sprite2D                    ## 身后一团淡淡的青灰背光，暗色的生物也能从压暗的画面里跳出来
var _mesh: MeshInstance2D
var _burst: CPUParticles2D
var _drip: CPUParticles2D
var _motes: CPUParticles2D
var _info: Control
var _rows: Array[Control] = []         ## 依次浮现的几行
var _row_y: Array[float] = []
var _name: Label
var _stage: Label
var _tribute: Label
var _tribute_note: Label
var _flame: TextureRect
var _level: Label
var _affix: Label
var _desc: Label
var _values := {}                      ## 栏目名 → [数值 Label, 小字 Label]
var _materials := {}                   ## 材料id → Label
var _buttons := {}
var _take: KeyPrompt                   ## 捞上来的东西只有这一个按钮
var _note := ""                        ## 写在介绍前面的一句（show_catch 的 note）
var _art_size := Vector2.ONE
var _time := 0.0
var _mouse := Vector2.ZERO
var _tween: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_motes = _make_motes()
	add_child(_motes)

	_root = Node2D.new()
	add_child(_root)
	_float = Node2D.new()
	_root.add_child(_float)
	_halo = Sprite2D.new()
	_halo.texture = Gothic.aura_texture()
	_halo.modulate = Color(0.55, 0.68, 0.72, 0.2)
	_float.add_child(_halo)
	_mesh = MeshInstance2D.new()
	_mesh.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mesh.material = CreatureArt.make_material()
	_float.add_child(_mesh)
	_burst = _make_drops(true)
	_float.add_child(_burst)
	_drip = _make_drops(false)
	_float.add_child(_drip)

	_info = Control.new()
	_info.set_anchors_preset(Control.PRESET_FULL_RECT)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_info)
	_build_info()


func _build_info() -> void:
	# 第一行：左边名字、时期、灵魂等级、词条，右边介绍
	var head := Control.new()
	head.position = Vector2(INFO_LEFT, HEAD_Y)
	head.size = Vector2(INFO_WIDTH, 52)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_row := HBoxContainer.new()
	name_row.size = Vector2(450, 52)
	name_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	name_row.add_theme_constant_override("separation", 8)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(name_row)
	_name = Gothic.label("", 36, Gothic.BONE, 6)
	name_row.add_child(_name)
	_stage = Gothic.label("", 18, Gothic.BONE_DARK)
	_stage.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(_stage)
	_flame = Gothic.icon_rect("icon_soul", Vector2(24, 27))
	_flame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(_flame)
	_level = Gothic.label("", 18)
	_level.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(_level)
	_affix = Gothic.label("", 18, Gothic.WARN)
	_affix.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(_affix)
	_desc = Gothic.label("", 14, Gothic.BONE_DARK)
	_desc.position = Vector2(470, 2)
	_desc.size = Vector2(INFO_WIDTH - 470, 50)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_desc)
	_add_row(head)

	# 第二行：祭值，后面跟一句灰色的批注
	var tribute := HBoxContainer.new()
	tribute.position = Vector2(INFO_LEFT, TRIBUTE_Y)
	tribute.size = Vector2(INFO_WIDTH, 36)
	tribute.add_theme_constant_override("separation", 10)
	tribute.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tribute_title := Gothic.label("祭值", 16, Gothic.BRONZE_LIGHT)
	tribute_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tribute.add_child(tribute_title)
	_tribute = Gothic.label("", 28, TRIBUTE_COLOR, 5)
	_tribute.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tribute.add_child(_tribute)
	_tribute_note = Gothic.label("", 14, Gothic.BONE_DARK)
	_tribute_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tribute.add_child(_tribute_note)
	_add_row(tribute)

	# 第三行：六栏数值
	var stats := HBoxContainer.new()
	stats.position = Vector2(INFO_LEFT, STATS_Y)
	stats.size = Vector2(INFO_WIDTH, 100)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for title in ["躯体规模", "灵魂强度", "能量", "载荷", "饱腹"]:
		var col := _column(title)
		var value := Gothic.label("", 22)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(value)
		var sub := Gothic.label("", 13, Gothic.BONE_DARK)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(sub)
		_values[title] = [value, sub]
		stats.add_child(col)
	var mats := _column("分解材料")
	for m in Materials.ALL:
		var line := HBoxContainer.new()
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_theme_constant_override("separation", 4)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(Gothic.icon_rect("mat_" + m, Vector2(18, 18)))
		var l := Gothic.label("", 15)
		line.add_child(l)
		_materials[m] = l
		mats.add_child(line)
	stats.add_child(mats)
	_add_row(stats)

	# 第四行：四个去向
	var prompts := HBoxContainer.new()
	prompts.position = Vector2(INFO_LEFT, PROMPTS_Y)
	prompts.size = Vector2(INFO_WIDTH, 36)
	prompts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in ACTIONS.size():
		var action := ACTIONS[i]
		var p := KeyPrompt.make(str(i + 1), ACTION_NAMES[action], 20)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.pressed.connect(func() -> void: decide(action))
		prompts.add_child(p)
		_buttons[action] = p
	_take = KeyPrompt.make("空格", "收下", 20)
	_take.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_take.pressed.connect(func() -> void: decide("take"))
	_take.visible = false
	prompts.add_child(_take)
	_add_row(prompts)


func _column(title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var header := Gothic.label(title, 14, Gothic.BRONZE_LIGHT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(header)
	return col


func _add_row(row: Control) -> void:
	_info.add_child(row)
	_rows.append(row)
	_row_y.append(row.position.y)


# ---------- 展示 ----------

## note：写在介绍前面的一句（进化：幼年期 → 成年期）
func show_catch(c: CatchData, who: Contractor, note := "") -> void:
	_disconnect()
	item_id = ""
	_note = note
	_set_item_mode(false)
	catch_data = c
	contractor = who
	contractor.changed.connect(refresh)
	var species := c.species()
	var tex: Texture2D = c.art() if c.art() else Gothic.tex("icon_fish")
	var aspect := tex.get_size().x / maxf(tex.get_size().y, 1.0)
	_art_size = Vector2(ART_BOX.y * aspect, ART_BOX.y)
	if _art_size.x > ART_BOX.x:
		_art_size = Vector2(ART_BOX.x, ART_BOX.x / aspect)
	_art_size *= STAGE_SCALE[clampi(c.stage, 0, STAGE_SCALE.size() - 1)]
	_mesh.mesh = CreatureArt.grid(_art_size)
	_mesh.texture = tex
	var mat := _mesh.material as ShaderMaterial
	## 按种类动（CreatureArt）；同一种的几条按个体错开一点
	CreatureArt.apply(mat, species, tex, _art_size, fmod(c.body * 7.31 + c.soul_strength * 0.137, 1.0))
	mat.set_shader_parameter("sheen", -1.0)
	mat.set_shader_parameter("dissolve", 0.0)
	mat.set_shader_parameter("hue_shift", c.hue_shift)
	mat.set_shader_parameter("mutation", 1.0 if c.is_mutated() else 0.0)
	_halo.scale = _art_size * 1.25 / _halo.texture.get_size()
	_burst.emission_rect_extents = Vector2(_art_size.x * 0.34, _art_size.y * 0.18)
	_drip.position = Vector2(0, _art_size.y * 0.16)
	_drip.emission_rect_extents = Vector2(_art_size.x * 0.3, 3.0)
	refresh()
	_play_enter()


## 捞上来的东西（道具或附加物的 id）：和渔获一样从水里提上来、浮在正中，信息只有名字、是什么、一句说明
func show_item(id: String, who: Contractor) -> void:
	_disconnect()
	catch_data = null
	item_id = id
	contractor = who
	_set_item_mode(true)
	var item := GameDB.get_item(id)
	var additive := GameDB.get_additive(id)
	var tex: Texture2D = item.icon if item and item.icon else (additive.icon if additive and additive.icon else Gothic.tex("charm"))
	_art_size = ITEM_SIZE
	_mesh.mesh = CreatureArt.grid(_art_size)
	_mesh.texture = tex
	var mat := _mesh.material as ShaderMaterial
	CreatureArt.apply_still(mat, _art_size)
	mat.set_shader_parameter("sheen", -1.0)
	mat.set_shader_parameter("dissolve", 0.0)
	mat.set_shader_parameter("hue_shift", 0.0)
	mat.set_shader_parameter("mutation", 0.0)
	_halo.scale = _art_size * 1.25 / _halo.texture.get_size()
	_burst.emission_rect_extents = Vector2(_art_size.x * 0.3, _art_size.y * 0.15)
	_drip.position = Vector2(0, _art_size.y * 0.2)
	_drip.emission_rect_extents = Vector2(_art_size.x * 0.2, 3.0)
	refresh()
	_play_enter()


func is_item() -> bool:
	return item_id != ""


## 展示捞上来的东西时：只留名字那一行和一个"收下"；祭值、六栏数值、四个去向都收起来
func _set_item_mode(on: bool) -> void:
	_rows[1].visible = not on
	_rows[2].visible = not on
	_flame.visible = not on
	_level.visible = not on
	for action in _buttons:
		_buttons[action].visible = not on
	_take.visible = on


## 船舱开着的时候把鱼和字淡下去（压暗层不动），关上再浮回来
func set_backgrounded(on: bool) -> void:
	if not visible or busy:
		return
	var tw := _new_tween()
	tw.tween_property(_root, "modulate:a", 0.0 if on else 1.0, 0.15)
	tw.parallel().tween_property(_info, "modulate:a", 0.0 if on else 1.0, 0.15)


## 按钮和快捷键都走这里；动画中、或者留不下时"留下"无效。捞上来的东西只认"收下"（[1] 留下也算）
func decide(action: String) -> void:
	if is_item():
		if not busy and visible and _info.modulate.a >= 0.5 and action in ["take", "keep"]:
			decided.emit("take")
		return
	if catch_data == null or busy or not visible or _info.modulate.a < 0.5:
		return
	if action == "keep" and not contractor.can_keep(catch_data):
		return
	decided.emit(action)


func refresh() -> void:
	if is_item():
		_refresh_item()
		return
	if catch_data == null:
		return
	var c := catch_data
	var species := c.species()
	_name.text = c.display_name()
	_stage.text = c.stage_name()
	_level.text = "%d级" % c.level
	_tribute.text = Gothic.grouped(c.tribute)
	_tribute_note.text = Gothic.tribute_note(c.tribute)
	_affix.text = "「%s」" % "、".join(c.affix_names()) if not c.affix_ids.is_empty() else ""
	var notes: PackedStringArray = []
	if _note != "":
		notes.append(_note + "。")
	for id in c.affix_ids:
		var affix := GameDB.get_affix(id)
		if affix:
			notes.append("「%s」%s" % [affix.display_name, affix.description])
	if species:
		notes.append(species.description)
	if contractor.carcass_ready():  ## 残躯为饵（恩赐）：拆过一条了，留下这条祭值多一截
		notes.append("残躯为饵：留下它，祭值 +%d%%。" % roundi(contractor.boon_amount("carcass") * 100.0))
	_desc.text = "　".join(notes)

	# 躯体规模：数值，下面写是哪一档（2026-11-04 你定的）；带「变异」的大一档，写琥珀色
	var odd := c.is_mutated()
	_set_value("躯体规模", c.body_text(), c.body_name() + ("（「变异」大一档）" if odd else ""),
		Gothic.WARN if odd or c.body_class() >= 4 else Gothic.BONE_DARK)
	_set_value("灵魂强度", str(c.soul_strength), _soul_word(c))
	_set_value("能量", str(c.energy), "%d 级平均 %d" % [c.level, roundi(contractor.config.energy_for(c.level))])
	var fits := contractor.can_keep(c)
	var hold := "船舱 %d/%d" % [contractor.hold_load(), contractor.hold_capacity()]
	_set_value("载荷", str(c.load_cost), hold if fits else hold + "，放不下", Gothic.BONE_DARK if fits else Gothic.WARN)
	var gain := contractor.eat_gain(c)
	var full: bool = gain.overflow >= 1.0
	var now := roundi(contractor.hunger)
	_set_value("饱腹", "+%d" % c.food, "%d → %d" % [now, roundi(contractor.hunger + gain.food)] if not full else "%d → 满，吃撑了" % now,
		Gothic.BONE_DARK if not full else Gothic.WARN)
	# 剖腹（奖励卡）还在的话，这一次处理翻倍：写翻倍以后的，字是幽绿的
	var got := contractor.dismantle_yield(c)
	var doubled := contractor.has_card("dissect")
	for m in Materials.ALL:
		_materials[m].text = "%s %d" % [Materials.DISPLAY[m], got.get(m, 0)]
		_materials[m].add_theme_color_override("font_color", Gothic.EERIE if doubled else Gothic.BONE)

	var keep: KeyPrompt = _buttons["keep"]
	keep.disabled = not fits
	keep.tooltip_text = "" if fits else "船舱放不下：载荷 %d/%d，它要占 %d" % [
		contractor.hold_load(), contractor.hold_capacity(), c.load_cost]


## 捞上来的东西：名字、是道具还是附加物（附加物写它带什么气味）、说明，后面写身上已经有几个
func _refresh_item() -> void:
	var item := GameDB.get_item(item_id)
	var additive := GameDB.get_additive(item_id)
	_name.text = item.display_name if item else (additive.display_name if additive else item_id)
	_stage.text = "道具" if item else "附加物"
	_affix.text = "（%s味）" % Aspect.display_name(additive.aspect) if additive and additive.aspect != "" else ""
	var have: int = contractor.items.get(item_id, 0) if item else contractor.additive_count(item_id)
	var desc: String = item.description if item else (additive.description if additive else "")
	_desc.text = desc + ("　身上已经有 %d 个。" % have if have > 0 else "")


## 灵魂强度比同级、同时期的平均高还是低：浓烈 / 寻常 / 稀薄
func _soul_word(c: CatchData) -> String:
	var config := contractor.config
	var mean: float = config.soul_base + config.soul_per_level * (c.level - 1) + BalanceConfig.pick(config.stage_soul_offset, c.stage, 0.0)
	if c.soul_strength >= mean + config.soul_spread:
		return "浓烈"
	if c.soul_strength <= mean - config.soul_spread:
		return "稀薄"
	return "寻常"


func _set_value(title: String, value: String, sub: String, sub_color := Gothic.BONE_DARK) -> void:
	var pair: Array = _values[title]
	pair[0].text = value
	pair[1].text = sub
	pair[1].add_theme_color_override("font_color", sub_color)


# ---------- 动画 ----------

func _play_enter() -> void:
	busy = true
	visible = true
	dim.visible = true
	_root.position = ART_CENTER + Vector2(0, 430)
	_root.rotation = -0.24
	_root.scale = Vector2(0.72, 0.72)
	_root.modulate = Color.WHITE
	_info.modulate = Color.WHITE
	for i in _rows.size():
		_rows[i].modulate.a = 0.0
		_rows[i].position.y = _row_y[i] + 14.0
	_motes.emitting = true
	_drip.emitting = false
	var tw := _new_tween()
	tw.tween_method(_set_dim, 0.0, 1.0, 0.35)
	tw.parallel().tween_property(_root, "position", ART_CENTER, 0.62).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_root, "rotation", 0.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_root, "scale", Vector2.ONE, 0.62).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_callback(_burst.restart).set_delay(0.1)
	tw.parallel().tween_method(_set_flash, 0.3, 0.0, 0.45).set_delay(0.08)
	tw.parallel().tween_method(_set_sheen, -0.3, 1.5, 0.9).set_delay(0.5)
	for i in _rows.size():
		var delay := 0.45 + i * 0.12
		tw.parallel().tween_property(_rows[i], "modulate:a", 1.0, 0.35).set_delay(delay)
		tw.parallel().tween_property(_rows[i], "position:y", _row_y[i], 0.45).set_delay(delay) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_enter_done)


func _enter_done() -> void:
	busy = false
	_drip.emitting = true


## 按去向退场，放完返回（await）
func play_exit(action: String) -> void:
	busy = true
	_disconnect()
	_drip.emitting = false
	var tw := _new_tween()
	tw.tween_property(_info, "modulate:a", 0.0, 0.18)
	match action:
		"keep":
			tw.parallel().tween_property(_root, "position", HOLD_TILE, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(_root, "scale", Vector2(0.07, 0.07), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(_root, "modulate:a", 0.0, 0.15).set_delay(0.38)
		"eat":
			tw.parallel().tween_property(_root, "scale", Vector2(1.9, 1.9), 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(_root, "modulate:a", 0.0, 0.26).set_delay(0.1)
			tw.parallel().tween_method(_set_flash, 0.0, 0.6, 0.12).set_delay(0.24)
			tw.tween_method(_set_flash, 0.6, 0.0, 0.5)
		"dismantle":
			tw.parallel().tween_method(_set_dissolve, 0.0, 1.0, 0.8)
		"take":
			tw.parallel().tween_property(_root, "position", ART_CENTER + Vector2(0, -80), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(_root, "scale", Vector2(0.55, 0.55), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(_root, "modulate:a", 0.0, 0.3).set_delay(0.15)
		_:
			tw.parallel().tween_property(_root, "position", ART_CENTER + Vector2(0, 560), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(_root, "rotation", 0.4, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_method(_set_dim, 1.0, 0.0, 0.3)
	await tw.finished
	_motes.emitting = false
	visible = false
	dim.visible = false
	catch_data = null
	item_id = ""
	busy = false


func _new_tween() -> Tween:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	return _tween


func _set_dim(v: float) -> void:
	(dim.material as ShaderMaterial).set_shader_parameter("amount", v)


func _set_flash(v: float) -> void:
	(dim.material as ShaderMaterial).set_shader_parameter("flash", v)


func _set_sheen(v: float) -> void:
	(_mesh.material as ShaderMaterial).set_shader_parameter("sheen", v if v < 1.45 else -1.0)


func _set_dissolve(v: float) -> void:
	(_mesh.material as ShaderMaterial).set_shader_parameter("dissolve", v)


func _disconnect() -> void:
	if contractor and contractor.changed.is_connected(refresh):
		contractor.changed.disconnect(refresh)


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	var m := (get_local_mouse_position() / size - Vector2(0.5, 0.5)) * 2.0
	_mouse = _mouse.lerp(m.clamp(Vector2(-1, -1), Vector2(1, 1)), minf(1.0, delta * 3.0))
	_float.position = _mouse * 12.0 + Vector2(0, sin(_time * 1.1) * 5.0)
	_float.rotation = sin(_time * 0.7) * 0.012 + _mouse.x * 0.012
	_motes.position = size * 0.5 + _mouse * 28.0
	_info.position = _mouse * 3.0


# ---------- 网格与粒子 ----------

## 水滴：burst 是提出水那一下甩出来的一蓬，否则是之后从身上不停往下滴的
static func _make_drops(burst: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = Gothic.glow_texture()
	p.local_coords = false
	p.emitting = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 1.0])
	fade.colors = PackedColorArray([Color(0.85, 0.95, 0.97, 0.9), Color(0.6, 0.8, 0.86, 0.0)])
	p.color_ramp = fade
	if burst:
		p.one_shot = true
		p.amount = 56
		p.lifetime = 1.3
		p.explosiveness = 0.85
		p.direction = Vector2(0, -1)
		p.spread = 80.0
		p.initial_velocity_min = 160.0
		p.initial_velocity_max = 460.0
		p.gravity = Vector2(0, 1000)
		p.scale_amount_min = 0.05
		p.scale_amount_max = 0.13
	else:
		p.amount = 18
		p.lifetime = 1.4
		p.direction = Vector2(0, 1)
		p.spread = 6.0
		p.initial_velocity_min = 0.0
		p.initial_velocity_max = 30.0
		p.gravity = Vector2(0, 800)
		p.scale_amount_min = 0.035
		p.scale_amount_max = 0.07
	return p


## 压暗以后画面里慢慢飘的浮尘
static func _make_motes() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = Gothic.glow_texture()
	p.local_coords = true
	p.emitting = false
	p.amount = 48
	p.lifetime = 9.0
	p.preprocess = 6.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(700, 400)
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 12.0
	p.gravity = Vector2(0, -4)
	p.scale_amount_min = 0.02
	p.scale_amount_max = 0.07
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	fade.colors = PackedColorArray([Color(0.75, 0.88, 0.9, 0.0), Color(0.75, 0.88, 0.9, 0.18), Color(0.75, 0.88, 0.9, 0.0)])
	p.color_ramp = fade
	return p
