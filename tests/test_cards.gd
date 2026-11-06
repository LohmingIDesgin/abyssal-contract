extends Node
## 供奉后的奖励卡自检（新回合机制 9.6，H2）。命令行运行：
##   Godot_v4.6.3-stable_win64.exe --headless --path . res://tests/test_cards.tscn
## 查：卡池七张都读得到、卡面写得齐；几张候选（不够 0、够了 2、超额 3，偿清和死了不给）、抽出来不重复；
## 拿到就生效的（饱餐、余饵）；留到下一夜的有次数、用完就没、再唤祂（offer）时清掉；
## 剖腹让下一夜每一次处理翻倍；引深让下一次咬钩的换成高一级的（不看水层）、只换一次；进化长一个时期、成年的不算、
## 只差一级的种类按灵魂强度定等级；壮魂让体力掉得慢；镇魂下一夜每一场都按高一级算。

var _failures := 0
var _config: BalanceConfig
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_config = GameDB.balance
	_rng.seed = 11
	_test_pool()
	_test_choices()
	_test_instant()
	_test_lasting()
	_test_dissect()
	_test_lure()
	_test_evolve()
	_test_vigor()
	_test_boons()
	_test_draw()
	_test_more_boons()
	print("\n==== %s（失败 %d 项）====" % ["全部通过" if _failures == 0 else "存在失败", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	print(("  [OK]   " if cond else "  [FAIL] ") + msg)
	if not cond:
		_failures += 1


func _test_pool() -> void:
	print("卡池")
	var ids := GameDB.cards.keys()
	ids.sort()
	_check(ids == ["abyss_walker", "bait_heart", "blood_lure", "bone_flute", "bone_pick", "carcass", "crown_catch", "dissect", "evolve",
		"feast", "fed_courage", "hungry_offer", "item_abyss_eye", "item_soul_nail", "item_soul_thread", "kin", "lure", "oddity", "overflow",
		"regular", "ride_waves", "spare_bait", "steady", "taut_line", "vigor"],
		"十六张永久恩赐（阶段 V 加了六张）、两张立刻生效的、四张一夜卡、三张道具卡：%s" % [ids])
	var permanent := GameDB.sorted_values(GameDB.cards).filter(func(c: RewardCard) -> bool: return c.permanent)
	_check(permanent.size() == 16 and permanent.all(func(c: RewardCard) -> bool: return not c.tags.is_empty()),
		"永久恩赐都标了引擎（资源 / 捕获 / 祭值）")
	for card: RewardCard in GameDB.sorted_values(GameDB.cards):
		_check(card.display_name != "" and card.description != "" and card.duration != "" and card.icon != null,
			"「%s」名字、效果、持续多久、图标都有（%s）" % [card.display_name, card.duration])


func _test_choices() -> void:
	print("几张候选")
	var met := {"met": true, "tribute": 2000, "demand": 2000, "repaid": false, "died": false}
	var over := {"met": true, "tribute": 3000, "demand": 2000, "repaid": false, "died": false}
	var short := {"met": false, "tribute": 1000, "demand": 2000, "repaid": false, "died": false}
	_check(RewardCards.choice_count(short, _config) == 0, "不够：没有候选，只有补给")
	_check(RewardCards.choice_count(met, _config) == 2, "够了（不到 150%）：两张")
	_check(RewardCards.choice_count({"met": true, "tribute": 2999, "demand": 2000}, _config) == 2, "差一点到 150%：还是两张")
	_check(RewardCards.choice_count(over, _config) == 3, "到了 150%：三张")
	var repaid := over.duplicate()
	repaid.repaid = true
	_check(RewardCards.choice_count(repaid, _config) == 0, "契约已偿：直接进结算清单，不选卡")
	var distinct := true
	var items_when_met := 0
	var items_when_over := 0
	for i in 400:
		var drawn := RewardCards.draw(3, _rng, i % 2 == 1)
		var ids := {}
		for c in drawn:
			ids[c.id] = true
			if c.effect == "item":
				if i % 2 == 1:
					items_when_over += 1
				else:
					items_when_met += 1
		distinct = distinct and drawn.size() == 3 and ids.size() == 3
	_check(distinct, "抽三张候选：四百回都不重复")
	_check(items_when_met == 0 and items_when_over > 0,
		"道具卡只有超额时抽得到（够了的 0 张，超额的两百回里抽到 %d 张；2026-11-04 起祂不再赐道具）" % items_when_over)
	var who := Contractor.new(_config)
	who.take_card(GameDB.get_card("item_soul_nail"))
	_check(who.items.get("soul_nail", 0) == 1 and who.card_effects.is_empty(), "道具卡：拿到一枚镇魂钉，进道具栏")
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 5
	b.seed = 5
	_check(RewardCards.draw(3, a).map(func(c): return c.id) == RewardCards.draw(3, b).map(func(c): return c.id), "同一个种子抽出来的一样")


func _test_instant() -> void:
	print("拿到就生效")
	var who := Contractor.new(_config)
	who.hunger = 30.0
	var r := who.take_card(GameDB.get_card("feast"))
	_check(is_equal_approx(who.hunger, 70.0) and r.baits == 0, "饱餐：饱腹 30 → %.0f" % who.hunger)
	who.hunger = 90.0
	who.take_card(GameDB.get_card("feast"))
	_check(is_equal_approx(who.hunger, _config.hunger_max), "饱餐：最多到满（%.0f）" % who.hunger)
	_check(not who.has_card("feast"), "饱餐：拿到就生效，不留到下一夜（生吞不长级了，吃撑不吃撑无所谓，2026-11-04）")
	r = who.take_card(GameDB.get_card("spare_bait"))
	_check(r.baits == 1 and not who.has_card("spare_bait"), "余饵：多一份万能饵（交给饵料篓），不留到下一夜")
	_check(who.cards_taken == ["feast", "feast", "spare_bait"], "选过的卡记在账上（结算清单用）：%s" % [who.cards_taken])


func _test_lasting() -> void:
	print("留到下一夜的")
	var who := Contractor.new(_config)
	who.take_card(GameDB.get_card("lure"))
	_check(who.has_card("lure"), "引深：留到下一夜")
	_check(who.use_card("lure") and not who.has_card("lure") and not who.use_card("lure"), "引深：一次，用了就没了")
	who.take_card(GameDB.get_card("steady"))
	_check(who.use_card("steady") and who.use_card("steady") and who.has_card("steady"), "镇魂：下一夜每一场都管，用几次都还在")
	var vigor := GameDB.get_card("vigor")
	who.take_card(vigor)
	_check(who.use_card("vigor") and who.has_card("vigor") and is_equal_approx(who.card_amount("vigor"), vigor.amount),
		"壮魂：一整夜都管，体力多撑 %.0f%%" % (vigor.amount * 100.0))
	who.offer([], _rng)
	_check(who.card_effects.is_empty(), "再唤祂（供奉）时，没用掉的清掉")
	var record := Settlement.record(who, "offering")
	_check(record.cards == ["lure", "steady", "vigor"], "结算清单里有选过的卡：%s" % [record.cards])


func _test_dissect() -> void:
	print("剖腹")
	var who := Contractor.new(_config)
	var c := CatchGenerator.generate(GameDB.get_fish("grey_dace"), _rng, _config, 0, 0)
	var c2 := CatchGenerator.generate(GameDB.get_fish("grey_dace"), _rng, _config, 0, 0)
	var c3 := CatchGenerator.generate(GameDB.get_fish("grey_dace"), _rng, _config, 0, 0)
	who.take_card(GameDB.get_card("dissect"))
	var preview := who.dismantle_yield(c)
	var got := who.dismantle(c)
	var doubled := true
	for m in c.materials:
		doubled = doubled and got.get(m, 0) == c.materials[m] * 2 and preview.get(m, 0) == got.get(m, 0)
	_check(doubled, "处理翻倍：%s → %s（看渔获、契约书里写的也是翻倍以后的）" % [Materials.format(c.materials), Materials.format(got)])
	var again := who.dismantle(c2)
	_check(again.values().reduce(func(s, x): return s + x, 0) == c2.materials.values().reduce(func(s, x): return s + x, 0) * 2,
		"下一夜每一次处理都翻倍")
	who.offer([], _rng)
	_check(who.dismantle(c3) == c3.materials, "再唤祂以后就是原来的份数")


func _test_lure() -> void:
	print("引深")
	var bait := BaitCrafter.make_universal(1)
	for level in [1, 2, 3]:
		var who := Contractor.new(_config)
		who.ability_override = level
		who.take_card(GameDB.get_card("lure"))
		var cast := {}
		for i in 200:
			cast = CastRoll.roll(bait, 0, who, _rng, _config)
			if cast.catch:
				break
		_check(cast.lured and cast.catch.level == level + 1 and not who.has_card("lure"),
			"%d 级在浅层：第一次咬钩的换成 %d 级的%s（%s），卡用掉了" % [level, cast.catch.level, cast.catch.display_name(), cast.catch.stage_name()])
		var next := {}
		for i in 200:
			next = CastRoll.roll(bait, 0, who, _rng, _config)
			if next.catch:
				break
		_check(not next.lured and next.catch.level == 1, "下一次咬钩的照常（浅层 1 级）")
	var levels := {}
	for i in 400:
		var c := CatchGenerator.generate_at_level(3, bait, _rng, _config)
		levels[c.level] = true
	_check(levels.keys() == [3], "引上来的都是那一级：%s" % [levels.keys()])


func _test_evolve() -> void:
	print("进化")
	var who := Contractor.new(_config)
	who.take_card(GameDB.get_card("evolve"))
	var adult := CatchGenerator.generate(GameDB.get_fish("lantern_crone"), _rng, _config, 0, -1, {"stage": 2, "level": 3})
	_check(who.evolve_catch(adult, _rng).is_empty() and who.boon_ready("evolve"), "成年的不算，这一夜的次数留给下一条")
	var c := CatchGenerator.generate(GameDB.get_fish("lantern_crone"), _rng, _config, 0, -1, {"stage": 0, "level": 1})
	var before := c.tribute
	var body := c.body
	var r := who.evolve_catch(c, _rng)
	_check(not r.is_empty() and r.from == 0 and c.stage > 0 and not who.boon_ready("evolve") and who.has_boon("evolve"),
		"磷灯婆幼年 → %s，这一夜的次数用掉了（恩赐还在）" % c.stage_name())
	_check(c.level == GameDB.get_fish("lantern_crone").stage_levels(c.stage).x and c.tribute > before and c.body > body
		and c.body_class() == GameDB.get_fish("lantern_crone").stage_body(c.stage) and c.load_cost == _config.load_for_stage(c.stage),
		"等级、祭值、躯体规模、载荷跟着变：%d 级，祭值 %d → %d，躯体规模 %.2f → %s（%s），载荷 %d" % [c.level, before, c.tribute, body,
			c.body_text(), c.body_name(), c.load_cost])
	# 幼年的有三成直接长成年
	var jumps := 0
	for i in 600:
		var j := CatchGenerator.generate(GameDB.get_fish("grey_dace"), _rng, _config, 0, -1, {"stage": 0, "level": 1})
		CatchGenerator.evolve(j, _rng, _config, 0.3)
		jumps += 1 if j.stage == 2 else 0
	_check(absf(jumps / 600.0 - 0.3) < 0.06, "幼年直接长成年的占 %.0f%%（三成上下）" % (jumps * 100.0 / 600.0))
	# 只差一级的种类（血齿冥鲳 1–2 级）：幼年长成成长期，按灵魂强度过没过门槛定 1 级还是 2 级
	var fish := GameDB.get_fish("bloodtooth_pomfret")
	var ok := true
	var twos := 0
	for i in 300:
		var j := CatchGenerator.generate(fish, _rng, _config, 0, -1, {"stage": 0, "level": 1})
		CatchGenerator.evolve(j, _rng, _config, 0.0)
		var raw := j.soul_strength
		for id in j.affix_ids:
			raw -= GameDB.get_affix(id).soul_bonus
		var line := CatchGenerator._soul_mean(fish, 1, _config) + _config.growth_up_soul
		## 灵魂强度存的是取整以后的，门槛那里差半点也算对
		var consistent: bool = raw >= roundf(line) if j.level == 2 else raw <= roundf(line)
		ok = ok and j.stage == 1 and consistent
		twos += 1 if j.level == 2 else 0
	_check(ok and twos > 0 and twos < 300, "血齿冥鲳幼年长成成长期：过了门槛的 2 级（%d / 300），没过的 1 级" % twos)


func _test_vigor() -> void:
	print("壮魂、镇魂")
	var fish := GameDB.get_fish("grey_dace")
	var plain := TensionModel.new(fish, 0.0, 23.0, _config, _rng)
	var strong := TensionModel.new(fish, 0.0, 23.0, _config, _rng, CatchData.Stage.GROWING, INF, 0.2)
	_check(is_equal_approx(plain.drain_mult / strong.drain_mult, 1.2), "壮魂：体力掉得慢，多撑两成（%.2f → %.2f）" % [plain.drain_mult, strong.drain_mult])
	_check(is_equal_approx(strong.stamina, plain.stamina), "体力上限不变（体力管照常显示）")

## 永久恩赐（v0.23）：存在契约者身上、过夜还在、换人就没；每一张的触发和次数
func _test_boons() -> void:
	print("永久恩赐")
	var who := Contractor.new(_config)
	for id in ["bone_pick", "bait_heart", "carcass", "fed_courage", "blood_lure", "taut_line", "kin", "oddity", "overflow"]:
		who.take_card(GameDB.get_card(id))
	_check(who.boons.size() == 9 and who.card_effects.is_empty(), "九张恩赐拿到身上（不进一夜卡的 card_effects）")
	who.offer([], _rng)
	_check(who.boons.size() == 9 and Contractor.new(_config).boons.is_empty(), "再唤祂以后还在；换一个契约者就没了")
	who.begin_night(_rng)

	# 剔骨：每夜头两次，多一份最多的那种材料
	var dace := GameDB.get_fish("grey_dace")
	var pick_uses: int = GameDB.get_card("bone_pick").uses
	var fish: Array[CatchData] = []
	for i in pick_uses + 1:
		fish.append(CatchGenerator.generate(dace, _rng, _config, 0, -1, {"stage": 1, "level": 1}))
	var sums: Array[int] = []
	for c in fish:
		var base: int = c.materials.values().reduce(func(s, x): return s + x, 0)
		var preview: int = who.dismantle_yield(c).values().reduce(func(s, x): return s + x, 0)
		var got: int = who.dismantle(c).values().reduce(func(s, x): return s + x, 0)
		sums.append(got - base)
		if preview != got:
			sums.append(-99)
	var want: Array[int] = []
	for i in pick_uses:
		want.append(1)
	want.append(0)
	_check(sums == want, "剔骨：这一夜头 %d 次各多一份，再往后没有（看渔获时写的也一样）：%s" % [pick_uses, sums])

	# 饵心：两份相同的基础材料做饵，这一夜头一回多一份
	var heart_uses: int = GameDB.get_card("bait_heart").uses
	who.materials = {Materials.FLESH: 2 * (heart_uses + 1), Materials.SHELL: 1, Materials.GLOW: 1}
	var basic := GameDB.basic_additive().id
	var made: Array[int] = []
	for i in heart_uses + 1:
		made.append(BaitCrafter.craft(who, [Materials.FLESH, Materials.FLESH], basic).uses)
	var want_baits: Array[int] = []
	for i in heart_uses:
		want_baits.append(2)
	want_baits.append(1)
	_check(made == want_baits, "饵心：两份血肉做的饵，这一夜头 %d 回是两份，再做就是一份：%s" % [heart_uses, made])
	who.begin_night(_rng)
	var mixed := BaitCrafter.craft(who, [Materials.SHELL, Materials.GLOW], basic)
	_check(mixed.uses == 1 and who.boon_ready("bait_heart"), "饵心：两份不一样的不算，次数还留着")

	# 残躯为饵：拆了一条以后，这一夜下一条留下的祭值 +20%
	var junk := CatchGenerator.generate(dace, _rng, _config, 0, -1, {"stage": 0, "level": 1})
	var keep1 := CatchGenerator.generate(dace, _rng, _config, 0, -1, {"stage": 2, "level": 1})
	var keep2 := CatchGenerator.generate(dace, _rng, _config, 0, -1, {"stage": 2, "level": 1})
	var plain1 := keep1.tribute
	var plain2 := keep2.tribute
	who.dismantle(junk)
	_check(who.carcass_ready(), "残躯为饵：拆了一条，记下了")
	who.keep(keep1)
	who.keep(keep2)
	var carcass: float = GameDB.get_card("carcass").amount
	_check(absi(keep1.tribute - roundi(plain1 * (1.0 + carcass))) <= 1 and keep2.tribute == plain2 and not who.carcass_ready(),
		"残躯为饵：下一条留下的 %d → %d（+%d%%），再下一条照常" % [plain1, keep1.tribute, roundi(carcass * 100.0)])
	var junk2 := CatchGenerator.generate(dace, _rng, _config, 0, -1, {"stage": 0, "level": 1})
	who.dismantle(junk2)
	who.begin_night(_rng)
	_check(not who.carcass_ready(), "残躯为饵：天黑就清掉（只管这一夜）")

	# 饱食之勇、韧线：体力消耗相乘
	var taut: float = GameDB.get_card("taut_line").amount
	var fed_cut: float = GameDB.get_card("fed_courage").amount
	var base_vigor := who.fight_vigor()
	_check(absf(base_vigor - (1.0 / (1.0 - taut) - 1.0)) < 0.001, "韧线：体力消耗 −%d%%（vigor %.2f）" % [roundi(taut * 100.0), base_vigor])
	who.eat(CatchGenerator.generate(dace, _rng, _config, 0, -1, {"stage": 0, "level": 1}))
	var fed := who.fight_vigor(true)
	_check(absf(fed - (1.0 / ((1.0 - taut) * (1.0 - fed_cut)) - 1.0)) < 0.001 and absf(who.fight_vigor() - base_vigor) < 0.001,
		"饱食之勇：吃了以后的下一场再 −%d%%（vigor %.2f），打完就没了" % [roundi(fed_cut * 100.0), fed])

	# 血诱：吃了以后这一夜下一口，35% 换成高一级的（浅层只出 1 级，换来的是 2 级）
	var bait := BaitCrafter.make_universal(1)
	var lifted := 0
	var tries := 0
	var consumed := true
	who.ability_override = 1
	for i in 600:
		who.boons["blood_lure"].used = 0
		who.boon_marks["blood"] = true
		var cast := {}
		for j in 50:
			cast = CastRoll.roll(bait, 0, who, _rng, _config)
			if cast.catch:
				break
		if cast.catch == null:
			continue
		tries += 1
		consumed = consumed and not who.boon_marks.has("blood")
		if cast.blood:
			lifted += 1
			consumed = consumed and cast.catch.level == 2 and cast.gap > 0.5
	_check(consumed and absf(lifted / float(tries) - 0.35) < 0.06,
		"血诱：下一口有 %.0f%% 换成 2 级的（照样要搏斗，等级差 > 0），换没换都用掉" % (lifted * 100.0 / tries))

	# 同族之献：同一种族每凑满两条 +12%，一夜最多加献上总数的三成
	var pair: Array[CatchData] = []
	for t in [1000, 900]:
		var c := CatchData.new()
		c.species_id = "grey_dace"
		c.tribute = t
		pair.append(c)
	var single := CatchData.new()
	single.species_id = "bloodtooth_pomfret"
	single.tribute = 1500
	var kin: float = GameDB.get_card("kin").amount
	var v := who.offer_value(pair + [single])
	_check(v.base == 3400 and v.kin == roundi(1900 * kin) and v.total == 3400 + v.kin,
		"同族之献：两条灰鲦（1,900）+%d%% = %d，一条血齿冥鲳不算" % [roundi(kin * 100.0), v.kin])
	var many: Array[CatchData] = []
	for i in 6:
		var c := CatchData.new()
		c.species_id = "grey_dace"
		c.tribute = 1000
		many.append(c)
	_check(who.offer_value(many).kin == roundi(6000 * kin), "同族之献：六条同种全配上（+%d），没到三成的上限" % roundi(6000 * kin))

	# 满溢之献：超额线 135%，超额的那一夜补给多一份
	_check(is_equal_approx(who.over_ratio(), 1.35), "满溢之献：超额线是需求的 135%")
	var rich := CatchData.new()
	rich.species_id = "bloodtooth_pomfret"
	rich.tribute = roundi(who.demand() * 1.4)
	who.hold.append(rich)
	var r := who.offer([rich], _rng)
	_check(r.over and r.supply == _config.supply_baits + 1 and RewardCards.is_over(r, _config),
		"满溢之献：献上 140%% 算超额，下一夜的补给 %d 份（多一份）" % r.supply)
	var plain := Contractor.new(_config)
	var rich2 := CatchData.new()
	rich2.species_id = "bloodtooth_pomfret"
	rich2.tribute = roundi(plain.demand() * 1.4)
	plain.hold.append(rich2)
	_check(not plain.offer([rich2], _rng).over, "没有满溢之献：140% 不算超额")

	# 异象收藏：船舱里带特殊词条的，每过一夜 +25%，最多 +75%
	var odd := CatchGenerator.generate(GameDB.get_fish("lantern_crone"), _rng, _config, 0, -1, {"stage": 1, "level": 2})
	odd.affix_ids = ["recolored"]
	CatchGenerator.evaluate(odd, odd.species(), _config)
	var start := odd.tribute
	who.hold.append(odd)
	var grown: Array[int] = []
	for i in 4:
		var ev := who.begin_night(_rng)
		grown.append(ev.oddities)
	_check(is_equal_approx(odd.bonus, 0.75) and absi(odd.tribute - roundi(start * 1.75)) <= 1 and grown == [1, 1, 1, 0],
		"异象收藏：带「变色」的过三夜 %d → %d（+75%%，到顶了不再长）" % [start, odd.tribute])

	# 进化（永久，每夜一次）：一夜只长一条，下一夜又能长
	var evo := Contractor.new(_config)
	evo.take_card(GameDB.get_card("evolve"))
	var a := CatchGenerator.generate(dace, _rng, _config, 0, -1, {"stage": 0, "level": 1})
	var b := CatchGenerator.generate(dace, _rng, _config, 0, -1, {"stage": 0, "level": 1})
	var r1 := evo.evolve_catch(a, _rng)
	var r2 := evo.evolve_catch(b, _rng)
	evo.begin_night(_rng)
	var c3 := CatchGenerator.generate(dace, _rng, _config, 0, -1, {"stage": 0, "level": 1})
	var r3 := evo.evolve_catch(c3, _rng)
	_check(not r1.is_empty() and r2.is_empty() and not r3.is_empty() and a.stage == 1,
		"进化：每夜第一条长一个时期（幼年 → 成长期，不跳级），同一夜第二条不长，下一夜又能长")


## 抽候选（v0.23）：开局三条引擎各一张；身上有的恩赐不再出；同标签的多一点；全是一条引擎时换一张
func _test_draw() -> void:
	print("抽恩赐")
	var who := Contractor.new(_config)
	var ok := true
	for i in 200:
		var cards := RewardCards.draw_opening(_rng, who)
		var tags := cards.map(func(c: RewardCard) -> String: return c.tags[0])
		ok = ok and cards.size() == 3 and tags == ["resource", "capture", "tribute"] \
			and cards.all(func(c: RewardCard) -> bool: return c.permanent and not (c.effect in RewardCards.OPENING_SKIP))
	_check(ok, "开局恩赐：资源、捕获、祭值各一张，都是永久的，第一夜用不上的（异象收藏、冥市熟客、逐浪）不出")
	var owned := ["bone_pick", "bait_heart", "carcass", "fed_courage", "blood_lure", "taut_line", "kin", "oddity", "overflow",
		"abyss_walker", "regular", "ride_waves", "crown_catch", "hungry_offer", "bone_flute"]
	for id in owned:
		who.take_card(GameDB.get_card(id))
	var clean := true
	var evolve_seen := false
	for i in 300:
		for c in RewardCards.draw(3, _rng, true, who):
			clean = clean and not (c.permanent and c.effect in owned)
			evolve_seen = evolve_seen or c.effect == "evolve"
	_check(clean and evolve_seen, "身上有的恩赐不再出（只剩进化还能抽到）")
	var fresh := Contractor.new(_config)
	fresh.take_card(GameDB.get_card("bone_pick"))
	_check(is_equal_approx(RewardCards.weight(GameDB.get_card("bait_heart"), fresh), 1.5)
		and is_equal_approx(RewardCards.weight(GameDB.get_card("kin"), fresh), 1.0)
		and is_equal_approx(RewardCards.weight(GameDB.get_card("feast"), fresh), RewardCards.OTHER_WEIGHT),
		"权重：同一条引擎的恩赐 1.5，别的恩赐 1，饱餐这种应急的 %.1f" % RewardCards.OTHER_WEIGHT)
	var same: Array[RewardCard] = [GameDB.get_card("bone_pick"), GameDB.get_card("bait_heart")]
	var pool: Array = [GameDB.get_card("kin"), GameDB.get_card("feast")]
	RewardCards._keep_variety(same, pool, _rng)
	_check(same[0].id == "bone_pick" and same[1].id == "kin", "两张恩赐全是资源的：换掉一张，留一条转型的路（换成了%s）" % same[1].display_name)

## 阶段 V 的六张恩赐
func _test_more_boons() -> void:
	print("阶段 V 的恩赐")
	var who := Contractor.new(_config)
	for id in ["abyss_walker", "regular", "ride_waves", "crown_catch", "hungry_offer", "bone_flute"]:
		who.take_card(GameDB.get_card(id))
	who.ability_override = 1
	_check(is_equal_approx(who.fight_vigor(false, 0), 0.0) and absf(who.fight_vigor(false, 1) - (1.0 / 0.65 - 1.0)) < 0.001,
		"深渊行者：1 档在浅层不管，在深水体力消耗 −35%%（vigor %.2f）" % who.fight_vigor(false, 1))
	who.night = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var ev := SeaEvents.start("trade", who, rng)
	_check(ev.offers[0].price == SeaEvents.price(roundi(who.demand() * 0.7), _config.trade_boon),
		"冥市熟客：价钱 −30%%（恩赐 %s）" % Gothic.grouped(ev.offers[0].price))
	var trades := 0
	for i in 1000:
		who.night = 2
		who.brands = 3
		who.begin_night(rng)
		trades += 1 if who.event_plan.get("id", "") == "trade" else 0
	var share: float = trades / 1000.0 / _config.event_chance
	var base: float = float(_config.event_weights.trade) / float(_config.event_weights.values().reduce(func(s, x): return s + x, 0.0))
	_check(share > base * 1.5, "冥市熟客：碰上冥市船的占 %.0f%%（平常 %.0f%%）" % [share * 100.0, base * 100.0])
	var dace := GameDB.get_fish("grey_dace")
	var c := CatchGenerator.generate(dace, rng, _config, 0, -1, {"stage": 1, "level": 1})
	var plain := c.tribute
	who.sea = "rough"
	var cast := {}
	for i in 100:
		cast = CastRoll.roll(BaitCrafter.make_universal(1), 0, who, rng, _config)
		if cast.catch:
			break
	var waves: float = GameDB.get_card("ride_waves").amount
	_check(cast.catch != null and is_equal_approx(cast.catch.bonus, waves), "逐浪：躁动的夜钓上来的祭值 +%d%%（bonus %.2f）" % [
		roundi(waves * 100.0), cast.catch.bonus])
	var a := CatchData.new()
	a.species_id = "grey_dace"
	a.tribute = 1000
	var b := CatchData.new()
	b.species_id = "bloodtooth_pomfret"
	b.tribute = 3000
	who.hunger = 80.0
	var crown: float = GameDB.get_card("crown_catch").amount
	var hungry: float = GameDB.get_card("hungry_offer").amount
	var v := who.offer_value([a, b])
	_check(v.crown == roundi(3000 * crown) and v.hungry == 0 and v.total == 4000 + v.crown,
		"渔获加冕：最值钱的那条 3,000 再加 %d%%（+%d）；饱腹 80 不算空腹" % [roundi(crown * 100.0), v.crown])
	who.hunger = 50.0
	v = who.offer_value([a, b])
	_check(v.hungry == roundi(4000 * hungry), "空腹之献：饱腹 50 时供奉，总数 +%d%%（+%d）" % [roundi(hungry * 100.0), v.hungry])
	var adult := CatchGenerator.generate(dace, rng, _config, 0, -1, {"stage": 2, "level": 1})
	var young := CatchGenerator.generate(dace, rng, _config, 0, -1, {"stage": 0, "level": 1})
	who.dismantle(young)
	var after_young := who.fight_steady()
	who.dismantle(adult)
	_check(after_young == 0 and who.fight_steady() == 1 and who.fight_steady(true) == 1 and who.fight_steady() == 0,
		"骨笛：拆了成年的（幼年的不算），下一场按低一级算，打完就没了")
	_check(plain > 0, "（灰鲦成长期祭值 %d）" % plain)
