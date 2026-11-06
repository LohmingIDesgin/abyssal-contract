class_name UiKit
extends RefCounted
## 原型阶段用代码搭 UI 的小工具，保证各界面风格一致。

const BG_COLOR := Color("0d1117")
const PANEL_COLOR := Color("161b22")
const ACCENT_COLOR := Color("c9b27c")
const TITLE_COLOR := Color("e8d7a8")


## 铺满父节点的背景 + 16px 边距，返回边距容器
static func backdrop(parent: Control) -> MarginContainer:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	parent.add_child(margin)
	return margin


## 创建带标题的面板，返回内部的 VBoxContainer；用 outer() 取得外层面板
static func panel(stretch: float, title: String) -> VBoxContainer:
	var container := PanelContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_stretch_ratio = stretch
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.set_corner_radius_all(6)
	container.add_theme_stylebox_override("panel", style)
	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 12)
	container.add_child(inner)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	inner.add_child(box)
	var heading := label(title, 20)
	heading.add_theme_color_override("font_color", ACCENT_COLOR)
	box.add_child(heading)
	return box


static func outer(panel_box: VBoxContainer) -> PanelContainer:
	return panel_box.get_parent().get_parent()


static func label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l
