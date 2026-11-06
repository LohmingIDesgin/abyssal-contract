class_name BoneRack
extends Control
## 左上角的骨架道具栏（参照 docs/reference/ui_style.webp）：
## 顶上一根横骨、左边一根长竖骨，交汇处挂一个头骨，头骨往右伸出一截小臂骨、吊着一枚獠牙坠子，
## 头骨下面一串脊椎。第一行四块羊皮卷：水层（测深锤）、灵魂等级（灵魂火）、船舱（鱼，写着载荷）、
## 唤祂（GPT 画的一轮暗红落日压着横雾，assets/icons/summon.png；船舱里的祭值够了时泛红光）；
## 竖列是饵料篓里的饵（Gothic.flask：瓶子按基础组合换样式，两份基础材料在瓶里分成上下两层；万能饵是 GPT 画的一只圆瓶，
## assets/icons/universal_bait.png），
## 左下角是附加物（图标，没有图标时盖它的气味印章），右下角写还剩几份。没有空钩了（新回合机制第 31 条）：饵用完了只画一个空瓶。
## 水层：左键下一个、右键上一个；船舱：点一下打开（钓鱼中途也能点，开不开由 FishingView 决定）；
## 唤祂：点一下（这会儿能不能唤由 FishingView 决定）；饵料：左键选中。

const SUMMON_ICON := preload("res://assets/icons/summon.png")
const UNIVERSAL_ICON := preload("res://assets/icons/universal_bait.png")

signal depth_changed(index: int)
signal hold_requested
signal summon_requested
signal selection_changed

const TILE := 64.0              ## 羊皮卷显示尺寸
const TILE_CANVAS := 80.0       ## 羊皮卷贴图的显示尺寸（含投影边距）
const SPINE_X := 26.0           ## 竖骨中线
const TOP_BONE_Y := 14.0        ## 横骨中线
const ROW_Y := 26.0             ## 第一行格子上边
const ROW_X0 := 48.0
const ROW_GAP := 8.0
const COLUMN_Y0 := 134.0        ## 饵料列第一块格子上边
const COLUMN_STEP := 72.0
const MAX_BAITS := 6            ## 最多显示几种饵
const SKULL_CENTER := Vector2(26, 112)
const VERTEBRA_Y0 := 140.0
const VERTEBRA_STEP := 8.6
const VERTEBRA_COUNT := 18
const BONE_CAP := 150.0         ## 长骨贴图两端不拉伸的长度（贴图像素）

var depth_names: Array = []
var depth := 1
var ability := 1          ## 能力档（2026-11-04 去掉了玩家等级）
var ability_tooltip := ""
var hold_label := ""     ## 船舱格子上的字，例如 "2/3"
var hold_tooltip := ""
var summon_tooltip := ""
var summon_glow := 0.0   ## 0~1：船舱里的祭值够了，唤祂那一格后面泛红光
var baits: Array[Bait] = []
## 选中的是饵料列的第几格（baits 的下标）；一种饵都没有是 −1
var selected := -1
var enabled := true:
	set(value):
		enabled = value
		queue_redraw()

var _hover := -1                ## 0~3 = 第一行；10 + i = 饵料列第 i 格
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_update_size()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## 换了饵料篓：原来选中的还在就接着选它；用完了就选第一种饵；一种都没有了是 −1
func set_baits(list: Array[Bait]) -> void:
	var previous := selected_bait()
	baits = list.slice(0, MAX_BAITS)
	var keep := baits.find(previous)
	selected = keep if keep >= 0 else (0 if not baits.is_empty() else -1)
	_update_size()


## 选中的饵；没有饵返回 null
func selected_bait() -> Bait:
	return baits[selected] if selected >= 0 and selected < baits.size() else null


func _update_size() -> void:
	var rows := maxi(baits.size(), 1)
	custom_minimum_size = Vector2(340, COLUMN_Y0 + rows * COLUMN_STEP + 16.0)
	size = custom_minimum_size


func _row_rect(i: int) -> Rect2:
	return Rect2(Vector2(ROW_X0 + i * (TILE + ROW_GAP), ROW_Y), Vector2(TILE, TILE))


func _bait_rect(i: int) -> Rect2:
	return Rect2(Vector2(ROW_X0, COLUMN_Y0 + i * COLUMN_STEP), Vector2(TILE, TILE))


func _slot_at(pos: Vector2) -> int:
	for i in 4:
		if _row_rect(i).has_point(pos):
			return i
	for i in baits.size():
		if _bait_rect(i).has_point(pos):
			return 10 + i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _slot_at(event.position)
		if h != _hover:
			_hover = h
			tooltip_text = _tooltip(h)
	elif event is InputEventMouseButton and event.pressed:
		var slot := _slot_at(event.position)
		if slot < 0:
			return
		accept_event()
		if slot == 2 and event.button_index == MOUSE_BUTTON_LEFT:
			hold_requested.emit()
			return
		if slot == 3 and event.button_index == MOUSE_BUTTON_LEFT:
			summon_requested.emit()
			return
		if not enabled:
			return
		var step := 1 if event.button_index == MOUSE_BUTTON_LEFT else (-1 if event.button_index == MOUSE_BUTTON_RIGHT else 0)
		if step == 0:
			return
		if slot == 0 and not depth_names.is_empty():
			depth = posmod(depth + step, depth_names.size())
			depth_changed.emit(depth)
		elif slot >= 10 and event.button_index == MOUSE_BUTTON_LEFT and slot - 10 != selected:
			selected = slot - 10
			selection_changed.emit()
		tooltip_text = _tooltip(slot)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1


func _tooltip(slot: int) -> String:
	match slot:
		0:
			return "水层：%s\n左键 / 右键切换" % (depth_names[depth] if depth < depth_names.size() else "")
		1:
			return ability_tooltip
		2:
			return hold_tooltip
		3:
			return summon_tooltip
	if slot >= 10 and slot - 10 < baits.size():
		var bait := baits[slot - 10]
		if bait.universal:
			return "万能饵（剩 %d 份）\n不用材料，哪一层都能用：咬钩的按这层水里本来的样子来，不偏向哪一种" % bait.uses
		var additive := bait.additive()
		var bases: PackedStringArray = []
		for m in bait.bases:
			bases.append(Materials.DISPLAY[m])
		return "%s（剩 %d 份）\n%s + %s" % [bait.display_name, bait.uses, " + ".join(bases),
			additive.display_name if additive else "?"]
	return ""


# ---------- 绘制 ----------

func _draw() -> void:
	var rows := maxi(baits.size(), 1)
	var bottom := COLUMN_Y0 + rows * COLUMN_STEP + 4.0
	# 竖骨、横骨
	var v := Gothic.tex("bone_long_v")
	var vw := v.get_width() * Gothic.ART_SCALE
	Gothic.three_slice_v(self, v, Rect2(SPINE_X - vw * 0.5, 0.0, vw, bottom), BONE_CAP)
	var hb := Gothic.tex("bone_long_h")
	var hh := hb.get_height() * Gothic.ART_SCALE
	Gothic.three_slice_h(self, hb, Rect2(4.0, TOP_BONE_Y - hh * 0.5, ROW_X0 + 4 * (TILE + ROW_GAP) + 10.0, hh), BONE_CAP)
	# 第一行
	_draw_tile(_row_rect(0), 0, "icon_depth", depth_names[depth] if depth < depth_names.size() else "")
	_draw_tile(_row_rect(1), 1, "icon_soul", "%d 档" % ability)
	_draw_tile(_row_rect(2), 2, "icon_fish", hold_label)
	if summon_glow > 0.0:
		var hc := _row_rect(3).get_center()
		var pulse := 0.75 + 0.25 * sin(_time * 3.0)
		draw_texture_rect(Gothic.aura_texture(), Rect2(hc - Vector2(40, 40), Vector2(80, 80)), false,
			Color(1.0, 0.32, 0.14, 0.5 * summon_glow * pulse))
	_draw_summon_tile(_row_rect(3))
	# 小臂骨 + 坠子（在头骨后面）
	var arm := Gothic.tex("bone_arm")
	var arm_size := arm.get_size() * Gothic.ART_SCALE
	draw_texture_rect(arm, Rect2(Vector2(SKULL_CENTER.x + 2.0, SKULL_CENTER.y + 6.0 - arm_size.y * 0.5), arm_size), false)
	var charm_pivot := Vector2(SKULL_CENTER.x + arm_size.x - 14.0, SKULL_CENTER.y + 10.0)
	draw_set_transform(charm_pivot, sin(_time * 1.1) * 0.08 + sin(_time * 2.7) * 0.03, Vector2.ONE)
	var charm := Gothic.tex("charm")
	var charm_size := charm.get_size() * Gothic.ART_SCALE * 1.45
	draw_texture_rect(charm, Rect2(Vector2(-charm_size.x * 0.5, 0), charm_size), false)
	draw_set_transform(Vector2.ZERO)
	# 脊椎：从下往上画，上一节压住下一节；越往下越宽一点
	for i in range(VERTEBRA_COUNT - 1, -1, -1):
		var y := VERTEBRA_Y0 + i * VERTEBRA_STEP
		if y > bottom - 20.0:
			continue
		var scale := 0.86 + 0.18 * float(i) / VERTEBRA_COUNT
		Gothic.sprite_centered(self, "vertebra_%d" % (i % 3), Vector2(SPINE_X + sin(i * 1.7) * 0.6, y), scale)
	Gothic.sprite_centered(self, "skull", SKULL_CENTER)
	# 饵料列：饵料篓里的饵；一份都没有了画一个空瓶
	if baits.is_empty():
		var rect := _bait_rect(0)
		_draw_parchment(rect, 0, Color(0.6, 0.6, 0.6))
		Gothic.sprite_centered(self, "flask_round", rect.get_center() + Vector2(0, -5), 0.92, Color(0.6, 0.6, 0.6, 0.5))
		Gothic.text(self, Vector2(rect.end.x + 10.0, rect.get_center().y + 6.0), "饵用完了", 15, Gothic.BONE_DARK)
		return
	for i in baits.size():
		_draw_bait(i)
	var sel := _bait_rect(maxi(selected, 0))
	var sel_name := selected_bait().display_name if selected_bait() else ""
	Gothic.text(self, Vector2(sel.end.x + 10.0, sel.get_center().y + 6.0), sel_name, 15, Gothic.BONE)


func _draw_parchment(rect: Rect2, variant: int, modulate: Color) -> void:
	var t := Gothic.tex("parchment_%d" % (variant % 4))
	var pad := (TILE_CANVAS - TILE) * 0.5
	draw_texture_rect(t, Rect2(rect.position - Vector2(pad, pad), Vector2(TILE_CANVAS, TILE_CANVAS)), false, modulate)


func _draw_tile(rect: Rect2, slot: int, icon: String, label: String) -> void:
	var hover := slot >= 0 and slot == _hover and enabled
	var shade := Color(1.08, 1.06, 1.02) if hover else (Color.WHITE if enabled else Color(0.72, 0.72, 0.72))
	_draw_parchment(rect, slot + 1, shade)
	if icon != "":
		Gothic.sprite_centered(self, icon, rect.get_center() + Vector2(0, -6), 0.86, shade)
	if label != "":
		Gothic.text(self, Vector2(rect.position.x, rect.end.y - 6.0), label, 12, Gothic.INK,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 0)


## 唤祂那一格：GPT 画的一轮暗红落日压着横雾，下面写"唤祂"
func _draw_summon_tile(rect: Rect2) -> void:
	var shade := Color(1.08, 1.06, 1.02) if _hover == 3 else Color.WHITE
	_draw_parchment(rect, 4, shade)
	var c := rect.get_center() + Vector2(0, -7)
	draw_texture_rect(SUMMON_ICON, Rect2(c - Vector2(21, 21), Vector2(42, 42)), false, shade)
	Gothic.text(self, Vector2(rect.position.x, rect.end.y - 6.0), "唤祂", 12, Gothic.INK, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 0)


## 饵料列第 i 格：baits[i]
func _draw_bait(i: int) -> void:
	var rect := _bait_rect(i)
	var bait := baits[i]
	var is_selected := i == selected
	var hover := _hover == 10 + i and enabled
	var shade := Color.WHITE
	if not enabled and not is_selected:
		shade = Color(0.6, 0.6, 0.6)
	elif hover:
		shade = Color(1.08, 1.06, 1.02)
	_draw_parchment(rect, i, Color(0.9, 1.06, 1.0) if is_selected else shade)
	var center := rect.get_center() + Vector2(0, -5)
	# 选中：瓶子后面一团幽绿的光，轻轻呼吸
	if is_selected:
		var pulse := 0.8 + 0.2 * sin(_time * 2.4)
		var r := 30.0
		draw_texture_rect(Gothic.aura_texture(), Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0), false,
			Color(0.25, 0.85, 0.66, 0.5 * pulse))
	if bait.universal:
		draw_texture_rect(UNIVERSAL_ICON, Rect2(center - Vector2(24, 24), Vector2(48, 48)), false, shade)
	else:
		Gothic.flask(self, center, 0.92, bait.bases, shade)
	Gothic.additive_mark(self, bait.additive(), rect.position + Vector2(3, rect.size.y - 21), 18.0, shade)
	Gothic.text(self, Vector2(rect.end.x - 26.0, rect.end.y - 7.0), str(bait.uses), 14, Gothic.INK,
		HORIZONTAL_ALIGNMENT_RIGHT, 20.0, 0)
