class_name RainLayer
extends ColorRect
## 雨丝（shaders/rain.gdshader）：FishingView 把它叠在手和鱼竿之上、后期之下（雨也过一遍调色和泛光）。
## 雨落在世界里：转头、船晃时整片雨跟着视线走；船头灯旁边的雨丝被照成暖色。
## 雨多大（amount）由 FishingView 按今夜的天气（Weather）给，同一个数也交给 WaterView（雾、云、水面的涟漪、船淋湿）。

var amount := 0.0:
	set(value):
		amount = value
		visible = value > 0.002


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/rain.gdshader")
	material = m
	visible = false


## 每帧从 WaterView 取视线（转头、横摇、地平线）和船头灯
func sync(water: WaterView, time: float) -> void:
	if not visible:
		return
	var m := material as ShaderMaterial
	m.set_shader_parameter("amount", amount)
	m.set_shader_parameter("time", time)
	m.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	m.set_shader_parameter("yaw", water.view_yaw())
	m.set_shader_parameter("roll", water.view_roll())
	m.set_shader_parameter("horizon_shift", water.view_horizon() - WaterView.HORIZON)
	m.set_shader_parameter("focal", WaterView.FOCAL)
	m.set_shader_parameter("lamp_uv", water.lamp_screen_position() / size)
	m.set_shader_parameter("lamp_energy", water.lamp_flicker)
