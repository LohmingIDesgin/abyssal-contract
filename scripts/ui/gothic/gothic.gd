class_name Gothic
extends RefCounted
## 哥特风 HUD 的贴图、字体和配色（参照 docs/reference/ui_style.webp）。
## 贴图由 tools/bake_ui_art.py 烘焙到 assets/ui/，是显示尺寸的 3 倍，画的时候缩小。

const ART_SCALE := 1.0 / 3.0

const BONE := Color("d8ccb0")
const BONE_DARK := Color("8f846c")
const BRONZE_LIGHT := Color("c9a35a")
const INK := Color("2b1a0c")
const EERIE := Color("4fe0bf")
const BLOOD := Color("b8352a")
const SHADOW := Color(0, 0, 0, 0.85)
## 警示（放不下、词条）用的偏红的骨色
const WARN := Color("d9826f")

## 基础材料 → 药瓶里液体的颜色（液体贴图是灰度的，按这个上色）
const LIQUID_COLORS := {
	"flesh": Color(0.64, 0.09, 0.07),
	"shell": Color(0.82, 0.7, 0.48),
	"glow": Color(0.32, 1.0, 0.8),
}
## 万能饵（没有基础材料）瓶里的颜色：浑浊的灰
const UNIVERSAL_LIQUID := Color(0.46, 0.44, 0.5)
## 两份基础材料在瓶里分层：沉的在下面（矿壳最沉，幽光最轻）
const LIQUID_DENSITY := {"shell": 2, "flesh": 1, "glow": 0}

## 发光字的几层光晕：[描边粗细, 不透明度]
const GLOW_LAYERS: Array[Vector2] = [Vector2(16, 0.04), Vector2(10, 0.07), Vector2(6, 0.12), Vector2(3, 0.22)]

static var _font: Font
static var _hand_fonts := {}
static var _textures := {}
static var _liquid_rects := {}  ## 液体贴图里有液体的那一块（贴图像素），分层时用


static func tex(name: String) -> Texture2D:
	if not _textures.has(name):
		_textures[name] = load("res://assets/ui/%s.png" % name)
	return _textures[name]


## 思源宋体（Noto Serif SC，系统里有就用），半粗
static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Noto Serif SC", "Source Han Serif SC", "Noto Serif CJK SC", "SimSun"])
		f.font_weight = 600
		_font = f
	return _font


## 英文手写体（斜着的连笔）：契约书上的编号和契约语用。Caveat（assets/fonts/Caveat-Variable.ttf，OFL 授权，
## 可以随游戏发布，授权全文在同一个文件夹的 Caveat-OFL.txt）。是可变字体，weight 400–700，越大越粗；
## 它没有的字（中文等）退回思源宋体
static func hand_font(weight := 500) -> Font:
	if not _hand_fonts.has(weight):
		var base := load("res://assets/fonts/Caveat-Variable.ttf") as FontFile
		if base == null:
			return font()
		var v := FontVariation.new()
		v.base_font = base
		v.variation_opentype = {"wght": weight}
		v.fallbacks = [font()]
		_hand_fonts[weight] = v
	return _hand_fonts[weight]


## 发光的字（契约书用）：先铺几层越来越粗、越来越淡的光晕，再写字本身；alpha 用来做浮现
static func glow_text(ci: CanvasItem, pos: Vector2, s: String, size: int, color: Color, glow: Color,
		alpha := 1.0, f: Font = null) -> void:
	if alpha <= 0.0:
		return
	if f == null:
		f = font()
	for layer in GLOW_LAYERS:
		ci.draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, int(layer.x), Color(glow, glow.a * layer.y * alpha))
	ci.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color, color.a * alpha))


static func text_width(s: String, size: int, f: Font = null) -> float:
	return (f if f else font()).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, color := BONE,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 4) -> void:
	var f := font()
	if outline > 0:
		ci.draw_string_outline(f, pos, s, align, width, size, outline, Color(SHADOW, SHADOW.a * color.a))
	ci.draw_string(f, pos, s, align, width, size, color)


## 每三位一个逗号："2,033"
static func grouped(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## 中文数字："两千零三十三""一千二百七十四""十二万两千六百五十五"（到亿以下）
static func chinese_number(n: int) -> String:
	if n == 0:
		return "零"
	var groups: Array[int] = []  ## 从低到高，每四位一组
	var rest := absi(n)
	while rest > 0:
		groups.append(rest % 10000)
		rest /= 10000
	var out := ""
	var need_zero := false
	for gi in range(groups.size() - 1, -1, -1):
		var g := groups[gi]
		if g == 0:
			need_zero = out != ""
			continue
		if need_zero or (out != "" and g < 1000):
			out += "零"
		var head := "两" if g == 2 and gi > 0 else _chinese_group(g, out == "")  ## 两万，不是二万
		out += head + ["", "万", "亿"][mini(gi, 2)]
		need_zero = false
	return out


## 四位以内的一组。first：整个数开头的那组（"十二"不写"一十二"；千、万位上的 2 读"两"）
static func _chinese_group(g: int, first: bool) -> String:
	const DIGITS := "零一二三四五六七八九"
	var units := ["千", "百", "十", ""]
	var digits := [g / 1000, g / 100 % 10, g / 10 % 10, g % 10]
	var out := ""
	var zero := false
	var started := false
	for i in 4:
		var d: int = digits[i]
		if d == 0:
			zero = started
			continue
		if zero:
			out += "零"
			zero = false
		if i == 2 and d == 1 and not started and first:
			out += "十"
		elif i == 0 and d == 2:
			out += "两千"
		else:
			out += DIGITS[d] + units[i]
		started = true
	return out


## 祭值的批注："此物积蓄的魂蕴，可折为两千零三十三份献礼。"
static func tribute_note(tribute: int) -> String:
	return "此物积蓄的魂蕴，可折为%s份献礼。" % chinese_number(tribute)


## 比例写成几成：0.6 → "六成"，0.2 → "两成"；到不了一成写"不到一成"，满了写"全部"
static func tenths(x: float) -> String:
	var n := clampi(roundi(x * 10.0), 0, 10)
	if n >= 10:
		return "全部"
	if n <= 0:
		return "不到一成"
	return ("两" if n == 2 else chinese_number(n)) + "成"


## 船舱、供奉里画渔获小图时乘的颜色：带「变色」的染上和展示时一样的颜色（creature_display.gdshader 的 recolor），
## 带「变异」的偏暗红；base 是原来要乘的颜色
static func catch_tint(c: CatchData, base: Color) -> Color:
	var t := Color.WHITE
	if c.hue_shift > 0.0:
		var grey := 0.6
		var yiq := Vector3(grey, 0.0, 0.0)
		var dir := Vector2.from_angle(c.hue_shift * TAU)
		var chroma := dir * 0.09 * smoothstep(0.03, 0.4, grey)
		var rgb := Color(yiq.x + 0.956 * chroma.x + 0.621 * chroma.y, yiq.x - 0.272 * chroma.x - 0.647 * chroma.y,
			yiq.x - 1.106 * chroma.x + 1.703 * chroma.y)
		t = Color(rgb.r / grey, rgb.g / grey, rgb.b / grey)
	elif c.is_mutated():
		t = Color(0.9, 0.55, 0.58)
	return Color(base.r * t.r, base.g * t.g, base.b * t.b, base.a)


## 按显示尺寸画一张 3 倍贴图（左上角在 pos）
static func sprite(ci: CanvasItem, name: String, pos: Vector2, scale := 1.0, modulate := Color.WHITE) -> void:
	var t := tex(name)
	ci.draw_texture_rect(t, Rect2(pos, t.get_size() * ART_SCALE * scale), false, modulate)


static func sprite_centered(ci: CanvasItem, name: String, center: Vector2, scale := 1.0, modulate := Color.WHITE) -> void:
	var t := tex(name)
	var size := t.get_size() * ART_SCALE * scale
	ci.draw_texture_rect(t, Rect2(center - size * 0.5, size), false, modulate)


## 竖向三段：两端按原比例，中间拉伸（贴图像素的 cap 长度）
static func three_slice_v(ci: CanvasItem, t: Texture2D, rect: Rect2, cap: float) -> void:
	var ts := t.get_size()
	var k := rect.size.x / ts.x
	var cap_d := cap * k
	var mid := maxf(rect.size.y - cap_d * 2.0, 0.0)
	ci.draw_texture_rect_region(t, Rect2(rect.position, Vector2(rect.size.x, cap_d)), Rect2(0, 0, ts.x, cap))
	ci.draw_texture_rect_region(t, Rect2(rect.position + Vector2(0, cap_d), Vector2(rect.size.x, mid)),
		Rect2(0, cap, ts.x, ts.y - cap * 2.0))
	ci.draw_texture_rect_region(t, Rect2(rect.position + Vector2(0, cap_d + mid), Vector2(rect.size.x, cap_d)),
		Rect2(0, ts.y - cap, ts.x, cap))


## 横向三段
static func three_slice_h(ci: CanvasItem, t: Texture2D, rect: Rect2, cap: float) -> void:
	var ts := t.get_size()
	var k := rect.size.y / ts.y
	var cap_d := cap * k
	var mid := maxf(rect.size.x - cap_d * 2.0, 0.0)
	ci.draw_texture_rect_region(t, Rect2(rect.position, Vector2(cap_d, rect.size.y)), Rect2(0, 0, cap, ts.y))
	ci.draw_texture_rect_region(t, Rect2(rect.position + Vector2(cap_d, 0), Vector2(mid, rect.size.y)),
		Rect2(cap, 0, ts.x - cap * 2.0, ts.y))
	ci.draw_texture_rect_region(t, Rect2(rect.position + Vector2(cap_d + mid, 0), Vector2(cap_d, rect.size.y)),
		Rect2(ts.x - cap, 0, cap, ts.y))


## 九宫格：四角按原比例显示（corner 是贴图像素），四边和中间拉伸
static func nine_slice(ci: CanvasItem, t: Texture2D, rect: Rect2, corner: float) -> void:
	var ts := t.get_size()
	var c := minf(corner * ART_SCALE, minf(rect.size.x, rect.size.y) * 0.5)
	var xs := [rect.position.x, rect.position.x + c, rect.end.x - c, rect.end.x]
	var ys := [rect.position.y, rect.position.y + c, rect.end.y - c, rect.end.y]
	var us := [0.0, corner, ts.x - corner, ts.x]
	var vs := [0.0, corner, ts.y - corner, ts.y]
	for j in 3:
		for i in 3:
			var dst := Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j])
			if dst.size.x > 0.0 and dst.size.y > 0.0:
				ci.draw_texture_rect_region(t, dst, Rect2(us[i], vs[j], us[i + 1] - us[i], vs[j + 1] - vs[j]))


## HUD 的字：骨白、黑描边，压在画面或灰褐色的皮上都看得清（和右下角按键提示同一种字）
static func label(s: String, font_size := 16, color := BONE, outline := 4) -> Label:
	var l := Label.new()
	l.text = s
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", outline)
	return l


## 同样的字，RichTextLabel 版（要嵌图标、换颜色时用）
static func rich(font_size := 16, outline := 4) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.add_theme_font_override("normal_font", font())
	r.add_theme_font_size_override("normal_font_size", font_size)
	r.add_theme_color_override("default_color", BONE)
	r.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	r.add_theme_constant_override("outline_size", outline)
	r.add_theme_constant_override("line_separation", 3)
	return r


## 显示尺寸为 display_size 的贴图（3 倍贴图缩小显示）
static func icon_rect(name: String, display_size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex(name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = display_size
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## RichTextLabel 里嵌一个小图标
static func bb_icon(name: String, px := 18) -> String:
	return "[img=%dx%d]res://assets/ui/%s.png[/img]" % [px, px, name]


## 三类材料，每类前面带图标（RichTextLabel 用）；names 为真时写上"血肉质"这样的名字
static func bb_materials(counts: Dictionary, px := 18, names := false) -> String:
	var parts: PackedStringArray = []
	for m in Materials.ALL:
		parts.append("%s %s%d" % [bb_icon("mat_" + m, px), Materials.DISPLAY[m] + " " if names else "", counts.get(m, 0)])
	return "   ".join(parts)


## 药瓶样式：带幽光的用细颈瓶，带矿壳的用广口罐，纯血肉用圆底烧瓶
static func flask_for(bases: Array) -> String:
	if Materials.GLOW in bases:
		return "bottle"
	if Materials.SHELL in bases:
		return "jar"
	return "round"


## 画一瓶饵（中心在 center）：两份基础材料不一样时，瓶里分成上下两层，沉的在下面；有幽光的瓶子后面透一点光。
## 没有基础材料的是万能饵：圆底烧瓶里一瓶浑浊的灰
static func flask(ci: CanvasItem, center: Vector2, scale: float, bases: Array, modulate := Color.WHITE) -> void:
	var style := flask_for(bases)
	var sorted := bases.duplicate()
	sorted.sort_custom(func(a, b) -> bool: return LIQUID_DENSITY.get(a, 0) > LIQUID_DENSITY.get(b, 0))
	if Materials.GLOW in bases:
		var g := glow_texture()
		var r := 24.0 * scale
		ci.draw_texture_rect(g, Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0), false,
			Color(LIQUID_COLORS.glow, 0.35 * modulate.a))
	var liquid := tex("flask_%s_liquid" % style)
	var size := liquid.get_size() * ART_SCALE * scale
	var dest := Rect2(center - size * 0.5, size)
	if sorted.is_empty():
		ci.draw_texture_rect(liquid, dest, false, _tint(UNIVERSAL_LIQUID, modulate))
	else:
		ci.draw_texture_rect(liquid, dest, false, _tint(LIQUID_COLORS.get(sorted[0], Color.GRAY), modulate))
	if sorted.size() > 1 and sorted[1] != sorted[0]:
		# 上面一层：液体那一块的上半截
		var used := _liquid_rect("flask_%s_liquid" % style)
		var split := used.position.y + used.size.y * 0.5
		var k := split / liquid.get_height()
		ci.draw_texture_rect_region(liquid, Rect2(dest.position, Vector2(dest.size.x, dest.size.y * k)),
			Rect2(0, 0, liquid.get_width(), split), _tint(LIQUID_COLORS.get(sorted[1], Color.GRAY), modulate))
	sprite_centered(ci, "flask_%s" % style, center, scale, modulate)


## 附加物的标记：有图标画图标，没有就盖它的气味印章；基础款什么都不画。pos 是左上角，size 是显示尺寸
static func additive_mark(ci: CanvasItem, additive: AdditiveData, pos: Vector2, size: float, modulate := Color.WHITE) -> void:
	if additive == null:
		return
	if additive.icon:
		ci.draw_texture_rect(additive.icon, Rect2(pos, Vector2(size, size)), false, modulate)
	elif additive.aspect != "":
		var seal := tex("seal_%s" % additive.aspect)
		ci.draw_texture_rect(seal, Rect2(pos, seal.get_size() * ART_SCALE * size / 18.0), false, modulate)


static func _tint(c: Color, modulate: Color) -> Color:
	return Color(c.r * modulate.r, c.g * modulate.g, c.b * modulate.b, modulate.a)


static func _liquid_rect(name: String) -> Rect2:
	if not _liquid_rects.has(name):
		var t := tex(name)
		var img := t.get_image()
		if img == null or img.is_empty():
			return Rect2(Vector2.ZERO, t.get_size())  ## 读不到像素（不开画面跑的时候）：当整张都是液体
		if img.is_compressed():
			img.decompress()
		_liquid_rects[name] = Rect2(img.get_used_rect())
	return _liquid_rects[name]


## 一团柔和的白光（径向衰减），按颜色调制后给选中的格子、宝石、灯用。
## 自己生成带 mipmap 的贴图：HUD 用"线性 + mipmap"过滤，没有 mipmap 的贴图缩小画会变透明
static func glow_texture() -> Texture2D:
	return _radial("_glow", func(r: float) -> float:
		var a := clampf(1.0 - r, 0.0, 1.0)
		return a * a * (0.6 + 0.4 * a))


## 比 glow_texture 平缓得多的光圈：中间大半都亮，只在外圈淡出（选中格子的光晕）
static func aura_texture() -> Texture2D:
	return _radial("_aura", func(r: float) -> float: return 1.0 - smoothstep(0.4, 1.0, r))


static func _radial(key: String, falloff: Callable) -> Texture2D:
	if not _textures.has(key):
		var n := 128
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var r := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
				img.set_pixel(x, y, Color(1, 1, 1, falloff.call(r)))
		img.generate_mipmaps()
		_textures[key] = ImageTexture.create_from_image(img)
	return _textures[key]
