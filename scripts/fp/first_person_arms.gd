class_name FirstPersonArms
extends Node3D
## 第一人称的双手和鱼竿（3D，三渲二）。由 FishingView 放进透明的 SubViewport，叠在 2D 画面上。
##
## 手臂来自 Blender 导出的 钓鱼动画.glb（右手_001 / 左手_002，各 25 根骨骼，只有前臂和手）。
## 大臂在画面外，用"虚拟肩关节 + 肘关节铰链 + 虚拟手腕"驱动整条手臂：
##   肩：上抬（绕摄像机 X）、内外摆（绕 Y）、内外旋（绕大臂轴）——带动大臂和前臂一起动
##       握竿时手臂是外展的，"前臂往上立起来"主要靠肩外旋（内旋为负）
##   肘：绕铰链轴屈伸（铰链轴 = 大臂与前臂所在平面的法线）——前臂在肩的基础上继续转
##   腕：模型没有手腕骨，五根掌骨根部重合在手腕处，一起旋转就是手腕；鱼竿挂在中指掌骨上跟着抖
## 动作分层：
##   1. 基础站位 _place_arms()：按屏幕落点摆好两只手，右手握竿
##   2. 姿势目标：各状态的基础姿势 BASE_POSES + 一次性动作 ACTIONS（Catmull-Rom 插值，速度连续）
##   3. 弹簧跟随：每个关节用阻尼弹簧追目标，肘比肩晚、腕比肘晚，带一点过冲；竿梢按惯性最后甩出
##   4. 弹簧之后叠加高频抖动（张力、挣扎），不被弹簧滤掉
## 手指姿势从 glb 自带的两段动画首尾帧采样（右手 松握→攥紧，左手 微屈伸），运行时按握力混合。

enum Action { CAST, NIBBLE, HOOK, CAUGHT, SNAPPED, SLIPPED }

const ARMS_SCENE := "res://钓鱼动画.glb"
const RIGHT := "右手_001"
const LEFT := "左手_002"
const ELBOW_BONE := 0
const FIRST_FINGER_BONE := 2  ## 0 = 肘部根骨，1 = 前臂，之后全是手指
const KNUCKLE_INDEX := "Bone.006"
const KNUCKLE_PINKY := "Bone.021"
const FIST_BONES := ["Bone.006", "Bone.007", "Bone.011", "Bone.012", "Bone.016", "Bone.017", "Bone.021", "Bone.022"]
const METACARPALS := ["Bone.002", "Bone.005", "Bone.010", "Bone.015", "Bone.020"]  ## 掌骨，根部就是手腕
const FOREARM_BONE := 1
const ROD_BONE := "Bone.010"  ## 鱼竿挂在中指掌骨上

const CAMERA_FOV := 50.0
## 月光：月亮在前方偏左的上空（与 WaterView.MOON_POS 对应），手和竿是逆光，朝镜头的一面多在暗部
const MOON_LIGHT_DIR := Vector3(-0.23, 0.28, -1.0)
const MOON_TINT := Color(0.56, 0.64, 0.68)
const LAMP_DEPTH := 2.9  ## 船头灯离镜头的距离（米），与 WaterView.LAMP_DEPTH 一致
## 手在屏幕上的落点（视口比例）、离摄像机的距离、肘部在屏幕外的方向
const RIGHT_HAND_SCREEN := Vector2(0.70, 0.76)
const RIGHT_ELBOW_SCREEN := Vector2(1.15, 1.25)
const LEFT_HAND_SCREEN := Vector2(0.42, 0.87)
const LEFT_ELBOW_SCREEN := Vector2(0.24, 1.45)
const HAND_DEPTH := 0.9
## 虚拟肩关节的位置（摄像机空间，摄像机在原点朝 -Z）
const RIGHT_SHOULDER := Vector3(0.36, -0.32, 0.09)
const LEFT_SHOULDER := Vector3(-0.36, -0.32, 0.09)
## 鱼竿静止时希望的朝向（摄像机空间）；左手指节希望的朝向
const ROD_DIRECTION := Vector3(-0.12, 1.0, -0.3)
const LEFT_KNUCKLE_DIRECTION := Vector3(1.0, 0.0, 0.2)
const ROD_BUTT_EXTRA := 0.17  ## 握点到竿尾的长度（握把要露出拳头下方一截）
## 手指各自弯成的圈：指根 / 中节 / 末节 / 指尖四个关节点。拟合出的圈心就是拳眼，竿从这里穿过
## 食指不算：原模型是握枪姿势，食指是扣扳机的形状，没有弯成圈（拟合半径是其他手指的两倍多）
const FINGER_LOOPS := [
	["Bone.011", "Bone.012", "Bone.013", "Bone.014"],
	["Bone.016", "Bone.017", "Bone.018", "Bone.019"],
	["Bone.021", "Bone.022", "Bone.023", "Bone.024"],
]
## 握点微调（手部坐标：x 沿竿往竿尖，y 沿前臂往手指，z 往掌心），默认就在拳眼正中
const ROD_GRIP_OFFSET := Vector3.ZERO
## 指骨圈心不等于皮肤围出来的握柄空间：手指前侧有指腹的厚度。
## 摆位时把竿轴沿视线往后推一点（占竿宽的比例），让前面的指腹盖住竿；之后竿跟着手骨一起动，不再每帧调整。
const GRIP_SKIN_INSET := 0.65
## 拇指额外弯曲（握枪姿势的拇指是伸直的，握竿要扣在竿上）：骨骼名 → 绕本地轴的旋转（度）
const THUMB_CURL := {"Bone.003": Vector3(40, 0, 0), "Bone.004": Vector3(32, 0, 0)}

## 关节弹簧：频率（Hz）越高跟得越紧，阻尼比越低回弹越多
const SHOULDER_SPRING := Vector2(4.0, 0.8)
const ELBOW_SPRING := Vector2(5.0, 0.55)
const WRIST_SPRING := Vector2(7.0, 0.5)
const BODY_SPRING := Vector2(3.0, 0.7)
const ELBOW_LAG := 0.05      ## 肘部读关键帧时比肩晚的秒数（近端先动、远端跟随）
const WRIST_LAG := 0.09
## 鱼竿是木杆，刚性很高：惯性只带出很小、很快的颤动，张力也只压弯一点点
const ROD_WHIP_GAIN := 0.02  ## 竿梢惯性：手的速度换算成反向弯曲的比例
const ROD_WHIP_SPRING := Vector2(9.0, 0.25)
const ROD_TENSION_BEND := 0.12  ## 满张力时竿梢弯过的弧度
const ROD_TREMBLE := Vector2(0.004, 0.014)  ## 收线时竿身微颤的幅度（弧度）：静止 / 满张力或挣扎
## 咬钩后左手握住鱼竿上半段，和右手一起拉、一起抬
## 握点在右手握点上方多远（模型单位，一个拳头约 0.1）；左肘大致朝哪边（摄像机空间，只用来决定绕竿转多少）
const LEFT_GRAB_ABOVE := 0.14
const LEFT_GRAB_ELBOW := Vector3(-0.75, -0.5, 0.55)
const LEFT_GRAB_SPRING := Vector2(3.5, 0.85)
## 左手模型自带的是张开的爪形，握竿时手指额外弯成拳（绕各指骨本地轴，度），按握竿权重生效。
## 仅用于拟合握点的初始姿势；最终指骨姿势由各自的竿身截面求解。
const LEFT_GRAB_CURL := Vector3(60, 0, 0)
## 握竿时左手腕弯的角度（度）：竿几乎是竖的，手腕不弯的话前臂只能横着摆，肘端截断面会露在画面里
const LEFT_GRAB_WRIST := 45.0
## 左手的拳眼：四指都弯成圈（左手食指不是扣扳机形状）
const LEFT_FINGER_LOOPS := [
	["Bone.006", "Bone.007", "Bone.008", "Bone.009"],
	["Bone.011", "Bone.012", "Bone.013", "Bone.014"],
	["Bone.016", "Bone.017", "Bone.018", "Bone.019"],
	["Bone.021", "Bone.022", "Bone.023", "Bone.024"],
]
## 一次性动作里左手握竿的权重曲线 [时间, 权重]；没有曲线时，收线状态下一直握着
const LEFT_GRAB_CURVES := {
	Action.HOOK: [[0.0, 0.0], [0.12, 0.0], [0.45, 1.0]],
	Action.CAUGHT: [[0.0, 1.0], [1.4, 1.0], [1.85, 0.0]],
	Action.SNAPPED: [[0.0, 1.0], [0.12, 0.0]],
	Action.SLIPPED: [[0.0, 1.0], [0.5, 0.0]],
}
const SPRING_STEP := 1.0 / 120.0

## 姿势 = [Vector4(肩上抬°, 肩内摆°, 肩内旋°, 肘屈°), 腕°]，都是相对基础站位的偏移
## 上抬为正 = 大臂抬起；内摆/内旋为正 = 朝身体中线（内旋为负 = 外旋，前臂立起来）；
## 肘屈为正 = 前臂往回收；腕为正 = 竿梢往前压（朝水面），为负 = 竿往后翘
const BASE_POSES := {
	WaterView.View.IDLE: [Vector4(0, 0, 0, 0), 0.0],
	WaterView.View.FLOAT: [Vector4(7, 3, 6, 2), 8.0],     ## 抛出去之后：肩回位、肘微微内收，竿梢朝浮漂
	WaterView.View.REELING: [Vector4(9, 0, -6, 8), 0.0],  ## 收线：竿立起来，被鱼拽时整条手臂往前送
}

## 一次性动作，叠加在当前基础姿势上。每个键 [时间(秒), 关节 Vector4, 腕°, 身体位移 Vector3]
## 抛竿在 0.7 秒出手（CastRoll.CAST_FLIGHT），之后基础姿势从 IDLE 换成 FLOAT，所以后半段是相对 FLOAT 的
const ACTIONS := {
	# 预备：竿梢往前一点 → 肩带大臂上抬、外旋把前臂立起来、肘再往回收，腕往后翘，到最高点
	# → 整条手臂打平甩出，腕最后抖出去 → 收势回到 FLOAT（肩回位、肘内收）
	Action.CAST: [
		[0.0, Vector4(0, 0, 0, 0), 0.0, Vector3.ZERO],
		[0.14, Vector4(-4, 0, 3, -4), 6.0, Vector3(0, -0.005, 0)],
		[0.4, Vector4(10, -3, -16, 6), -12.0, Vector3(0, 0.01, 0.015)],
		[0.55, Vector4(13, -5, -24, 10), -28.0, Vector3(0, 0.015, 0.03)],
		[0.63, Vector4(12, -5, -22, 10), -32.0, Vector3(0, 0.015, 0.03)],
		[0.74, Vector4(9, -3, 24, -32), 22.0, Vector3(0, 0, -0.04)],
		[0.86, Vector4(3, -2, 26, -26), 32.0, Vector3(0, -0.005, -0.045)],
		[1.15, Vector4(-1, 0, 4, -2), 6.0, Vector3(0, 0, -0.01)],
		[1.5, Vector4(0, 0, 0, 0), 0.0, Vector3.ZERO],
	],
	Action.NIBBLE: [
		[0.0, Vector4(0, 0, 0, 0), 0.0, Vector3.ZERO],
		[0.07, Vector4(-2, 0, 2, -2), 4.0, Vector3.ZERO],
		[0.3, Vector4(0, 0, 0, 0), 0.0, Vector3.ZERO],
	],
	# 提竿（相对 REELING）：从等待姿势出发，先往下送一点，再以手腕为主猛地往后翘，肩肘小幅跟上
	Action.HOOK: [
		[0.0, Vector4(-2, 3, 12, -6), 8.0, Vector3.ZERO],
		[0.06, Vector4(-5, 2, 15, -10), 14.0, Vector3(0, 0, -0.01)],
		[0.15, Vector4(1, -2, -2, 2), -30.0, Vector3(0, 0.008, 0.03)],
		[0.4, Vector4(1, 0, -2, 1), -8.0, Vector3(0, 0, 0.01)],
		[0.7, Vector4(0, 0, 0, 0), 0.0, Vector3.ZERO],
	],
	# 钓上（相对 IDLE）：把竿举高
	Action.CAUGHT: [
		[0.0, Vector4(6, 0, -5, 8), 0.0, Vector3.ZERO],
		[0.2, Vector4(5, 1, -3, 7), 2.0, Vector3.ZERO],
		[0.6, Vector4(4, -2, -5, 4), -12.0, Vector3(0, 0.008, 0.02)],
		[1.3, Vector4(3, -2, -4, 3), -9.0, Vector3(0, 0.005, 0.01)],
		[1.9, Vector4(0, 0, 0, 0), 0.0, Vector3.ZERO],
	],
	# 断线（相对 IDLE）：拉着的力突然消失，整个人往后一仰，手臂被自己的力甩上去
	Action.SNAPPED: [
		[0.0, Vector4(-4, 0, -5, -6), 10.0, Vector3(0, 0, -0.03)],
		[0.1, Vector4(14, -4, -22, 12), -30.0, Vector3(0, 0.03, 0.08)],
		[0.45, Vector4(8, -2, -10, 6), -10.0, Vector3(0, 0.01, 0.04)],
		[1.3, Vector4(0, 0, 0, 0), 0.0, Vector3.ZERO],
	],
	# 脱钩（相对 IDLE）：线一松先往上带一下，然后泄气垂下
	Action.SLIPPED: [
		[0.0, Vector4(6, 0, -5, 8), 0.0, Vector3.ZERO],
		[0.2, Vector4(9, 0, -8, 9), -8.0, Vector3.ZERO],
		[0.9, Vector4(-6, 0, 4, -8), 10.0, Vector3(0, -0.01, 0)],
		[1.6, Vector4(0, 0, 0, 0), 0.0, Vector3.ZERO],
	],
}

## —— 由 FishingView 每帧写入 ——
var view := WaterView.View.IDLE
var tension := 0.0
var struggling := false
var holding := false
var bob := 0.0
var water_target_screen := Vector2.ZERO  ## 浮漂/入水点的屏幕位置，鱼竿会弯向它
var lamp_screen := Vector2(-1000, -1000)  ## 船头灯的屏幕位置（WaterView），手朝灯的一面会被照暖
var lamp_energy := 0.0

var camera: Camera3D
var rod: FishingRod3D
var grip_offset := ROD_GRIP_OFFSET
var left_grab_above := LEFT_GRAB_ABOVE
var left_grab_elbow := LEFT_GRAB_ELBOW
var left_grab_curl := LEFT_GRAB_CURL
var left_grab_wrist := LEFT_GRAB_WRIST
var thumb_curl: Dictionary = THUMB_CURL

static var _arm_material := _make_arm_material()

var _arms: Dictionary = {}  ## side → { root, skeleton, original, home, shoulder, elbow, hand, pose_a, pose_b, springs }
var _action: Array = []
var _action_kind := -1
var _action_time := 0.0
var _time := 0.0
var _grip := 0.5
var _lean := 0.0
var _body := Spring.new(Vector3.ZERO, BODY_SPRING)
var _whip := Spring.new(Vector3.ZERO, ROD_WHIP_SPRING)
var _left_grab := Spring.new(0.0, LEFT_GRAB_SPRING)
var _tension_bend := 0.0
var _last_rod_tip := Vector3.ZERO
var _spring_time := 0.0


## 阻尼弹簧，value 可以是 float / Vector3 / Vector4
class Spring:
	var value
	var velocity
	var frequency: float
	var damping: float

	func _init(initial, params: Vector2) -> void:
		value = initial
		velocity = initial * 0.0
		frequency = params.x
		damping = params.y

	func step(target, dt: float) -> void:
		var w := TAU * frequency
		velocity += (w * w * (target - value) - 2.0 * damping * w * velocity) * dt
		value += velocity * dt


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = CAMERA_FOV
	camera.near = 0.02
	add_child(camera)
	camera.current = true

	var scene: Node3D = load(ARMS_SCENE).instantiate()
	add_child(scene)
	var player: AnimationPlayer = scene.get_node("AnimationPlayer")
	for side in [RIGHT, LEFT]:
		var root: Node3D = scene.get_node(side)
		var skeleton: Skeleton3D = root.get_node("Skeleton3D")
		_arms[side] = {
			"root": root,
			"skeleton": skeleton,
			"original": root.global_transform,
			"shoulder_spring": Spring.new(Vector3.ZERO, SHOULDER_SPRING),
			"elbow_spring": Spring.new(0.0, ELBOW_SPRING),
			"wrist_spring": Spring.new(0.0, WRIST_SPRING),
		}
		for mesh: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", false, false):
			mesh.material_override = _arm_material
	_sample_finger_poses(player, RIGHT, "右手_001Action")
	_sample_finger_poses(player, LEFT, "左手_002Action")
	player.queue_free()

	rod = FishingRod3D.new()
	rod.tint = MOON_TINT
	var hand_bone := BoneAttachment3D.new()
	hand_bone.bone_name = ROD_BONE
	_arms[RIGHT].skeleton.add_child(hand_bone)
	hand_bone.add_child(rod)

	get_viewport().size_changed.connect(_place_arms)
	_place_arms()
	_last_rod_tip = rod.straight_tip_global_position()


func play(action: Action) -> void:
	_action = ACTIONS[action]
	_action_kind = action
	_action_time = 0.0


func rod_tip_screen_position() -> Vector2:
	return camera.unproject_position(rod.tip_global_position())


func _process(delta: float) -> void:
	_time += delta
	if not _action.is_empty():
		_action_time += delta
		if _action_time >= _action[-1][0]:
			_action = []

	var targets := _pose_targets(delta)
	# 固定步长推进弹簧，帧率波动时也稳定
	_spring_time += delta
	while _spring_time >= SPRING_STEP:
		_spring_time -= SPRING_STEP
		for side in [RIGHT, LEFT]:
			var t: Vector4 = targets[side]
			_arms[side].shoulder_spring.step(Vector3(t.x, t.y, t.z), SPRING_STEP)
			_arms[side].elbow_spring.step(t.w, SPRING_STEP)
		_arms[RIGHT].wrist_spring.step(targets.wrist, SPRING_STEP)
		_body.step(targets.body, SPRING_STEP)
		_left_grab.step(targets.left_grab, SPRING_STEP)

	var shake := _tremble()
	for side in [RIGHT, LEFT]:
		var arm: Dictionary = _arms[side]
		var joints := Vector4(arm.shoulder_spring.value.x, arm.shoulder_spring.value.y,
			arm.shoulder_spring.value.z, arm.elbow_spring.value)
		if side == RIGHT:
			joints += shake
		_apply_arm(side, joints, _body.value)
	_apply_fingers(RIGHT, _grip, _arms[RIGHT].wrist_spring.value + shake.w * 0.5)
	var grab := clampf(_left_grab.value, 0.0, 1.0)
	var grab_k := smoothstep(0.0, 1.0, grab)
	_apply_fingers(LEFT, lerpf(targets.left_flex, 1.0, grab), left_grab_wrist * grab_k, left_grab_curl * grab_k)
	_straighten_left_elbow(grab_k)
	if grab > 0.001:
		_apply_left_grab(smoothstep(0.0, 1.0, grab))
	_update_rod(delta)
	_update_lamp()


# ---------- 姿势目标 ----------

func _pose_targets(delta: float) -> Dictionary:
	var right: Vector4 = BASE_POSES[view][0]
	var wrist: float = BASE_POSES[view][1]
	var left := Vector4.ZERO
	var body := Vector3.ZERO
	var left_flex := 0.5 + sin(_time * 0.9) * 0.1
	var left_grab := 1.0 if view == WaterView.View.REELING else 0.0

	if not _action.is_empty():
		# 近端先动、远端跟随：肘、腕各自晚一点读关键帧
		var shoulder_part: Array = _sample_action(_action, _action_time)
		var elbow_part: Array = _sample_action(_action, _action_time - ELBOW_LAG)
		var wrist_part: Array = _sample_action(_action, _action_time - WRIST_LAG)
		var j: Vector4 = shoulder_part[0]
		right += Vector4(j.x, j.y, j.z, elbow_part[0].w)
		wrist += wrist_part[1]
		body += shoulder_part[2]
		if _action_kind in LEFT_GRAB_CURVES:
			left_grab = _sample_curve(LEFT_GRAB_CURVES[_action_kind], _action_time)

	# 呼吸：肩和肘错开相位
	var breath := _time * 1.3
	right += Vector4(sin(breath) * 1.2, 0, 0, sin(breath + 0.6) * 1.0)
	left += Vector4(sin(breath + 0.4) * 1.0, 0, 0, sin(breath + 1.0) * 1.2)

	var target_grip := 0.45
	var target_lean := 0.0
	match view:
		WaterView.View.FLOAT:
			target_grip = 0.6
		WaterView.View.REELING:
			target_grip = 0.55 + tension * 0.45
			target_lean = tension
			if struggling:
				# 鱼往外冲的低频拉拽，走弹簧，所以手臂是被"拖"过去而不是瞬移
				right += Vector4(-4.0, sin(_time * 2.3) * 4.0, 0, -6.0) * (0.5 + 0.5 * sin(_time * 3.1))
			if holding:
				# 按住收线：双手握竿一起往回带，一下一下地拉
				var pull := maxf(0.0, sin(_time * 7.0))
				right += Vector4(pull * 3.0, 0, -pull * 2.0, pull * 5.0)

	_grip = lerpf(_grip, target_grip, delta * 8.0)
	_lean = lerpf(_lean, target_lean, delta * 4.0)
	# 被鱼拽：肘伸直、肩略往下压，整条手臂朝鱼伸出去
	right += Vector4(-_lean * 4.0, 0, _lean * 2.0, -_lean * 10.0)
	return {RIGHT: right, LEFT: left, "wrist": wrist, "body": body, "left_grab": left_grab, "left_flex": clampf(left_flex, 0.0, 1.0)}


## 高频抖动直接叠在弹簧输出上：张力越大越抖，挣扎时更凶
func _tremble() -> Vector4:
	if view != WaterView.View.REELING:
		return Vector4.ZERO
	var amount := tension * tension * 1.4 + (2.0 if struggling else 0.0)
	return Vector4(sin(_time * 29.0), sin(_time * 23.0 + 1.0), sin(_time * 33.0 + 2.0), sin(_time * 26.0 + 0.5) * 1.5) * amount


## 简单的 [时间, 值] 曲线，段间平滑插值
func _sample_curve(keys: Array, t: float) -> float:
	if t <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if t <= keys[i][0]:
			var k := smoothstep(keys[i - 1][0], keys[i][0], t)
			return lerpf(keys[i - 1][1], keys[i][1], k)
	return keys[-1][1]


## Catmull-Rom 插值：经过每个关键帧时速度连续，不会一顿一顿
func _sample_action(keys: Array, t: float) -> Array:
	if t <= keys[0][0]:
		return keys[0].slice(1)
	var last := keys.size() - 1
	if t >= keys[last][0]:
		return keys[last].slice(1)
	var i := 1
	while t > keys[i][0]:
		i += 1
	var u: float = (t - keys[i - 1][0]) / (keys[i][0] - keys[i - 1][0])
	return [_hermite(keys, i, 1, u), _hermite(keys, i, 2, u), _hermite(keys, i, 3, u)]


## 在第 i-1 和第 i 个关键帧之间插值 field 字段
func _hermite(keys: Array, i: int, field: int, u: float) -> Variant:
	var k1: Array = keys[i - 1]
	var k2: Array = keys[i]
	var span: float = k2[0] - k1[0]
	# 首尾关键帧的切线为 0，动作从静止开始、回到静止
	var m1 = k1[field] * 0.0
	var m2 = k2[field] * 0.0
	if i >= 2:
		m1 = (k2[field] - keys[i - 2][field]) / (k2[0] - keys[i - 2][0]) * span
	if i + 1 < keys.size():
		m2 = (keys[i + 1][field] - k1[field]) / (keys[i + 1][0] - k1[0]) * span
	var u2 := u * u
	var u3 := u2 * u
	return k1[field] * (2 * u3 - 3 * u2 + 1) + m1 * (u3 - 2 * u2 + u) + k2[field] * (-2 * u3 + 3 * u2) + m2 * (u3 - u2)


# ---------- 关节链 ----------

## joints = (肩上抬, 肩内摆, 肩内旋, 肘屈)；body = 身体位移（两条手臂一起动）
func _apply_arm(side: String, joints: Vector4, body: Vector3) -> void:
	var arm: Dictionary = _arms[side]
	if not arm.has("home"):
		return
	var mirror := 1.0 if side == RIGHT else -1.0  ## 左手的内摆/内旋方向相反
	var shoulder: Vector3 = arm.shoulder
	var elbow: Vector3 = arm.elbow
	var upper: Vector3 = (elbow - shoulder).normalized()
	var fore: Vector3 = (arm.hand - elbow).normalized()
	var hinge := upper.cross(fore)
	hinge = hinge.normalized() if hinge.length() > 0.05 else Vector3.RIGHT

	var elbow_xf := _rotate_about(elbow, Basis(hinge, deg_to_rad(joints.w)))
	var shoulder_basis := Basis(Vector3.UP, deg_to_rad(joints.y * mirror)) \
		* Basis(Vector3.RIGHT, deg_to_rad(joints.x)) \
		* Basis(upper, deg_to_rad(-joints.z * mirror))
	var shoulder_xf := Transform3D(Basis(), body) * _rotate_about(shoulder, shoulder_basis)
	arm.root.global_transform = shoulder_xf * elbow_xf * arm.home


## 展开左肘的模型末端，保留手腕和握点。
func _straighten_left_elbow(weight: float) -> void:
	# 根骨带着模型末端的一截肘部。展开它，保持前臂和整只手的世界姿势不变。
	var skeleton: Skeleton3D = _arms[LEFT].skeleton
	var forearm := skeleton.get_bone_global_pose(FOREARM_BONE)
	var root_pose := skeleton.get_bone_pose(ELBOW_BONE)
	var rotation := root_pose.basis.get_rotation_quaternion().slerp(
		forearm.basis.get_rotation_quaternion(), weight)
	var basis := Basis(rotation)
	var offset := skeleton.get_bone_pose_position(FOREARM_BONE)
	skeleton.set_bone_pose_rotation(ELBOW_BONE, rotation)
	skeleton.set_bone_pose_position(ELBOW_BONE, forearm.origin - basis * offset)
	skeleton.set_bone_pose_rotation(FOREARM_BONE,
		(basis.inverse() * forearm.basis).get_rotation_quaternion())


## 拳眼对准竿身；绕竿旋转使左肘朝指定方向。
func _apply_left_grab(weight: float) -> void:
	var right: Dictionary = _arms[RIGHT]
	var left: Dictionary = _arms[LEFT]
	# 直接从骨骼姿势算鱼竿的世界变换，避免挂点节点晚一帧更新
	var rod_xf: Transform3D = _bone_global(right, right.skeleton.find_bone(ROD_BONE)) * rod.transform
	var grab_point := rod_xf * Vector3(0, ROD_BUTT_EXTRA + left_grab_above, 0)  ## 竿本地原点在竿尾
	var rod_dir := rod_xf.basis.y.normalized()

	var center: Vector3 = left.grip_center_local
	var align := Quaternion(left.grip_axis_local.normalized(), rod_dir)
	var to_elbow: Vector3 = align * (left.elbow_local - center)
	var want := left_grab_elbow.normalized()
	var ep := (to_elbow - rod_dir * to_elbow.dot(rod_dir)).normalized()
	var wp := (want - rod_dir * want.dot(rod_dir)).normalized()
	var roll := atan2(ep.cross(wp).dot(rod_dir), ep.dot(wp))
	var grab_basis := Basis(Quaternion(rod_dir, roll) * align)
	var grab_xf := Transform3D(grab_basis, grab_point - grab_basis * center)
	var root: Node3D = left.root
	root.global_transform = root.global_transform.interpolate_with(grab_xf, weight)


static func _rotate_about(pivot: Vector3, basis: Basis) -> Transform3D:
	return Transform3D(Basis(), pivot) * Transform3D(basis, Vector3.ZERO) * Transform3D(Basis(), -pivot)


# ---------- 鱼竿 ----------

func _update_rod(delta: float) -> void:
	# 惯性甩动：竿梢落后于手的运动，手停下时再往前抽出去
	var tip := rod.straight_tip_global_position()
	var velocity := (tip - _last_rod_tip) / maxf(delta, 0.001)
	_last_rod_tip = tip
	var whip_steps := maxi(1, roundi(delta / SPRING_STEP))
	for i in whip_steps:
		_whip.step(-velocity * ROD_WHIP_GAIN, delta / whip_steps)

	var target_bend := 0.0
	var tremble := 0.0
	match view:
		WaterView.View.FLOAT:
			target_bend = 0.01 + maxf(0.0, bob) * 0.002
		WaterView.View.REELING:
			target_bend = minf(tension, 1.0) * ROD_TENSION_BEND
			var strain := clampf(tension, 0.0, 1.0) * (1.0 if struggling else 0.6)
			tremble = lerpf(ROD_TREMBLE.x, ROD_TREMBLE.y, strain)
	_tension_bend = lerpf(_tension_bend, target_bend, delta * 6.0)

	var toward_water := (camera.project_position(water_target_screen, 30.0) - rod.global_position).normalized()
	# 细微颤抖：几个不成倍数的高频正弦叠加，听起来像木杆在绷着的线上发颤
	var jitter := sin(_time * 47.0) * 0.6 + sin(_time * 71.0 + 1.3) * 0.4
	var bend: Vector3 = toward_water * (_tension_bend + jitter * tremble) + _whip.value
	rod.set_bend(minf(bend.length(), 0.3), bend)


# ---------- 第 1 层：基础站位 ----------

## 按屏幕落点摆放两只手；视口尺寸变化时重新计算
func _place_arms() -> void:
	var size := get_viewport().get_visible_rect().size
	for side in [RIGHT, LEFT]:
		_arms[side].root.global_transform = _arms[side].original
	_apply_fingers(RIGHT, 0.6)
	_apply_fingers(LEFT, 0.5)

	_place(RIGHT, RIGHT_HAND_SCREEN * size, RIGHT_ELBOW_SCREEN * size, ROD_DIRECTION, RIGHT_SHOULDER)
	_place(LEFT, LEFT_HAND_SCREEN * size, LEFT_ELBOW_SCREEN * size, LEFT_KNUCKLE_DIRECTION, LEFT_SHOULDER)

	_measure_left_grip()

	# 鱼竿穿过右拳眼：先按指节方向拟合各指圈的圈心，再用中指圈心 → 小指圈心的连线作为竿的轴线
	var arm: Dictionary = _arms[RIGHT]
	var knuckle_axis := (_bone_pos(arm, KNUCKLE_INDEX) - _bone_pos(arm, KNUCKLE_PINKY)).normalized()
	var loops: Array[Vector3] = []
	for chain in FINGER_LOOPS:
		loops.append(_loop_center(arm, chain, knuckle_axis))
	var up := (loops[0] - loops[-1]).normalized()
	var to_fingers: Vector3 = (arm.hand - arm.elbow)
	to_fingers = (to_fingers - up * to_fingers.dot(up)).normalized()
	var to_palm := up.cross(to_fingers)
	var loop_mid := Vector3.ZERO
	for c in loops:
		loop_mid += c / loops.size()
	var center := loop_mid + up * grip_offset.x + to_fingers * grip_offset.y + to_palm * grip_offset.z
	center += (center - camera.global_position).normalized() * rod._width * GRIP_SKIN_INSET
	var forward := up.cross(Vector3.RIGHT).normalized()
	var rod_global := Transform3D(Basis(up.cross(forward), up, forward).orthonormalized(), center - up * ROD_BUTT_EXTRA)
	rod.transform = _bone_global(arm, arm.skeleton.find_bone(ROD_BONE)).affine_inverse() * rod_global

	# 手腕轴（前臂骨本地空间）：垂直于前臂和竿，绕它转 = 竿往前压/往后翘
	var forearm_dir: Vector3 = (arm.hand - arm.elbow).normalized()
	var axis_world := up.cross(forearm_dir).normalized()
	arm.wrist_axis = (_bone_global(arm, FOREARM_BONE).basis.orthonormalized().inverse() * axis_world).normalized()


## 左手攥成拳（握竿时的手指姿势）后，拟合四个指圈得到拳眼中心和轴线，存成手臂根节点本地坐标
func _measure_left_grip() -> void:
	var arm: Dictionary = _arms[LEFT]
	arm.erase("grip_pose")
	arm.erase("grip_positions")
	arm.erase("grip_scales")
	# 手腕轴：垂直于拳眼方向（指节）和前臂，绕它转 = 手腕往小指侧/拇指侧弯
	_apply_fingers(LEFT, 1.0, 0.0, left_grab_curl)
	var knuckle := (_bone_pos(arm, KNUCKLE_INDEX) - _bone_pos(arm, KNUCKLE_PINKY)).normalized()
	var forearm_dir: Vector3 = (arm.hand - arm.elbow).normalized()
	var axis_world := knuckle.cross(forearm_dir).normalized()
	arm.wrist_axis = (_bone_global(arm, FOREARM_BONE).basis.orthonormalized().inverse() * axis_world).normalized()
	_apply_fingers(LEFT, 1.0, left_grab_wrist, left_grab_curl)
	var knuckle_axis := (_bone_pos(arm, KNUCKLE_INDEX) - _bone_pos(arm, KNUCKLE_PINKY)).normalized()
	var loops: Array[Vector3] = []
	for chain in LEFT_FINGER_LOOPS:
		loops.append(_loop_center(arm, chain, knuckle_axis))
	var center := Vector3.ZERO
	for c in loops:
		center += c / loops.size()
	# 每根手指在独立的截面内绕竿，避免本地 X 轴不同导致三根手指挤到一起。
	var skeleton: Skeleton3D = arm.skeleton
	var axis := (loops[0] - loops[-1]).normalized()
	var finger_index := 0
	for chain in LEFT_FINGER_LOOPS:
		var finger_bone := skeleton.find_bone(chain[0])
		var finger_parent := skeleton.get_bone_parent(finger_bone)
		var original_root := _bone_pos(arm, chain[0])
		# 无名指略短于中指，小指更短、更靠近无名指，不能等间距拉开。
		var finger_scale: float = [1.0, 0.90, 0.92, 0.76][finger_index]
		skeleton.set_bone_pose_scale(finger_bone, Vector3.ONE * finger_scale)
		var spacing: float = [0.0495, 0.0165, -0.014, -0.039][finger_index]
		var shift := axis * (spacing - (original_root - center).dot(axis))
		skeleton.set_bone_pose_position(finger_bone, skeleton.get_bone_pose_position(finger_bone)
			+ _bone_global(arm, finger_parent).basis.inverse() * shift)
		finger_index += 1
		var root_point := _bone_pos(arm, chain[0])
		var circle_center := center + axis * (root_point - center).dot(axis)
		var radial := root_point - circle_center
		var radius := maxf(radial.length(), rod._width * 0.5 + 0.013)
		var tangent := axis.cross(radial).normalized()
		var direction := _bone_pos(arm, chain[1]) - root_point
		var sign_value := 1.0 if tangent.dot(direction) >= 0.0 else -1.0
		var angle := 0.0
		for segment in 3:
			var bone := skeleton.find_bone(chain[segment])
			var next := skeleton.find_bone(chain[segment + 1])
			var current := _bone_pos_index(arm, bone)
			var link := _bone_pos_index(arm, next) - current
			angle += 2.0 * asin(clampf(link.length() / (2.0 * radius), 0.0, 0.95)) * sign_value
			var target := circle_center + Basis(axis, angle) * radial.normalized() * radius
			var rotation := Quaternion(link.normalized(), (target - current).normalized())
			var parent := skeleton.get_bone_parent(bone)
			var local_basis := _bone_global(arm, parent).basis.inverse() * Basis(rotation) * _bone_global(arm, bone).basis
			skeleton.set_bone_pose_rotation(bone, local_basis.orthonormalized().get_rotation_quaternion())
	var pose: Array[Quaternion] = []
	var positions: Array[Vector3] = []
	var scales: Array[Vector3] = []
	for bone in skeleton.get_bone_count():
		pose.append(skeleton.get_bone_pose_rotation(bone))
		positions.append(skeleton.get_bone_pose_position(bone))
		scales.append(skeleton.get_bone_pose_scale(bone))
	arm.grip_pose = pose
	arm.grip_positions = positions
	arm.grip_scales = scales
	var to_local: Transform3D = arm.root.global_transform.affine_inverse()
	arm.grip_center_local = to_local * center
	arm.grip_axis_local = to_local.basis * axis  ## 小指 → 食指，朝竿尖
	_apply_fingers(LEFT, 0.5)


func _place(side: String, hand_screen: Vector2, elbow_screen: Vector2, knuckle_dir: Vector3, shoulder: Vector3) -> void:
	var arm: Dictionary = _arms[side]
	var hand := _fist_center(arm)
	var elbow := _bone_pos_index(arm, ELBOW_BONE)
	var hand_target := camera.project_position(hand_screen, HAND_DEPTH)
	var elbow_hint := camera.project_position(elbow_screen, HAND_DEPTH * 0.55)
	var from := (hand - elbow).normalized()
	var to := (hand_target - elbow_hint).normalized()
	var align := Quaternion(from, to)

	# 绕前臂轴翻滚，让指节朝向 knuckle_dir
	var knuckle := align * (_bone_pos(arm, KNUCKLE_INDEX) - _bone_pos(arm, KNUCKLE_PINKY)).normalized()
	var want := knuckle_dir.normalized()
	var kp := (knuckle - to * knuckle.dot(to)).normalized()
	var wp := (want - to * want.dot(to)).normalized()
	var roll := atan2(kp.cross(wp).dot(to), kp.dot(wp))
	var rotation_basis := Basis(Quaternion(to, roll) * align)

	var root: Node3D = arm.root
	root.global_transform = Transform3D(rotation_basis, hand_target) * Transform3D(Basis(), -hand) * root.global_transform
	arm.home = root.global_transform
	arm.shoulder = shoulder
	arm.elbow = _bone_pos_index(arm, ELBOW_BONE)
	arm.hand = _fist_center(arm)
	# 手臂根节点本地空间里的肘，供左手握竿时决定绕竿转多少
	arm.elbow_local = root.global_transform.affine_inverse() * arm.elbow


# ---------- 手指 ----------

## 从 glb 动画的首尾帧采样手指姿势，pose_a = 第 0 秒，pose_b = 最后一帧
func _sample_finger_poses(player: AnimationPlayer, side: String, animation: String) -> void:
	var skeleton: Skeleton3D = _arms[side].skeleton
	var length := player.get_animation(animation).length
	for key in ["pose_a", "pose_b"]:
		player.play(animation)
		player.seek(0.0 if key == "pose_a" else length, true)
		var pose: Array[Quaternion] = []
		for i in skeleton.get_bone_count():
			pose.append(skeleton.get_bone_pose_rotation(i))
		_arms[side][key] = pose
	player.stop()


## amount：0 = pose_a，1 = pose_b；只改手指，前臂保持 pose_b 不动，避免拳头位置漂移
## wrist_deg：虚拟手腕角度，作用在五根掌骨上；curl：手指（掌骨以外）额外弯曲，绕骨骼本地轴（度）
func _apply_fingers(side: String, amount: float, wrist_deg := 0.0, curl := Vector3.ZERO) -> void:
	var arm: Dictionary = _arms[side]
	var skeleton: Skeleton3D = arm.skeleton
	var a: Array[Quaternion] = arm.pose_a
	var b: Array[Quaternion] = arm.pose_b
	var wrist := Quaternion.IDENTITY
	if side == LEFT:
		skeleton.set_bone_pose_position(ELBOW_BONE, skeleton.get_bone_rest(ELBOW_BONE).origin)
	if arm.has("wrist_axis") and wrist_deg != 0.0:
		wrist = Quaternion(arm.wrist_axis, deg_to_rad(wrist_deg))
	for i in skeleton.get_bone_count():
		if side == LEFT and i >= FIRST_FINGER_BONE:
			skeleton.set_bone_pose_position(i, skeleton.get_bone_rest(i).origin)
			skeleton.set_bone_pose_scale(i, Vector3.ONE)
		var q := b[i] if i < FIRST_FINGER_BONE else a[i].slerp(b[i], amount)
		var bone_name := skeleton.get_bone_name(i)
		if bone_name in METACARPALS:
			q = wrist * q
		elif i >= FIRST_FINGER_BONE and curl != Vector3.ZERO:
			# 指根包住竿，指尖少弯，避免每节都加 60° 后累计卷进掌心。
			var curl_weight := 0.0
			for chain in LEFT_FINGER_LOOPS:
				var segment: int = chain.find(bone_name)
				if segment >= 0:
					curl_weight = [1.0, 0.7, 0.2, 0.0][segment]
			if bone_name == "Bone.003":
				curl_weight = 1.0
			elif bone_name == "Bone.004":
				curl_weight = 0.7
			q = q * Quaternion.from_euler(curl * curl_weight * (PI / 180.0))
		if side == RIGHT and thumb_curl.has(bone_name):
			var euler: Vector3 = thumb_curl[bone_name] * (PI / 180.0)
			q = q * Quaternion.from_euler(euler)
		if side == LEFT and arm.has("grip_pose") and i >= FIRST_FINGER_BONE:
			var grip_weight := clampf(curl.x / maxf(left_grab_curl.x, 0.001), 0.0, 1.0)
			q = a[i].slerp(b[i], amount).slerp(arm.grip_pose[i], grip_weight)
			skeleton.set_bone_pose_position(i, skeleton.get_bone_rest(i).origin.lerp(arm.grip_positions[i], grip_weight))
			skeleton.set_bone_pose_scale(i, Vector3.ONE.lerp(arm.grip_scales[i], grip_weight))
		skeleton.set_bone_pose_rotation(i, q)


## 一根手指弯成的圈的圆心：把几个关节点投到垂直于 axis 的平面上，最小二乘拟合圆
func _loop_center(arm: Dictionary, chain: Array, axis: Vector3) -> Vector3:
	var u := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u)
	var origin := _bone_pos(arm, chain[0])
	# 解 [2x 2y 1]·[a b c] = x² + y²（正规方程，3×3）
	var ata := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var atb := Vector3.ZERO
	var along := 0.0
	for bone in chain:
		var rel := _bone_pos(arm, bone) - origin
		var x := rel.dot(u)
		var y := rel.dot(v)
		along += rel.dot(axis)
		var row := Vector3(2.0 * x, 2.0 * y, 1.0)
		ata.x += row * row.x
		ata.y += row * row.y
		ata.z += row * row.z
		atb += row * (x * x + y * y)
	var solved := ata.inverse() * atb
	return origin + u * solved.x + v * solved.y + axis * (along / chain.size())


func _fist_center(arm: Dictionary) -> Vector3:
	var sum := Vector3.ZERO
	for bone in FIST_BONES:
		sum += _bone_pos(arm, bone)
	return sum / FIST_BONES.size()


func _bone_pos(arm: Dictionary, bone_name: String) -> Vector3:
	return _bone_pos_index(arm, arm.skeleton.find_bone(bone_name))


func _bone_pos_index(arm: Dictionary, bone: int) -> Vector3:
	return _bone_global(arm, bone).origin


func _bone_global(arm: Dictionary, bone: int) -> Transform3D:
	var skeleton: Skeleton3D = arm.skeleton
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone)


# ---------- 材质 ----------

## 船头灯在手臂这个 3D 场景里的位置：沿屏幕上灯的位置往里推到灯的真实距离
func _update_lamp() -> void:
	_arm_material.set_shader_parameter("lamp_pos", camera.project_position(lamp_screen, LAMP_DEPTH))
	_arm_material.set_shader_parameter("lamp_energy", lamp_energy)


## 手臂材质：平涂手绘着色 + 烘焙贴图，next_pass 是描边。两只手共用（UV 相同）
static func _make_arm_material() -> ShaderMaterial:
	var outline := ShaderMaterial.new()
	outline.shader = preload("res://shaders/toon_outline.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/toon.gdshader")
	mat.set_shader_parameter("albedo_texture", preload("res://assets/textures/arm_albedo.png"))
	mat.set_shader_parameter("light_dir", MOON_LIGHT_DIR)
	mat.set_shader_parameter("light_tint", MOON_TINT)
	mat.next_pass = outline
	return mat



