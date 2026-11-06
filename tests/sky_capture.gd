extends Node
## 天气和祂发怒的截图：下雨（小雨、大雨、浮漂在远处、转头）、远处天上飞过的大鸟（几种随机样子，每种隔一会儿截几张看扇翅）、
## 黄昏供奉不够时祂发怒（四级，各截发怒前、发怒那一下、之后几个时刻）；
## 转头（2026-11-05：往左转时海面有条带）：往左、正前、往右各截一张，没雨、下雨各一组。
## 要出画面跑（不能 --headless）；截图写到 -- out=文件夹（默认 user://sky_capture）：
##   Godot_v4.6.3-stable_win64.exe --path . --resolution 1280x720 res://tests/sky_capture.tscn -- out=D:/tmp/sky
## 加 only=rain、only=birds,anger、only=look 之类只截其中几种。签约用模拟按键（和 tests/showcase.gd 一样）；不写试玩日志，契约没结束也不会写名册。

var fishing: Control
var water: WaterView
var out_dir := "user://sky_capture"
var only := ""


func _ready() -> void:
	PlayLog._failed = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out_dir = arg.substr(4)
		elif arg.begins_with("only="):
			only = arg.substr(5)
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
	await _take_opening()
	await _wait(6.0)
	fishing.set_process(false)  ## 天气、黄昏由这里摆；手和后期照样每帧同步（_process）
	fishing._birds.dismiss()
	if only == "" or "rain" in only:
		await _rain()
	if only == "" or "birds" in only:
		await _birds()
	if only == "" or "anger" in only:
		await _anger()
	if only == "" or "look" in only:
		await _look()
	get_tree().quit()


## 转头：往左看到底、正前、往右看到底（look_range 的一半），没雨、下雨各一组；每张都等云图跟上
func _look() -> void:
	var edge := deg_to_rad(fishing.look_range * 0.5)
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for rain in [0.0, 1.0]:
		for shot in [["left", -edge], ["front", 0.0], ["right", edge]]:
			water.rain = rain
			water.view = WaterView.View.IDLE
			water.yaw = shot[1]
			await _wait(2.0)
			# 整帧的 GPU 时间（毫秒），隔几帧取平均：看海面着色器改了以后贵了多少
			var gpu := 0.0
			for i in 20:
				await RenderingServer.frame_post_draw
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			print("look %s rain=%.0f gpu_ms=%.2f" % [shot[0], rain, gpu / 20.0])
			await _save("look_%s%s" % [shot[0], "_rain" if rain > 0.0 else ""])
	water.rain = 0.0
	water.yaw = 0.0
	await _wait(1.0)


func _process(_delta: float) -> void:
	if fishing and not fishing.is_processing():
		fishing._sync_presentation()


func _rain() -> void:
	for shot in [["rain_none", 0.0, WaterView.View.IDLE, 0.0], ["rain_half", 0.5, WaterView.View.IDLE, 0.0],
			["rain_full", 1.0, WaterView.View.IDLE, 0.0], ["rain_float", 1.0, WaterView.View.FLOAT, 0.0],
			["rain_look", 1.0, WaterView.View.FLOAT, -0.45]]:
		water.rain = shot[1]
		water.view = shot[2]
		water.line_ratio = 0.7
		water.yaw = shot[3]
		await _wait(2.0)  ## 云图要累积十几帧才跟上新的云量
		await _save(shot[0])
	water.rain = 0.0
	water.view = WaterView.View.IDLE
	water.yaw = 0.0
	await _wait(2.0)


## 几种随机的大鸟：领头的放到正前方（飞到一半），隔 0.35 秒截一张，看翅膀扇
func _birds() -> void:
	var rng := RandomNumberGenerator.new()
	var birds: SkyBirds = fishing._birds
	for seed in [3, 8, 21, 40, 77]:
		rng.seed = seed
		birds.launch(rng)
		birds._t = birds._duration * 0.5
		print("birds seed=%d count=%d span=%.3f period=%.2f flaps=%d glide=%.1f" % [seed, birds._birds.size(), birds._span,
			birds._period, birds._flaps, birds._glide])
		for i in 6:
			await _wait(0.35)
			await _save("birds_%d_%d" % [seed, i])
	birds.dismiss()
	await _wait(3.0)


## 祂发怒的四级：黄昏、祂出来了、船舱空着打开供奉，等祂的话写完，献上（什么也没有），截发怒前后
func _anger() -> void:
	var who: Contractor = GameState.contractor
	water.dusk = 1.0
	fishing._god.presence = 1.0
	fishing._set_hud_visible(false)
	fishing._captions.visible = false
	await _wait(1.5)
	for level in [1, 2, 3, 4]:
		who.hold.clear()
		who.failed_offerings = level - 1
		who.brands = maxi(0, who.config.brands - level + 1)
		who.status = Contractor.Status.ALIVE
		fishing._offering.open(who, fishing._rng)
		await _wait(2.8)
		await _save("anger%d_0_before" % level)
		fishing._offering.confirm()
		var t0 := Time.get_ticks_msec() / 1000.0
		for mark in [["1_erupt", 0.95], ["2_shake", 1.12], ["3_after", 1.5], ["4_settle", 2.6]]:
			await _wait(maxf(0.0, t0 + mark[1] - Time.get_ticks_msec() / 1000.0))
			await _save("anger%d_%s" % [level, mark[0]])
		fishing._offering._close()
		await _wait(1.2)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out_dir, name]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _key(keycode: int, pressed: bool, unicode := 0) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = pressed
	e.unicode = unicode
	Input.parse_input_event(e)


## 签约以后的开局恩赐（v0.23）：挑第一张收下，才天黑
func _take_opening() -> void:
	for i in 40:
		if fishing._reward.is_open:
			break
		await _wait(0.15)
	if not fishing._reward.is_open:
		return
	await _wait(0.8)
	_key(KEY_1, true)
	_key(KEY_1, false)
	await _wait(0.4)
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
