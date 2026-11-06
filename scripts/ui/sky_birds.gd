class_name SkyBirds
extends ColorRect
## 夜里偶尔从远处天上飞过的大鸟（一夜最多一回，什么时候飞由 Weather 定，FishingView 调 launch）。
## 离得远，只看得见剪影，在云和流动的雾里若隐若现，看得出翅膀一下一下地扇。又大又远，所以扇得慢，扇几下滑一阵。
## 每回飞过的都不一样（launch 时随机）：一只孤零零的巨鸟、三两只、或者一小队排成人字；翅膀的长短宽窄、脖子尾巴、
## 扇的快慢、扇几下滑多久、从哪边飞到哪边、飞多高、飞多快、隔着多少雾。
## 放在 WaterView 里：天之上、祂之下（WaterView.add_birds）。鸟在天上的方向用 WaterView.sky_point 换成屏幕位置，
## 形状由 shaders/sky_birds.gdshader 按距离场画；投影参数、云图由 WaterView 每帧给（_sync_birds）。

const MAX_BIRDS := 8                 ## 和着色器里数组的长度一致
const FADE := 0.07                   ## 飞过的头尾各用这么一段淡入淡出（占全程）
const GLIDE_POSE := 0.25             ## 滑翔时翅膀平伸、微微上翘

var water: WaterView

var _flying := false
var _t := 0.0
var _duration := 45.0
var _leaving := false                ## dismiss 以后几秒内淡掉
var _fade := 1.0
var _from := Vector2.ZERO            ## 领头那只的起点、终点：(方位角, 仰角)，弧度
var _to := Vector2.ZERO
var _heading := 1.0                  ## +1 往右飞，-1 往左飞
var _span := 0.1                     ## 翼展（占屏幕高）
var _period := 2.0                   ## 扇一下几秒
var _flaps := 3                      ## 扇几下
var _glide := 2.0                    ## 再滑几秒
## 每只：offset（相对领头的方位角、仰角，弧度）、phase（扇翅错开几秒）、scale（大小）、alpha、sway（侧倾的相位）
var _birds: Array[Dictionary] = []
var _bird_a := PackedVector4Array()
var _bird_b := PackedVector4Array()
var _material := ShaderMaterial.new()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material.shader = preload("res://shaders/sky_birds.gdshader")
	material = _material
	_bird_a.resize(MAX_BIRDS)
	_bird_b.resize(MAX_BIRDS)
	visible = false


func is_flying() -> bool:
	return _flying


## 飞过一回：这一回是什么样全在这里随机定下
func launch(rng: RandomNumberGenerator) -> void:
	var kind := rng.randi_range(0, 2)  ## 0 一只巨鸟，1 三两只，2 一小队人字
	var count: int = [1, rng.randi_range(2, 3), rng.randi_range(4, 6)][kind]
	_span = [rng.randf_range(0.17, 0.27), rng.randf_range(0.09, 0.13), rng.randf_range(0.06, 0.085)][kind]
	_period = [rng.randf_range(2.8, 3.8), rng.randf_range(1.9, 2.6), rng.randf_range(1.4, 2.0)][kind]
	_duration = [rng.randf_range(55.0, 75.0), rng.randf_range(40.0, 55.0), rng.randf_range(34.0, 46.0)][kind]
	_flaps = rng.randi_range(2, 4)
	_glide = _period * rng.randf_range(0.8, 2.2)
	_heading = -1.0 if rng.randf() < 0.5 else 1.0
	var reach := deg_to_rad(rng.randf_range(60.0, 80.0))
	var elevation := deg_to_rad(rng.randf_range(7.0, 12.0) if kind == 0 else rng.randf_range(9.0, 16.0))  ## 巨鸟飞得低，贴着雾
	_from = Vector2(-_heading * reach, elevation)
	_to = Vector2(_heading * reach, elevation + deg_to_rad(rng.randf_range(-3.0, 4.0)))
	# 翅膀：内节长、翅膀宽（巨鸟的宽）、翅尖下垂、远侧那只缩到多长；身子：脖子、尾巴、头、粗细
	var chord := rng.randf_range(0.06, 0.09) if kind == 0 else rng.randf_range(0.045, 0.07)
	_material.set_shader_parameter("wing_shape", Vector4(rng.randf_range(0.14, 0.22), chord,
		rng.randf_range(0.0, 0.05), rng.randf_range(0.72, 0.95)))
	_material.set_shader_parameter("body_shape", Vector4(rng.randf_range(0.0, 0.1), rng.randf_range(0.03, 0.1),
		rng.randf_range(0.014, 0.024), rng.randf_range(0.9, 1.3)))
	_material.set_shader_parameter("haze", [rng.randf_range(0.12, 0.28), rng.randf_range(0.05, 0.18), rng.randf_range(0.05, 0.15)][kind])
	_material.set_shader_parameter("softness", 2.6 if kind == 0 else 1.6)
	var gap := _span / WaterView.FOCAL * 1.5  ## 鸟和鸟隔多远（弧度）
	_birds.clear()
	for i in count:
		var offset := Vector2.ZERO
		if kind == 1 and i > 0:
			offset = Vector2(rng.randf_range(-1.6, 1.6), rng.randf_range(-0.8, 0.8)) * gap
		elif kind == 2 and i > 0:
			var rank := (i + 1) / 2
			var side := 1.0 if i % 2 == 1 else -1.0
			offset = Vector2(-_heading * rank * 0.9, side * rank * 0.45) * gap  ## 领头的在前，后面的往两边斜排开
		_birds.append({"offset": offset, "phase": rng.randf() * _period * (0.4 if kind == 2 else 1.0),
			"scale": 1.0 if i == 0 else rng.randf_range(0.85, 1.05), "alpha": rng.randf_range(0.88, 1.0),
			"sway": rng.randf() * TAU})
	_t = 0.0
	_fade = 1.0
	_leaving = false
	_flying = true
	visible = true


## 黄昏、换人的时候：还在天上的几秒内淡掉
func dismiss() -> void:
	if _flying:
		_leaving = true


func _process(delta: float) -> void:
	if not _flying or water == null:
		return
	_t += delta
	if _leaving:
		_fade -= delta / 2.5
	var k := _t / _duration
	if k >= 1.0 or _fade <= 0.0:
		_flying = false
		visible = false
		return
	var show := smoothstep(0.0, FADE, k) * (1.0 - smoothstep(1.0 - FADE, 1.0, k)) * _fade
	var lead := _from.lerp(_to, k) + Vector2(0.0, sin(_t * 0.23) * 0.006)  ## 飞着飞着慢慢起伏
	var count := mini(_birds.size(), MAX_BIRDS)
	for i in count:
		var b: Dictionary = _birds[i]
		var dir: Vector2 = lead + b.offset
		var pos := water.sky_point(dir.x, dir.y)
		var t: float = _t + b.phase
		_bird_a[i] = Vector4(pos.x, pos.y, _span * size.y * b.scale, _heading)
		_bird_b[i] = Vector4(_wing(t), _wing(t - _period * 0.12), show * b.alpha, sin(_t * 0.5 + b.sway) * 0.07)
	_material.set_shader_parameter("bird_count", count)
	_material.set_shader_parameter("bird_a", _bird_a)
	_material.set_shader_parameter("bird_b", _bird_b)
	_material.set_shader_parameter("time", _t)


## 翅膀翘起多少（-0.5 ~ 1）：扇 _flaps 下（从滑翔的姿势往上抬、往下压、回到滑翔），再平伸着滑 _glide 秒
func _wing(t: float) -> float:
	var flapping := _flaps * _period
	var s := fposmod(t, flapping + _glide)
	if s >= flapping:
		return GLIDE_POSE
	return GLIDE_POSE + 0.75 * sin(TAU * s / _period)
