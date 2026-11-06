class_name KeyPrompt
extends Control
## 全界面统一的文字按钮："[键] 文字"。键名古铜色、文字骨白，都带黑描边。
## 右下角的按键提示、渔获展示的四个去向、船舱里的按钮都用它，长得一样。
## 能点的：悬停时提亮、文字下面浮出一道细线，按下时往下沉一个像素；不可用时整体发灰。
## 没有快捷键的按钮只写文字（key_text 留空）。

signal pressed

const KEY_COLOR := Gothic.BRONZE_LIGHT
const LABEL_COLOR := Gothic.BONE
const HOVER_KEY := Color("e8c57c")
const HOVER_LABEL := Color("f4ebd3")
const OFF_COLOR := Color(0.5, 0.48, 0.44, 0.75)
const GAP := 6.0
const OUTLINE := 5

var key_text := "":
	set(value):
		key_text = value
		_relayout()
var label := "":
	set(value):
		label = value
		_relayout()
var font_size := 18:
	set(value):
		font_size = value
		_relayout()
var disabled := false:
	set(value):
		disabled = value
		queue_redraw()
## 文字的颜色；契约书里是蓝灰色
var label_color := LABEL_COLOR:
	set(value):
		label_color = value
		queue_redraw()
## 纯提示（不能点）时为 false
var interactive := true:
	set(value):
		interactive = value
		mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if value else Control.CURSOR_ARROW

var _hover := false
var _down := false


static func make(key: String, text: String, size := 18, clickable := true) -> KeyPrompt:
	var p := KeyPrompt.new()
	p.key_text = key
	p.label = text
	p.font_size = size
	p.interactive = clickable
	return p


func _init() -> void:
	interactive = true
	focus_mode = Control.FOCUS_NONE


func _key_string() -> String:
	return "[%s]" % key_text if key_text != "" else ""


func _text_width() -> float:
	var f := Gothic.font()
	var k := _key_string()
	var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if k != "":
		w += f.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + GAP
	return w


func _relayout() -> void:
	custom_minimum_size = Vector2(ceilf(_text_width()) + OUTLINE * 2, ceilf(font_size * 1.55))
	queue_redraw()


func _draw() -> void:
	var f := Gothic.font()
	var k := _key_string()
	var lit := interactive and _hover and not disabled
	var x := (size.x - _text_width()) * 0.5
	var baseline := (size.y + f.get_ascent(font_size) - f.get_descent(font_size)) * 0.5
	if lit and _down:
		baseline += 1.0
	var kc := OFF_COLOR if disabled else (HOVER_KEY if lit else KEY_COLOR)
	var lc := OFF_COLOR if disabled else (HOVER_LABEL if lit else label_color)
	if k != "":
		Gothic.text(self, Vector2(x, baseline), k, font_size, kc, HORIZONTAL_ALIGNMENT_LEFT, -1, OUTLINE)
		x += f.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + GAP
	Gothic.text(self, Vector2(x, baseline), label, font_size, lc, HORIZONTAL_ALIGNMENT_LEFT, -1, OUTLINE)
	if lit:
		var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var y := baseline + f.get_descent(font_size) * 0.6 + 2.0
		draw_line(Vector2(x, y + 1.0), Vector2(x + lw, y + 1.0), Color(0, 0, 0, 0.7), 3.0)
		draw_line(Vector2(x, y), Vector2(x + lw, y), HOVER_KEY, 1.5)


func _gui_input(event: InputEvent) -> void:
	if not interactive or disabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if event.pressed:
			_down = true
		elif _down:
			_down = false
			if Rect2(Vector2.ZERO, size).has_point(event.position):
				pressed.emit()
		queue_redraw()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_hover = false
			_down = false
			queue_redraw()
