extends Node
## 契约周期自检。命令行运行：
##   Godot_v4.6.3-stable_win64.exe --headless --path . res://tests/test_contract.tscn
## 查：每夜的需求、能力档跟着夜数走、烙印（剪线扣一枚、续魂丝补一枚）、黄昏供奉的几种结局（够了、不够扣烙印、没烙印就死、
## 契约已偿、最后一夜不够的补偿周期）、不够的次数（祂发怒一次比一次重）、捞上来的东西、名册存盘、每夜的天气；
## 许汝之物、这份契约的账、结算清单和评价（核心调整 G4）；每次结算以后发的补给（新回合机制）。

const TEST_ROSTER := "user://test_roster.json"

var _failures := 0
var _config: BalanceConfig
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_config = GameDB.balance
	_rng.seed = 7
	_test_nights()
	_test_brands()
	_test_offering()
	_test_last_night()
	_test_items()
	_test_roster()
	_test_weather()
	_test_promise()
	_test_ledger()
	_test_rating()
	_test_sea()
	_test_events()
	_test_more_events()
	print("\n==== %s（失败 %d 项）====" % ["全部通过" if _failures == 0 else "存在失败", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	print(("  [OK]   " if cond else "  [FAIL] ") + msg)
	if not cond:
		_failures += 1


func _catch(species: String, tribute: int, affixes: Array[String] = []) -> CatchData:
	var c := CatchData.new()
	c.species_id = species
	c.tribute = tribute
	c.affix_ids = affixes
	c.load_cost = 1
	return c


func _test_promise() -> void:
	print("许汝之物")
	var all: Array = GameDB.sorted_values(GameDB.promises)
	_check(all.size() == 6 and all.all(func(p: PromiseData) -> bool: return p.line != "" and p.thing != "" and p.display_name != ""),
		"六样许汝之物，每样有英文的一句、中文的那样东西（%s）" % "、".join(all.map(func(p: PromiseData) -> String: return p.display_name)))
	var years := GameDB.get_promise("years")
	_check(years.note() == "许汝之物：被夺走的寿数。" and years.returned_text() == "祂归还了：被夺走的寿数。",
		"批注和结算里的写法：%s / %s" % [years.note(), years.returned_text()])
	var fresh := GameState._fresh_contractor()
	_check(GameDB.promises.has(fresh.promise) and fresh.promise_data() != null, "新的契约者分到一样（%s）" % fresh.promise_data().display_name)
	GameState.roster.append({"number": 999, "promise": "beloved"})
	var repeats := 0
	for i in 60:
		repeats += int(GameState._roll_promise() == "beloved")
	GameState.roster.pop_back()
	_check(repeats == 0, "和名册上最后一位分到的不一样")
	var lines := ContractScreen.terms_for(fresh)
	_check(lines.size() == ContractScreen.TERMS.size() + 1 and lines[-1][0] == fresh.promise_data().line
		and lines[-1][1] == fresh.promise_data().note(), "契约上三句契约语，下面一行是许汝之物")
	_check(ContractScreen.terms_for(Contractor.new(_config)).size() == ContractScreen.TERMS.size(), "还没分到的就只有三句")


func _test_ledger() -> void:
	print("这份契约的账")
	var who := _signed()
	who.number = 12
	who.contractor_name = "亚瑟"
	who.promise = "crown"
	var first := _catch("grey_dace", who.demand() + 300)
	first.stage = CatchData.Stage.JUVENILE
	var second := _catch("blind_bone_eel", 30000)
	second.stage = CatchData.Stage.ADULT
	second.level = 3
	second.body = 7.5
	second.affix_ids = ["recolored"]
	second.hue_shift = 0.4
	who.hold.assign([first, second])
	var r1 := who.offer([first], _rng)
	who.begin_night(_rng)
	var r2 := who.offer([], _rng)
	who.begin_night(_rng)
	var r3 := who.offer([second], _rng)
	_check(who.tribute_total == first.tribute + second.tribute and who.demand_total == r1.demand + r2.demand + r3.demand,
		"献上的祭值加起来 %d，要的加起来 %d（不够的那一夜也算要的）" % [who.tribute_total, who.demand_total])
	_check(who.brands_lost() == 1 and r3.met and not r1.has("reward") and who.items.is_empty(), "丢了一枚烙印；够了也不赐道具（2026-11-04）")
	_check(who.offered_kinds.has("grey_dace:0") and who.offered_kinds.has("blind_bone_eel:2") and who.offered_kinds.size() == 2
		and who.best_offering == second, "献过的种类和时期（%s），最珍贵的一件是那条成年的鳗" % [who.offered_kinds.keys()])
	who.cut_line()
	_check(who.cuts == 1 and who.brands_lost() == 2, "剪了一次线，又扣一枚烙印（一共丢两枚）")
	var bait := BaitCrafter.make_universal(9)
	for i in 5:
		CastRoll.roll(bait, 0, who, _rng, _config)
	_check(who.casts == 5, "抛了几竿：每抛一竿记一下（%d）" % who.casts)
	who.take_card(GameDB.get_card("steady"))
	who.status = Contractor.Status.REPAID
	var rec := Settlement.record(who, "repaid")
	_check(rec.casts == 5 and rec.cards == ["steady"], "结算清单里有抛了几竿、选过的卡（H3）")
	_check(rec.number == 12 and rec.name == "亚瑟" and rec.promise == "crown" and rec.status == "repaid" and rec.cuts == 1
		and rec.brands_lost == 2 and not rec.has("wishes") and not rec.has("gifts") and rec.ability == who.ability
		and rec.kinds == ["blind_bone_eel:2", "grey_dace:0"] and rec.best.species == "blind_bone_eel" and rec.best.stage == 2,
		"结算清单：%s，评价 %s" % [Settlement.outcome_text(rec), rec.rating])
	var entries: Array[Dictionary] = [rec]
	Roster.save_to(TEST_ROSTER, entries)
	var back := Roster.load_from(TEST_ROSTER)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_ROSTER))
	var e := back[0]
	_check(typeof(e.tribute) == TYPE_INT and e.tribute == rec.tribute and typeof(e.best.stage) == TYPE_INT
		and typeof(e.casts) == TYPE_INT and e.casts == 5 and e.cards == rec.cards and Settlement.has_ledger(e),
		"存进名册再读回来一样（数字还是整数）")
	var best := Settlement.best_catch(e)
	_check(best != null and best.species_id == "blind_bone_eel" and best.stage == CatchData.Stage.ADULT and best.tribute == 30000
		and best.hue_shift > 0.0 and best.art() != null, "最珍贵的那一件还原得出来（插图按时期、带变色）")
	_check(not Settlement.has_ledger({"number": 1, "name": "旧的", "night": 3, "status": "dead", "cause": "fall"})
		and Settlement.best_catch({}) == null, "G4 以前的名册条目没有账")
	_check(Settlement.farewell(rec) == "No.0012 偿清了契约，离开了冥海。" and Settlement.farewell({"number": 3, "cause": "fall"})
		== "No.0003 坠入了冥海。", "下一位签约时写的那句话")


func _test_rating() -> void:
	print("评价")
	var demand := 100000
	var cases := [
		["fall", demand * 2, 0, Settlement.DROWNED],
		["offering", demand, 3, Settlement.BROKEN],
		["repaid", roundi(demand * Settlement.DEVOTED_RATIO), 0, "献心"],
		["repaid", roundi(demand * Settlement.DEVOTED_RATIO) - 100, 0, "虔诚"],
		["repaid", roundi(demand * Settlement.PIOUS_RATIO), 0, "虔诚"],
		["repaid", roundi(demand * Settlement.PIOUS_RATIO) - 100, 0, "守约"],
		["repaid", demand * 3, 1, "守约" if Settlement.KEPT_BRANDS >= 1 else "勉强"],
		["repaid", demand * 3, Settlement.KEPT_BRANDS, "守约" if Settlement.KEPT_BRANDS > 0 else "献心"],
		["repaid", demand * 3, Settlement.KEPT_BRANDS + 1, "勉强"],
	]
	var bad := []
	for c in cases:
		var got := Settlement.rate(c[0], c[1], demand, c[2])
		if got != c[3]:
			bad.append("%s 献 %d 丢 %d → %s（应为 %s）" % [c[0], c[1], c[2], got, c[3]])
	_check(bad.is_empty(), "落水殒于冥海、被吞背约；偿清了按献上的倍数、丢的烙印分四档（不再看合心意） %s" % ", ".join(bad))
	for rating in Settlement.RATINGS + [Settlement.BROKEN, Settlement.DROWNED]:
		_check(Settlement.RATING_NOTES.has(rating), "「%s」下面有一句话：%s" % [rating, Settlement.RATING_NOTES.get(rating, "")])


func _signed() -> Contractor:
	var who := Contractor.new(_config)
	who.begin_night(_rng, true)
	return who


func _test_nights() -> void:
	print("黑夜")
	var who := _signed()
	_check(who.night == 1, "签约后是第 1 夜（一夜没有钟，玩家自己唤祂）")
	var demands: PackedInt32Array = []
	for n in range(1, 10):
		demands.append(_config.demand_for(n))
	_check(demands[0] == _config.offering_demand[0] and demands[6] == _config.offering_demand[6] and demands[7] == demands[6]
		and demands[8] == demands[6], "每夜的需求按表走，第 7 夜以后的补偿周期不再涨（%s）" % [demands])
	var abilities: Array[int] = [who.ability]
	var ups: Array[int] = []
	who.brands = 1
	for n in range(2, 10):
		var ev := who.begin_night(_rng)
		abilities.append(who.ability)
		if ev.ability_up:
			ups.append(ev.night)
	_check(abilities == [1, 1, 2, 2, 3, 3, 3, 3, 3] and ups == [3, 5],
		"能力档跟着夜数走：%s，第 3、5 夜升一档（%s）" % [abilities, ups])
	_check(who.brands == 1, "烙印不会自己长回来")
	who.ability_override = 2
	_check(who.ability == 2, "测试、模拟器可以固定能力档")
	who.hunger = 40.0
	who.spend_hunger(_config.hunger_per_cast)
	who.begin_night(_rng)
	_check(is_equal_approx(who.hunger, 40.0 - _config.hunger_per_cast), "抛一竿扣饱腹（%.0f）；天黑了饱腹不回满" % who.hunger)


## 烙印（2026-11-04 和灵魂线并成一样）：剪线扣一枚，没了剪不了；续魂丝补一枚，满了补不了
func _test_brands() -> void:
	print("烙印")
	var who := _signed()
	_check(who.brands == _config.brands, "签约时 %d 枚" % who.brands)
	for i in _config.brands:
		_check(who.cut_line(), "剪线扣一枚烙印（还剩 %d 枚）" % who.brands)
	_check(not who.cut_line() and who.brands == 0 and who.cuts == _config.brands, "烙印没了剪不了线")
	var r := who.offer([], _rng)
	_check(r.died, "剪线把烙印用光了，再供奉不够就死")
	var other := _signed()
	other.cut_line()
	other.add_item("soul_thread")
	_check(other.use_item("soul_thread") and other.restore_brand() and other.brands == _config.brands, "续魂丝补回一枚烙印")
	_check(not other.restore_brand(), "烙印满了补不了")


func _test_offering() -> void:
	print("黄昏供奉")
	var who := _signed()
	var need := _config.demand_for(1)
	var a := _catch("grey_dace", need / 3)
	var b := _catch("bloodtooth_pomfret", need - need / 3 + 500)
	var keep := _catch("grey_dace", 1000)
	who.hold.assign([a, b, keep])
	var r := who.offer([a, b], _rng)
	_check(r.met and not r.brand_lost and who.brands == _config.brands, "祭值 %d ≥ 需求 %d：过了这一夜，烙印不扣" % [r.tribute, r.demand])
	_check(r.supply == _config.supply_baits, "够了，还有下一夜：发 %d 份万能饵" % r.supply)
	_check(not who.hold.has(a) and who.hold.has(keep), "献上的从船舱里拿走，没献的留到下一夜")
	_check(not r.has("reward") and who.items.is_empty(), "祂不再赐道具（2026-11-04）")
	who.begin_night(_rng)
	var big := _catch("grey_dace", who.demand() + 1000)
	who.hold.append(big)
	r = who.offer([big], _rng)
	_check(r.met, "第二夜也够了")
	who.begin_night(_rng)
	for i in _config.brands:
		r = who.offer([], _rng)
		_check(r.brand_lost and not r.died and who.brands == _config.brands - 1 - i and r.supply == _config.supply_baits,
			"不够：吃掉一枚烙印（还剩 %d 枚），人还活着照样发补给" % who.brands)
	r = who.offer([], _rng)
	_check(r.died and who.status == Contractor.Status.DEAD and r.supply == 0, "烙印吃完了再不够：死，不发补给")
	_check(who.failed_offerings == _config.brands + 1, "不够的次数记下来了（%d 次），够了的那两次不算" % who.failed_offerings)


func _test_last_night() -> void:
	print("最后一夜")
	var who := _signed()
	who.night = _config.contract_nights
	var r := who.offer([], _rng)
	_check(r.brand_lost and not r.repaid and who.status == Contractor.Status.ALIVE, "最后一夜不够：扣一枚烙印，契约没偿清")
	who.begin_night(_rng)
	_check(who.is_compensation() and who.demand() == _config.demand_for(_config.contract_nights),
		"再来一夜补偿周期（第 %d 夜），需求不涨" % who.night)
	var c := _catch("grey_dace", who.demand())
	who.hold.append(c)
	r = who.offer([c], _rng)
	_check(r.met and r.repaid and who.status == Contractor.Status.REPAID and r.supply == 0, "补偿周期够了：契约已偿，没有下一夜就不发补给")


func _test_items() -> void:
	print("道具和捞上来的东西")
	_check(GameDB.items.size() >= 3, "道具 %d 种" % GameDB.items.size())
	for id in _config.salvage_table:
		_check(GameDB.get_item(id) != null or GameDB.get_additive(id) != null, "捞上来的「%s」认得" % id)
	for card: RewardCard in GameDB.sorted_values(GameDB.cards):
		if card.effect == "item":
			_check(GameDB.get_item(card.item_id) != null and card.over_only, "道具卡「%s」给的是道具，只有超额时抽得到" % card.display_name)
	var who := _signed()
	var eggs: int = who.additives.get("rotten_harpy_egg", 0)
	who.add_salvage("rotten_harpy_egg")
	who.add_salvage("soul_thread")
	_check(who.additives.rotten_harpy_egg == eggs + 1 and who.items.get("soul_thread", 0) == 1, "附加物进附加物，道具进道具栏")
	who.brands = 1
	_check(who.use_item("soul_thread") and who.restore_brand() and who.brands == 2 and not who.items.has("soul_thread"),
		"续魂丝补回一枚烙印")
	_check(not who.use_item("soul_thread"), "用完了就没了")


func _test_roster() -> void:
	print("名册")
	var entries: Array[Dictionary] = [
		{"number": 1, "name": "亚瑟", "night": 3, "status": "dead", "cause": "fall"},
		{"number": 2, "name": "Morrow", "night": 7, "status": "repaid", "cause": "repaid"}]
	_check(Roster.save_to(TEST_ROSTER, entries), "存得下")
	var back := Roster.load_from(TEST_ROSTER)
	_check(back.size() == 2 and back[1].name == "Morrow" and back[0].night == 3 and back[1].status == "repaid", "读回来一样")
	_check(Roster.next_number(back) == 3 and Roster.next_number([]) == 1, "下一位的编号接着往下排")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_ROSTER))
	_check(Roster.load_from(TEST_ROSTER).is_empty(), "没有名册文件就是空的")


func _test_weather() -> void:
	print("天气")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var seconds := 360.0
	var nights := 2000
	var rainy := 0
	var flights := 0
	var bad_rain := 0
	var bad_birds := 0
	var loudest := 0.0
	for i in nights:
		var w := Weather.plan(rng, seconds)
		if w.rains():
			rainy += 1
			if w.rain_end > seconds or w.rain_end <= w.rain_start or w.rain_at(seconds) > 0.001 or w.rain_at(w.rain_start) > 0.001:
				bad_rain += 1
			for s in range(0, int(seconds) + 1, 4):
				loudest = maxf(loudest, w.rain_at(s))
		elif w.rain_at(seconds * 0.5) > 0.0:
			bad_rain += 1
		if w.birds_at >= 0.0:
			flights += 1
			if w.birds_at < seconds * Weather.BIRDS_WINDOW.x - 0.001 or w.birds_at > seconds * Weather.BIRDS_WINDOW.y + 0.001:
				bad_birds += 1
	_check(absf(rainy / float(nights) - Weather.RAIN_CHANCE) < 0.04, "下雨的夜约占 %d%%（%d / %d）" % [roundi(Weather.RAIN_CHANCE * 100), rainy, nights])
	_check(bad_rain == 0 and loudest <= 1.0 and loudest > 0.9, "雨渐大、渐停，到黄昏前停住（最大 %.2f）" % loudest)
	_check(absf(flights / float(nights) - Weather.BIRDS_CHANCE) < 0.04 and bad_birds == 0,
		"大鸟一夜最多飞一回，约一半的夜有（%d / %d），都在排好的那一段里" % [flights, nights])

## 海况和冥海侵蚀（v0.23）：第一夜平静；之后每夜按权重掷；每一夜的数值表按夜数和海况改，总表不动
func _test_sea() -> void:
	print("海况与冥海侵蚀")
	var config := GameDB.balance
	var who := Contractor.new(config)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var ev := who.begin_night(rng, true)
	_check(ev.sea == "calm" and who.sea == "calm", "签约后的第一夜是平静")
	var counts := {"calm": 0, "rough": 0, "eerie": 0}
	for i in 3000:
		who.begin_night(rng)
		counts[who.sea] += 1
	_check(absf(counts.calm / 3000.0 - 0.45) < 0.04 and absf(counts.rough / 3000.0 - 0.35) < 0.04 and absf(counts.eerie / 3000.0 - 0.2) < 0.03,
		"海况按权重掷：平静 %d、躁动 %d、异化 %d（三千夜）" % [counts.calm, counts.rough, counts.eerie])
	var n1 := config.for_night(1, "eerie")
	var n7 := config.for_night(7, "eerie")
	var adult1 := n1.stage_share[2] / (n1.stage_share[0] + n1.stage_share[1] + n1.stage_share[2])
	var adult7 := n7.stage_share[2] / (n7.stage_share[0] + n7.stage_share[1] + n7.stage_share[2])
	_check(adult7 > adult1 and is_equal_approx(n7.soul_base, config.soul_base + 6.0) and is_equal_approx(n1.soul_base, config.soul_base),
		"冥海侵蚀：第 7 夜成年的占 %.0f%%（第 1 夜 %.0f%%），灵魂强度的平均 +6" % [adult7 * 100.0, adult1 * 100.0])
	_check(is_equal_approx(n1.special_chance_mult, 3.0) and is_equal_approx(n7.special_chance_mult, 3.0 * 1.9)
		and is_equal_approx(config.special_chance_mult, 1.0), "异化：特殊词条 ×3；第 7 夜再 ×1.9；总表不动")
	var calm := config.for_night(1, "calm")
	var rough := config.for_night(1, "rough")
	var deep := func(c: BalanceConfig) -> Array[float]: return WaterLayers.level_shares(1, c)
	var base: Array[float] = deep.call(config)
	var calm_s: Array[float] = deep.call(calm)
	var rough_s: Array[float] = deep.call(rough)
	_check(calm_s[0] > base[0] and calm_s[2] < base[2] and rough_s[0] < base[0] and rough_s[2] > base[2]
		and WaterLayers.level_shares(0, rough) == WaterLayers.level_shares(0, config),
		"深水 1 / 3 级：平静 %.0f%% / %.0f%%，平常 %.0f%% / %.0f%%，躁动 %.0f%% / %.0f%%；浅层只出一级，不变" % [calm_s[0] * 100.0,
			calm_s[2] * 100.0, base[0] * 100.0, base[2] * 100.0, rough_s[0] * 100.0, rough_s[2] * 100.0])
	who.night = 5
	who.sea = "rough"
	var cfg := who.night_config()
	_check(cfg == who.night_config() and cfg != config and is_equal_approx(cfg.soul_base, config.soul_base + 4.0),
		"契约者这一夜的数值表按夜缓存（第 5 夜躁动：灵魂强度 +4）")

## 海上事件（阶段 IV）：第 1 夜没有；之后按 event_chance 有一件、在第 2–3 竿；那一竿等来的是事、不扣饵；每一件的选择和代价
func _test_events() -> void:
	print("海上事件")
	var config := GameDB.balance
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var who := Contractor.new(config)
	who.begin_night(rng, true)
	_check(who.event_plan.is_empty(), "签约后的第一夜没有海上事件")
	var with_event := 0
	var ats := {}
	var kinds := {}
	for i in 2000:
		who.night = 1
		who.brands = 3
		who.begin_night(rng)
		if not who.event_plan.is_empty():
			with_event += 1
			ats[who.event_plan.at] = true
			kinds[who.event_plan.id] = kinds.get(who.event_plan.id, 0) + 1
	_check(absf(with_event / 2000.0 - config.event_chance) < 0.04 and ats.keys().all(func(a) -> bool: return a >= 2 and a <= 3)
		and kinds.size() == SeaEvents.NAMES.size(), "第 2 夜起约 %.0f%% 的夜有一件，在第 2–3 竿；%d 种都出：%s" % [with_event / 20.0,
			SeaEvents.NAMES.size(), kinds])
	who.brands = 1
	var whisper := false
	for i in 500:
		who.night = 1
		who.begin_night(rng)
		whisper = whisper or who.event_plan.get("id", "") == "whisper"
	_check(not whisper, "烙印只剩一枚时，祂的低语不出")

	var bait := BaitCrafter.make_universal(1)
	var w2 := Contractor.new(config)
	w2.night = 3
	w2.event_plan = {"id": "wreck", "at": 2}
	var first := CastRoll.roll(bait, 0, w2, rng, config)
	var second := CastRoll.roll(bait, 0, w2, rng, config)
	var third := CastRoll.roll(bait, 0, w2, rng, config)
	_check(first.event == "" and second.event == "wreck" and second.fish == null and third.event == "" and w2.events_seen == {"wreck": 1},
		"第 2 竿等来残骸（不是咬钩、不扣饵），一夜只有一件")

	# 冥市船
	var trader := Contractor.new(config)
	trader.night = 3
	for t in [800, 1500, 2100, 3000]:
		var c := CatchData.new()
		c.species_id = "grey_dace"
		c.tribute = t
		trader.hold.append(c)
	var ev := SeaEvents.start("trade", trader, rng)
	var need := trader.demand()
	_check(ev.offers.size() == 3 and ev.offers[0].kind == "boon" and ev.offers[0].price == SeaEvents.price(need, config.trade_boon)
		and ev.offers[1].kind == "baits" and ev.offers[2].kind == "item",
		"冥市船三样货：恩赐、%d 份万能饵、一件道具；价钱 %s（今夜要 %s）" % [config.trade_bait_count,
			ev.offers.map(func(o: Dictionary) -> int: return o.price), Gothic.grouped(need)])
	var pay := SeaEvents.payment(trader, 2000)
	_check(pay.size() == 1 and pay[0].tribute == 2100, "付 2,000：交出 2,100 那一条（多出来最少）")
	pay = SeaEvents.payment(trader, 2400)
	_check(pay.size() == 1 and pay[0].tribute == 3000, "付 2,400：交出 3,000 那一条（比 1,500 + 2,100 多出来的少）")
	pay = SeaEvents.payment(trader, 6000)
	var paid := 0
	for c in pay:
		paid += c.tribute
	_check(paid == 6600 or paid == 6900 or paid == 7400, "付 6,000：几条凑起来（%d）" % paid)
	var boon: RewardCard = ev.offers[0].card
	var before := trader.hold.size()
	var r := SeaEvents.resolve(ev, 0, trader, rng)
	_check(trader.has_boon(boon.effect) and trader.hold.size() < before and r.paid >= ev.offers[0].price,
		"买下恩赐「%s」：交出 %s 祭值的渔获" % [boon.display_name, Gothic.grouped(r.paid)])
	var poor := Contractor.new(config)
	poor.night = 3
	_check(SeaEvents.options(SeaEvents.start("trade", poor, rng), poor).all(func(o: Dictionary) -> bool: return not o.enabled),
		"船舱是空的：三样都换不了")

	# 溺者之手
	var h := Contractor.new(config)
	for t in [500, 4000]:
		var c := CatchData.new()
		c.species_id = "grey_dace"
		c.tribute = t
		h.hold.append(c)
	var rh := SeaEvents.resolve(SeaEvents.start("hand", h, rng), 1, h, rng)
	_check(rh.baits == 1 and h.hold.size() == 1 and h.hold[0].tribute == 4000, "溺者之手：最不值钱的一条换一份万能饵")
	SeaEvents.resolve(SeaEvents.start("hand", h, rng), 0, h, rng)
	_check(h.hold.is_empty() and h.items.values().reduce(func(s, x): return s + x, 0) == 1, "溺者之手：最值钱的一条换一件道具")

	# 残骸
	var tally := {"item": 0, "materials": 0, "nothing": 0}
	var spent := true
	for i in 2000:
		var wr := Contractor.new(config)
		var rr := SeaEvents.resolve(SeaEvents.start("wreck", wr, rng), 0, wr, rng, 3)
		spent = spent and rr.spend_bait == 1
		var kind := "item" if config.trade_items.has(rr.got) else ("materials" if rr.got == "materials" else "nothing")
		tally[kind] += 1
	_check(spent and absf(tally.item / 2000.0 - 0.4) < 0.04 and absf(tally.nothing / 2000.0 - 0.2) < 0.03,
		"残骸：花一份饵；道具 %d、材料 %d、什么也没有 %d（两千回）" % [tally.item, tally.materials, tally.nothing])
	var empty := Contractor.new(config)
	_check(not SeaEvents.options(SeaEvents.start("wreck", empty, rng), empty, 0)[0].enabled, "手里没有饵：钩不了残骸")

	# 血月
	var bm := Contractor.new(config)
	bm.night = 5
	bm.ability_override = 3
	var top_plain: float = WaterLayers.level_shares(2, bm.night_config())[4]
	SeaEvents.resolve(SeaEvents.start("blood_moon", bm, rng), 0, bm, rng)
	var top_moon: float = WaterLayers.level_shares(2, bm.night_config())[4]
	var cast := {}
	for i in 100:
		cast = CastRoll.roll(bait, 2, bm, rng, bm.night_config())
		if cast.catch:
			break
	_check(bm.blood_moon and top_moon > top_plain and cast.catch != null and is_equal_approx(cast.catch.bonus, config.blood_moon_bonus),
		"血月：渊底 5 级的 %.0f%% → %.0f%%，钓上来的祭值 +%d%%" % [top_plain * 100.0, top_moon * 100.0, roundi(config.blood_moon_bonus * 100.0)])
	bm.begin_night(rng)
	_check(not bm.blood_moon, "血月：天黑就散了")

	# 祂的低语
	var wh := Contractor.new(config)
	var rw := SeaEvents.resolve(SeaEvents.start("whisper", wh, rng), 0, wh, rng)
	_check(wh.brands == 2 and wh.brands_lost() == 1 and rw.choose_boon.size() == 3
		and rw.choose_boon.all(func(c: RewardCard) -> bool: return c.permanent), "祂的低语：烙印 3 → 2（照算丢的），从三张恩赐里挑")
	var rw2 := SeaEvents.resolve(SeaEvents.start("whisper", wh, rng), -1, wh, rng)
	_check(wh.brands == 2 and rw2.choose_boon.is_empty(), "不应：什么也不变")

## 阶段 V：三件新事（亡魂、暴雨、冥市的赌徒）和祂的返还
func _test_more_events() -> void:
	print("阶段 V 的海上事件和祂的返还")
	var config := GameDB.balance
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var g := Contractor.new(config)
	g.hunger = 80.0
	var rg := SeaEvents.resolve(SeaEvents.start("ghost", g, rng), 0, g, rng)
	_check(config.trade_items.has(rg.got) and is_equal_approx(g.hunger, 80.0 - config.ghost_hunger),
		"亡魂：一件道具（%s），饱腹 −%d" % [rg.got, roundi(config.ghost_hunger)])
	var named := SeaEvents.lines({"id": "ghost", "ghost_name": "No.0003 亚瑟"})
	_check(named[0].begins_with("No.0003 亚瑟 的亡魂"), "亡魂：名册上有死了的就写出是谁（%s）" % named[0])
	var s := Contractor.new(config)
	var fish := CatchGenerator.generate(GameDB.get_fish("grey_dace"), rng, config, 0, -1, {"stage": 1, "level": 1})
	var before: int = s.dismantle_yield(fish).values().reduce(func(t, x): return t + x, 0)
	SeaEvents.resolve(SeaEvents.start("storm", s, rng), 0, s, rng)
	var during: int = s.dismantle_yield(fish).values().reduce(func(t, x): return t + x, 0)
	_check(s.storm and during == before + config.storm_materials and is_equal_approx(s.cast_hunger(), config.hunger_per_cast + config.storm_hunger),
		"暴雨：分解多 %d 份（%d → %d），每竿多掉 %d 饱腹" % [config.storm_materials, before, during, roundi(config.storm_hunger)])
	s.begin_night(rng)
	_check(not s.storm and is_equal_approx(s.cast_hunger(), config.hunger_per_cast), "暴雨：天黑就停了")
	var wins := 0
	var losses := 0
	for i in 1000:
		var gm := Contractor.new(config)
		var c := CatchGenerator.generate(GameDB.get_fish("grey_dace"), rng, config, 0, -1, {"stage": 1, "level": 1})
		if i % 2 == 1:  ## 一半带着别的加成（像残躯为饵的 +30%），赢了也要整整两倍
			c.bonus = 0.3
			c.tribute = CatchGenerator.tribute_of(c, c.species(), config)
		var t := c.tribute
		gm.hold.append(c)
		var rr := SeaEvents.resolve(SeaEvents.start("gambler", gm, rng), 0, gm, rng)
		if rr.got == "win" and absi(c.tribute - t * 2) <= 1 and gm.hold.size() == 1:
			wins += 1
		elif rr.got == "lose" and gm.hold.is_empty():
			losses += 1
	_check(wins + losses == 1000 and absf(wins / 1000.0 - config.gambler_win) < 0.05,
		"冥市的赌徒：押上的一条，赢了祭值翻倍（带着别的加成也是两倍，%d 回）、输了被收走（%d 回）" % [wins, losses])
	# 祂的返还
	var years := GameDB.get_promise("years")
	var texts := []
	for rating in ["献心", "虔诚", "守约", "勉强"]:
		texts.append(years.returned_text(rating))
	_check(texts.size() == 4 and texts[0] != texts[1] and texts[2] != texts[3] and years.returned_text("背约") == "祂归还了：被夺走的寿数。",
		"祂的返还：四档各一句（献心：%s）；别的评价还是原来那句" % texts[0])
	var all_ok := true
	for p in GameDB.sorted_values(GameDB.promises):
		all_ok = all_ok and p.returns.size() == 4
	_check(all_ok, "六样许汝之物都写了四种还法")
