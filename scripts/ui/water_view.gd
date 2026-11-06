class_name WaterView
extends Control
## 第一人称钓鱼画面的 2D 部分：冥海夜景（shaders/sea_scene.gdshader）、船头、鲸油灯、浮漂、水纹、水花、鱼线。
## 手和鱼竿是 3D 三渲二（FirstPersonArms），叠在这一层上面。
## 船的运动不是另编的正弦：GDScript 用和着色器同一套涌浪参数，在船头、船尾、左右舷取样海面高度算出来，
## 所以船是真的骑在画面里的浪上。浮漂和入水点也落在同一个海面上。
## 人坐在船上会本能地稳住视线：横摇和俯仰有 VIEW_STABILIZATION 这一部分由视线（整个海面）承担，
## 剩下的由船身贴图自己晃出来；船身怎么晃，贴图底边都不会露进画面。
## 船一直在往前漂（_travel）：海面、雾、云都按世界坐标画，礁石沿航路确定性地摆好，
## 由远及近从雾里显出来、从两侧退出画面。
## 状态由 FishingView 每帧写入。

signal press_changed(down: bool)

enum View { IDLE, FLOAT, REELING }

const SCENE_SHADER := preload("res://shaders/sea_scene.gdshader")
const CLOUD_SHADER := preload("res://shaders/sky_clouds.gdshader")
const BOAT_SHADER := preload("res://shaders/boat.gdshader")
const BOAT_TEXTURE := preload("res://assets/textures/boat_bow.png")
const CLOUD_SCALE := 3      ## 云单独画在 1/CLOUD_SCALE 分辨率的离屏图上（云是软的，看不出来），省下的算力用来多步进
const MAX_CLOUD_WIDTH := 640.0
const CLOUD_HISTORY := 0.92 ## 云图每帧里上一帧占多少：相当于把最近十几帧的样本平均起来，云边不再闪噪点

## —— 相机（着色器用同样的投影）——
const HORIZON := 0.12       ## 船平稳时地平线的位置（屏幕坐标：中心为 0、向下为正，单位为屏幕高度）
const FOCAL := 1.3
const CAM_HEIGHT := 1.55    ## 眼睛离水面的高度（米）
const MOON_POS := Vector2(-0.3, -0.25)  ## 船平稳时月亮在屏幕上的位置（同上的屏幕坐标）
const DUSK_SUN_POS := Vector2(-0.16, -0.05)  ## 黄昏时那轮暗红日轮的位置：比月亮低，快贴到海面上
## 黑夜 → 黄昏的两组颜色（交接文档 §3.2、设计对照文档 3.2 第 17 条）：同一个场景只换颜色。
## 每项是 [uniform 名, 黑夜（着色器里的默认值）, 黄昏]；SCENE 给海面和云两个材质，其余各给一个
const DUSK_SHARED := [
	["sky_top", Color(0.07, 0.1, 0.115), Color(0.1, 0.035, 0.035)],
	["fog_dark", Color(0.2, 0.27, 0.29), Color(0.2, 0.08, 0.065)],
	["moon_color", Color(0.86, 0.93, 0.92), Color(1.0, 0.3, 0.13)],
]
const DUSK_SEA := [
	["fog_light", Color(0.62, 0.69, 0.69), Color(0.42, 0.19, 0.13)],
	["water_scatter", Color(0.03, 0.2, 0.25), Color(0.12, 0.07, 0.06)],
	["water_deep", Color(0.004, 0.03, 0.05), Color(0.02, 0.008, 0.01)],
	["foam_color", Color(0.74, 0.81, 0.8), Color(0.7, 0.46, 0.38)],
]
const DUSK_BOAT := [
	["ambient", Color(0.4, 0.48, 0.5), Color(0.42, 0.25, 0.21)],
	["fog_color", Color(0.36, 0.44, 0.46), Color(0.34, 0.16, 0.12)],
]
## 云图覆盖的范围：船平稳时屏幕 UV 的 x、y、宽、高，下沿正好是地平线。云图不跟船晃，四周要多留：
## 正常海况下地平线最多偏 0.093 个屏幕高、横摇最多 0.028 弧度，屏幕的四个角都还落在这里面
const CLOUD_RECT := Vector4(-0.02, -0.14, 1.04, 0.64 + HORIZON)
## 涌浪：[传播方向（弧度，0 = 向右，-π/2 = 朝镜头）, 波长（米）, 振幅（米）, 相位]
## 角频率按深水色散 ω = √(g·k) 算，长浪走得快
const SWELLS := [
	[-1.25, 46.0, 0.34, 0.0],
	[-1.62, 29.0, 0.2, 1.7],
	[-0.92, 18.0, 0.12, 4.1],
	[-2.05, 11.0, 0.065, 2.6],
	[-1.38, 7.0, 0.035, 5.3],
]
const STOKES := 3.0         ## 二阶斯托克斯波的放大：浪尖更尖、浪谷更平
const GRAVITY := 9.81
## 船身取样点（米，相机为原点，x 右、z 前）：船头、船尾、左舷、右舷
const PROBE_BOW := Vector2(0.0, 3.4)
const PROBE_STERN := Vector2(0.0, -0.8)
const PROBE_PORT := Vector2(-1.15, 1.2)
const PROBE_STARBOARD := Vector2(1.15, 1.2)
const MOTION_SPRING := Vector2(0.55, 0.75)  ## 船体惯性：频率（Hz）、阻尼比
const SLAM_RATE := -0.11    ## 船头往下扎的角速度（弧度/秒）超过这个就溅水花
const VIEW_STABILIZATION := 0.55  ## 横摇、俯仰里由视线承担的比例（其余由船身贴图晃出来）
const LUNGE_PITCH := 0.13   ## lunge = 1 时船头往下压多少（弧度）
const LUNGE_HEAVE := 0.3    ## lunge = 1 时整条船往下沉多少（米）
const QUAKE_DECAY := 2.4    ## 祂发怒时那一下震动（quake）每秒退到 e^-2.4
const QUAKE_HORIZON := 0.013  ## quake = 1 时地平线上下抖多少（屏幕高）
const QUAKE_ROLL := 0.011   ## quake = 1 时视线横摇抖多少（弧度）
const BOTTOM_MARGIN := 4.0  ## 船身贴图底边至少在屏幕下沿以下多少像素
const BOAT_3D_MARGIN := Vector2(0.12, 0.2)  ## 3D 木船那一层四周多渲染的边（占屏幕宽、高的比例）：整层晃起来四角不露空
const LANTERN_SCALE_3D := 0.00226  ## 3D 木船上鲸油灯的大小 = 灯所在远近每米多少像素 × 这个（和贴图船头上的灯一样大）

const NEAR_Z := 9.0         ## line_ratio = 0 时入水点离船的距离（米）
const FAR_Z := 62.0         ## line_ratio = 1 时
const BASE_BEARING := 0.16  ## 浮漂默认落在船头右前方（x / z 的比例）
const LATERAL_SPREAD := 0.14 ## lateral = ±1 时再偏多少
const LAMP_DEPTH := 2.9     ## 船头灯离相机的距离（米），用来把灯的屏幕位置换回世界坐标
const FOG_DENSITY := 0.0264 ## 海面上的雾浓度（每米），浮漂、鱼线和着色器用同样的雾
## 下雨（rain 0~1）：雾浓多少、云多盖住多少（着色器里 cloud_coverage 默认 0.5）、哪几样颜色暗多少（rain = 1 时）
const RAIN_FOG := 0.6
const CLOUD_COVERAGE := 0.5
const RAIN_COVERAGE := 0.22
const RAIN_DIM := {"sky_top": 0.3, "moon_color": 0.45, "fog_light": 0.22, "fog_dark": 0.15}
const FOG_HEIGHT := 8.0     ## 每升高这么多米雾浓度降到 1/e：贴着海面最浓，高耸的礁石顶能从雾里探出来

## —— 航行 ——
const SAIL_SPEED := 2.0     ## 空竿时船往前漂的速度（米/秒）
const DRIFT_SPEED := 0.6    ## 下了钩就停桨，只随水慢慢漂
## —— 礁石：航路每 ROCK_CELL 米一段，每段按段号确定性地决定有没有礁石、是什么、在哪一侧 ——
const ROUTE_SEED := 1907
const ROCK_CELL := 90.0
const ROCK_CHANCE := 0.72
const ROCK_AHEAD := 720.0   ## 这么远的礁石才开始从雾里显出来（着色器在 480~700 米之间淡入）
const ROCK_BEHIND := 40.0   ## 退到身后这么远就不再画
const MAX_ROCKS := 8        ## 和着色器里 rock_a / rock_b 的长度一致
var boat_width_ratio := 1.18
var boat_screen_top := 0.66
## 用 3D 木船（Boat3D）代替船头贴图；上面两项只管贴图
var use_3d_boat := true:
	set(value):
		use_3d_boat = value
		if is_node_ready():
			_apply_boat_mode()
## 3D 木船里人坐的位置（模型坐标的 z，船头柱顶 +4.87、船尾 −4.09）：越大越靠前，船头越近
var boat_seat_z := 1.47:
	set(value):
		boat_seat_z = value
		_boat3d.seat_z = value
const SLAM_SPEED := -0.006  ## 兼容旧接口（未使用）

const LINE_COLOR := Color(0.74, 0.8, 0.8, 0.55)
const FOAM := Color(0.74, 0.8, 0.79)
const BONE := Color("d8ccb0")
const FLOAT_GLOW := Color(0.45, 1.0, 0.82)
const LAMP_COLOR := Color(1.0, 0.6, 0.27)
const FOG_TINT := Color(0.42, 0.5, 0.51)

var view := View.IDLE
var bob := 0.0            ## 浮漂下沉量（FishingView 给的像素值，这里换算成米）
var line_ratio := 0.5     ## 浮漂/入水点的远近 0（近）~ 1（远）
var lateral := 0.0        ## 入水点左右偏移 -1 ~ 1
var depth_ratio := 0.5    ## 鱼所在水层深浅
var tension := 0.0
var struggling := false
var snap_danger := 0.0
var lunge := 0.0          ## 被它往前拽（0~1，落水时更大）：船头往下压、人往前扑。走船体的弹簧，所以是被拖过去的
## 黄昏的程度：0 = 黑夜，1 = 黄昏。月亮沉下去变成一轮低垂的暗红日轮，月光路、雾、天、船上的光一起转红（FishingView 给）
var dusk := 0.0
var _applied_dusk := -1.0
## 雨多大（0~1，FishingView 按今夜的天气给）：雾更浓、云更厚更暗、近处水面起涟漪、船淋湿。雨丝是 FishingView 的 RainLayer
var rain := 0.0
var _applied_rain := -1.0
## 返回 3D 鱼竿竿尖的屏幕位置；在绘制时才调用，保证和本帧的手臂动作对齐
var rod_tip_source: Callable
var lamp_flicker := 1.0   ## 火苗亮度，给其他层（手、后期）用
## 转头：视线绕竖直轴转了多少（弧度，> 0 朝右看），FishingView 每帧给。只有 3D 木船能转，见 view_yaw()
var yaw := 0.0
## 抛竿那一刻朝哪看（弧度）：浮漂、入水点落在那个方向
var cast_yaw := 0.0

var _time := 0.0
var _roll := 0.0
var _pitch := 0.0
var _heave := 0.0
var _motion_velocity := Vector3.ZERO  ## (heave, pitch, roll) 的变化速度
var _splash := 0.0
var _quake := 0.0
var _quake_offset := Vector2.ZERO  ## 这一帧震动让地平线（屏幕高）、横摇（弧度）偏了多少，乘 QUAKE_HORIZON / QUAKE_ROLL 之前
var _motion_ready := false
var _swell_uniforms := []
var _swell_phases := PackedFloat32Array()
var _material := ShaderMaterial.new()
var _cloud_material := ShaderMaterial.new()
var _boat_material := ShaderMaterial.new()
var _scene := ColorRect.new()
var _cloud_viewports: Array[SubViewport] = []  ## 两张云图轮流画：这一帧画一张，读另一张（上一帧的）来累积
var _boat := TextureRect.new()
var _boat3d := Boat3D.new()
var _boat3d_viewport := SubViewport.new()
var _boat3d_layer := TextureRect.new()
var _layer_xform := Transform2D.IDENTITY  ## 3D 木船那一层：渲染像素 → 本节点坐标（地平线下移 + 视线横摇，和 _project 一致）
var _port_screen := PackedVector2Array()  ## 两舷船舷上沿投影到屏幕上（从近到远）
var _starboard_screen := PackedVector2Array()
var _outline_top := 0.0   ## 3D 木船轮廓最高处的屏幕 y
var _lantern := Lantern.new()
var _marker := DrawLayer.new()
var _line := DrawLayer.new()
var _spray: Array[CPUParticles2D] = []
var _boat_mask_image: Image
var _boat_row_edges: Dictionary = {}
var _boat_column_tops := PackedFloat32Array()
var _landing_side := 1.0
var _boat_xform := Transform2D.IDENTITY  ## 船身贴图本地像素 → 本节点坐标（含晃动）
var _bottom_clamp := 0.0  ## 这一帧为了不露底边往下压了多少像素（0 = 没压）
var _travel := 0.0        ## 船已经往前漂了多少米
var _speed := SAIL_SPEED
var _cloud_frame := 0     ## 云图已经累积了几帧（0 = 从头开始）
var _cloud_travel := 0.0  ## 上一帧画云图时船的位置：船瞬移了（调试、读档）就从头累积
var _cloud_yaw := 0.0     ## 上一帧云图朝的方向：云图跟着视线转，累积时按方向对回来
var _god: GodPresence     ## 黄昏时浮出来的祂，放在天和海之上、浮漂和船之下（add_god）
var _birds: SkyBirds      ## 夜里偶尔从远处天上飞过的大鸟（add_birds），在天之上、祂之下
var _rock_cells := {}     ## 段号 → 这一段的礁石（Dictionary，没有礁石为空）
var _rock_a := PackedVector4Array()
var _rock_b := PackedVector4Array()


## 只负责调用一个绘制函数的透明层，用来把浮漂、鱼线插在船的前后
class DrawLayer:
	extends Control
	var painter: Callable

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self)


func _ready() -> void:
	_boat_mask_image = BOAT_TEXTURE.get_image()
	_measure_boat_tops()
	for s in SWELLS:
		var k: float = TAU / s[1]
		var dir := Vector2.from_angle(s[0])
		_swell_uniforms.append(Vector4(dir.x * k, dir.y * k, s[2], sqrt(GRAVITY * k)))
		_swell_phases.append(s[3])

	# 云：两张离屏图轮流画（乒乓），每张里只放一个跑云着色器的色块。这一帧画的那张读另一张（上一帧的结果）来累积。
	# 不用 hint_screen_texture 读自己的上一帧：那份拷贝的 alpha 被定成 1，透过率就丢了；
	# 也不开 use_hdr_2d：开了以后 2D 按线性色彩算，source_color 的颜色会被换算，云整体变暗
	_cloud_material.shader = CLOUD_SHADER
	for i in 2:
		var viewport := SubViewport.new()
		viewport.transparent_bg = true
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var cloud_rect := ColorRect.new()
		cloud_rect.material = _cloud_material
		cloud_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		viewport.add_child(cloud_rect)
		add_child(viewport)
		_cloud_viewports.append(viewport)

	_material.shader = SCENE_SHADER
	_material.set_shader_parameter("swells", _swell_uniforms)
	_material.set_shader_parameter("swell_phase", _swell_phases)
	_material.set_shader_parameter("stokes", STOKES)
	_material.set_shader_parameter("fog_density", FOG_DENSITY)
	_material.set_shader_parameter("fog_height", FOG_HEIGHT)
	_material.set_shader_parameter("noise_tex3", _make_noise_3d())
	_material.set_shader_parameter("noise_tex2", _make_noise_2d())
	for m: ShaderMaterial in [_material, _cloud_material]:
		m.set_shader_parameter("focal", FOCAL)
		m.set_shader_parameter("base_horizon", HORIZON)
		m.set_shader_parameter("moon_pos", MOON_POS)
		m.set_shader_parameter("cloud_rect", CLOUD_RECT)
	_rock_a.resize(MAX_ROCKS)
	_rock_b.resize(MAX_ROCKS)
	_scene.material = _material
	_scene.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scene)

	_marker.painter = _draw_marker
	add_child(_marker)

	_boat.texture = BOAT_TEXTURE
	_boat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_boat.stretch_mode = TextureRect.STRETCH_SCALE
	_boat.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_boat_material.shader = BOAT_SHADER
	_boat_material.set_shader_parameter("tex_aspect", float(BOAT_TEXTURE.get_width()) / BOAT_TEXTURE.get_height())
	_boat.material = _boat_material
	_boat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_boat)
	# 3D 木船：渲染到透明 SubViewport，作为一层画在船头贴图的位置（两个只显示一个）
	_boat3d_viewport.transparent_bg = true
	_boat3d_viewport.own_world_3d = true
	_boat3d_viewport.msaa_3d = Viewport.MSAA_4X
	_boat3d.seat_z = boat_seat_z
	_boat3d_viewport.add_child(_boat3d)
	add_child(_boat3d_viewport)
	_boat3d_layer.texture = _boat3d_viewport.get_texture()
	_boat3d_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_boat3d_layer.stretch_mode = TextureRect.STRETCH_SCALE
	_boat3d_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_boat3d_layer)
	_apply_boat_mode()

	add_child(_lantern)

	for side in [-1.0, 0.0, 1.0]:  ## 左舷、船头、右舷
		var spray := _make_spray(side)
		add_child(spray)
		_spray.append(spray)

	_line.painter = _draw_line
	add_child(_line)
	# 鱼线和入水点位于船外。用船贴图的真实透明轮廓遮挡它，
	# 不能通过把入水点锁在船头前来掩盖穿插，否则收线会看起来停止。
	move_child(_line, _boat.get_index())


func _process(delta: float) -> void:
	_time += delta
	if view == View.FLOAT and absf(lateral) > 0.05:
		_landing_side = signf(BASE_BEARING + lateral * LATERAL_SPREAD)
	var target_speed := SAIL_SPEED if view == View.IDLE else DRIFT_SPEED
	_speed = lerpf(_speed, target_speed, 1.0 - exp(-delta * 0.35))
	_travel += _speed * delta
	_update_boat_motion(delta)
	_update_quake(delta)
	lamp_flicker = 0.86 + 0.08 * sin(_time * 7.3) * sin(_time * 3.1 + 1.2) + 0.06 * sin(_time * 17.9 + sin(_time * 5.0))

	if use_3d_boat:
		_layout_boat_3d()
	else:
		_layout_boat()
	_update_rocks()
	var lamp_world := _unproject(_lantern.glass_position(), LAMP_DEPTH)
	# 云图按屏幕上的真实像素算（窗口放大时不糊；canvas_items 拉伸的倍数在视口的 final transform 里），
	# 但屏幕最宽按 640 算：再大看不出区别，只是更费
	var pixels := size * get_global_transform_with_canvas().get_scale() * get_viewport().get_final_transform().get_scale()
	var cloud_scale := minf(1.0 / CLOUD_SCALE, MAX_CLOUD_WIDTH / maxf(pixels.x, 1.0))
	var cloud_size := Vector2i(maxi(1, int(pixels.x * cloud_scale * CLOUD_RECT.z)), maxi(1, int(pixels.y * cloud_scale * CLOUD_RECT.w)))
	if _cloud_viewports[0].size != cloud_size or absf(_travel - _cloud_travel) > 20.0:
		for viewport in _cloud_viewports:
			viewport.size = cloud_size
		_cloud_frame = 0
	_cloud_travel = _travel
	# 这一帧画哪张、读哪张。刚开始的几帧直接求平均（第 n 帧占 1/(n+1)），之后上一帧固定占 CLOUD_HISTORY
	var cloud_target := _cloud_viewports[_cloud_frame % 2]
	cloud_target.render_target_update_mode = SubViewport.UPDATE_ONCE
	_cloud_material.set_shader_parameter("history", _cloud_viewports[(_cloud_frame + 1) % 2].get_texture())
	_cloud_material.set_shader_parameter("frame_index", _cloud_frame % 1024)
	_cloud_material.set_shader_parameter("history_weight", minf(_cloud_frame / (_cloud_frame + 1.0), CLOUD_HISTORY))
	_cloud_material.set_shader_parameter("history_yaw", _cloud_yaw)
	_material.set_shader_parameter("cloud_tex", cloud_target.get_texture())
	_cloud_frame += 1
	for m: ShaderMaterial in [_material, _cloud_material]:
		m.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
		m.set_shader_parameter("horizon", _horizon())
		m.set_shader_parameter("roll", _world_roll())
		m.set_shader_parameter("cam_height", _cam_height())
		m.set_shader_parameter("sea_time", _time)
		m.set_shader_parameter("travel", _travel)
		m.set_shader_parameter("yaw", view_yaw())
	_cloud_yaw = view_yaw()
	_material.set_shader_parameter("lamp_pos", lamp_world)
	_material.set_shader_parameter("lamp_energy", lamp_flicker)
	if _god:
		_sync_god(cloud_target.get_texture())
	if _birds and _birds.visible:
		_sync_birds(cloud_target.get_texture())
	_boat_material.set_shader_parameter("lamp_energy", lamp_flicker)
	if use_3d_boat:
		_update_boat3d_lamp()
	if not is_equal_approx(dusk, _applied_dusk) or not is_equal_approx(rain, _applied_rain):
		_apply_dusk()


## 按 dusk 把黑夜、黄昏两组颜色插好，交给海面、云、船三个材质；月亮（日轮）的位置也跟着沉下去。
## 下雨（rain）也在这里：天、月光、雾压暗一些，雾更浓，云更厚，船淋湿
func _apply_dusk() -> void:
	_applied_dusk = dusk
	_applied_rain = rain
	var k := clampf(dusk, 0.0, 1.0)
	var wet := clampf(rain, 0.0, 1.0)
	for entry in DUSK_SHARED:
		var c: Color = entry[1].lerp(entry[2], k).darkened(RAIN_DIM.get(entry[0], 0.0) * wet)
		_material.set_shader_parameter(entry[0], c)
		_cloud_material.set_shader_parameter(entry[0], c)
	for entry in DUSK_SEA:
		_material.set_shader_parameter(entry[0], entry[1].lerp(entry[2], k).darkened(RAIN_DIM.get(entry[0], 0.0) * wet))
	for entry in DUSK_BOAT:
		_boat_material.set_shader_parameter(entry[0], entry[1].lerp(entry[2], k))
	_boat3d.set_colors(DUSK_BOAT[0][1].lerp(DUSK_BOAT[0][2], k), DUSK_BOAT[1][1].lerp(DUSK_BOAT[1][2], k))
	for m: ShaderMaterial in [_material, _cloud_material]:
		m.set_shader_parameter("moon_pos", _moon_pos())
		m.set_shader_parameter("cloud_coverage", CLOUD_COVERAGE + RAIN_COVERAGE * wet)
	_material.set_shader_parameter("rain", wet)
	_material.set_shader_parameter("fog_density", _fog_density())
	_boat3d.set_wet(wet)


## 海面上的雾浓度（每米）：下雨时更浓
func _fog_density() -> float:
	return FOG_DENSITY * (1.0 + RAIN_FOG * clampf(rain, 0.0, 1.0))


## 月亮（黄昏时是日轮）在屏幕上的位置（船平稳时）
func _moon_pos() -> Vector2:
	return MOON_POS.lerp(DUSK_SUN_POS, clampf(dusk, 0.0, 1.0))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		press_changed.emit(event.pressed)
		accept_event()


## 浮漂/入水点在画面上的位置
func water_point() -> Vector2:
	var point := _project(_water_world())
	if use_3d_boat:
		return _water_point_3d(point)
	if _boat.size.y <= 0.0 or _boat_mask_image == null:
		return point
	# 保留纵向的距离投影；靠船时沿船舷外侧水面继续拉近。
	# 只有船的实际轮廓会影响横向路径，不把整片近处水面封住。
	# 船身会晃：在船身贴图的本地坐标里找这一行的轮廓，再换回屏幕上的横坐标。
	var local := _boat_xform.affine_inverse() * point
	var approach := smoothstep(-32.0, 0.0, local.y)
	if approach <= 0.0:
		return point
	var row := clampi(int((local.y + 14.0) / _boat.size.y * _boat_mask_image.get_height()), 0, _boat_mask_image.get_height() - 1)
	var edges := _boat_edges_at_row(row)
	if edges.x < 0.0:
		return point
	var left_edge := (_boat_xform * Vector2(edges.x * _boat.size.x, local.y)).x - 22.0
	var right_edge := (_boat_xform * Vector2(edges.y * _boat.size.x, local.y)).x + 22.0
	# 已经在两侧水面上的位置保持不动；收线途中不反复切换船舷。
	if point.x <= left_edge or point.x >= right_edge:
		return point
	var landing_x := left_edge if _landing_side < 0.0 else right_edge
	point.x = lerpf(point.x, landing_x, approach)
	return point


## 船头灯玻璃的屏幕位置和闪烁，给手臂和后期用
func lamp_screen_position() -> Vector2:
	return _lantern.glass_position()


## 月亮在屏幕上的位置（0~1），给后期的月光光柱用；跟着船的俯仰、横摇、转头走
func moon_screen_uv() -> Vector2:
	var m := _moon_pos()
	var v := _to_view(Vector3(m.x / FOCAL, (HORIZON - m.y) / FOCAL, 1.0))
	var q := Vector2(v.x / v.z * FOCAL, _horizon() - v.y / v.z * FOCAL)
	var c := cos(_world_roll())
	var s := sin(_world_roll())
	var p := Vector2(c * q.x + s * q.y, -s * q.x + c * q.y)
	return p / Vector2(size.x / maxf(size.y, 1.0), 1.0) + Vector2(0.5, 0.5)


func _boat_edges_at_row(row: int) -> Vector2:
	if _boat_row_edges.has(row):
		return _boat_row_edges[row]
	var image_width := _boat_mask_image.get_width()
	var edges := Vector2(-1.0, -1.0)
	for x in image_width:
		if _boat_mask_image.get_pixel(x, row).a > 0.25:
			if edges.x < 0.0:
				edges.x = float(x) / image_width
			edges.y = float(x + 1) / image_width
	_boat_row_edges[row] = edges
	return edges


## 预先量好船贴图每一列最上面的不透明像素（船舷上沿），水花沿着它喷
func _measure_boat_tops() -> void:
	var w := _boat_mask_image.get_width()
	var h := _boat_mask_image.get_height()
	for i in 65:
		var x := clampi(int(i / 64.0 * (w - 1)), 0, w - 1)
		var top := 1.0
		for y in range(0, h, 2):
			if _boat_mask_image.get_pixel(x, y).a > 0.5:
				top = float(y) / h
				break
		_boat_column_tops.append(top)


func _boat_top_at(u: float) -> float:
	var f := clampf(u, 0.0, 1.0) * 64.0
	var i := mini(int(f), 63)
	return lerpf(_boat_column_tops[i], _boat_column_tops[i + 1], f - i)


# ---------- 海面与船的运动（与着色器一致） ----------

func _swell_height(xz: Vector2, t: float) -> float:
	var h := 0.0
	for i in _swell_uniforms.size():
		var s: Vector4 = _swell_uniforms[i]
		var k := Vector2(s.x, s.y).length()
		var th := s.x * xz.x + s.y * xz.y - s.w * t + _swell_phases[i]
		var q := 0.5 * k * s.z * STOKES
		h += s.z * (cos(th) + q * cos(2.0 * th))
	return h


## 相机坐标（x 右、z 前，相机为原点）→ 海面的世界坐标：船往前漂了多远，海面就往后挪多远
func _world_xz(xz: Vector2) -> Vector2:
	return xz + Vector2(0.0, _travel)


## 在船头、船尾、左右舷取样海面，算出船的起伏、俯仰、横摇，再用弹簧加上船体惯性
func _update_boat_motion(delta: float) -> void:
	var hb := _swell_height(_world_xz(PROBE_BOW), _time)
	var hs := _swell_height(_world_xz(PROBE_STERN), _time)
	var hp := _swell_height(_world_xz(PROBE_PORT), _time)
	var hr := _swell_height(_world_xz(PROBE_STARBOARD), _time)
	var target := Vector3(
		(hb + hs + hp + hr) * 0.25,
		atan2(hb - hs, PROBE_BOW.y - PROBE_STERN.y),
		atan2(hp - hr, PROBE_STARBOARD.x - PROBE_PORT.x))
	target += Vector3(-LUNGE_HEAVE, -LUNGE_PITCH, 0.0) * lunge
	if not _motion_ready:
		_motion_ready = true
		_heave = target.x
		_pitch = target.y
		_roll = target.z
		_splash = 3.0  ## 开场几秒内不溅水花
	var current := Vector3(_heave, _pitch, _roll)
	var w := TAU * MOTION_SPRING.x
	var steps := maxi(1, ceili(delta / 0.01))
	var dt := delta / steps
	for i in steps:
		_motion_velocity += (w * w * (target - current) - 2.0 * MOTION_SPRING.y * w * _motion_velocity) * dt
		current += _motion_velocity * dt
	_heave = current.x
	_pitch = current.y
	_roll = current.z
	# 船头往下扎得够快时，船舷和船头溅起水花
	if _motion_velocity.y < SLAM_RATE and _splash <= 0.0:
		_splash = 1.0
		for spray in _spray:
			spray.restart()
	_splash = maxf(0.0, _splash - delta * 1.2)


## 祂发怒时整个世界震一下（strength 约 0.5~1.5，越怒越大）：震的是视线，所以海、天、祂、船、浮漂一起抖，四边不露空
func quake(strength: float) -> void:
	_quake = maxf(_quake, strength)


## 震动：一阵低沉的晃（5 Hz 上下）叠一点碎抖（12 Hz 上下），越来越弱
func _update_quake(delta: float) -> void:
	_quake *= exp(-delta * QUAKE_DECAY)
	if _quake < 0.002:
		_quake = 0.0
		_quake_offset = Vector2.ZERO
		return
	var t := _time * TAU
	_quake_offset = Vector2(sin(t * 5.3) * 0.55 + sin(t * 12.7 + 1.3) * 0.45,
		sin(t * 4.6 + 0.7) * 0.55 + sin(t * 11.9 + 2.1) * 0.45) * _quake


func _horizon() -> float:
	return HORIZON + _pitch * VIEW_STABILIZATION * FOCAL + _quake_offset.x * QUAKE_HORIZON


## 视线跟着船转的那部分横摇（整个海面在屏幕上转的角度），加上震动
func _world_roll() -> float:
	return _roll * VIEW_STABILIZATION + _quake_offset.y * QUAKE_ROLL


func _cam_height() -> float:
	return CAM_HEIGHT + _heave


func _water_world() -> Vector3:
	var z := lerpf(NEAR_Z, FAR_Z, clampf(line_ratio, 0.0, 1.0))
	var x := (BASE_BEARING + lateral * LATERAL_SPREAD) * z
	# 抛竿时朝哪边看，浮漂就落在哪边（cast_yaw）
	var xz := Vector2(cos(cast_yaw) * x + sin(cast_yaw) * z, -sin(cast_yaw) * x + cos(cast_yaw) * z)
	return Vector3(xz.x, _swell_height(_world_xz(xz), _time), xz.y)


## 世界坐标（船上的 x 右、y 上、z 前，摄像机在 (0, 相机高度, 0)）→ 屏幕像素；转头先转到视线坐标
func _project(world: Vector3) -> Vector2:
	var v := _to_view(world)
	var q := Vector2(v.x * FOCAL / v.z, _horizon() - (v.y - _cam_height()) * FOCAL / v.z)
	var c := cos(_world_roll())
	var s := sin(_world_roll())
	var p := Vector2(c * q.x + s * q.y, -s * q.x + c * q.y)  ## 着色器里 q = R(roll)·p，这里反过来
	var aspect := size.x / maxf(size.y, 1.0)
	return (p / Vector2(aspect, 1.0) + Vector2(0.5, 0.5)) * size


## 屏幕像素 + 视线前方距离 z → 世界坐标（_project 的逆）
func _unproject(screen: Vector2, z: float) -> Vector3:
	var aspect := size.x / maxf(size.y, 1.0)
	var p := (screen / size - Vector2(0.5, 0.5)) * Vector2(aspect, 1.0)
	var c := cos(_world_roll())
	var s := sin(_world_roll())
	var q := Vector2(c * p.x - s * p.y, s * p.x + c * p.y)
	return _from_view(Vector3(q.x * z / FOCAL, _cam_height() + (_horizon() - q.y) * z / FOCAL, z))


## 船上的坐标 → 视线坐标（转头 yaw 以后的 x 右、z 前）
func _to_view(p: Vector3) -> Vector3:
	var a := view_yaw()
	return Vector3(cos(a) * p.x - sin(a) * p.z, p.y, sin(a) * p.x + cos(a) * p.z)


## 视线坐标 → 船上的坐标（_to_view 的逆）
func _from_view(p: Vector3) -> Vector3:
	var a := view_yaw()
	return Vector3(cos(a) * p.x + sin(a) * p.z, p.y, -sin(a) * p.x + cos(a) * p.z)


## 实际转了多少头：只有 3D 木船能转（船头贴图是一张固定的画）
func view_yaw() -> float:
	return yaw if use_3d_boat else 0.0


## 视线这一帧的横摇（弧度，含震动）、地平线（屏幕坐标，含震动）：雨丝跟着它们走
func view_roll() -> float:
	return _world_roll()


func view_horizon() -> float:
	return _horizon()


## 天上某个方向在屏幕上的像素位置。azimuth：方位角，0 = 船头正前方、> 0 偏右；elevation：地平线以上多高（都是弧度）。
## 跟着转头、地平线起伏和横摇，和天空同一个投影；转到身后去的给一个远在屏幕外的点
func sky_point(azimuth: float, elevation: float) -> Vector2:
	var a := azimuth - view_yaw()
	var dz := cos(elevation) * cos(a)
	if dz < 0.05:
		return Vector2(-1e5, -1e5)
	var q := Vector2(cos(elevation) * sin(a) * FOCAL / dz, _horizon() - sin(elevation) * FOCAL / dz)
	var c := cos(_world_roll())
	var s := sin(_world_roll())
	var p := Vector2(c * q.x + s * q.y, -s * q.x + c * q.y)
	var aspect := size.x / maxf(size.y, 1.0)
	return (p / Vector2(aspect, 1.0) + Vector2(0.5, 0.5)) * size


## 天上的大鸟放在天之上、祂之下（FishingView 建好以后交过来）
func add_birds(birds: SkyBirds) -> void:
	_birds = birds
	birds.water = self
	add_child(birds)
	move_child(birds, _scene.get_index() + 1)


## 大鸟和天空用同一个投影、同一张云图（飞进云里就被遮住一些）
func _sync_birds(clouds: Texture2D) -> void:
	var m := _birds.material as ShaderMaterial
	m.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
	m.set_shader_parameter("horizon", _horizon())
	m.set_shader_parameter("roll", _world_roll())
	m.set_shader_parameter("focal", FOCAL)
	m.set_shader_parameter("base_horizon", HORIZON)
	m.set_shader_parameter("cloud_rect", CLOUD_RECT)
	m.set_shader_parameter("cloud_tex", clouds)
	m.set_shader_parameter("rect_size", size)


## 祂放在天和海之上、浮漂和船之下（FishingView 建好以后交过来）
func add_god(god: GodPresence) -> void:
	_god = god
	add_child(god)
	move_child(god, _scene.get_index() + 1)


## 祂（原画、黑雾）和天空用同一个投影、同一张云图，雾色跟着黄昏的程度；祂的脚跟着地平线走
func _sync_god(clouds: Texture2D) -> void:
	for m: ShaderMaterial in [_god.art_material, _god.fog_material]:
		m.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))
		m.set_shader_parameter("horizon", _horizon())
		m.set_shader_parameter("roll", _world_roll())
		m.set_shader_parameter("focal", FOCAL)
		m.set_shader_parameter("base_horizon", HORIZON)
	var art := _god.art_material
	art.set_shader_parameter("cloud_rect", CLOUD_RECT)
	art.set_shader_parameter("cloud_tex", clouds)
	art.set_shader_parameter("haze_color", DUSK_SEA[0][1].lerp(DUSK_SEA[0][2], clampf(dusk, 0.0, 1.0)))
	_god.view_yaw = view_yaw()
	_god.horizon_shift = (_horizon() - HORIZON) * size.y
	_god.roll = _world_roll()


## 某个距离上每米对应多少像素
func _pixels_per_meter(z: float) -> float:
	return size.y * FOCAL / z


## 和着色器一样的雾（浓度随高度指数变稀）：从眼睛看向 dist 米外的水面，0 = 清楚，1 = 完全化进雾里
func _fog_at(dist: float) -> float:
	var y0 := maxf(_cam_height(), 0.1)
	var ray_length := sqrt(dist * dist + y0 * y0)
	var optical := _fog_density() * FOG_HEIGHT * (1.0 - exp(-y0 / FOG_HEIGHT)) * ray_length / y0
	return 1.0 - exp(-optical)


# ---------- 礁石 ----------

## 航路上第 cell 段的礁石（没有就是空字典）。只由段号决定：同一段无论什么时候经过都长一个样
func _rock_in_cell(cell: int) -> Dictionary:
	if _rock_cells.has(cell):
		return _rock_cells[cell]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(cell, ROUTE_SEED))
	var rock := {}
	if rng.randf() < ROCK_CHANCE:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var roll := rng.randf()
		var r: float
		rock.z = (cell + rng.randf_range(0.15, 0.85)) * ROCK_CELL
		rock.seed = rng.randf_range(0.0, 50.0)
		rock.angle = rng.randf_range(-0.5, 0.5)
		rock.beacon = false
		if roll < 0.42:
			# 海蚀柱：又高又瘦，有的脚下点着一盏灯
			r = rng.randf_range(7.0, 17.0)
			rock.kind = 0
			rock.h = r * rng.randf_range(4.0, 7.0)
			rock.x = side * (r * 2.2 + rng.randf_range(12.0, 110.0))
			rock.beacon = rng.randf() < 0.3
		elif roll < 0.54:
			# 海蚀拱：大多在一侧，偶尔正好横跨航路，船从拱洞底下穿过去
			r = rng.randf_range(6.0, 10.0)
			rock.kind = 1
			rock.h = r * rng.randf_range(5.0, 7.0)
			if rng.randf() < 0.35:
				rock.x = rng.randf_range(-2.0, 2.0)
				rock.angle = rng.randf_range(-0.12, 0.12)
			else:
				rock.x = side * (r * 4.6 + rng.randf_range(15.0, 90.0))
		elif roll < 0.72:
			# 崖壁：顺着航路的一长段石墙
			r = rng.randf_range(50.0, 120.0)
			rock.kind = 2
			rock.h = rng.randf_range(45.0, 105.0)
			rock.x = side * (r * 0.35 + rng.randf_range(30.0, 90.0))
			rock.angle = rng.randf_range(-0.2, 0.2)
			rock.beacon = rng.randf() < 0.3
		else:
			# 低礁：离航路近，浪在上面碎成白花
			r = rng.randf_range(5.0, 11.0)
			rock.kind = 3
			rock.h = r
			rock.x = side * (r * 2.0 + rng.randf_range(8.0, 45.0))
		rock.r = r
	_rock_cells[cell] = rock
	return rock


## 礁石沿航路方向的半长（米）：决定什么时候开始画、什么时候不再画
static func _rock_extent(rock: Dictionary) -> float:
	match int(rock.kind):
		1:
			return rock.r * 4.6
		2:
			return rock.r
		_:
			return rock.r * 2.2


## 礁石用的可平铺噪声贴图（着色器里 tnoise3 / tnoise2）：64³，每 8 个体素一格噪声，一个周期 8 格
static func _make_noise_3d() -> ImageTexture3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.frequency = 1.0 / 8.0
	noise.seed = ROUTE_SEED
	var images := noise.get_seamless_image_3d(64, 64, 64)
	var texture := ImageTexture3D.new()
	texture.create(images[0].get_format(), 64, 64, 64, false, images)
	return texture


## 256²，每 8 个像素一格噪声，一个周期 32 格
static func _make_noise_2d() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.frequency = 1.0 / 8.0
	noise.seed = ROUTE_SEED + 1
	return ImageTexture.create_from_image(noise.get_seamless_image(256, 256))


## 挑出离船最近的几处礁石写给着色器（相机坐标：x 右、z 前）
func _update_rocks() -> void:
	var near := []
	var first := floori((_travel - ROCK_BEHIND - 150.0) / ROCK_CELL)
	var last := floori((_travel + ROCK_AHEAD + 150.0) / ROCK_CELL)
	for cell in range(first, last + 1):
		var rock := _rock_in_cell(cell)
		if rock.is_empty():
			continue
		var z: float = rock.z - _travel
		var extent := _rock_extent(rock)
		if z + extent < -ROCK_BEHIND or z - extent > ROCK_AHEAD:
			continue
		near.append([maxf(z - extent, 0.0), rock])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var count := mini(near.size(), MAX_ROCKS)
	for i in MAX_ROCKS:
		if i < count:
			var rock: Dictionary = near[i][1]
			_rock_a[i] = Vector4(rock.x, rock.z - _travel, rock.r, rock.h)
			_rock_b[i] = Vector4(rock.kind, rock.seed, rock.angle, 1.0 if rock.beacon else 0.0)
		else:
			_rock_a[i] = Vector4.ZERO
			_rock_b[i] = Vector4.ZERO
	_material.set_shader_parameter("rock_count", count)
	_material.set_shader_parameter("rock_a", _rock_a)
	_material.set_shader_parameter("rock_b", _rock_b)
	for cell: int in _rock_cells.keys():
		if cell < first - 2:
			_rock_cells.erase(cell)


# ---------- 船 ----------

func _layout_boat() -> void:
	var w := size.x * boat_width_ratio
	var h := w * BOAT_TEXTURE.get_height() / BOAT_TEXTURE.get_width()
	var base := Vector2((size.x - w) * 0.5, size.y * boat_screen_top)
	# 船身自己晃出的那部分：绕人坐的位置（屏幕下沿正中）转，船头抬起时整条船往上走
	var rest := 1.0 - VIEW_STABILIZATION
	var bob := sin(_time * 1.3 + 0.5) * 1.5
	_boat.size = Vector2(w, h)
	_boat.pivot_offset = Vector2(size.x * 0.5, size.y) - base
	_boat.rotation = _roll * rest
	_boat.position = base + Vector2(sin(_time * 0.9) * 1.2, -_pitch * rest * FOCAL * size.y + bob)
	# 底边不许露出来：量出旋转后底边在屏幕左右两端的高度，不够低就整体往下压
	var xf := _boat.get_transform()
	var bottom_left := xf * Vector2(0.0, h)
	var bottom_right := xf * Vector2(w, h)
	var span := bottom_right.x - bottom_left.x
	var y_left := lerpf(bottom_left.y, bottom_right.y, (0.0 - bottom_left.x) / span)
	var y_right := lerpf(bottom_left.y, bottom_right.y, (size.x - bottom_left.x) / span)
	var gap := size.y + BOTTOM_MARGIN - minf(y_left, y_right)
	_bottom_clamp = maxf(gap, 0.0)
	if gap > 0.0:
		_boat.position.y += gap
	_boat_xform = _boat.get_transform()
	# 鲸油灯：灯架随船身，灯本身按重力摆
	_lantern.boat_xform = _boat_xform
	_lantern.post_local = Vector2(w * 0.497, h * 0.035)
	_lantern.size_scale = w / 2074.0
	_lantern.gravity_angle = -_world_roll()
	_lantern.flicker = lamp_flicker
	var lamp_uv := (_boat_xform.affine_inverse() * _lantern.glass_position()) / _boat.size
	_boat_material.set_shader_parameter("lamp_uv", lamp_uv)
	# 水花从左右船舷上沿和船头两舷交汇处喷出来
	for k in _spray.size():
		var u: float = [0.24, 0.5, 0.76][k]
		var top := _boat_top_at(u) if k != 1 else 0.2   ## 船头：两舷交汇处往下一点，别贴着灯
		_spray[k].position = _boat_xform * Vector2(u * w, top * h + 2.0)


## 船头贴图和 3D 木船只显示一个；3D 那层不用的时候也不渲染
func _apply_boat_mode() -> void:
	_boat.visible = not use_3d_boat
	_boat3d_layer.visible = use_3d_boat
	_boat3d_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if use_3d_boat else SubViewport.UPDATE_DISABLED


## 3D 木船：这一层的渲染尺寸和视角、船身自己晃的那部分、整层的 2D 变换（和 _project 一样），
## 再按投影摆好鲸油灯、水花，量好两舷在屏幕上的轮廓（鱼线贴着船走用）
func _layout_boat_3d() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	var render_size := (size * (Vector2.ONE + BOAT_3D_MARGIN * 2.0)).round()
	if Vector2(_boat3d_viewport.size) != render_size:
		_boat3d_viewport.size = Vector2i(render_size)
		_boat3d_layer.size = render_size
	_boat3d.set_view(render_size, size.y * FOCAL)
	var rest := 1.0 - VIEW_STABILIZATION
	_boat3d.set_motion(_pitch * rest, _roll * rest)
	_boat3d.set_yaw(view_yaw())
	# 渲染出来的是地平线在正中、不转的画面：整层往下移到地平线，再绕屏幕中心转视线承担的横摇
	var c := cos(_world_roll())
	var s := sin(_world_roll())
	var x_axis := Vector2(c, -s)
	var y_axis := Vector2(s, c)
	var shift := Vector2(0.0, _horizon() * size.y) - render_size * 0.5
	_layer_xform = Transform2D(x_axis, y_axis, size * 0.5 + x_axis * shift.x + y_axis * shift.y)
	_boat3d_layer.position = _layer_xform.origin
	_boat3d_layer.rotation = -_world_roll()
	_port_screen = _project_sheer(_boat3d.port_sheer)
	_starboard_screen = _project_sheer(_boat3d.starboard_sheer)
	_outline_top = size.y
	for p in _port_screen + _starboard_screen:
		_outline_top = minf(_outline_top, p.y)
	# 鲸油灯挂在船头柱顶：灯架跟着船头柱在屏幕上的朝向转，大小按远近
	var stem := _boat3d.stem_top
	var post := _boat_screen(stem)
	var up := (post - _boat_screen(stem - Vector3(0.0, 0.3, 0.0))).normalized()
	_lantern.boat_xform = Transform2D(atan2(up.x, -up.y), post)
	_lantern.post_local = Vector2.ZERO
	_lantern.size_scale = LANTERN_SCALE_3D * _pixels_per_meter(maxf(_boat3d.depth_of(stem), 0.5))
	_lantern.gravity_angle = -_world_roll()
	_lantern.flicker = lamp_flicker
	# 水花从左右船舷上沿和船头喷出来
	var z := _boat3d.seat_z + 2.0
	var points := [_boat3d.sheer_at(-1.0, z), stem - Vector3(0.0, 0.45, 0.0), _boat3d.sheer_at(1.0, z)]
	for k in _spray.size():
		_spray[k].position = _boat_screen(points[k])


## 3D 木船上一点（模型坐标）→ 本节点坐标
func _boat_screen(model_point: Vector3) -> Vector2:
	return _layer_xform * _boat3d.project(model_point)


## 船舷上沿投影到屏幕上，只要眼睛前方的部分
func _project_sheer(line: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in line:
		if _boat3d.depth_of(p) > 0.4:
			out.append(_boat_screen(p))
	return out


## 船头灯照 3D 木船：灯玻璃在屏幕上的位置退回这一层的渲染像素，再沿视线推到船头柱的远近
func _update_boat3d_lamp() -> void:
	var render_point := _layer_xform.affine_inverse() * _lantern.glass_position()
	var depth := maxf(_boat3d.depth_of(_boat3d.stem_top), 0.5)
	_boat3d.set_lamp(_boat3d.camera.project_position(render_point, depth), lamp_flicker)


## 和贴图版的 water_point 一样：靠近船时，入水点沿船舷外侧的水面拉近，不穿进船里；船的轮廓用两舷船舷上沿的投影
func _water_point_3d(point: Vector2) -> Vector2:
	var approach := smoothstep(-32.0, 0.0, point.y - _outline_top)
	if approach <= 0.0 or _port_screen.size() < 2 or _starboard_screen.size() < 2:
		return point
	var left_edge := _outline_x_at(_port_screen, point.y) - 22.0
	var right_edge := _outline_x_at(_starboard_screen, point.y) + 22.0
	if point.x <= left_edge or point.x >= right_edge:
		return point
	var landing_x := left_edge if _landing_side < 0.0 else right_edge
	point.x = lerpf(point.x, landing_x, approach)
	return point


## 折线在屏幕高度 y 处的横坐标；y 超出折线上下两头时，按最靠近的那一段延长
static func _outline_x_at(line: PackedVector2Array, y: float) -> float:
	var best := 0
	var best_gap := INF
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		if (y - a.y) * (y - b.y) <= 0.0 and not is_equal_approx(a.y, b.y):
			return lerpf(a.x, b.x, (y - a.y) / (b.y - a.y))
		var gap := minf(absf(y - a.y), absf(y - b.y))
		if gap < best_gap:
			best_gap = gap
			best = i
	var p := line[best]
	var q := line[best + 1]
	if is_equal_approx(p.y, q.y):
		return p.x
	return lerpf(p.x, q.x, (y - p.y) / (q.y - p.y))


func _make_spray(side: float) -> CPUParticles2D:
	var dot_texture := GradientTexture2D.new()
	dot_texture.width = 16
	dot_texture.height = 16
	dot_texture.fill = GradientTexture2D.FILL_RADIAL
	dot_texture.fill_from = Vector2(0.5, 0.5)
	dot_texture.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	dot_texture.gradient = g

	var p := CPUParticles2D.new()
	p.texture = dot_texture
	p.emitting = false
	p.one_shot = true
	p.amount = 34 if side == 0.0 else 54
	p.lifetime = 1.1
	p.explosiveness = 0.82
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(90, 8) if side != 0.0 else Vector2(30, 4)
	p.direction = Vector2(side * 0.45, -1.0)
	p.spread = 26.0 if side != 0.0 else 70.0
	p.initial_velocity_min = 200.0 if side != 0.0 else 120.0
	p.initial_velocity_max = 470.0 if side != 0.0 else 260.0
	p.gravity = Vector2(0, 1100)
	p.scale_amount_min = 0.3
	p.scale_amount_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(FOAM, 0.8))
	fade.set_color(1, Color(FOAM, 0.0))
	p.color_ramp = fade
	return p


# ---------- 浮漂、水纹、鱼线 ----------

func _draw_marker(layer: Control) -> void:
	if view == View.IDLE:
		return
	var world := _water_world()
	var p := water_point()
	var depth := maxf(_to_view(world).z, 1.0)  ## 视线方向上的远近（转头以后不是 world.z）
	var ppm := _pixels_per_meter(depth)
	var squash := _cam_height() / depth   ## 从高处斜看水面，圆形水纹被压扁
	var fog := _fog_at(Vector2(world.x, world.z).length())
	var clear := 1.0 - fog * 0.85
	var foam := FOAM.lerp(FOG_TINT, fog)
	if view == View.FLOAT:
		var sink := bob * 0.012 * ppm
		if absf(bob) > 3.0:
			_ripple(layer, p, 0.5 * ppm, squash, absf(bob) / 16.0 * clear, foam)
		_ripple(layer, p, 0.25 * ppm, squash, 0.25 * clear, foam)
		var top := p + Vector2(0, sink)
		var w := maxf(0.07 * ppm, 2.0)
		var h := maxf(0.22 * ppm, 5.0)
		layer.draw_rect(Rect2(top.x - w * 0.5, top.y - h, w, h), Color("5a1c14").lerp(FOG_TINT, fog * 0.8))
		# 夜光漂尖：一点幽绿的光，光比物体更能穿透雾
		layer.draw_circle(top + Vector2(0, -h), w * 3.0, Color(FLOAT_GLOW, 0.16))
		layer.draw_circle(top + Vector2(0, -h), w * 0.7, FLOAT_GLOW.lerp(Color.WHITE, 0.2))
	else:
		var strength := (1.0 if struggling else 0.35) * clear
		_ripple(layer, p, (0.7 + sin(_time * 6.0) * 0.12) * ppm, squash, strength, foam)
		if struggling:
			for i in 6:
				var a := _time * 9.0 + i * 1.3
				var drop := p + Vector2(cos(a) * 0.45, -absf(sin(a * 1.7)) * 0.6) * ppm
				layer.draw_circle(drop, maxf(0.05 * ppm, 1.5), Color(foam, 0.75 * clear))


func _ripple(layer: Control, p: Vector2, radius: float, squash: float, strength: float, color: Color) -> void:
	for i in 2:
		var r := radius * (1.0 + i * 0.6 + fmod(_time, 1.0) * 0.4)
		layer.draw_set_transform(p, -_world_roll(), Vector2(1.0, clampf(squash * 1.6, 0.08, 0.6)))
		layer.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(color, 0.4 * strength / (i + 1)), 1.5)
	layer.draw_set_transform(Vector2.ZERO)


func _draw_line(layer: Control) -> void:
	if view == View.IDLE or not rod_tip_source.is_valid():
		return
	var tip: Vector2 = rod_tip_source.call()
	var target := water_point()
	var near_color := LINE_COLOR.lerp(Color("c0392b"), clampf(snap_danger * 1.5, 0.0, 1.0))
	# 入水那一端在雾里：颜色往雾色靠、更透明
	var far_color := Color(near_color.lerp(FOG_TINT, _fog_at(_water_world().z) * 0.8), near_color.a * 0.6)
	var pts: PackedVector2Array
	if view == View.REELING and tension < 0.25:
		# 线松的时候往下垂
		var sag := (0.25 - tension) * 260.0
		var control := tip.lerp(target, 0.5) + Vector2(0, sag)
		pts = _bezier(tip, control, target, 20)
	else:
		pts = PackedVector2Array([tip, tip.lerp(target, 0.5), target])
	var colors := PackedColorArray()
	for i in pts.size():
		colors.append(near_color.lerp(far_color, float(i) / (pts.size() - 1)))
	layer.draw_polyline_colors(pts, colors, 1.2, true)


static func _bezier(a: Vector2, c: Vector2, b: Vector2, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments + 1:
		var t := float(i) / segments
		pts.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	return pts
