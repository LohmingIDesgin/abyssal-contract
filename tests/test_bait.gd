extends Node
## 饵料自检 + 测量表。命令行运行：
##   Godot_v4.6.3-stable_win64.exe --headless --path . res://tests/test_bait.tscn
## 测量表：每个水层、六种基础组合（配基础款附加物）和万能饵，各自的空竿率、最常咬钩的三种，
## 以及每咬一口平均能处理出多少材料、全拆的话每咬一口换回几份饵（假设都钓上来、都处理掉，所以是上限）；
## 再看三种附加物把倾向往哪边推。一份饵挂一次、真咬钩才扣（新回合机制第 30 条），所以"每咬一口换回几份饵"要小于 1，
## 不然没有倒计时就能一直钓下去。

const COMBOS := [["flesh", "flesh"], ["flesh", "shell"], ["flesh", "glow"], ["shell", "shell"], ["shell", "glow"], ["glow", "glow"]]
const SAMPLES := 400  ## 每种生物抽多少个个体，算平均处理出来的材料

var _failures := 0
var _config: BalanceConfig
var _avg := {}  ## 种类id → 平均材料


func _ready() -> void:
	_config = GameDB.balance
	_test_data()
	_test_crafting()
	_test_universal()
	_test_spent_on_bite()
	_test_bite_rules()
	_measure()
	print("\n==== %s（失败 %d 项）====" % ["全部通过" if _failures == 0 else "存在失败", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	print(("  [OK]   " if cond else "  [FAIL] ") + msg)
	if not cond:
		_failures += 1


func _bait(bases: Array, additive_id := "skin_mince") -> Bait:
	return BaitCrafter.make(bases, additive_id, _config)


func _chance(table: Array[Dictionary], id: String) -> float:
	for e in table:
		if (e.fish == null and id == "") or (e.fish != null and e.fish.id == id):
			return e.chance
	return 0.0


func _test_data() -> void:
	print("数据")
	_check(GameDB.additives.size() >= 4, "附加物 %d 种" % GameDB.additives.size())
	var unlimited: Array = GameDB.additives.values().filter(func(a: AdditiveData) -> bool: return a.unlimited)
	_check(unlimited.size() == 1 and GameDB.basic_additive().display_name == "皮屑肉糜混合物",
		"只有一种用不完的基础款：皮屑肉糜混合物")
	for a: AdditiveData in GameDB.additives.values():
		if not a.unlimited:
			_check(a.aspect in Aspect.ALL and a.name_token != "", "%s 带一种气味（%s）" % [a.display_name, Aspect.display_name(a.aspect)])
	for fish: FishData in GameDB.fish.values():
		var ok := true
		for k in fish.preferences:
			ok = ok and k in Aspect.ALL
		_check(ok, "%s 的偏好都是认得的气味" % fish.display_name)


func _test_crafting() -> void:
	print("制饵")
	var who := Contractor.new(_config)
	var no_bases := true
	for m in Materials.ALL:
		no_bases = no_bases and who.materials.get(m, 0) == 0
	_check(no_bases and who.additives.get("drowned_nail", 0) == 1, "开局不送基础材料（第 34 条），附加物各一个")
	who.materials = {"flesh": 4, "shell": 2, "glow": 2}
	_check(BaitCrafter.combo_key(["shell", "flesh"]) == "flesh+shell", "两份基础材料不分先后")
	_check(BaitCrafter.name_for(["shell", "shell"], GameDB.get_additive("drowned_nail")) == "甲·骨渣饵"
		and BaitCrafter.name_for(["flesh", "flesh"], GameDB.basic_additive()) == "腥糜饵", "起名：甲·骨渣饵、腥糜饵")
	var bait := BaitCrafter.craft(who, ["shell", "flesh"], "drowned_nail")
	_check(bait != null and bait.uses == 1 and _config.bait_uses == 1 and bait.bases == ["flesh", "shell"],
		"血肉 + 矿壳 + 指甲 → 「%s」，一份挂一次（第 30 条）" % [bait.display_name if bait else ""])
	_check(who.materials.flesh == 3 and who.materials.shell == 1 and who.additives.drowned_nail == 0, "扣了一份血肉、一份矿壳、一个指甲")
	var before := who.materials.duplicate()
	_check(BaitCrafter.craft(who, ["flesh", "flesh"], "drowned_nail") == null and who.materials == before,
		"指甲用完了就做不了，什么也不扣")
	_check(BaitCrafter.craft(who, ["glow", "glow"], "skin_mince") != null and who.additive_count("skin_mince") == -1,
		"基础款用不完")
	_check(BaitCrafter.craft(who, ["glow", "glow"], "skin_mince") == null, "幽光不够两份就做不了")
	_check(bait.same_recipe(_bait(["flesh", "shell"], "drowned_nail")) and not bait.same_recipe(_bait(["flesh", "shell"])),
		"同一配方才叠在一起")


func _test_universal() -> void:
	print("万能饵")
	var u := BaitCrafter.make_universal(3)
	_check(u.universal and u.uses == 3 and u.bases.is_empty() and u.display_name == "万能饵", "三份万能饵叠成一叠，没有基础材料")
	_check(u.same_recipe(BaitCrafter.make_universal(1)) and not u.same_recipe(_bait(["flesh", "flesh"])), "万能饵和万能饵叠，不和做的饵叠")
	GameState.baits.clear()
	GameState._give_starter_bait()
	_check(GameState.baits.size() == 1 and GameState.baits[0].universal and GameState.baits[0].uses == _config.start_baits,
		"开局送 %d 份万能饵" % _config.start_baits)
	var table := BiteCalculator.bite_table(u, 0, _config)
	var dace := GameDB.get_fish("grey_dace")
	var rest := 1.0 - _config.universal_nothing
	_check(is_equal_approx(_chance(table, ""), _config.universal_nothing)
		and is_equal_approx(_chance(table, "grey_dace"), rest * WaterLayers.presence(dace, 0, _config)),
		"万能饵：空的固定 %.0f%%，咬钩的按这层水本来的样子（浅层灰鲦 %.0f%%）" % [_config.universal_nothing * 100,
			_chance(table, "grey_dace") * 100])


## 咬钩才扣饵（第 30 条，2026-11-02 改）：整局模拟器里每一夜咬钩用掉的饵正好是咬钩的口数，
## 什么也没咬、捞到东西、碰上海上事件（阶段 IV）的那几竿不扣（残骸花的那一份饵是事件里选的，不算在这里）
func _test_spent_on_bite() -> void:
	print("咬钩才扣饵")
	var sim := ContractSim.new(_config, ContractSim.STRATEGIES["多拆续钓"], ContractSim.SKILLS["普通"])
	var nights := 0
	var free := 0
	var ok := true
	for s in 20:
		for n in sim.run(500 + s).nights:
			nights += 1
			var event := 1 if n.event != "" else 0
			free += n.nothing + n.salvage + event
			ok = ok and n.universal_used + n.crafted_used == n.bites and n.casts == n.bites + n.nothing + n.salvage + event
	_check(ok and free > 0, "20 份契约 %d 夜：咬钩用掉的饵 = 咬钩的口数，%d 竿什么也没咬、捞到东西或者碰上海上事件，没扣饵" % [nights, free])


func _test_bite_rules() -> void:
	print("上钩")
	var all_ok := true
	for depth in GameDB.DEPTH_NAMES.size():
		for bases in COMBOS:
			for additive in GameDB.additives:
				var sum := 0.0
				for e in BiteCalculator.bite_table(_bait(bases, additive), depth, _config):
					sum += e.chance
				all_ok = all_ok and is_equal_approx(sum, 1.0)
		var universal_sum := 0.0
		for e in BiteCalculator.bite_table(BaitCrafter.make_universal(1), depth, _config):
			universal_sum += e.chance
		all_ok = all_ok and is_equal_approx(universal_sum, 1.0)
	_check(all_ok, "每张上钩表的概率加起来都是 1")
	var shallow := BiteCalculator.bite_table(_bait(["flesh", "flesh"]), 0, _config)
	_check(shallow[0].fish != null and shallow[0].fish.id in ["bloodtooth_pomfret", "grey_dace"], "浅层用腥糜饵，最常咬钩的是冥鲳或灰鲦")
	var mid := BiteCalculator.bite_table(_bait(["shell", "shell"]), 1, _config)
	_check(mid[0].fish != null and mid[0].fish.id in ["salt_corpse_crab", "blind_bone_eel"], "深水用骨渣饵，最常咬钩的是盐尸蟹或噬骸鳗（%s）" % (mid[0].fish.display_name if mid[0].fish else "—"))
	var deep := BiteCalculator.bite_table(_bait(["glow", "glow"]), 1, _config)
	_check(deep[0].fish != null and deep[0].fish.id in ["soul_jelly", "lantern_crone"], "深水用萤浆饵，最常咬钩的是磷魂母或磷灯婆（%s）" % (deep[0].fish.display_name if deep[0].fish else "—"))
	var nail := _chance(BiteCalculator.bite_table(_bait(["shell", "shell"], "drowned_nail"), 1, _config), "ferryman_sturgeon")
	var plain := _chance(BiteCalculator.bite_table(_bait(["shell", "shell"]), 1, _config), "ferryman_sturgeon")
	_check(nail > plain * 1.5, "指甲把白鲟（幼年）引上来（深水骨渣饵 %.0f%% → %.0f%%）" % [plain * 100, nail * 100])
	var bug := _chance(BiteCalculator.bite_table(_bait(["shell", "shell"], "phosphor_bug"), 1, _config), "blind_bone_eel")
	var eel := _chance(mid, "blind_bone_eel")
	_check(bug < eel * 0.8, "磷火虫让怕光的噬骸鳗躲开（深水骨渣饵 %.0f%% → %.0f%%）" % [eel * 100, bug * 100])
	var egg := _chance(BiteCalculator.bite_table(_bait(["flesh", "flesh"], "rotten_harpy_egg"), 0, _config), "bloodtooth_pomfret")
	var pomfret := _chance(shallow, "bloodtooth_pomfret")
	_check(egg < pomfret, "坏怪鸟蛋让嫌腐的冥鲳躲开（浅层腥糜饵 %.0f%% → %.0f%%）" % [pomfret * 100, egg * 100])
	# 什么也没咬（第 32 条）：对路的饵是 nothing_chance，不对路的往上加，万能饵固定。
	# 阶段 V 上线以后每层水三种材料多的都有（浅层有骨刺鳉），纯一种材料的饵哪层都对路，不对路的按公式查（最不合的时候加满）
	var fit := _chance(shallow, "")
	var shell := _chance(BiteCalculator.bite_table(_bait(["shell", "shell"]), 0, _config), "")
	var deep_empty := _chance(deep, "")
	var worst := BiteCalculator.nothing_chance(_bait(["shell", "shell"]), 0.0, _config)
	_check(absf(fit - _config.nothing_chance) < 0.03 and absf(deep_empty - _config.nothing_chance) < 0.03
		and absf(shell - _config.nothing_chance) < 0.03 and absf(worst - _config.nothing_chance - _config.mismatch_nothing) < 0.001,
		"什么也没咬：浅层腥糜饵 %.0f%%、深水萤浆饵 %.0f%%、浅层骨渣饵 %.0f%%（都对路），最不合的饵 %.0f%%" % [fit * 100, deep_empty * 100, shell * 100, worst * 100])


## 每种生物处理出来的平均材料（全部处理时）
func _average_materials() -> void:
	var rng := RandomNumberGenerator.new()
	for fish: FishData in GameDB.fish.values():
		var total := Materials.empty()
		for s in SAMPLES:
			rng.seed = s * 7919
			var c := CatchGenerator.generate(fish, rng, _config, 0, WaterLayers.depths_of(fish, CodexScreen._config_for(fish))[-1])
			for m in Materials.ALL:
				total[m] += c.materials.get(m, 0)
		var avg := {}
		for m in Materials.ALL:
			avg[m] = float(total[m]) / SAMPLES
		_avg[fish.id] = avg


## 一张上钩表平均每咬一口能处理出的材料 {flesh, shell, glow}（什么也没咬的不算：不扣饵）
func _yield_per_bite(table: Array[Dictionary]) -> Dictionary:
	var result := Materials.empty_ratio()
	var bite := 1.0 - _chance(table, "")
	for e in table:
		if e.fish == null:
			continue
		var avg: Dictionary = _avg[e.fish.id]
		for m in Materials.ALL:
			result[m] += e.chance / maxf(bite, 0.001) * avg[m]
	return result


func _row(label: String, table: Array[Dictionary]) -> String:
	var top: PackedStringArray = []
	for e in table:
		if e.fish != null and top.size() < 3:
			top.append("%s %2.0f%%" % [e.fish.display_name, e.chance * 100.0])
	var y := _yield_per_bite(table)
	var per_bite: float = (y.flesh + y.shell + y.glow) / 2.0
	return "    %-8s 空 %2.0f%% | 每口材料 血肉 %.2f 矿壳 %.2f 幽光 %.2f，换回 %.2f 份饵 | %s" % [label, _chance(table, "") * 100.0,
		y.flesh, y.shell, y.glow, per_bite, "、".join(top)]


func _measure() -> void:
	_average_materials()
	print("\n测量表：每咬一口平均能处理出的材料（都钓上、都处理时的上限；一份饵花 2 份基础材料，咬一口用掉一份）")
	for depth in GameDB.DEPTH_NAMES.size():
		print("  %s" % GameDB.DEPTH_NAMES[depth])
		for bases in COMBOS:
			var b := _bait(bases)
			print(_row(b.display_name, BiteCalculator.bite_table(b, depth, _config)))
		print(_row("万能饵", BiteCalculator.bite_table(BaitCrafter.make_universal(1), depth, _config)))
	print("\n附加物的作用（血骨饵，即血肉 + 矿壳）：")
	for depth in GameDB.DEPTH_NAMES.size():
		print("  %s" % GameDB.DEPTH_NAMES[depth])
		for a: AdditiveData in GameDB.sorted_values(GameDB.additives):
			var b := _bait(["flesh", "shell"], a.id)
			print(_row(b.display_name, BiteCalculator.bite_table(b, depth, _config)))
	print("\n每种生物处理出来的平均材料（在它最深的那层水钓上来的）：")
	for fish: FishData in GameDB.sorted_values(GameDB.fish):
		var avg: Dictionary = _avg[fish.id]
		print("    %-6s 血肉 %.2f 矿壳 %.2f 幽光 %.2f（共 %.2f）" % [fish.display_name, avg.flesh, avg.shell, avg.glow,
			avg.flesh + avg.shell + avg.glow])
