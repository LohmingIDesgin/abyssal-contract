extends Node
## 渔获个体与船舱自检。命令行运行：
##   Godot_v4.6.3-stable_win64.exe --headless --path . res://tests/test_catch.tscn

const SAMPLES := 3000

var _failures := 0


func _ready() -> void:
	_test_data()
	_test_generation()
	_test_stages()
	_test_tribute()
	_test_numbers()
	_test_values()
	_test_hold()
	_test_body()
	_test_hunger()
	_test_drafts()
	_report()
	print("\n==== %s（失败 %d 项）====" % ["全部通过" if _failures == 0 else "存在失败", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## 阶段 V 的名册草案（data/fish_draft/，还没有插图）：读得进来、数都在范围里；只在某些夜里出的只在那种夜里出（引深也引不上来）；
## 加进来以后每层水各级占的比例不变（只是同一级里多了几种分）；无面鲂的特殊词条多。用完拿掉，后面的不受影响
func _test_drafts() -> void:
	print("名册（阶段 V 的十三种 2026-11-05 上线了，草案文件夹现在是空的）")
	var config := GameDB.balance
	var before := GameDB.fish.size()
	var bait := BaitCrafter.make_universal(1)
	var levels_before := []
	for d in GameDB.DEPTH_NAMES.size():
		levels_before.append(WaterLayers.level_shares(d, config))
	var n := GameDB.use_draft_fish()
	_check(n == 0 and GameDB.fish.size() == 20, "十三种都上线了：草案里剩 %d 种，正式的一共 %d 种" % [n, GameDB.fish.size()])
	var bad := []
	for fish: FishData in GameDB.sorted_values(GameDB.fish):
		var ok := fish.display_name != "" and fish.description != "" and fish.level_min >= 1 and fish.level_max <= 5 \
			and fish.level_min <= fish.level_max and fish.adult_body >= 0 and fish.adult_body <= 4 and fish.tribute_base > 0.0 \
			and fish.yield_base > 0.0 and fish.special_mult >= 1.0
		for aspect in fish.preferences:
			ok = ok and Aspect.ALL.has(aspect)
		for m in fish.material_ratio:
			ok = ok and Materials.ALL.has(m)
		for w in fish.appears_when:
			ok = ok and (w == "blood_moon" or BalanceConfig.SEA_NAMES.has(w))
		if not ok:
			bad.append(fish.id)
	_check(bad.is_empty(), "%d 种的数都在范围里（1–5 级、五档躯体、气味和材料都认得）：%s" % [GameDB.fish.size(),
		"没有不对的" if bad.is_empty() else "、".join(bad)])
	var levels_after := []
	for d in GameDB.DEPTH_NAMES.size():
		levels_after.append(WaterLayers.level_shares(d, config))
	_check(levels_after == levels_before, "加进来以后，每层水各级占的比例不变（只是同一级里多了几种分）")

	var eel := GameDB.get_fish("blood_moon_eel")
	var bream := GameDB.get_fish("faceless_bream")
	var plain := config.for_night(3, "rough")
	var moon := config.for_night(3, "rough", true)
	var eerie := config.for_night(3, "eerie")
	var anywhere := func(fish: FishData, cfg: BalanceConfig) -> bool:
		for d in GameDB.DEPTH_NAMES.size():
			if WaterLayers.presence(fish, d, cfg) > 0.0:
				return true
		return false
	_check(not anywhere.call(eel, config) and not anywhere.call(eel, plain) and anywhere.call(eel, moon) and not anywhere.call(eel, eerie),
		"血月鳗只在迎着血月钓的那一夜出（总表、躁动的夜、异化的夜都没有）")
	_check(not anywhere.call(bream, config) and not anywhere.call(bream, plain) and anywhere.call(bream, eerie) and not anywhere.call(bream, moon),
		"无面鲂只在异化的夜里出")
	var sum := 0.0
	var leaked := false
	for e in BiteCalculator.bite_table(bait, 1, plain):
		sum += e.chance
		leaked = leaked or e.fish == eel or e.fish == bream
	_check(absf(sum - 1.0) < 0.001 and not leaked, "平常的夜，深水的上钩表里没有它们，加起来还是 1（%.3f）" % sum)
	var lured := 0
	var rng := _rng(5)
	for i in 400:
		var c := CatchGenerator.generate_at_level(3, bait, rng, plain)
		if c and (c.species_id == eel.id or c.species_id == bream.id):
			lured += 1
	_check(lured == 0, "引深引上来的也不会是今夜不在的那几种")
	var odd := func(fish: FishData, forced: Dictionary) -> float:
		var r := _rng(9)
		var k := 0
		for i in SAMPLES:
			var c := CatchGenerator.generate(fish, r, eerie, 0, -1, forced)
			if c.affix_ids.any(func(id: String) -> bool: return GameDB.get_affix(id).special):
				k += 1
		return float(k) / SAMPLES
	var bream_rate: float = odd.call(bream, {"stage": 1, "level": 2})
	var dace_rate: float = odd.call(GameDB.get_fish("grey_dace"), {"stage": 1, "level": 1})
	_check(bream_rate > dace_rate * 2.0, "无面鲂带特殊词条的机会是别的种类的 %.1f 倍（异化的第 3 夜：%.0f%% 对 %.0f%%）" % [
		bream.special_mult, bream_rate * 100.0, dace_rate * 100.0])
	GameDB.use_draft_fish(false)
	_check(GameDB.fish.size() == before, "用完拿掉，回到 %d 种" % before)


func _check(cond: bool, msg: String) -> void:
	print(("  [OK]   " if cond else "  [FAIL] ") + msg)
	if not cond:
		_failures += 1


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## 手搓一条渔获，只填船舱用得到的几项；载荷按时期
func _make(level: int, mats := {}, stage := CatchData.Stage.JUVENILE) -> CatchData:
	var c := CatchData.new()
	c.species_id = "grey_dace"
	c.level = level
	c.stage = stage
	c.load_cost = GameDB.balance.load_for_stage(stage)
	c.materials = mats
	return c


func _test_data() -> void:
	print("数据")
	_check(GameDB.balance != null, "读到了 data/balance.tres")
	var specials := GameDB.sorted_values(GameDB.affixes).filter(func(a: AffixData) -> bool: return a.special)
	_check(GameDB.affixes.size() - specials.size() >= 6 and specials.size() == 2
		and specials.all(func(a: AffixData) -> bool: return a.chance > 0.0 and a.tribute_bonus > 0.0),
		"普通词条 %d 个，特殊词条 %d 个（变色、变异，各有机会和祭值加成）" % [GameDB.affixes.size() - specials.size(), specials.size()])
	for fish: FishData in GameDB.sorted_values(GameDB.fish):
		var ratio := 0.0
		for m in Materials.ALL:
			ratio += fish.material_ratio.get(m, 0.0)
		_check(fish.level_min <= fish.level_max and fish.adult_body >= 0 and fish.adult_body < CatchData.BODY_NAMES.size()
			and ratio > 0.0 and fish.icon != null and fish.icon_juvenile != null and fish.icon_adult != null and fish.tribute_base > 0.0,
			"%s：等级 %d–%d，成年期%s，有材料比例、三个时期的插图、祭值基础值 %d" % [fish.display_name, fish.level_min,
				fish.level_max, CatchData.BODY_NAMES[fish.adult_body], fish.tribute_base])


func _test_generation() -> void:
	print("个体生成")
	var config := GameDB.balance
	var ok := true
	for fish: FishData in GameDB.sorted_values(GameDB.fish):
		var rng := _rng(7)
		var deepest: int = WaterLayers.depths_of(fish, CodexScreen._config_for(fish))[-1]
		for i in 300:
			var c := CatchGenerator.generate(fish, rng, config, 0, deepest)
			var mats := 0
			var mats_ok := true
			for m in Materials.ALL:
				mats += c.materials.get(m, 0)
				mats_ok = mats_ok and c.materials.get(m, 0) >= 0
			mats_ok = mats_ok and mats >= config.min_materials[c.stage]
			if c.level < fish.level_min or c.level > fish.level_max \
					or c.body_class() != CatchGenerator.body_class_for(fish, c.stage, c.is_mutated()) or c.food < 1 or c.energy <= 0 or not mats_ok or mats > 10 \
					or c.load_cost != config.load_for_stage(c.stage) or c.stage < 0 or c.stage > 2 \
					or c.soul_strength < 5 or c.soul_strength > 100 or c.tribute < 1 or c.size < 0.3 or c.size > 2.5:
				ok = false
				print("    越界：%s" % c.summary())
				break
	_check(ok, "每种 300 条：等级、时期、躯体规模（成年期是这一种的那一档，往前每个时期小一档，带「变异」大一档）、灵魂强度、个头、祭值在范围内，处理所得幼年至少 %d 份、成长期和成年期至少 %d 份、最多 10 份（新回合机制第 42 条），载荷按时期" % [
		config.min_materials[0], config.min_materials[1]])

	var a := CatchGenerator.generate(GameDB.get_fish("lantern_crone"), _rng(42))
	var b := CatchGenerator.generate(GameDB.get_fish("lantern_crone"), _rng(42))
	_check(a.summary() == b.summary(), "同一个种子生成同一条")

	# 等级跟着时期走（2026-11-03）：幼年是最低等级、成年是最高等级、成长期在中间；只差一级的，成长期两级各一半，
	# 看灵魂强度过没过门槛
	var mapped := true
	var where := ""
	for fish: FishData in GameDB.sorted_values(GameDB.fish):
		var rng := _rng(5)
		for i in 400:
			var c := CatchGenerator.generate(fish, rng, config)
			var levels := fish.stage_levels(c.stage)
			if c.level < levels.x or c.level > levels.y:
				mapped = false
				where = "%s %s %d 级" % [fish.display_name, c.stage_name(), c.level]
	_check(mapped and GameDB.get_fish("grey_dace").stage_levels(2) == Vector2i(1, 1)
		and GameDB.get_fish("bloodtooth_pomfret").stage_levels(1) == Vector2i(1, 2)
		and GameDB.get_fish("lantern_crone").stage_levels(1) == Vector2i(2, 2)
		and GameDB.get_fish("ferryman_sturgeon").stage_levels(0) == Vector2i(3, 3)
		and GameDB.get_fish("thousand_eye_catfish").stage_levels(2) == Vector2i(4, 4),
		"等级跟着时期走：灰鲦三个时期都是 1 级，磷灯婆 1/2/3，千目窥渊鲶 2/3/4，白鲟 3/4/5，血齿冥鲳的成长期 1–2 级 %s" % where)
	var pomfret := GameDB.get_fish("bloodtooth_pomfret")
	var line := Codex.growth_line(pomfret, config)
	var ups := 0
	var growing := 0
	var split_ok := true
	var rng := _rng(3)
	for i in SAMPLES:
		var c := CatchGenerator.generate(pomfret, rng, config)
		if c.stage != CatchData.Stage.GROWING or not c.affix_ids.is_empty():
			continue
		growing += 1
		ups += int(c.level == 2)
		## 灵魂强度存的是四舍五入以后的整数：正好在门槛上的两边都可能
		split_ok = split_ok and (c.soul_strength >= roundi(line) if c.level == 2 else c.soul_strength <= roundi(line))
	_check(split_ok and absf(ups / float(growing) - config.growth_up_chance()) < 0.04,
		"血齿冥鲳的成长期：灵魂强度 %d 以上的是 2 级（%.0f%%，该是 %.0f%%），以下的是 1 级" % [roundi(line),
			ups * 100.0 / growing, config.growth_up_chance() * 100.0])

	# 每层水出几级（挂万能饵）：浅层只有 1 级；深水大多 2、3 级、偶尔 1 级；渊底大多 4、5 级、偶尔 2、3 级、没有 1 级
	var universal := BaitCrafter.make_universal(1)
	var layer_ok := true
	var mixes: PackedStringArray = []
	for depth in GameDB.DEPTH_NAMES.size():
		var table := BiteCalculator.bite_table(universal, depth, config)
		var counts := [0, 0, 0, 0, 0]
		var n := 0
		var lrng := _rng(40 + depth)
		while n < SAMPLES:
			var fish := BiteCalculator.roll(table, lrng)
			if fish == null:
				continue
			counts[CatchGenerator.generate(fish, lrng, config, 0, depth).level - 1] += 1
			n += 1
		var expect := WaterLayers.level_shares(depth, config)
		var parts: PackedStringArray = []
		for i in 5:
			layer_ok = layer_ok and absf(counts[i] / float(n) - expect[i]) < 0.025
			if counts[i] > 0:
				parts.append("%d 级 %.0f%%" % [i + 1, counts[i] * 100.0 / n])
		mixes.append("%s %s" % [GameDB.DEPTH_NAMES[depth], " · ".join(parts)])
	var shallow := WaterLayers.level_shares(0, config)
	var abyss := WaterLayers.level_shares(2, config)
	_check(layer_ok and shallow[0] == 1.0 and abyss[0] == 0.0, "各层水出几级和定的一样：%s" % "；".join(mixes))


func _test_stages() -> void:
	print("时期")
	var config := GameDB.balance
	var dace := GameDB.get_fish("grey_dace")
	var counts := [0, 0, 0]
	var rng := _rng(17)
	for i in SAMPLES:
		counts[CatchGenerator.generate(dace, rng, config, 0, 0).stage] += 1
	var share_sum := 0.0
	for x in config.stage_share:
		share_sum += x
	var close := true
	for s in 3:
		close = close and absf(counts[s] / float(SAMPLES) - config.stage_share[s] / share_sum) < 0.03
	_check(close, "同一级的几个时期按 stage_share 分：浅层的灰鲦（三个时期都是 1 级）幼年 %d、成长 %d、成年 %d" % counts)

	var sums := [0.0, 0.0, 0.0]
	var souls := [0.0, 0.0, 0.0]
	counts = [0, 0, 0]
	rng = _rng(23)
	var eel := GameDB.get_fish("blind_bone_eel")
	for i in SAMPLES:
		var c := CatchGenerator.generate(eel, rng, config)
		sums[c.stage] += c.body
		souls[c.stage] += c.soul_strength
		counts[c.stage] += 1
	var w := [sums[0] / counts[0], sums[1] / counts[1], sums[2] / counts[2]]
	var s := [souls[0] / counts[0], souls[1] / counts[1], souls[2] / counts[2]]
	var in_class := true
	for st in 3:
		in_class = in_class and config.body_class_of(w[st]) == eel.stage_body(st)
	_check(w[0] < w[1] and w[1] < w[2] and in_class,
		"盲眼噬骸鳗平均躯体规模：幼年 %.2f（中型）、成长 %.2f（大型）、成年 %.2f（巨型）" % w)
	_check(s[0] < s[1] and s[1] < s[2], "灵魂强度：幼年 %.0f、成长 %.0f、成年 %.0f" % s)

	var young := TensionModel.new(eel, 0, 15.0, config, null, CatchData.Stage.JUVENILE)
	var grown := TensionModel.new(eel, 0, 15.0, config, null, CatchData.Stage.GROWING)
	var old := TensionModel.new(eel, 0, 15.0, config, null, CatchData.Stage.ADULT)
	_check(is_equal_approx(young.struggle, old.struggle) and is_equal_approx(young.endurance_max, old.endurance_max)
		and is_equal_approx(grown.struggle, eel.struggle),
		"搏斗不按时期变（强弱看差几级，等级跟着时期走）：挣扎 %.2f / %.2f / %.2f，耐力 %.1f / %.1f / %.1f" % [young.struggle,
			grown.struggle, old.struggle, young.endurance_max, grown.endurance_max, old.endurance_max])


func _test_tribute() -> void:
	print("祭值")
	var config := GameDB.balance
	var dace := GameDB.get_fish("grey_dace")
	var c := CatchData.new()
	c.species_id = dace.id
	c.level = 1
	c.stage = CatchData.Stage.GROWING
	c.body = CatchGenerator.typical_body(dace, CatchData.Stage.GROWING, config)
	c.soul_strength = 40
	c.energy = 12
	CatchGenerator.evaluate(c, dace, config)
	var st: float = config.stage_tribute[1]
	_check(c.tribute == roundi(300.0 * st * 12 / 10.0 * (1.5 + 40 * 0.05)),
		"灰鲦 1 级成长期、灵魂强度 40、能量 12：300 × %.1f × 12 ÷ 10 × (1.5 + 40 × 0.05) = %d" % [st, c.tribute])
	var big := c.duplicate() as CatchData
	big.body = 10.0
	CatchGenerator.evaluate(big, dace, config)
	_check(big.tribute == c.tribute and big.body_class() == 3 and c.body_class() == 0 and big.food > c.food,
		"躯体规模不算祭值（2026-11-04）：小型 %s，巨型的也是 %s（饱腹 +%d、+%d 不一样）" % [Gothic.grouped(c.tribute),
			Gothic.grouped(big.tribute), c.food, big.food])
	var example := c.duplicate() as CatchData
	example.energy = 15
	example.affix_ids = ["blood_rich"]
	CatchGenerator.evaluate(example, dace, config)
	var expect := roundi(300.0 * st * 15 / 10.0 * (1.5 + 40 * 0.05) * 1.12)
	_check(example.tribute == expect, "能量 15、血旺（+12%%）→ %s" % Gothic.grouped(example.tribute))
	var stages := []
	for s in 3:
		var x := c.duplicate() as CatchData
		x.stage = s
		x.body = CatchGenerator.typical_body(dace, s, config)
		CatchGenerator.evaluate(x, dace, config)
		stages.append(x.tribute)
	var ratio := [config.stage_tribute[1] / config.stage_tribute[0], config.stage_tribute[2] / config.stage_tribute[0]]
	_check(absf(stages[1] / float(stages[0]) - ratio[0]) < 0.01 and absf(stages[2] / float(stages[0]) - ratio[1]) < 0.01,
		"同样个头、灵魂强度，时期系数 1 : %.1f : %.1f（%d / %d / %d）" % [ratio[0], ratio[1], stages[0], stages[1], stages[2]])
	var energies := {}
	var rng0 := _rng(19)
	for i in 2000:
		var x := CatchGenerator.generate(GameDB.get_fish("blind_bone_eel"), rng0, config, 0, 1)
		energies[x.level] = energies.get(x.level, []) + [x.energy]
	var mean := func(xs: Array) -> float: return xs.reduce(func(s, v): return s + v, 0.0) / maxf(xs.size(), 1)
	_check(absf(mean.call(energies[2]) / config.energy_for(2) - 1.0) < 0.05 and absf(mean.call(energies[3]) / config.energy_for(3) - 1.0) < 0.05
		and energies[3].max() > energies[3].min(),
		"能量按等级：盲眼噬骸鳗 2 级平均 %.1f（表上 %.0f）、3 级 %.1f（%.0f），个体上下浮动" % [mean.call(energies[2]), config.energy_for(2),
			mean.call(energies[3]), config.energy_for(3)])
	var odd := c.duplicate() as CatchData
	odd.affix_ids = ["mutated"]
	CatchGenerator.evaluate(odd, dace, config)
	_check(odd.tribute == c.tribute * 2, "「变异」祭值翻倍（%d → %d）" % [c.tribute, odd.tribute])

	var rng := _rng(31)
	var recolored := 0
	var mutated := 0
	var hue_ok := true
	var total := 20000
	for i in total:
		var x := CatchGenerator.generate(dace, rng, config)
		var has_hue := x.affix_ids.has("recolored")
		recolored += int(has_hue)
		mutated += int(x.is_mutated())
		hue_ok = hue_ok and has_hue == (x.hue_shift > 0.0)
	_check(absf(recolored / float(total) - 0.03) < 0.006 and absf(mutated / float(total) - 0.0097) < 0.004 and hue_ok,
		"特殊词条：变色 %.1f%%（插图转色相）、变异 %.1f%%" % [recolored * 100.0 / total, mutated * 100.0 / total])


func _test_numbers() -> void:
	print("数字的写法")
	var cases := {2033: "两千零三十三", 1274: "一千二百七十四", 122655: "十二万两千六百五十五", 100001: "十万零一",
		10500: "一万零五百", 20000: "两万", 12: "十二", 1012: "一千零一十二", 120000: "十二万", 22000: "两万两千"}
	var bad := []
	for n in cases:
		if Gothic.chinese_number(n) != cases[n]:
			bad.append("%d → %s" % [n, Gothic.chinese_number(n)])
	_check(bad.is_empty(), "中文数字（批注用）：2033 两千零三十三、1274 一千二百七十四…… %s" % ", ".join(bad))
	_check(Gothic.grouped(1274) == "1,274" and Gothic.grouped(122655) == "122,655" and Gothic.grouped(300) == "300",
		"祭值每三位一个逗号：1,274")
	_check(Gothic.tribute_note(1274) == "此物积蓄的魂蕴，可折为一千二百七十四份献礼。", "批注：%s" % Gothic.tribute_note(1274))
	_check(Gothic.tenths(0.62) == "六成" and Gothic.tenths(0.2) == "两成" and Gothic.tenths(1.0) == "全部",
		"比例写成几成：0.62 六成、0.2 两成、1 全部")

func _average_materials(id: String) -> Dictionary:
	var sums := Materials.empty()
	var rng := _rng(11)
	for i in 500:
		var c := CatchGenerator.generate(GameDB.get_fish(id), rng)
		for m in Materials.ALL:
			sums[m] += c.materials[m]
	return sums


func _test_values() -> void:
	print("各项用途")
	var eel := _average_materials("blind_bone_eel")
	_check(eel[Materials.SHELL] > eel[Materials.FLESH] and eel[Materials.SHELL] > eel[Materials.GLOW], "盲眼噬骸鳗处理出来矿壳最多（%s）" % Materials.format(eel))
	var crone := _average_materials("lantern_crone")
	_check(crone[Materials.GLOW] > crone[Materials.FLESH] and crone[Materials.GLOW] > crone[Materials.SHELL], "磷灯婆处理出来幽光最多（%s）" % Materials.format(crone))

	var config := GameDB.balance
	var fish := GameDB.get_fish("ferryman_sturgeon")
	var low := CatchData.new()
	low.species_id = fish.id
	low.level = 3
	low.body = 8.0
	low.soul_strength = roundi(config.mean_soul(3))
	var high := low.duplicate() as CatchData
	high.level = 5
	high.soul_strength = roundi(config.mean_soul(5))
	CatchGenerator.evaluate(low, fish, config)
	CatchGenerator.evaluate(high, fish, config)
	_check(low.food == high.food and high.load_cost == low.load_cost, "饱腹只看躯体规模，不看等级（3 级 %d，5 级 %d）；载荷也不看等级" % [
		low.food, high.food])
	var strong := low.duplicate() as CatchData
	strong.soul_strength = low.soul_strength + 20
	CatchGenerator.evaluate(strong, fish, config)
	_check(strong.tribute > low.tribute, "灵魂强度越高，祭值越高（%s → %s）" % [Gothic.grouped(low.tribute), Gothic.grouped(strong.tribute)])
	var foods := []
	for v in [0.3, 1.0, 3.0, 8.0, 25.0]:
		var x := low.duplicate() as CatchData
		x.body = v
		CatchGenerator.evaluate(x, fish, config)
		foods.append(x.food)
	_check(foods == [8, 17, 33, 59, 117], "饱腹 = 17 × 躯体规模^0.6：0.3（小型）%d、1（中型）%d、3（大型）%d、8（巨型）%d、25（畸变）%d" % foods)
	var loads := []
	for s in 3:
		var x := low.duplicate() as CatchData
		x.stage = s
		CatchGenerator.evaluate(x, fish, config)
		loads.append(x.load_cost)
	_check(loads == [1, 2, 3], "载荷按时期：幼年 %d、成长 %d、成年 %d" % loads)

	var plain := low.duplicate() as CatchData
	var iron := low.duplicate() as CatchData
	iron.affix_ids = ["iron_bone"]
	CatchGenerator.evaluate(plain, fish, config)
	CatchGenerator.evaluate(iron, fish, config)
	_check(iron.materials[Materials.SHELL] > plain.materials[Materials.SHELL] and iron.materials[Materials.FLESH] == plain.materials[Materials.FLESH],
		"「铁骨」只多出矿壳（%d → %d）" % [plain.materials[Materials.SHELL], iron.materials[Materials.SHELL]])
	var fat := low.duplicate() as CatchData
	fat.affix_ids = ["fat"]
	CatchGenerator.evaluate(fat, fish, config)
	var thin := low.duplicate() as CatchData
	thin.affix_ids = ["scrawny"]
	CatchGenerator.evaluate(thin, fish, config)
	_check(absi(fat.food - roundi(plain.food * 1.4)) <= 1 and absi(thin.food - roundi(plain.food * 0.6)) <= 1,
		"「多肉」饱腹 × 1.4、「枯瘦」× 0.6（%d → %d、%d）" % [plain.food, fat.food, thin.food])
	var dense := low.duplicate() as CatchData
	dense.affix_ids = ["soul_dense"]
	dense.soul_strength = low.soul_strength + 20
	CatchGenerator.evaluate(dense, fish, config)
	_check(dense.tribute > plain.tribute, "「魂蕴」多出的灵魂强度让祭值高（%s → %s）" % [Gothic.grouped(plain.tribute), Gothic.grouped(dense.tribute)])


func _test_hold() -> void:
	print("船舱")
	var config := BalanceConfig.new()
	config.hold_capacity = 3  ## 测的是装满的规则，用一个小的上限
	var who := Contractor.new(config)
	_check(Contractor.new(BalanceConfig.new()).hold_capacity() == 20, "船舱的载荷上限 20，一样大（2026-11-04）")
	var ones := [_make(1), _make(1), _make(1)]
	for c in ones:
		who.keep(c)
	_check(who.hold_load() == 3 and not who.keep(_make(1)), "装满了，再来一条留不下")
	who.eat(ones[0])
	_check(who.hold.size() == 2 and who.hold_load() == 2, "生吞船舱里的一条，腾出 1 载荷")
	var two := _make(2, {}, CatchData.Stage.GROWING)
	_check(not who.can_keep(two), "剩 1 载荷时成长期（占 2）留不下")
	who.dismantle(ones[1])
	_check(who.keep(two) and who.hold_load() == 3, "腾出地方后成长期 + 幼年期正好装满")
	var adult := _make(4, {}, CatchData.Stage.ADULT)
	_check(not who.can_keep(adult) and adult.load_cost == 3, "成年期占 3")
	var rich := _make(1, {Materials.FLESH: 3, Materials.SHELL: 1, Materials.GLOW: 2})
	who.eat(ones[2])
	who.keep(rich)
	var before := who.materials.duplicate()
	var got := who.dismantle(rich)
	_check(not who.hold.has(rich) and got[Materials.FLESH] == 3 and who.materials[Materials.FLESH] == before[Materials.FLESH] + 3
		and who.materials[Materials.GLOW] == before[Materials.GLOW] + 2,
		"处理把它移出船舱，材料入库（%s）" % Materials.format(who.materials))


## 躯体规模（2026-11-04 你定的）：一个数值，0.1–0.5 小型、0.5–2.0 中型、2.0–5.0 大型、5.0–15.0 巨型、15.0 以上畸变（含上限）；
## 成年期是这一种的那一档，成长期小一档、幼年期再小一档（最小到小型），带「变异」的再大一档
func _test_body() -> void:
	print("躯体规模")
	var config := GameDB.balance
	var names := []
	for v in [0.1, 0.5, 0.51, 2.0, 2.01, 5.0, 5.01, 15.0, 15.01, 40.0]:
		names.append(CatchData.BODY_NAMES[config.body_class_of(v)])
	_check(names == ["小型", "小型", "中型", "中型", "大型", "大型", "巨型", "巨型", "畸变", "畸变"],
		"分档（含上限）：0.1、0.5 小型，0.51、2.0 中型，2.01、5.0 大型，5.01、15.0 巨型，15.01 以上畸变：%s" % "、".join(names))
	var rows := []
	var steps := true
	for fish: FishData in GameDB.sorted_values(GameDB.fish):
		var cls := [fish.stage_body(0), fish.stage_body(1), fish.stage_body(2)]
		steps = steps and cls[2] == fish.adult_body and cls[1] == maxi(fish.adult_body - 1, 0) and cls[0] == maxi(fish.adult_body - 2, 0)
		rows.append("%s %s / %s / %s" % [fish.display_name, CatchData.BODY_NAMES[cls[0]], CatchData.BODY_NAMES[cls[1]],
			CatchData.BODY_NAMES[cls[2]]])
	_check(steps, "成年期是这一种的那一档，成长期小一档、幼年期再小一档（最小到小型）：%s" % "，".join(rows))
	var dace := GameDB.get_fish("grey_dace")
	var sturgeon := GameDB.get_fish("ferryman_sturgeon")
	_check(CatchGenerator.body_class_for(sturgeon, CatchData.Stage.ADULT, true) == 4
		and CatchGenerator.body_class_for(dace, CatchData.Stage.JUVENILE, true) == 1
		and CatchGenerator.body_class_for(sturgeon, CatchData.Stage.JUVENILE, true) == 2,
		"带「变异」的大一档：成年的渡魂白鲟是畸变，幼年的灰鲦是中型，幼年的渡魂白鲟是大型")
	var rng := _rng(23)
	var right := true
	var inside := true
	var mutated := 0
	for i in 4000:
		var c := CatchGenerator.generate(sturgeon, rng, config)
		var want := CatchGenerator.body_class_for(sturgeon, c.stage, c.is_mutated())
		var r := config.body_range(want)
		right = right and c.body_class() == want
		inside = inside and c.body >= r.x and c.body <= r.y
		mutated += int(c.is_mutated())
	_check(right and inside and mutated > 0, "四千条渡魂白鲟：躯体规模都落在该在的那一档里（%d 条带「变异」的大一档）" % mutated)
	var middle := []
	for cls in 5:
		middle.append(config.body_at(cls, 0.5))
	_check(absf(middle[0] - 0.224) < 0.01 and absf(middle[2] - 3.16) < 0.02 and absf(config.body_mean(1) / 1.04 - 1.0) < 0.02,
		"每一档的中间（几何平均）：小型 %.2f、中型 %.2f、大型 %.2f、巨型 %.2f、畸变 %.1f；中型掷出来平均 %.2f" % (middle + [config.body_mean(1)]))
	var c := _make(1)
	c.body = 0.23
	var t1 := c.body_text()
	c.body = 3.21
	var t2 := c.body_text()
	_check(t1 == "0.23" and t2 == "3.2", "数值写成字：%s、%s（2 以下两位小数）" % [t1, t2])


func _test_hunger() -> void:
	print("饱腹")
	var config := BalanceConfig.new()
	var who := Contractor.new(config)
	_check(is_equal_approx(who.hunger, 100.0) and who.hunger_tier() == 0 and is_equal_approx(who.stamina_cap(), 1.0),
		"签约时饱腹是满的，不饿，体力上限是满的")
	who.spend_hunger(config.hunger_per_cast)
	_check(is_equal_approx(who.hunger, 100.0 - config.hunger_per_cast), "抛一竿扣 %.0f（新回合机制第 36 条）" % config.hunger_per_cast)
	var fight := TensionModel.new(GameDB.get_fish("blind_bone_eel"), 0, 15.0, config)
	fight.tension = 0.5
	for i in 20:
		fight.step(0.1, true)
	_check(fight.spent > 0.0 and is_equal_approx(fight.spent, config.stamina_max - fight.stamina),
		"搏斗记下耗了多少体力（收线 2 秒 %.1f），打完按每点 %.2f 扣饱腹" % [fight.spent, config.hunger_per_stamina])
	who.spend_hunger(500.0)
	_check(who.hunger == 0.0, "饿到 0 就不再往下掉")
	var caps := []
	var drains := []
	for h in [100.0, 60.0, 59.0, 30.0, 29.0, 0.0]:
		caps.append(config.stamina_cap(h))
		drains.append(config.stamina_drain_mult(h))
	var expect_caps := [1.0, 1.0, 0.85, 0.85, 0.65, 0.65]
	var expect_drains := [1.0, 1.0, 1.0, 1.0, 1.2, 1.2]
	var same := true
	for i in caps.size():
		same = same and is_equal_approx(caps[i], expect_caps[i]) and is_equal_approx(drains[i], expect_drains[i])
	_check(same,
		"饱腹 60 以下体力上限 −15%%，30 以下 −35%%、体力掉得快 20%%：%s" % ", ".join(caps.map(func(x: float) -> String: return "%.2f" % x)))

	var eater := Contractor.new(config)
	eater.hunger = 95.0
	var big := _make(1)
	big.food = 30
	var gain := eater.eat_gain(big)
	eater.eat(big)
	_check(eater.hunger == 100.0 and gain.food == 5.0 and gain.overflow == 25.0, "吃撑了饱腹到 100 为止（加上 %.0f，多出 %.0f）" % [gain.food, gain.overflow])

	var eel := GameDB.get_fish("blind_bone_eel")
	var fed := TensionModel.new(eel, 0, 15.0, config, null, CatchData.Stage.GROWING, 80.0)
	var hungry := TensionModel.new(eel, 0, 15.0, config, null, CatchData.Stage.GROWING, 45.0)
	var starving := TensionModel.new(eel, 0, 15.0, config, null, CatchData.Stage.GROWING, 10.0)
	_check(is_equal_approx(fed.stamina, 100.0) and is_equal_approx(hungry.stamina, 85.0) and is_equal_approx(starving.stamina, 65.0)
		and is_equal_approx(starving.stamina_cap(), 0.65), "上钩时的体力：饱 %.0f、饿 %.0f、饿得发慌 %.0f" % [fed.stamina, hungry.stamina, starving.stamina])
	fed.tension = 0.5
	starving.tension = 0.5
	fed.step(0.1, true)
	starving.step(0.1, true)
	_check(is_equal_approx(65.0 - starving.stamina, (100.0 - fed.stamina) * 1.2), "饿得发慌时收线耗的体力是 1.2 倍")
	for i in 600:
		starving.step(0.1, false)
	_check(starving.stamina <= 65.0 + 0.001, "松手歇着回体力，回不过饿掉以后的上限（%.1f）" % starving.stamina)


## 每种生物的个体概况，改了数值后看一眼
func _report() -> void:
	print("个体概况（每种 500 条的平均）")
	for fish: FishData in GameDB.sorted_values(GameDB.fish):
		var rng := _rng(5)
		var level := 0.0
		var food := 0.0
		var energy := 0.0
		var tribute := 0.0
		var mats := Materials.empty()
		for i in 500:
			var c := CatchGenerator.generate(fish, rng)
			level += c.level
			food += c.food
			energy += c.energy
			tribute += c.tribute
			for m in Materials.ALL:
				mats[m] += c.materials[m]
		print("    %-6s 等级 %.2f  祭值 %6.0f  饱腹 %5.1f  能量 %4.1f  材料 血肉 %4.1f 矿壳 %4.1f 幽光 %4.1f" % [
			fish.display_name, level / 500.0, tribute / 500.0, food / 500.0, energy / 500.0,
			mats[Materials.FLESH] / 500.0, mats[Materials.SHELL] / 500.0, mats[Materials.GLOW] / 500.0])
