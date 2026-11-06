@tool
extends Control
## 在 2D 编辑器中预览船的位置；游戏运行时由 WaterView 绘制。
const BOAT := preload("res://assets/textures/boat_bow.png")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	if not Engine.is_editor_hint():
		hide()
		queue_free()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var top_value = get_parent().get("boat_screen_top")
	var width_value = get_parent().get("boat_width_ratio")
	var top: float = float(top_value) if top_value != null else 0.66
	var width_ratio: float = float(width_value) if width_value != null else 1.18
	draw_rect(Rect2(Vector2.ZERO, size), Color("101c29"))
	draw_line(Vector2(0, size.y * 0.62), Vector2(size.x, size.y * 0.62), Color("344857"), 2.0)
	var width := size.x * width_ratio
	var height := width * BOAT.get_height() / BOAT.get_width()
	draw_texture_rect(BOAT, Rect2(Vector2((size.x - width) * 0.5, size.y * top), Vector2(width, height)), false, Color(0.74, 0.8, 0.9))
