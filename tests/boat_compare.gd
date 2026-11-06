extends Node
## 船头贴图和 3D 木船的对比截图：船停着、浮漂在远处、收线（线收到船边）、黄昏（祂浮出来）、
## 朝左看、朝右看几种状态，贴图船和 3D 木船各截一张（贴图船不能转头），同一个状态的两张只隔几帧。
## 要出画面跑（不能 --headless）；截图写到 -- out=文件夹（默认 user://boat_compare）：
##   Godot_v4.6.3-stable_win64.exe --path . --resolution 1280x720 res://tests/boat_compare.tscn -- out=D:/tmp/boat
## 签约用模拟按键（和 tests/showcase.gd 一样）；不写试玩日志，契约没结束也不会写名册。
## 加 raw：3D 木船只显示颜色贴图（不打光、不压暗、不描线），看贴图在模型上是什么样。
## 加 motion：再给 3D 木船在船停着时每隔 0.6 秒截一张（motion_0~5），看船和地平线一起随浪晃的方向对不对。

## 名字、浮漂状态、线放出去多远、张力、黄昏程度、转头（弧度）、祂出来到哪一步（GodPresence.presence）
const SHOTS := [
	["idle", WaterView.View.IDLE, 0.5, 0.0, 0.0, 0.0, 0.0],
	["float", WaterView.View.FLOAT, 0.75, 0.0, 0.0, 0.0, 0.0],
	["reel", WaterView.View.REELING, 0.08, 0.5, 0.0, 0.0, 0.0],
	["god_fog", WaterView.View.IDLE, 0.5, 0.0, 1.0, 0.0, 0.3],
	["god_eyes", WaterView.View.IDLE, 0.5, 0.0, 1.0, 0.0, 0.5],
	["dusk", WaterView.View.IDLE, 0.5, 0.0, 1.0, 0.0, 1.0],
	["look_left", WaterView.View.FLOAT, 0.6, 0.0, 0.0, -0.5, 0.0],
	["look_right", WaterView.View.FLOAT, 0.6, 0.0, 0.0, 0.5, 0.0],
]

var fishing: Control
var water: WaterView
var out_dir := "user://boat_compare"


func _ready() -> void:
	PlayLog._failed = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out_dir = arg.substr(4)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var main: Node = load("res://scenes/main/prototype_main.tscn").instantiate()
	add_child(main)
	fishing = main.get_node("钓鱼")
	water = fishing._water
	fishing.capture_mouse = false  ## 别把桌面上的鼠标锁进窗口
	await _wait(1.0)
	for ch in "Test":
		_key(KEY_NONE, true, ch.unicode_at(0))
		_key(KEY_NONE, false, ch.unicode_at(0))
	await _wait(0.3)
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, false)
	await _wait(6.0)
	fishing.set_process(false)  ## 状态由这里摆，FishingView 不再改；手和后期照样每帧同步（_process）
	for shot in SHOTS:
		water.view = shot[1]
		water.line_ratio = shot[2]
		water.tension = shot[3]
		water.dusk = shot[4]
		water.yaw = shot[5]
		fishing._god.presence = shot[6]
		fishing._set_hud_visible(shot[4] < 0.5)  ## 黄昏时 HUD 收起来，和游戏里一样
		await _wait(1.5)
		for use_3d in [false, true]:
			fishing.boat_3d = use_3d
			if use_3d and OS.get_cmdline_user_args().has("raw"):
				for m in water._boat3d.materials:
					_show_raw_texture(m)
			for i in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path := "%s/%s_%s.png" % [out_dir, shot[0], "3d" if use_3d else "2d"]
			get_viewport().get_texture().get_image().save_png(path)
			print("saved ", path)
	if OS.get_cmdline_user_args().has("motion"):
		water.view = WaterView.View.IDLE
		water.dusk = 0.0
		for i in 6:
			await _wait(0.6)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/motion_%d.png" % [out_dir, i])
		print("saved motion_0~5")
	get_tree().quit()


func _process(_delta: float) -> void:
	if fishing and not fishing.is_processing():
		fishing._sync_presentation()


func _show_raw_texture(m: ShaderMaterial) -> void:
	for p in [["light_tint", Color.WHITE], ["shade_tint", Vector3.ONE], ["lamp_strength", 0.0],
			["contour_width", 0.0], ["fog_max", 0.0], ["paper_strength", 0.0], ["relief_cavity", 0.0], ["ao_bottom", 1.0],
			["spec_strength", 0.0]]:
		m.set_shader_parameter(p[0], p[1])


func _key(keycode: int, pressed: bool, unicode := 0) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = pressed
	e.unicode = unicode
	Input.parse_input_event(e)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
