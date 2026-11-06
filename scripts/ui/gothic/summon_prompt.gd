class_name SummonPrompt
extends Control
## 唤祂之前的确认（新回合机制第 37 条）：一夜没有钟，玩家自己决定什么时候停手。按 F（或者点道具栏上"唤祂"那一格）先浮出这一块：
## 还剩几份饵（身上的材料还能做几份）、船舱里的祭值、黄昏要多少、超额线（需求的 over_ratio 倍），下面一根细条把三个数摆在一起。
## [空格] 唤祂：天转红、祂出来，就不能退了（可以一条也不献）。[Esc] 再钓一会儿：什么也不发、不算供奉。
## 开着的时候按键自己收（FishingView 不处理）。

signal confirmed
signal cancelled

const CX := 640.0
const TITLE_Y := 262.0
const LINES_Y := 330.0
const BAR := Rect2(460, 384, 360, 6)
const PROMPTS_Y := 432.0

var is_open := false

var _who: Contractor
var _baits := 0
var _craftable := 0
var _shade: ColorRect
var _content: Control
var _confirm: KeyPrompt
var _time := 0.0
var _opened_at := 0.0
var _tween: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_shade = ColorRect.new()
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color(0.0, 0.01, 0.015, 0.62)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
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
	_confirm = KeyPrompt.make("空格", "唤祂", 21)
	_confirm.pressed.connect(confirm)
	prompts.add_child(_confirm)
	var back := KeyPrompt.make("Esc", "再钓一会儿", 21)
	back.pressed.connect(cancel)
	prompts.add_child(back)


## who：契约者；baits：饵料篓里还剩几份；craftable：身上的基础材料还能做几份
func open(who: Contractor, baits: int, craftable: int) -> void:
	_who = who
	_baits = baits
	_craftable = craftable
	is_open = true
	visible = true
	_opened_at = _time
	modulate.a = 0.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.25)


func confirm() -> void:
	if _close():
		confirmed.emit()


func cancel() -> void:
	if _close():
		cancelled.emit()


func _close() -> bool:
	if not is_open:
		return false
	is_open = false
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.2)
	_tween.tween_callback(func() -> void: visible = false)
	return true


func _input(event: InputEvent) -> void:
	if not is_open or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_F]:
		confirm()
	elif event.keycode == KEY_ESCAPE:
		cancel()
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_time += delta
	if visible:
		_content.queue_redraw()


func _centered(y: float, s: String, size_t: int, color: Color, outline := 4) -> void:
	Gothic.text(_content, Vector2(CX - Gothic.text_width(s, size_t) * 0.5, y), s, size_t, color, HORIZONTAL_ALIGNMENT_LEFT, -1, outline)


func _draw_content() -> void:
	if _who == null:
		return
	var demand := _who.demand()
	var over := ceili(demand * _who.config.over_ratio)
	var hold := _who.hold_tribute()
	_centered(TITLE_Y, "唤祂来收供奉？", 30, Gothic.BONE, 6)
	_centered(TITLE_Y + 32.0, "这一夜就到这里。祂来了以后，不能再钓。", 15, ContractScreen.NOTE, 3)
	var bait_line := "还剩 %d 份饵" % _baits
	if _craftable > 0:
		bait_line += "　身上的材料还能做 %d 份" % _craftable
	_centered(LINES_Y, bait_line, 17, Gothic.BONE if _baits + _craftable > 0 else Gothic.BONE_DARK)
	var verdict := "超额" if hold >= over else ("够了" if hold >= demand else "还差 %s" % Gothic.grouped(demand - hold))
	var color := Gothic.BRONZE_LIGHT if hold >= over else (Gothic.BONE if hold >= demand else Gothic.WARN)
	var line := "船舱里的祭值 %s　黄昏要 %s　超额 %s　" % [Gothic.grouped(hold), Gothic.grouped(demand), Gothic.grouped(over)]
	var w := Gothic.text_width(line, 17) + Gothic.text_width(verdict, 17)
	var x := CX - w * 0.5
	Gothic.text(_content, Vector2(x, LINES_Y + 30.0), line, 17, Gothic.BONE)
	Gothic.text(_content, Vector2(x + Gothic.text_width(line, 17), LINES_Y + 30.0), verdict, 17, color)
	# 一根细条：满格是超额线，中间一道刻痕是需求
	var full := maxf(float(over), 1.0)
	_content.draw_rect(BAR.grow(1.5), Color(0, 0, 0, 0.8))
	_content.draw_rect(BAR, Color(ContractScreen.ASH, 1.0))
	var k := clampf(hold / full, 0.0, 1.0)
	if k > 0.0:
		_content.draw_rect(Rect2(BAR.position, Vector2(BAR.size.x * k, BAR.size.y)), color)
	var mx := BAR.position.x + BAR.size.x * demand / full
	_content.draw_line(Vector2(mx, BAR.position.y - 4.0), Vector2(mx, BAR.end.y + 4.0), Gothic.BONE, 1.5)
	Gothic.text(_content, Vector2(mx - Gothic.text_width("要的", 12) * 0.5, BAR.end.y + 18.0), "要的", 12, Gothic.BONE_DARK,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	Gothic.text(_content, Vector2(BAR.end.x - Gothic.text_width("超额", 12) * 0.5, BAR.end.y + 18.0), "超额", 12, Gothic.BONE_DARK,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
