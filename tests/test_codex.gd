extends Node
## 图鉴的数据自检（Codex）：图鉴上写的机会、平均祭值和真去钓（CatchGenerator、BiteCalculator）对得上。命令行运行：
##   Godot_v4.6.3-stable_win64.exe --headless --path . res://tests/test_codex.tscn
## 最后印一份图鉴的内容（各种生物、各层水域），和游戏里 C 键打开的是同一份数。
## 立绘的动效（2026-11-05）：每一种的 motion_style 都认得；正式的每张插图都烘了动效遮罩（tools/bake_motion_masks.py），宽高比对得上；
## 会游的每张插图还有"脊"（沿着弯的身子传波）。

const SAMPLES := 12000

var _failures := 0
var _config: BalanceConfig


func _ready() -> void:
	_config = GameDB.balance
	_test_known()
	_test_sampled()
	_test_bites()
	_test_layers()
	_test_motion()
	_report()
	print("\n==== %s（失败 %d 项）====" % ["全部通过" if _failures == 0 else "存在失败", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## 动效：每一种（连名册草案）的 motion_style 在 CreatureArt.STYLES 里；正式的每个时期的插图都有遮罩，宽高比和插图一样
## （新加了插图忘了跑 tools/bake_motion_masks.py，这里会报出来）
func _test_motion() -> void:
	print("立绘的动效")
	GameDB.use_draft_fish()
	var unknown := []
	for fish: FishData in GameDB.sorted_values(GameDB.fish):
		if not CreatureArt.STYLES.has(fish.motion_style):
			unknown.append("%s（%s）" % [fish.display_name, fish.motion_style])
	_check(unknown.is_empty(), "二十种的动效都认得：%s" % ("没有不认得的" if unknown.is_empty() else "、".join(unknown)))
	GameDB.use_draft_fish(false)
	var missing := []
	var off := []
	var spines := []
	var styles := {}
	for fish: FishData in Codex.species_order():
		styles[fish.motion_style] = styles.get(fish.motion_style, 0) + 1
		for s in 3:
			var tex: Texture2D = fish.stage_icon(s)
			if tex == null:
				continue
			if fish.motion_style in CreatureArt.SWIMMERS and CreatureArt.body_for(tex) == null:
				spines.append(tex.resource_path.get_file())
			var mask := CreatureArt.mask_for(tex)
			if mask == null:
				missing.append(tex.resource_path.get_file())
				continue
			var ratio := tex.get_size().x / tex.get_size().y
			var mratio := mask.get_size().x / mask.get_size().y
			if absf(ratio - mratio) / ratio > 0.03:
				off.append(tex.resource_path.get_file())
	_check(missing.is_empty(), "正式的每张插图都烘了动效遮罩：%s" % ("都有" if missing.is_empty() else "缺 " + "、".join(missing)))
	_check(off.is_empty(), "遮罩和插图的宽高比对得上：%s" % ("都对" if off.is_empty() else "不对 " + "、".join(off)))
	_check(spines.is_empty(), "会游的每张插图都有脊（沿着弯的身子传波）：%s" % ("都有" if spines.is_empty() else "缺 " + "、".join(spines)))
	var parts: PackedStringArray = []
	for k in styles:
		parts.append("%s %d" % [CreatureArt.STYLES[k].name, styles[k]])
	_check(styles.size() >= 4, "正式的七种至少分四种动效（%s）" % "、".join(parts))


func _check(cond: bool, msg: String) -> void:
	print(("  [OK]   " if cond else "  [FAIL] ") + msg)
	if not cond:
		_failures += 1


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _test_known() -> void:
	print("收录")
	var all := Codex.species_order()
	_check(all.size() == GameDB.fish.size() and Codex.reveal_all and Codex.known_count() == all.size(),
		"测试期间全开：%d 种都收录了" % Codex.known_count())
	var names: PackedStringArray = []
	for f: FishData in all:
		names.append(f.display_name)
	var sorted_ok := true
	for i in range(1, all.size()):
		var p: FishData = all[i - 1]
		var q: FishData = all[i]
		sorted_ok = sorted_ok and (p.level_min < q.level_min or (p.level_min == q.level_min and p.level_max <= q.level_max))
	_check(all[0].id == "grey_dace" and sorted_ok, "顺序从弱到强（先按最低等级，再按最高等级）：%s" % "、".join(names))
	Codex.reveal_all = false
	var saved := GameState.catches.duplicate()
	GameState.catches.clear()
	var none := Codex.known_count()
	GameState.record_catch(GameDB.get_fish("grey_dace"))
	var one := Codex.known_count()
	GameState.catches = saved
	Codex.reveal_all = true
	_check(none == 0 and one == 1, "关掉全开：没钓上来过的不收录（%d 种），钓上一条灰鲦就收录它（%d 种）" % [none, one])


## 图鉴上每层水里它钓上来是哪个时期几级、平均祭值、平均处理材料，和真去生成一样（每种、每层水生成 SAMPLES 条）。
## 祭值、材料只比没带词条的：图鉴上写的是没有词条的那一条
func _test_sampled() -> void:
	print("和真去生成的比")
	var rng := _rng(11)
	var worst := {"odds": [0.0, ""], "tribute": [0.0, ""], "materials": [0.0, ""]}
	for fish: FishData in Codex.species_order():
		for depth in Codex.depths(fish, _config):
			var where := "%s 在%s" % [fish.display_name, GameDB.DEPTH_NAMES[depth]]
			var entries := Codex.stage_entries(fish, depth, _config)
			var counts := {}
			var tribute := 0.0
			var mats := 0.0
			var plain := 0
			for i in SAMPLES:
				var c := CatchGenerator.generate(fish, rng, _config, 0, depth)
				var key := "%d:%d" % [c.stage, c.level]
				counts[key] = counts.get(key, 0) + 1
				if c.affix_ids.is_empty():
					plain += 1
					tribute += c.tribute
					for m in Materials.ALL:
						mats += c.materials.get(m, 0)
			var covered := 0
			for e in entries:
				var key := "%d:%d" % [e.stage, e.level]
				covered += counts.get(key, 0)
				_worse(worst, "odds", absf(counts.get(key, 0) / float(SAMPLES) - e.share),
					"%s%s %d 级" % [where, CatchData.STAGE_NAMES[e.stage], e.level])
			_worse(worst, "odds", 1.0 - covered / float(SAMPLES), where + "（图鉴上没有的时期、等级）")
			var expect := Codex.mean_tribute(fish, depth, _config)
			var mean := tribute / maxf(plain, 1.0)
			_worse(worst, "tribute", absf(mean / expect - 1.0), "%s：图鉴 %s、生成的 %s" % [where, Gothic.grouped(roundi(expect)),
				Gothic.grouped(roundi(mean))])
			var mm := Codex.mean_materials(fish, depth, _config)
			var expect_mats: float = mm.flesh + mm.shell + mm.glow
			_worse(worst, "materials", absf(mats / maxf(plain, 1.0) / expect_mats - 1.0), "%s：图鉴 %.2f 份、生成的 %.2f 份" % [
				where, expect_mats, mats / maxf(plain, 1.0)])
	_check(worst.odds[0] < 0.02, "钓上来是哪个时期几级（差得最多 %.1f%%：%s）" % [worst.odds[0] * 100.0, worst.odds[1]])
	_check(worst.tribute[0] < 0.04, "平均祭值（差得最多 %.1f%%：%s）" % [worst.tribute[0] * 100.0, worst.tribute[1]])
	_check(worst.materials[0] < 0.04, "平均处理材料（差得最多 %.1f%%：%s）" % [worst.materials[0] * 100.0, worst.materials[1]])


func _worse(worst: Dictionary, key: String, gap: float, where: String) -> void:
	if gap > worst[key][0]:
		worst[key] = [gap, where]


## 万能饵下占的就是这层水本来的份额（WaterLayers.presence）；最招它的饵不会比万能饵差
func _test_bites() -> void:
	print("上钩")
	var universal := BaitCrafter.make_universal(1)
	var ok := true
	var better := true
	for depth in GameDB.DEPTH_NAMES.size():
		for fish: FishData in Codex.species_order():
			var share := Codex.bite_share(fish, universal, depth, _config)
			ok = ok and absf(share - WaterLayers.presence(fish, depth, _config)) < 0.0001
			if WaterLayers.has(fish, depth, _config):
				better = better and Codex.best_bait(fish, depth, _config).share >= share - 0.0001
	_check(ok, "万能饵：咬钩的里面各占几成 = 这层水本来的样子（按这层水出几级、它哪个时期是几级）")
	_check(better and Codex.all_baits(_config).size() == 1 + 6 * GameDB.additives.size(),
		"%d 份饵（万能饵 + 六种基础组合 × %d 种附加物）里挑出的最招它的饵，都不比万能饵差" % [Codex.all_baits(_config).size(),
		GameDB.additives.size()])


func _test_layers() -> void:
	print("各层水域")
	var ok := true
	var shallow_ok := true
	var abyss_ok := true
	for depth in GameDB.DEPTH_NAMES.size():
		var info := Codex.layer(depth, _config)
		var sum := 0.0
		for row in info.species:
			sum += row.share
			for e in row.entries:
				shallow_ok = shallow_ok and (depth != 0 or e.level == 1)
				abyss_ok = abyss_ok and (depth != 2 or e.level >= 2)
		ok = ok and absf(sum - 1.0) < 0.0001 and info.tribute > 0.0
	_check(ok, "三层水都有东西咬钩，各种占的加起来是 1，每咬一口的平均祭值算得出来")
	_check(shallow_ok and abyss_ok, "浅层只出 1 级的，渊底没有 1 级的")


func _pct(x: float) -> String:
	return "%d%%" % roundi(x * 100.0)


## 印一份图鉴的内容
func _report() -> void:
	print("\n图鉴（常见的一条：中等个头、平均灵魂强度、没有词条）")
	for fish: FishData in Codex.species_order():
		var stages: PackedStringArray = []
		for s in 3:
			stages.append("%s %s" % [CatchData.STAGE_NAMES[s], Codex.stage_level_text(fish, s)])
		print("\n%s　%s（%s）　出没：%s　身上的材料：%s" % [fish.display_name, Codex.level_text(fish), "、".join(stages),
			Codex.depth_text(fish, _config), " · ".join(Materials.ALL.map(func(m: String) -> String:
				return "%s %s" % [Materials.SHORT[m], _pct(Materials.normalized(fish.material_ratio)[m])]))])
		for depth in Codex.depths(fish, _config):
			var parts: PackedStringArray = []
			for e in Codex.stage_entries(fish, depth, _config):
				parts.append("%s %d 级 %s" % [CatchData.STAGE_NAMES[e.stage], e.level, _pct(e.share)])
			var best := Codex.best_bait(fish, depth, _config)
			print("  %s　%s　万能饵下占 %s　平均祭值 %s　最招它的饵 %s（%s，空竿 %s）" % [GameDB.DEPTH_NAMES[depth], " · ".join(parts),
				_pct(Codex.bite_share(fish, BaitCrafter.make_universal(1), depth, _config)),
				Gothic.grouped(roundi(Codex.mean_tribute(fish, depth, _config))), best.bait.display_name, _pct(best.share),
				_pct(best.nothing)])
		for s in 3:
			var levels := fish.stage_levels(s)
			for level in range(levels.x, levels.y + 1):
				var c := Codex.typical(fish, level, s, _config)
				var m := Codex.materials_range(fish, level, s, _config)
				var mats := "%d" % m.x if m.x == m.y else "%d–%d" % [m.x, m.y]
				print("  %s %d 级　祭值 %s（%s，处理 %s 份，饱腹 +%d，能量 %d，灵魂强度约 %d）" % [CatchData.STAGE_NAMES[s], level,
					Gothic.grouped(c.tribute), c.body_name(), mats, c.food, c.energy, c.soul_strength])
	print("\n各层水域（万能饵；咬钩的里面各占几成）")
	for depth in GameDB.DEPTH_NAMES.size():
		var info := Codex.layer(depth, _config)
		var rows: PackedStringArray = []
		for row in info.species:
			rows.append("%s %s" % [row.fish.display_name, _pct(row.share)])
		var levels: PackedStringArray = []
		for i in 5:
			if info.levels[i] > 0.0:
				levels.append("%d 级 %s" % [i + 1, _pct(info.levels[i])])
		var m: Dictionary = info.materials
		print("  %s　%s　｜%s；每咬一口平均祭值 %s，处理 血肉 %.2f 矿壳 %.2f 幽光 %.2f；幼 %s 成长 %s 成年 %s；空 %s" % [
			GameDB.DEPTH_NAMES[depth], " · ".join(rows), " · ".join(levels), Gothic.grouped(roundi(info.tribute)), m.flesh,
			m.shell, m.glow, _pct(info.stages[0]), _pct(info.stages[1]), _pct(info.stages[2]), _pct(info.nothing)])
