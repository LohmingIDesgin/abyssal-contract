class_name Compass
extends Control
## 右下角的钢壳罗盘（参照 docs/reference/ui_style.webp）：表壳、表盘、罗经花是贴图，
## 指针单独一张贴图绕轴心转，玻璃罩的反光盖在最上面。指针指向浮漂/鱼所在的方向，带一点晃动。

const DIAL_CENTER := Vector2(70, 88)   ## 表盘中心（显示单位）

var heading := 0.0   ## 指针角度（弧度，0 = 正前方/北，正值偏右）

var _time := 0.0
var _needle := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	custom_minimum_size = Gothic.tex("compass_body").get_size() * Gothic.ART_SCALE


func _process(delta: float) -> void:
	_time += delta
	var wobble := sin(_time * 1.7) * 0.06 + sin(_time * 4.3) * 0.02
	_needle = lerp_angle(_needle, heading + wobble, delta * 4.0)
	queue_redraw()


func _draw() -> void:
	var k := size.x / (Gothic.tex("compass_body").get_width() * Gothic.ART_SCALE)
	Gothic.sprite(self, "compass_body", Vector2.ZERO, k)
	var needle := Gothic.tex("compass_needle")
	var ns := needle.get_size() * Gothic.ART_SCALE * k
	draw_set_transform(DIAL_CENTER * k, _needle, Vector2.ONE)
	draw_texture_rect(needle, Rect2(-ns * 0.5, ns), false)
	draw_set_transform(Vector2.ZERO)
	Gothic.sprite(self, "compass_glass", Vector2.ZERO, k)
