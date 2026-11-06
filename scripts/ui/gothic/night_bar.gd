class_name NightBar
extends Control
## 屏幕顶上的一条（设计对照文档第 2 条：烙印显示在屏幕顶上）：
## - 三枚烙印：还在的燃着幽蓝，被吃掉的只剩一点灰（和契约书里画的一样）
## - 下面一行小字：第几夜（补偿周期另写）、黄昏要多少祭值、船舱里现在有多少、今夜祂想要什么
## 字是 HUD 的骨白描边；祂想要的那个用偏红的骨色。

var contractor: Contractor:
	set(value):
		contractor = value
		queue_redraw()

const BRAND_Y := 20.0
const BRAND_GAP := 40.0
const BRAND_SIZE := 26.0
const INFO_Y := 56.0

var _time := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	custom_minimum_size = Vector2(640, 64)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var who := contractor
	if who == null:
		return
	var cx := size.x * 0.5
	var brand := Gothic.tex("soul_brand")
	var glow := Gothic.glow_texture()
	var total := who.config.brands
	for i in total:
		var c := Vector2(cx + (i - (total - 1) * 0.5) * BRAND_GAP, BRAND_Y)
		var live := i < who.brands
		if live:
			var pulse := 0.35 + 0.1 * sin(_time * 2.2 + i * 1.7)
			draw_texture_rect(glow, Rect2(c - Vector2(22, 22), Vector2(44, 44)), false, Color(ContractScreen.LIVE, pulse))
		var s := Vector2(BRAND_SIZE, BRAND_SIZE)
		draw_texture_rect(brand, Rect2(c - s * 0.5, s), false, ContractScreen.LIVE if live else ContractScreen.ASH)
	var night := "第 %d 夜" % who.night if not who.is_compensation() else "补偿之夜"
	var parts: PackedStringArray = [night, "黄昏要 %s 祭值（船舱里 %s）" % [Gothic.grouped(who.demand()), Gothic.grouped(who.hold_tribute())],
		"海况：%s" % BalanceConfig.SEA_NAMES.get(who.sea, who.sea) + ("　血月" if who.blood_moon else "")]
	var info := "　·　".join(parts)
	var wish_part := ""  ## 祂不再挑今夜想要什么（2026-11-04）
	var width := Gothic.text_width(info, 14) + Gothic.text_width(wish_part, 14)
	var x := cx - width * 0.5
	Gothic.text(self, Vector2(x, INFO_Y), info, 14, Gothic.BONE_DARK)
	if wish_part != "":
		Gothic.text(self, Vector2(x + Gothic.text_width(info, 14), INFO_Y), wish_part, 14, Gothic.WARN)
