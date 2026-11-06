class_name BiteQte
extends Control
## 咬钩的那一下（QTE）：屏幕中上浮出 [空格] 提竿！（挂住东西时是"拉上来"），下面一道骨白的细线从两头往中间收，
## 收完了还没按就算没来得及（鱼吐钩跑了）。样子和体力耗尽时的剪线 / 硬撑（LastStand）一样：同一种 KeyPrompt、同一道细线。
## 浮出来时从大往回弹一下；按到了一鼓、淡出，没按到灰下去、淡出。
## 按键由 FishingView 处理，这里只管显示；点按钮也行（pressed）。

signal pressed

## 以下坐标都按基准分辨率 1280×720：在顶上的状态字下面、浮漂上面
const TOP := 286.0
const LINE_Y := 352.0
const LINE_HALF := 150.0

var _prompt: KeyPrompt
var _remaining := 1.0
var _missed := false
var _tween: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var row := HBoxContainer.new()
	row.position = Vector2(0, TOP)
	row.size = Vector2(1280, 0)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_prompt = KeyPrompt.make("空格", "提竿！", 32)
	_prompt.pressed.connect(func() -> void: pressed.emit())
	row.add_child(_prompt)


## 咬钩了：浮出来；text 是按钮上的字
func open(text := "提竿！") -> void:
	_prompt.label = text
	_prompt.disabled = false
	_remaining = 1.0
	_missed = false
	visible = true
	modulate.a = 0.0
	_restart_tween()
	_prompt.scale = Vector2(1.35, 1.35)
	_tween.tween_property(self, "modulate:a", 1.0, 0.12)
	_tween.parallel().tween_property(_prompt, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()


## 剩下的时间 0~1（细线跟着收）
func set_remaining(r: float) -> void:
	_remaining = clampf(r, 0.0, 1.0)
	queue_redraw()


## hit：按到了（一鼓、淡出）；没按到：灰下去
func close(hit: bool) -> void:
	if not visible:
		return
	_restart_tween()
	if hit:
		_tween.tween_property(_prompt, "scale", Vector2(1.18, 1.18), 0.1)
		_tween.parallel().tween_property(self, "modulate:a", 0.0, 0.25).set_delay(0.08)
	else:
		_missed = true
		_prompt.disabled = true
		_tween.tween_property(self, "modulate:a", 0.0, 0.45)
	_tween.tween_callback(func() -> void:
		visible = false
		_prompt.scale = Vector2.ONE)


func _restart_tween() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_prompt.pivot_offset = _prompt.size * 0.5


func _draw() -> void:
	# 倒计时：一道骨白的细线从两头往中间收，两端各一个小点（和 LastStand 一样）；快没了偏红
	var half := LINE_HALF * _remaining
	if half < 0.5 or _missed:
		return
	var col := Gothic.BONE.lerp(Gothic.WARN, clampf(1.0 - _remaining * 2.0, 0.0, 1.0))
	draw_line(Vector2(640.0 - half, LINE_Y), Vector2(640.0 + half, LINE_Y), Color(0, 0, 0, 0.6), 4.0)
	draw_line(Vector2(640.0 - half, LINE_Y), Vector2(640.0 + half, LINE_Y), Color(col, 0.9), 1.8)
	for side in [-1.0, 1.0]:
		draw_circle(Vector2(640.0 + side * half, LINE_Y), 2.8, Color(col, 0.95))
