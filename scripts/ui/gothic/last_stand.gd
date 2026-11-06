class_name LastStand
extends Control
## 体力耗尽的那一刻（设计对照文档 3.1 第 5 条）：画面放慢（FishingView 调 Engine.time_scale），屏幕正中浮出两个选择——
## [X] 剪线：扣一枚烙印（2026-11-04 起灵魂线并进了烙印），它沉回黑暗里；[空格] 硬撑：大概率被拖下水、当场死亡，小概率把它钓上来。
## 下面一道骨白的细线从两头往中间收，收完了还没选就算硬撑。硬撑的机会不给数字，只给一句话（九死一生 / 凶多吉少 / 尚有一线）。
## 烙印没了剪线是灰的。按键由 FishingView 处理，这里只管显示，点按钮也行。
## 画面放慢时这里的动画照常速度走（tween 不受 time_scale 影响）。

signal chosen(cut: bool)

## 以下坐标都按基准分辨率 1280×720
const TOP := 372.0
const LINE_Y := 560.0
const LINE_HALF := 190.0

var _box: VBoxContainer
var _title: Label
var _sub: Label
var _cut: KeyPrompt
var _cut_note: Label
var _hold: KeyPrompt
var _hold_note: Label
var _remaining := 1.0
var _tween: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_box = VBoxContainer.new()
	_box.position = Vector2(0, TOP)
	_box.size = Vector2(1280, 0)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 2)
	add_child(_box)
	_title = _centered(Gothic.label("体力耗尽", 36, Color("e0705c"), 7))
	_sub = _centered(Gothic.label("它在把你往水里拖", 16, Gothic.BONE_DARK))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 16)
	_box.add_child(gap)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 96)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(row)
	var cut_col := _column(row)
	_cut = KeyPrompt.make("X", "剪线", 26)
	_cut.pressed.connect(func() -> void: chosen.emit(true))
	_cut.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cut_col.add_child(_cut)
	_cut_note = Gothic.label("", 15, Gothic.BONE_DARK)
	_cut_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cut_col.add_child(_cut_note)
	var hold_col := _column(row)
	_hold = KeyPrompt.make("空格", "硬撑", 26)
	_hold.pressed.connect(func() -> void: chosen.emit(false))
	_hold.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hold_col.add_child(_hold)
	_hold_note = Gothic.label("", 15, Gothic.WARN)
	_hold_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hold_col.add_child(_hold_note)


func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(l)
	return l


func _column(row: HBoxContainer) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.custom_minimum_size = Vector2(170, 0)
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	return col


## brands：还剩几枚烙印；phrase：硬撑的那一句话
func open(brands: int, phrase: String) -> void:
	set_brands(brands)
	_hold_note.text = phrase
	_remaining = 1.0
	visible = true
	modulate.a = 0.0
	_box.position.y = TOP + 14.0
	_restart_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.35)
	_tween.parallel().tween_property(_box, "position:y", TOP, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	queue_redraw()


## 决定的时候用了续魂丝：烙印补回一枚，剪线又能用了
func set_brands(brands: int) -> void:
	_cut.disabled = brands <= 0
	_cut.interactive = brands > 0
	_cut_note.text = "扣一枚烙印（余 %d 枚）" % brands if brands > 0 else "烙印已经没了"
	_cut_note.add_theme_color_override("font_color", Gothic.BONE_DARK if brands > 0 else Gothic.WARN)


## 剩下的决定时间 0~1（细线跟着收）
func set_remaining(r: float) -> void:
	_remaining = clampf(r, 0.0, 1.0)
	queue_redraw()


## 选好了：选中的那个亮一下，整体淡出
func close(cut: bool) -> void:
	if not visible:
		return
	var picked := _cut if cut else _hold
	_restart_tween()
	_tween.tween_property(picked, "scale", Vector2(1.12, 1.12), 0.12)
	_tween.parallel().tween_property(self, "modulate:a", 0.0, 0.45).set_delay(0.12)
	_tween.tween_callback(func() -> void:
		visible = false
		picked.scale = Vector2.ONE)


func _restart_tween() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	for p: KeyPrompt in [_cut, _hold]:
		p.pivot_offset = p.size * 0.5
		p.scale = Vector2.ONE


func _draw() -> void:
	# 倒计时：一道骨白的细线从两头往中间收，两端各一个小点
	var half := LINE_HALF * _remaining
	if half < 0.5:
		return
	var y := LINE_Y
	draw_line(Vector2(640.0 - half, y), Vector2(640.0 + half, y), Color(0, 0, 0, 0.6), 4.0)
	draw_line(Vector2(640.0 - half, y), Vector2(640.0 + half, y), Color(Gothic.BONE, 0.85), 1.6)
	for side in [-1.0, 1.0]:
		draw_circle(Vector2(640.0 + side * half, y), 2.6, Color(Gothic.BONE, 0.9))
