class_name Boat3D
extends Node3D
## 3D 木船（三渲二）：assets/models/木船2.glb，两块网格各一套贴图——装饰件（横梁、铁件的图集）、船板（平铺的木板）。
## 原件在 art_src/木船2.glb，只有颜色贴图；网格、法线、粗糙度由 tools/convert_boat.py 转出来、照着颜色画出来。
## 质感往参照图的旧木船靠，见 shaders/boat_toon.gdshader。
## WaterView 把它放进透明 SubViewport，叠在 2D 海面上：鱼线在它下面，鲸油灯和水花在它上面。
##
## 相机和海面着色器是同一个针孔投影（焦距 WaterView.FOCAL 个屏幕高）。这里只渲染"船平稳、地平线在正中"的样子：
## 地平线下移、由视线承担的那部分俯仰和横摇，由 WaterView 把整层在 2D 里平移、旋转（和海面、浮漂的投影一模一样）；
## 船身自己晃的那部分（1 − VIEW_STABILIZATION）在这里绕眼睛正下方水线上的一点转，所以船头的摆动有真的透视。
## 船的升沉不用管：人和船一起起落，相对相机不动（海面那边已经按 CAM_HEIGHT + 升沉画了）。
##
## 模型坐标：船头朝 +Z（船头柱顶在 z = 4.87），船尾在 −4.09，龙骨在 y = −0.2，船舷约 1.07，单位米，宽 3.07。

const MODEL := preload("res://assets/models/木船2.glb")
## 网格上的材质名 → 贴图名（assets/textures/boat3d_<名>_albedo / normal / roughness.png）
const PARTS := {"木船2_装饰": "trim", "木船2_船板": "planks"}
const EYE_Y := 1.62              ## 眼睛在模型里的高度（米）：坐在横梁上，比船舷高半米多。水线 = 这个减 eye_height
const SHEER_STEP := 0.12         ## 量船舷上沿时每段多长（米）
const OUTLINE_PX := 3.4          ## 外轮廓线宽（像素），和手一样（船用屏幕空间按深度找边，见 shaders/boat_outline.gdshader）

## 人坐的位置（模型坐标的 z；船头柱顶在 +4.87、船尾在 −4.09）。越大越靠前，船头越近、在画面里越大
var seat_z := 1.47:
	set(value):
		seat_z = value
		if _hull:
			_place_hull()
## 眼睛离水面多高（米），和海面着色器的相机高度一致
var eye_height := WaterView.CAM_HEIGHT
var camera := Camera3D.new()
## 每块网格一个材质（同一个着色器，贴图不同）
var materials: Array[ShaderMaterial] = []
## 左舷、右舷船舷上沿（模型坐标），从船尾到船头；WaterView 投影到屏幕上，算鱼线和水花贴着船的哪里
var port_sheer := PackedVector3Array()
var starboard_sheer := PackedVector3Array()
## 船头柱顶：挂鲸油灯的地方（模型坐标）
var stem_top := Vector3(0.0, 1.68, 3.7)

var _pivot := Node3D.new()
var _hull: Node3D


func _ready() -> void:
	camera.near = 0.05
	camera.far = 40.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(camera)
	camera.make_current()
	add_child(_pivot)
	_add_outline()
	var by_part := {}
	for part: String in PARTS.values():
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/boat_toon.gdshader")
		for map in ["albedo", "normal", "roughness"]:
			m.set_shader_parameter(map + "_texture", load("res://assets/textures/boat3d_%s_%s.png" % [part, map]))
		by_part[part] = m
		materials.append(m)
	_hull = MODEL.instantiate()
	_pivot.add_child(_hull)
	var verts := PackedVector3Array()
	for mesh: MeshInstance3D in _hull.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface)
			var part: String = PARTS.get(source.resource_name if source else "", "planks")
			mesh.set_surface_override_material(surface, by_part[part])
			var arrays := mesh.mesh.surface_get_arrays(surface)
			if not arrays.is_empty():
				verts.append_array(arrays[Mesh.ARRAY_VERTEX])
	_measure(verts)
	_place_hull()


## 外轮廓：相机前一块铺满画面的面片，按深度找边描黑（船舷、横梁是有厚度的方木，手那种反转外壳描不出来）
func _add_outline() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var outline := ShaderMaterial.new()
	outline.shader = preload("res://shaders/boat_outline.gdshader")
	outline.set_shader_parameter("outline_px", OUTLINE_PX)
	var sheet := MeshInstance3D.new()
	sheet.mesh = quad
	sheet.material_override = outline
	sheet.extra_cull_margin = 16384.0  ## 顶点着色器直接铺满画面，别按它原本的位置剔掉
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(sheet)


## 渲染尺寸和焦距（像素）：竖直视角按焦距换算，所以多渲染出来的那圈边不会改变船的大小
func set_view(render_size: Vector2, focal_px: float) -> void:
	camera.fov = rad_to_deg(2.0 * atan(render_size.y * 0.5 / focal_px))


## 船身自己晃的那部分（弧度）：pitch > 0 船头抬起，roll > 0 左舷抬起（和 WaterView 的 _pitch、_roll 同号）
func set_motion(pitch: float, roll: float) -> void:
	_pivot.basis = Basis.from_euler(Vector3(pitch, 0.0, -roll))


## 转头（弧度，> 0 朝右看）：相机绕竖直轴转，船不动
func set_yaw(a: float) -> void:
	camera.rotation.y = -a


## 船头灯的位置（相机坐标）和亮度
func set_lamp(camera_position: Vector3, energy: float) -> void:
	for m in materials:
		m.set_shader_parameter("lamp_pos", camera_position)
		m.set_shader_parameter("lamp_energy", energy)


## 月夜的环境光和雾色（黄昏时 WaterView 一起换成暗红）
func set_colors(ambient: Color, fog: Color) -> void:
	for m in materials:
		m.set_shader_parameter("light_tint", ambient)
		m.set_shader_parameter("fog_color", fog)


## 下雨淋湿多少（0~1）：木头变深、发亮
func set_wet(amount: float) -> void:
	for m in materials:
		m.set_shader_parameter("wet", amount)


## 模型坐标 → 船的坐标（摄像机在原点、没转头时朝 −Z）
func to_camera(model_point: Vector3) -> Vector3:
	return _pivot.transform * (_hull.transform * model_point)


## 模型坐标 → 这一层渲染出来的像素
func project(model_point: Vector3) -> Vector2:
	return camera.unproject_position(to_camera(model_point))


## 模型上一点在视线前方多远（米，转头以后按视线算）；在身后为负
func depth_of(model_point: Vector3) -> float:
	return -(camera.transform.affine_inverse() * to_camera(model_point)).z


## 某一舷在模型 z 处的船舷上沿（左舷 side < 0）；超出量到的范围就取两头
func sheer_at(side: float, z: float) -> Vector3:
	var line := port_sheer if side < 0.0 else starboard_sheer
	if line.is_empty():
		return Vector3(0.0, EYE_Y - 0.4, z)
	if z <= line[0].z:
		return line[0]
	for i in range(1, line.size()):
		if z <= line[i].z:
			return line[i - 1].lerp(line[i], inverse_lerp(line[i - 1].z, line[i].z, z))
	return line[line.size() - 1]


## 眼睛在模型里的位置
func eye() -> Vector3:
	return Vector3(0.0, EYE_Y, seat_z)


## 把船摆到相机前：船头转向 −Z；船身自己晃的支点（_pivot）在眼睛正下方的水线上
func _place_hull() -> void:
	_pivot.position = Vector3(0.0, -eye_height, 0.0)
	var flip := Basis(Vector3.UP, PI)
	_hull.transform = Transform3D(flip, flip * -Vector3(0.0, EYE_Y - eye_height, seat_z))


## 从网格量出两舷船舷上沿（每 SHEER_STEP 一段，取这一段里最靠外的宽度和最高的高度）和船头柱顶。
## 转过来以后模型的 +X 在左边，所以 +X 一侧是左舷
func _measure(verts: PackedVector3Array) -> void:
	if verts.is_empty():
		return
	var lo := INF
	var hi := -INF
	var top := -INF
	for v in verts:
		lo = minf(lo, v.z)
		hi = maxf(hi, v.z)
		if v.y > top:
			top = v.y
			stem_top = v
	var n := ceili((hi - lo) / SHEER_STEP)
	var width := [PackedFloat32Array(), PackedFloat32Array()]
	var height := [PackedFloat32Array(), PackedFloat32Array()]
	for side in 2:
		width[side].resize(n)
		width[side].fill(0.0)
		height[side].resize(n)
		height[side].fill(-INF)
	for v in verts:
		var i := clampi(int((v.z - lo) / SHEER_STEP), 0, n - 1)
		var side := 0 if v.x >= 0.0 else 1
		width[side][i] = maxf(width[side][i], absf(v.x))
		height[side][i] = maxf(height[side][i], v.y)
	for i in n:
		var z := lo + (i + 0.5) * SHEER_STEP
		if height[0][i] > -INF:
			port_sheer.append(Vector3(width[0][i], height[0][i], z))
		if height[1][i] > -INF:
			starboard_sheer.append(Vector3(-width[1][i], height[1][i], z))
