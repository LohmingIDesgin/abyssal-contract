class_name FishingRod3D
extends Node3D
## 鱼竿：沿本地 +Y 排列的一串骨节，手绘贴图铺在朝向镜头的半圆柱表面。
## set_bend() 让竿身弯向某个方向，越靠近竿尖弯得越多；贴图跟着骨节一起弯。
## 条带顶点放在鱼竿本地空间，跟随手骨渲染，快速挥竿时不会和手错位。

const SEGMENTS := 12
const TEXTURE := preload("res://assets/textures/rod.png")
const TIP_INSET := 0.017  ## 贴图顶端圆环中心离贴图顶边的比例，鱼线挂在这里
const CROSS_SEGMENTS := 12  ## 可见半圆截面，让贴图拥有真实的竿身深度

@export var length := 0.85
@export var width_scale := 1.3  ## 贴图按原比例时偏细，适当加粗
@export var tint := Color.WHITE  ## 场景光色

var _joints: Array[Node3D] = []
var _weights: Array[float] = []
var _tip: Node3D
var _mesh := ImmediateMesh.new()
var _material := StandardMaterial3D.new()
var _width: float


func _ready() -> void:
	var seg_len := length / SEGMENTS
	var parent: Node3D = self
	var weight_sum := 0.0
	for i in SEGMENTS:
		var joint := Node3D.new()
		joint.position.y = seg_len if i > 0 else 0.0
		parent.add_child(joint)
		_joints.append(joint)
		var w := pow(float(i + 1) / SEGMENTS, 1.8)
		_weights.append(w)
		weight_sum += w
		parent = joint
	for i in SEGMENTS:
		_weights[i] /= weight_sum
	_tip = Node3D.new()
	_tip.position.y = seg_len * (1.0 - TIP_INSET * SEGMENTS)
	parent.add_child(_tip)

	_width = length * TEXTURE.get_width() / TEXTURE.get_height() * width_scale
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_texture = TEXTURE
	_material.albedo_color = tint
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_material.alpha_scissor_threshold = 0.5
	_material.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var ribbon := MeshInstance3D.new()
	ribbon.mesh = _mesh
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ribbon)


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera:
		_rebuild_ribbon(global_transform.affine_inverse() * camera.global_position)


func tip_global_position() -> Vector3:
	return _tip.global_position


## 不弯曲时竿尖的位置，用来算手的运动速度（竿梢惯性）
func straight_tip_global_position() -> Vector3:
	return global_transform * Vector3(0, length, 0)


## angle：竿尖相对竿根总共弯过的弧度；toward_global：希望弯向的世界方向
func set_bend(angle: float, toward_global: Vector3) -> void:
	var local_dir := global_basis.inverse() * toward_global
	var axis := Vector3.UP.cross(local_dir)
	if axis.length() < 0.001:
		axis = Vector3.RIGHT
	axis = axis.normalized()
	for i in SEGMENTS:
		_joints[i].basis = Basis(axis, angle * _weights[i])


## 沿骨节铺一条正对镜头的条带；贴图 v=0 在竿尖，v=1 在竿尾
func _rebuild_ribbon(eye_local: Vector3) -> void:
	var points: Array[Vector3] = []
	var xf := Transform3D()
	for joint in _joints:
		xf = xf * joint.transform
		points.append(xf.origin)
	points.append(xf * Vector3(0, length / SEGMENTS, 0))

	_mesh.clear_surfaces()
	# 每条纵向色带落在圆柱表面，而不是把整张贴图推到手掌后面。
	# UV 仍按投影宽度采样，保留手绘贴图的外观和透明轮廓。
	for strip in CROSS_SEGMENTS:
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _material)
		for i in points.size():
			var p := points[i]
			var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
			var to_eye := eye_local - p
			to_eye = (to_eye - tangent * to_eye.dot(tangent)).normalized()
			var side := tangent.cross(to_eye).normalized()
			for edge in 2:
				var u := float(strip + edge) / CROSS_SEGMENTS
				var x := u * 2.0 - 1.0
				var depth := sqrt(maxf(0.0, 1.0 - x * x))
				_mesh.surface_set_uv(Vector2(u, 1.0 - float(i) / SEGMENTS))
				_mesh.surface_add_vertex(p + (side * x + to_eye * depth) * _width * 0.5)
		_mesh.surface_end()

