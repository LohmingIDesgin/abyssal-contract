class_name TensionGauge
extends Control
## 右上角的搏斗仪表（参照 docs/reference/ui_style.webp），不在搏斗时整体暗下去：
## - 鱼线张力：黑铁框（矛尖、卷草、铆钉）里一根玻璃管，管里的青色液柱就是张力，发光的金色刻线是当前值。
##   右端暗红的一段是红区：线拉不断，进了红区就大量耗体力（TensionModel）。
##   铭牌写"鱼线张力 TENSION"和距离，线放到头时改成"线已放尽"；铭牌右端的宝石：青 = 在甜区，琥珀 = 太松，红 = 在红区。
##   主管左下角写对手的相对强弱（弱 / 相当 / 强 / 极强，按等级差分档）。
## - 体力：下面一根细铁管（stamina_frame），液柱暖白，见底时变成血红、一跳一跳；刚掉下去的那截慢一点才退掉。
##   饿了体力上限低一截：管子右端饿掉的那一截是暗的、划着斜纹，左边一道琥珀色的刻线。
## - 饱腹：再下面一根同样的细铁管，液柱是油脂似的赭黄，60、30 两处有刻痕；饿了标签变成琥珀色，
##   饿得发慌时液柱发红、一跳一跳（核心调整 G3）。不在搏斗时也不暗下去太多，看渔获、决定吃不吃时看得清。
## - 烙印：右下的小铁梁上垂着几枚小小的烙印（剪线一次扣一枚，2026-11-04 起灵魂线并进了烙印），还在的燃着幽蓝，没了的只剩灰。

const FRAME_NAME := "gauge_frame"
const STAMINA_NAME := "stamina_frame"
const DISPLAY_WIDTH := 360.0
## 以下坐标都在贴图的"设计单位"里（贴图像素 / 3），绘制时按 DISPLAY_WIDTH 缩放
const DESIGN_WIDTH := 420.0
const WINDOW := Rect2(62, 34, 296, 20)
const TEXT_AREA := Rect2(156, 70, 196, 16)
const GEM := Vector2(366, 78)
const TIER_POS := Vector2(54, 84)                  ## 对手强弱：主管下方、铭牌左边的空处
const STAMINA_TOP := 94.0                          ## 体力管贴图的上沿
const STAMINA_WINDOW := Rect2(74, 13.8, 244, 8.4)  ## 体力管贴图里的玻璃窗（相对体力管贴图）
const STAMINA_LABEL := Vector2(10, 23)
const HUNGER_TOP := STAMINA_TOP + 24.0             ## 饱腹管：同一张体力管贴图，只画左边的管子（不带小铁梁）
const TUBE_SOURCE_WIDTH := 1042.0                  ## 体力管贴图里管子那一截的宽（贴图像素），右边是挂烙印的小铁梁
const STRANDS := Vector2(381, 8.0)                 ## 烙印挂在小铁梁上的中点（梁的下沿，相对体力管贴图）
const STRAND_GAP := 13.0
const STRAND_LENGTH := 21.0
const LOW_STAMINA := 0.3                           ## 低于这个比例，体力的液柱变成血红、一跳一跳
const TIER_COLORS: Array[Color] = [Gothic.BONE_DARK, Gothic.BONE, Gothic.WARN, Color("ff5a44")]
const SOUL_LIVE := ContractScreen.LIVE
const SOUL_GLOW := ContractScreen.GLOW
const SOUL_ASH := ContractScreen.ASH

var tension := 0.0
var red_tension := 0.95  ## 红区从哪里开始（BalanceConfig.red_tension）
var straining := false   ## 张力在红区
var slack_danger := 0.0
var active := false
var distance := -1.0
var line_out := false    ## 线放到头了，正被拽着
var stamina := 1.0       ## 0~1（占满格的几成）
var stamina_cap := 1.0   ## 体力上限占满格的几成：饿了不到 1
var hunger := 1.0        ## 饱腹 0~1
var hunger_marks := PackedFloat32Array([0.6, 0.3])  ## 饿了、饿得发慌从哪里开始（0~1）
var hunger_tier := 0     ## 0 不饿，1 饿了，2 饿得发慌
var brands := 3
var brands_max := 3
var tier := -1           ## TensionModel.tier()；-1 = 不显示

var _time := 0.0
var _shown := 0.0
var _display := 0.0
var _stamina_shown := 1.0
var _stamina_ghost := 1.0  ## 刚掉下去的那截，慢一点退
var _cap_shown := 1.0
var _hunger_shown := 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var k := DISPLAY_WIDTH / DESIGN_WIDTH
	var bottom := HUNGER_TOP + Gothic.tex(STAMINA_NAME).get_height() * Gothic.ART_SCALE
	custom_minimum_size = Vector2(DISPLAY_WIDTH, ceilf(bottom * k))


func _process(delta: float) -> void:
	_time += delta
	_shown = move_toward(_shown, 1.0 if active else 0.0, delta * 3.0)
	_display = lerpf(_display, tension if active else 0.0, minf(delta * 12.0, 1.0))
	_stamina_shown = lerpf(_stamina_shown, stamina, minf(delta * 10.0, 1.0))
	_stamina_ghost = maxf(move_toward(_stamina_ghost, stamina, delta * 0.35), _stamina_shown)
	_cap_shown = lerpf(_cap_shown, stamina_cap, minf(delta * 6.0, 1.0))
	_hunger_shown = lerpf(_hunger_shown, hunger, minf(delta * 6.0, 1.0))
	queue_redraw()


func _k() -> float:
	return size.x / DESIGN_WIDTH


func _r(r: Rect2, offset := Vector2.ZERO) -> Rect2:
	var k := _k()
	return Rect2((r.position + offset) * k, r.size * k)


func _draw() -> void:
	var alpha := lerpf(0.55, 1.0, _shown)
	_draw_tension(alpha)
	_draw_stamina(alpha)
	_draw_hunger(alpha if hunger_tier == 0 else maxf(alpha, 0.92))
	_draw_brands(alpha)


func _draw_tension(alpha: float) -> void:
	var k := _k()
	var win := _r(WINDOW)
	var max_t := TensionModel.MAX_TENSION
	# 玻璃管里：暗色底，甜区一抹青、红区一抹红（在红区时更亮）
	draw_rect(win, Color(0.012, 0.02, 0.024))
	_zone(win, TensionModel.SWEET_MIN, TensionModel.SWEET_MAX, Color(0.1, 0.32, 0.3, 0.35 * alpha))
	var red_glow := 0.4 * (0.5 + 0.5 * sin(_time * 14.0)) if straining else 0.0
	_zone(win, red_tension, max_t, Color(0.42, 0.06, 0.05, (0.45 + red_glow) * alpha))
	# 液柱：越往右越亮，进红区变成血红；表面有缓慢流动的光纹
	var ratio := clampf(_display / max_t, 0.0, 1.0)
	if ratio > 0.002:
		var fill := Rect2(win.position, Vector2(win.size.x * ratio, win.size.y))
		var hot := clampf((_display - TensionModel.SWEET_MAX) / (red_tension - TensionModel.SWEET_MAX), 0.0, 1.0)
		var c0 := Color(0.08, 0.28, 0.3).lerp(Color(0.35, 0.06, 0.04), hot)
		var c1 := Color(0.42, 0.86, 0.8).lerp(Color(0.95, 0.35, 0.22), hot)
		_liquid(fill, c0, c1, alpha)
		# 当前值：一道发光的金白色刻线，在红区时闪红
		var x := fill.end.x
		var flash := straining and fmod(_time, 0.2) < 0.1
		var mark := Color("ffd9a0") if not flash else Color("ff6a50")
		for j in 4:
			var wj := 2.0 + j * 3.0
			draw_rect(Rect2(x - wj * 0.5, win.position.y - 3.0, wj, win.size.y + 6.0), Color(mark, (0.5 - j * 0.11) * _shown))
		draw_rect(Rect2(x - 1.0, win.position.y - 4.0, 2.0, win.size.y + 8.0), Color(Color.WHITE.lerp(mark, 0.3), _shown))
	# 铁框
	var frame := Gothic.tex(FRAME_NAME)
	var shade := alpha * 0.25 + 0.75
	draw_texture_rect(frame, Rect2(Vector2.ZERO, frame.get_size() * Gothic.ART_SCALE * k), false, Color(shade, shade, shade))
	# 铭牌文字：线放到头时右边的距离换成"线已放尽"
	var text_rect := _r(TEXT_AREA)
	var base := text_rect.position + Vector2(0, text_rect.size.y - 2.0)
	Gothic.text(self, base, "鱼线张力  TENSION", 13, Color(Gothic.BONE, alpha), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	if distance >= 0.0 and _shown > 0.05:
		var right := "%.1f 米" % distance
		var color := Color(Gothic.BONE_DARK, _shown)
		if line_out:
			right = "线已放尽"
			color = Color(Gothic.WARN, _shown * (0.7 + 0.3 * sin(_time * 9.0)))
		Gothic.text(self, base, right, 13, color, HORIZONTAL_ALIGNMENT_RIGHT, text_rect.size.x, 3)
	# 对手的相对强弱
	if tier >= 0 and _shown > 0.05:
		var p := TIER_POS * k
		Gothic.text(self, p, "对手", 12, Color(Gothic.BONE_DARK, _shown), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
		var tier_name: String = TensionModel.TIER_NAMES[tier]
		Gothic.text(self, p + Vector2(Gothic.text_width("对手", 12) + 4.0, 1.0), tier_name, 16, Color(TIER_COLORS[tier], _shown),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
	# 宝石：按状态变色、轻轻呼吸
	var gem_color := Color(0.25, 0.85, 0.75)
	if active:
		if straining or _display >= red_tension:
			gem_color = Color(1.0, 0.25, 0.18)
		elif _display < TensionModel.SWEET_MIN:
			gem_color = Color(1.0, 0.7, 0.25)
	var gem := GEM * k
	var pulse := 0.8 + 0.2 * sin(_time * 3.0)
	var g := Gothic.glow_texture()
	var gr := 11.0 * k
	draw_texture_rect(g, Rect2(gem - Vector2(gr, gr) * 1.6, Vector2(gr, gr) * 3.2), false, Color(gem_color, 0.35 * pulse * alpha))
	draw_circle(gem, 4.4 * k, Color(gem_color * 0.55, alpha))
	draw_circle(gem, 3.4 * k, Color(gem_color, alpha))
	draw_circle(gem + Vector2(-1.2, -1.2) * k, 1.2 * k, Color(1, 1, 1, 0.7 * alpha))


func _draw_stamina(alpha: float) -> void:
	var k := _k()
	var top := Vector2(0, STAMINA_TOP)
	var win := _r(STAMINA_WINDOW, top)
	draw_rect(win, Color(0.02, 0.016, 0.014))
	_draw_cap(win, alpha)
	var low := _stamina_shown < LOW_STAMINA
	var beat := 0.5 + 0.5 * sin(_time * 9.0) if low else 0.0
	# 刚掉下去的那截：暗红，慢慢退
	if _stamina_ghost > _stamina_shown + 0.003:
		var x0 := win.position.x + win.size.x * _stamina_shown
		var x1 := win.position.x + win.size.x * _stamina_ghost
		draw_rect(Rect2(x0, win.position.y, x1 - x0, win.size.y), Color(0.55, 0.1, 0.06, 0.75 * alpha))
	if _stamina_shown > 0.002:
		var fill := Rect2(win.position, Vector2(win.size.x * _stamina_shown, win.size.y))
		var c0 := Color(0.3, 0.2, 0.1)
		var c1 := Color(0.93, 0.8, 0.55)
		if low:
			c0 = Color(0.32, 0.04, 0.03)
			c1 = Color(0.85, 0.2, 0.12).lerp(Color(1.0, 0.45, 0.3), beat)
		_liquid(fill, c0, c1, alpha)
	var frame := Gothic.tex(STAMINA_NAME)
	var shade := alpha * 0.25 + 0.75
	draw_texture_rect(frame, Rect2(top * k, frame.get_size() * Gothic.ART_SCALE * k), false, Color(shade, shade, shade))
	var label_color := Gothic.BONE if not low else Gothic.WARN.lerp(Color("ff6a50"), beat)
	Gothic.text(self, (top + STAMINA_LABEL) * k, "体力", 13, Color(label_color, alpha), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)


## 饿掉的那截体力上限：暗下去、划着斜纹，边上一道琥珀色的刻线
func _draw_cap(win: Rect2, alpha: float) -> void:
	if _cap_shown > 0.995:
		return
	var k := _k()
	var x0 := win.position.x + win.size.x * _cap_shown
	var lost := Rect2(x0, win.position.y, win.end.x - x0, win.size.y)
	draw_rect(lost, Color(0.07, 0.06, 0.058, alpha))
	# 斜纹：一道道 45° 的细线，裁在这一截里
	var h := lost.size.y
	var x := lost.position.x - h
	while x < lost.end.x:
		var t0 := clampf((lost.position.x - x) / h, 0.0, 1.0)
		var t1 := clampf((lost.end.x - x) / h, 0.0, 1.0)
		if t1 > t0:
			draw_line(Vector2(x + t0 * h, lost.end.y - t0 * h), Vector2(x + t1 * h, lost.end.y - t1 * h),
				Color(0.3, 0.27, 0.25, 0.55 * alpha), 1.0)
		x += 5.0 * k
	draw_rect(Rect2(x0 - 1.0, win.position.y - 2.0, 2.0, win.size.y + 4.0), Color(Gothic.WARN, 0.85 * alpha))


## 饱腹：体力管下面同样一根细管，油脂似的赭黄；60、30 处两道刻痕，饿得发慌时发红、一跳一跳
func _draw_hunger(alpha: float) -> void:
	var k := _k()
	var top := Vector2(0, HUNGER_TOP)
	var win := _r(STAMINA_WINDOW, top)
	draw_rect(win, Color(0.02, 0.016, 0.014))
	var starving := hunger_tier >= 2
	var beat := 0.5 + 0.5 * sin(_time * 5.0) if starving else 0.0
	if _hunger_shown > 0.002:
		var fill := Rect2(win.position, Vector2(win.size.x * clampf(_hunger_shown, 0.0, 1.0), win.size.y))
		var c0 := Color(0.22, 0.12, 0.05)
		var c1 := Color(0.76, 0.52, 0.24)
		if starving:
			c0 = Color(0.26, 0.06, 0.03)
			c1 = Color(0.66, 0.24, 0.12).lerp(Color(0.86, 0.36, 0.2), beat)
		_liquid(fill, c0, c1, alpha)
	for mark in hunger_marks:
		var mx := win.position.x + win.size.x * mark
		var below := _hunger_shown < mark
		var col := Color(Gothic.WARN, 0.8 * alpha) if below else Color(0.42, 0.38, 0.34, 0.7 * alpha)
		draw_rect(Rect2(mx - 0.75, win.position.y, 1.5, win.size.y), Color(0, 0, 0, 0.6 * alpha))
		draw_rect(Rect2(mx - 0.5, win.end.y - win.size.y * 0.45, 1.0, win.size.y * 0.45), col)
	var frame := Gothic.tex(STAMINA_NAME)
	var shade := alpha * 0.25 + 0.75
	var src := Rect2(0, 0, TUBE_SOURCE_WIDTH, frame.get_height())
	draw_texture_rect_region(frame, Rect2(top * k, src.size * Gothic.ART_SCALE * k), src, Color(shade, shade, shade))
	var label_color := Gothic.BONE
	if hunger_tier == 1:
		label_color = Gothic.WARN
	elif starving:
		label_color = Gothic.WARN.lerp(Color("ff6a50"), beat)
	Gothic.text(self, (top + STAMINA_LABEL) * k, "饱腹", 13, Color(label_color, alpha), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)


## 烙印：小铁梁上用细链垂下来几枚小小的烙印，轻轻晃；还在的燃着幽蓝，没了的只剩灰（剪线一次扣一枚，看得出还剪得起几次）
func _draw_brands(alpha: float) -> void:
	var k := _k()
	var top := Vector2(0, STAMINA_TOP)
	var brand := Gothic.tex("soul_brand")
	var glow := Gothic.glow_texture()
	for i in brands_max:
		var x := STRANDS.x + (i - (brands_max - 1) * 0.5) * STRAND_GAP
		var p0 := (top + Vector2(x, STRANDS.y)) * k
		var sway := sin(_time * 1.6 + i * 1.3) * 1.2 * k
		var p1 := p0 + Vector2(sway, STRAND_LENGTH * 0.45 * k)
		var live := i < brands
		draw_line(p0, p1, Color(0, 0, 0, 0.5 * alpha), 2.4 * k)
		draw_line(p0, p1, Color(SOUL_ASH.lightened(0.2), alpha), 1.0 * k)
		var size := Vector2(11, 11) * k
		var c := p1 + Vector2(0, size.y * 0.5)
		if live:
			draw_texture_rect(glow, Rect2(c - size * 1.1, size * 2.2), false, Color(SOUL_GLOW, 0.35 * alpha))
		if brand:
			draw_texture_rect(brand, Rect2(c - size * 0.5, size), false, Color(SOUL_LIVE if live else SOUL_ASH, alpha))
		else:
			draw_circle(c, size.x * 0.35, Color(SOUL_LIVE if live else SOUL_ASH, alpha))


## 一段液柱：左暗右亮，表面有缓慢流动的光纹
func _liquid(fill: Rect2, c0: Color, c1: Color, alpha: float) -> void:
	var pts := PackedVector2Array([fill.position, Vector2(fill.end.x, fill.position.y), fill.end, Vector2(fill.position.x, fill.end.y)])
	draw_polygon(pts, PackedColorArray([Color(c0, alpha), Color(c1, alpha), Color(c1 * 0.7, alpha), Color(c0 * 0.6, alpha)]))
	for i in 3:
		var y := fill.position.y + fill.size.y * (0.3 + 0.22 * i)
		var x0 := fill.position.x + fmod(_time * (18.0 + i * 7.0) + i * 53.0, maxf(fill.size.x, 1.0))
		draw_line(Vector2(x0, y), Vector2(minf(x0 + 26.0, fill.end.x), y), Color(1, 1, 1, 0.08 * alpha), 1.0)


func _zone(win: Rect2, from: float, to: float, color: Color) -> void:
	var max_t := TensionModel.MAX_TENSION
	var x0 := win.position.x + win.size.x * from / max_t
	var x1 := win.position.x + win.size.x * minf(to, max_t) / max_t
	draw_rect(Rect2(x0, win.position.y, x1 - x0, win.size.y), color)
