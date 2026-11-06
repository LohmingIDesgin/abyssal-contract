extends Control
## 船随浪晃动的自检：长时间模拟海浪，每一帧检查船身贴图的底边都在屏幕下沿以下。
## 3D 木船：整层晃起来屏幕下面两个角始终在渲染出来的画面里；入水点从远到近、从左到右都不会落进船的轮廓里。
## 命令行运行：
##   Godot_v4.6.3-stable_win64.exe --headless --path . res://tests/test_boat_motion.tscn

const DT := 1.0 / 30.0

var _failures := 0


func _ready() -> void:
	# 无头模式下根节点没有尺寸，直接给一块 1280×720 的画面
	size = Vector2(1280, 720)
	var water := WaterView.new()
	add_child(water)
	water.size = size
	await get_tree().process_frame
	await get_tree().process_frame
	water.set_process(false)
	print("船随浪晃动（画面 %s）" % [water.size])
	_run(water, "正常海况，你调好的船（宽 1.18，顶 0.66）", 1.0, 1.18, 0.66, 300.0)
	_run(water, "三倍浪高（压力测试）", 3.0, 1.18, 0.66, 200.0)
	_run(water, "三倍浪高 + 更小的船（宽 1.0）", 3.0, 1.0, 0.66, 200.0)
	_run_3d(water, "3D 木船：正常海况", 1.0, 300.0)
	_run_3d(water, "3D 木船：三倍浪高（压力测试）", 3.0, 200.0)
	_check_water_point_3d(water)
	print("\n==== %s（失败 %d 项）====" % ["全部通过" if _failures == 0 else "存在失败", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	print(("  [OK]   " if cond else "  [FAIL] ") + msg)
	if not cond:
		_failures += 1


func _run(water: WaterView, title: String, wave_scale: float, width: float, top: float, seconds: float) -> void:
	print(title)
	water.boat_width_ratio = width
	water.boat_screen_top = top
	var original: Array = water._swell_uniforms.duplicate()
	for i in water._swell_uniforms.size():
		var sw: Vector4 = original[i]
		water._swell_uniforms[i] = Vector4(sw.x, sw.y, sw.z * wave_scale, sw.w)
	water._time = 0.0
	water._motion_ready = false
	water._motion_velocity = Vector3.ZERO
	var min_margin := INF
	var max_tilt := 0.0
	var max_lift := 0.0
	var clamped := 0
	var frames := int(seconds / DT)
	for f in frames:
		water._time += DT
		water._travel += WaterView.SAIL_SPEED * DT   ## 船一直往前漂：迎着浪走，晃得比停着时更勤
		water._update_boat_motion(DT)
		water._layout_boat()
		var h := water._boat.size.y
		var w := water._boat.size.x
		var bl := water._boat_xform * Vector2(0.0, h)
		var br := water._boat_xform * Vector2(w, h)
		var y_left := lerpf(bl.y, br.y, (0.0 - bl.x) / (br.x - bl.x))
		var y_right := lerpf(bl.y, br.y, (water.size.x - bl.x) / (br.x - bl.x))
		min_margin = minf(min_margin, minf(y_left, y_right) - water.size.y)
		max_tilt = maxf(max_tilt, absf(water._boat.rotation))
		max_lift = maxf(max_lift, absf(water._boat.position.y - water.size.y * top))
		if water._bottom_clamp > 0.0:
			clamped += 1
	for i in original.size():
		water._swell_uniforms[i] = original[i]
	print("    船身最大倾斜 %.2f°，最大上下移动 %.1f 像素；底边离屏幕下沿最近 %.1f 像素；需要往下压的帧 %d / %d" % [
		rad_to_deg(max_tilt), max_lift, min_margin, clamped, frames])
	_check(min_margin >= WaterView.BOTTOM_MARGIN - 0.01, "底边始终没有露出来")
	if wave_scale == 1.0:
		_check(rad_to_deg(max_tilt) > 0.5, "船身看得出在随浪晃")
		_check(clamped == 0, "正常海况不需要靠强行下压来藏底边")


## 3D 木船那一层：渲染的时候四周多留了边（WaterView.BOAT_3D_MARGIN），整层下移、转动以后，
## 屏幕下面两个角要始终落在渲染出来的画面里（上面是天，露空也看不出来）
func _run_3d(water: WaterView, title: String, wave_scale: float, seconds: float) -> void:
	print(title)
	var original: Array = water._swell_uniforms.duplicate()
	for i in water._swell_uniforms.size():
		var sw: Vector4 = original[i]
		water._swell_uniforms[i] = Vector4(sw.x, sw.y, sw.z * wave_scale, sw.w)
	water._time = 0.0
	water._motion_ready = false
	water._motion_velocity = Vector3.ZERO
	var min_cover := INF
	var bow_lo := INF
	var bow_hi := -INF
	var frames := int(seconds / DT)
	for f in frames:
		water._time += DT
		water._travel += WaterView.SAIL_SPEED * DT
		water._update_boat_motion(DT)
		water._layout_boat_3d()
		var inv := water._layer_xform.affine_inverse()
		var render := Vector2(water._boat3d_viewport.size)
		for corner in [Vector2(0.0, water.size.y), water.size]:
			var p: Vector2 = inv * corner
			min_cover = minf(min_cover, minf(minf(p.x, p.y), minf(render.x - p.x, render.y - p.y)))
		var post := water._boat_screen(water._boat3d.stem_top)
		bow_lo = minf(bow_lo, post.y)
		bow_hi = maxf(bow_hi, post.y)
	for i in original.size():
		water._swell_uniforms[i] = original[i]
	print("    屏幕下角离渲染画面的边最近 %.1f 像素；船头柱顶上下摆动 %.1f 像素" % [min_cover, bow_hi - bow_lo])
	_check(min_cover > 0.0, "屏幕下面两个角始终在渲染出来的画面里")
	if wave_scale == 1.0:
		_check(bow_hi - bow_lo > 4.0, "船头看得出在随浪晃")


## 浮漂、入水点从远到近、从左到右，都贴着船舷外侧，不会落进 3D 木船的轮廓里；朝左、正前、朝右看着抛竿都一样
func _check_water_point_3d(water: WaterView) -> void:
	print("3D 木船：入水点贴着船舷外侧（转头 ±30° 也一样）")
	var inside := 0
	var total := 0
	for look in [-0.52, 0.0, 0.52]:
		water.yaw = look
		water.cast_yaw = look
		water._update_boat_motion(DT)
		water._layout_boat_3d()
		if water._port_screen.size() < 2 or water._starboard_screen.size() < 2:
			_check(false, "量出了两舷船舷上沿（转头 %.2f）" % look)
			continue
		for lateral in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			for i in 21:
				water.lateral = lateral
				water.line_ratio = i / 20.0
				var p := water.water_point()
				total += 1
				if p.y > water._outline_top:
					var left := WaterView._outline_x_at(water._port_screen, p.y)
					var right := WaterView._outline_x_at(water._starboard_screen, p.y)
					if p.x > left - 20.0 and p.x < right + 20.0:
						inside += 1
	_check(inside == 0, "入水点没有一次落进船里（%d 个位置）" % total)
	# 转头以后，投影和反投影还对得上（灯的位置、月亮都靠它）
	var worst := 0.0
	for look in [-0.52, 0.3, 0.52]:
		water.yaw = look
		for p: Vector3 in [Vector3(2.0, 0.0, 9.0), Vector3(-5.0, 1.0, 20.0), Vector3(0.5, 1.6, 3.0)]:
			var back := water._unproject(water._project(p), water._to_view(p).z)
			worst = maxf(worst, back.distance_to(p))
	_check(worst < 0.001, "转头以后投影、反投影对得上（最大误差 %.5f 米）" % worst)
	water.yaw = 0.0
	water.cast_yaw = 0.0
	water.lateral = 0.0
	water.line_ratio = 0.5
