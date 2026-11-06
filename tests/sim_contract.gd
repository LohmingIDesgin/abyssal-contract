extends Node
## 整局模拟器的报告（设计对照文档 5.3、5.4；新回合机制 9.7）。命令行运行：
##   Godot_v4.6.3-stable_win64.exe --headless --path . res://tests/sim_contract.tscn
## 打印：每一层水、每一级的鱼值多少（定需求用）；每种脚本玩家几百份契约的结局；每种走法每一夜的账（抛了几竿、咬了几口、
## 钓上的怎么分、做了几份饵、饵和材料剩多少、饱腹、能力档、献上的是需求的几倍、够没够、超额没有、为什么唤祂）；
## 按能力档看一夜咬得到第 4、第 5 口的有几成；一夜最长咬几口、一份契约最长几分钟；"全拆续钓"会不会一夜钓不完；结算清单的评价各占几成。
## 祭值都按千写。数值从 data/balance.tres 读。想试别的数不用改文件，在命令行后面加（逗号分隔）：
##   ... res://tests/sim_contract.tscn -- demand=1600,2000,2600,3800,5500,8000,12000 ability=1,1,2,2,3,3,3 runs=80 quick
## 饵和材料：yield=0.4（处理所得的总缩放）levelyield=0.1（每高一级多出的材料）stageyield=0.6,1,1.5（三个时期的倍率）
##   minmat=1,2,2（三个时期至少拆得出几份）
##   supply=3（每夜补给）start=3（开局的饵）salvage=0.1（打捞）nothing=0.08（对路的饵空的机会）capacity=20（船舱上限）
##   over=1.5（超额线）
## 能力档：ability=1,1,2,2,3,3,3（第 1–7 夜各是几档；2026-11-04 去掉了玩家等级）；能量：energy=12,22,36,52,72（1–5 级生物的平均能量）
## 水层：layers=1,0,0,0,0,0.1,0.5,0.4,0,0,0,0.1,0.1,0.55,0.25（浅层、深水、渊底各出 1–5 级的比例）
## brands=99：烙印给够，没有人被吞、剪线不怕用光（测每夜留得下多少祭值，定需求用）
## 饱腹：cast=4（每抛一竿扣多少）stamina=0.05（搏斗里每耗 1 点体力扣多少）food=12（生吞加的饱腹 = 这个数 × 躯体规模^0.6）
## 海上事件（阶段 IV）：events=0.5（第 2 夜起每夜有一件的机会；0 = 关掉）only=trade（只出这一种）hungry=60,30 caps=0.85,0.65
## 走法：s.键=值 把所有走法的这一项都改掉（比如 s.target=99 只在饵用完时唤祂）。
## quick = 只跑三种走法（普通的手）。dump = 每份契约的结算再打一行 REC,玩家,结局,献上÷要的,剪线,丢的烙印（定评价的阈值用）。
## 奖励卡（H2）：choices=0,2,3（不够 / 够了 / 超额时几张候选）card=lure（候选里有就挑这张）cards=none（一张也不挑）
##   force=lure（每次结算都直接拿这张）cardtest（三种走法各跑一遍"不挑卡"和七张卡各拿一次，看每张卡把结局推多少）
##   card.vigor.amount=0.5 card.steady.uses=0（试卡的数值；uses=0 是一整夜都管）
## 名册（阶段 V）：roster=draft（加上 data/fish_draft/ 的十三种草案，还没有插图）species（多打一张“每一种”的表；带着草案时自动打）

const RUNS := 150
const PLAYERS := [["达标就收", "普通"], ["先吃再备", "普通"], ["多拆续钓", "普通"], ["达标就收", "熟练"], ["达标就收", "生疏"]]
const QUICK_PLAYERS := [["达标就收", "普通"], ["先吃再备", "普通"], ["多拆续钓", "普通"]]
const NIGHTS := 7
const ABILITY_MAX := 3  ## 能力档 1–3
const REF_BITES := 6000  ## 参考表每一层水抽多少口
const SPECIES_SAMPLES := 300  ## “每一种”的表每个时期抽几条

var _config: BalanceConfig
var _runs := RUNS
var _overrides := {}
var _prefer_card := ""
var _force_card := ""
var _no_cards := false
var _drafts := 0  ## 加进来的名册草案有几种（roster=draft）


func _ready() -> void:
	_config = GameDB.balance.duplicate() as BalanceConfig
	var players := PLAYERS
	var dump := false
	var card_test := false
	var show_species := false
	var floats := func(s: String) -> PackedFloat32Array: return PackedFloat32Array(Array(s.split(",")).map(func(x): return float(x)))
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=")
		match kv[0]:
			"demand":
				_config.offering_demand = PackedInt32Array(Array(kv[1].split(",")).map(func(x): return int(x)))
			"ability":
				_config.ability_by_night = PackedInt32Array(Array(kv[1].split(",")).map(func(x): return int(x)))
			"energy":
				_config.energy_by_level = floats.call(kv[1])
			"capacity":
				_config.hold_capacity = int(kv[1])
			"brands":
				_config.brands = int(kv[1])
			"yield":
				_config.yield_scale = float(kv[1])
			"levelyield":
				_config.yield_per_level = float(kv[1])
			"stageyield":
				_config.stage_yield = floats.call(kv[1])
			"minmat":
				_config.min_materials = PackedInt32Array(Array(kv[1].split(",")).map(func(x): return int(x)))
			"layers":
				_config.layer_levels = floats.call(kv[1])
			"supply":
				_config.supply_baits = int(kv[1])
			"start":
				_config.start_baits = int(kv[1])
			"salvage":
				_config.salvage_chance = float(kv[1])
			"nothing":
				_config.nothing_chance = float(kv[1])
			"over":
				_config.over_ratio = float(kv[1])
			"choices":
				_config.reward_choices = PackedInt32Array(Array(kv[1].split(",")).map(func(x): return int(x)))
			"card":
				_prefer_card = kv[1]
			"cards":
				_no_cards = kv[1] == "none"
			"force":
				_force_card = kv[1]
			"cardtest":
				card_test = true
			"deeper":
				## 带着哪几张一整夜都管的卡时往深一层钓（默认镇魂、壮魂）：deeper=steady 只有镇魂
				_overrides["deeper"] = Array(kv[1].split(","))
			"cast":
				_config.hunger_per_cast = float(kv[1])
			"stamina":
				_config.hunger_per_stamina = float(kv[1])
			"food":
				_config.hunger_per_body = float(kv[1])
			"events":
				_config.event_chance = float(kv[1])
			"only":  ## only=trade：海上事件只出这一种（测每一种单独的影响）
				var only := {}
				only[kv[1]] = 1.0
				_config.event_weights = only
			"hungry":
				_config.hungry_at = floats.call(kv[1])
			"caps":
				_config.hungry_stamina = floats.call(kv[1])
			"runs":
				_runs = int(kv[1])
			"dump":
				dump = true
			"quick":
				players = QUICK_PLAYERS
			"roster":
				if kv.size() == 2 and kv[1] == "draft":
					_drafts = GameDB.use_draft_fish()
			"species":
				show_species = true
			_:
				## s.键=值：所有走法的这一项都改掉（试走法用，比如 s.target=99 只在饵用完时唤祂）
				if kv[0].begins_with("s.") and kv.size() == 2:
					_overrides[kv[0].substr(2)] = float(kv[1])
				## card.卡.amount=值 / card.卡.uses=次数：试卡的数值（比如 card.vigor.amount=0.5、card.steady.uses=0 一整夜都管）
				elif kv[0].begins_with("card.") and kv.size() == 2:
					var parts := kv[0].split(".")
					var card := GameDB.get_card(parts[1])
					if card and parts.size() == 3:
						card.set(parts[2], int(kv[1]) if parts[2] == "uses" else float(kv[1]))
	var t0 := Time.get_ticks_msec()
	print("整局模拟器：每组 %d 份契约；每夜需求 %s；每夜的能力档 %s；各级的平均能量 %s" % [_runs, Array(_config.offering_demand),
		Array(_config.ability_by_night), Array(_config.energy_by_level)])
	print("  饵：开局 %d 份、每夜补给 %d 份，真咬钩才扣；处理所得缩放 %.2f、每级 +%.0f%%、时期 %s，至少 %s 份；打捞 %.0f%%；对路的饵空 %.0f%%、万能饵空 %.0f%%；船舱 %s；超额线 %.0f%%" % [
		_config.start_baits, _config.supply_baits, _config.yield_scale, _config.yield_per_level * 100.0, Array(_config.stage_yield),
		Array(_config.min_materials),
		_config.salvage_chance * 100.0, _config.nothing_chance * 100.0, _config.universal_nothing * 100.0, _config.hold_capacity,
		_config.over_ratio * 100.0])
	print("  奖励卡：不够 / 够了 / 超额各 %s 张候选；%s" % [Array(_config.reward_choices), "一张也不挑" if _no_cards else
		("每次都拿「%s」" % _force_card if _force_card != "" else ("先挑「%s」" % _prefer_card if _prefer_card != "" else "按走法的顺序挑"))])
	if _drafts > 0:
		print("  名册：正式的 %d 种 + 阶段 V 的草案 %d 种（data/fish_draft/）" % [GameDB.fish.size() - _drafts, _drafts])
	if card_test:
		_print_card_strength()
		get_tree().quit()
		return
	print("  饱腹：每竿 %.1f、每点体力 %.2f；%s 以下饿（体力上限 %s）；各层水出 1–5 级的比例 %s" % [
		_config.hunger_per_cast, _config.hunger_per_stamina, Array(_config.hungry_at), Array(_config.hungry_stamina),
		Array(_config.layer_levels)])
	_print_reference()
	if show_species or _drafts > 0:
		_print_species()
	var by_player := {}
	print("\n结局（一夜几竿 / 咬几口 / 咬到第 4 口、第 5 口的夜 / 饵够咬第 4 口的夜：咬了的 + 剩的饵 + 材料做得出的；一份契约几分钟按真人的节奏估，含黄昏、签约和结算清单）")
	print("    %-10s %6s %6s %6s %6s | %s" % ["玩家", "偿清", "落水", "被吞噬", "拖延",
		"每份契约供奉不够丢的烙印 / 剪线（也扣烙印）/ 偿清时最后一夜的能力档 | 竿 / 咬 / ≥4 口 / ≥5 口 / 饵够咬第 4 口 | 一夜几分钟 / 一份契约几分钟"])
	for p in players:
		var key := "%s·%s" % p
		var results := _run_many(_config, ContractSim.STRATEGIES[p[0]], ContractSim.SKILLS[p[1]])
		by_player[key] = results
		_print_outcomes(key, results)
		if dump:
			for r in results:
				var rec: Dictionary = r.record
				if not rec.is_empty():
					print("REC,%s,%s,%.3f,%d,%d" % [key, rec.cause, float(rec.tribute) / maxf(float(rec.demand), 1.0),
						rec.cuts, rec.brands_lost])
	for p in QUICK_PLAYERS:
		_print_nights("%s·%s" % p, by_player["%s·%s" % p])
	_print_by_level(by_player)
	_print_tails(by_player)
	_print_loop_check()
	_print_ratings(by_player)
	_print_cards(by_player)
	_print_events(by_player)
	print("\n用时 %.1f 秒" % ((Time.get_ticks_msec() - t0) / 1000.0))
	get_tree().quit()


func _run_many(config: BalanceConfig, strategy: Dictionary, skill: Dictionary, override := true) -> Array:
	var spec := strategy.duplicate()
	if override:
		for k in _overrides:
			spec[k] = _overrides[k]
	var sim := ContractSim.new(config, spec, skill)
	sim.prefer_card = _prefer_card
	sim.force_card = _force_card
	sim.no_cards = _no_cards
	var results := []
	for s in _runs:
		results.append(sim.run(1000 + s))
	return results


## 一份契约的真实分钟数（按真人的节奏估）：每夜钓鱼 + 每夜的黄昏 + 签约和结算清单
static func _contract_minutes(r: Dictionary) -> float:
	var s := ContractSim.CONTRACT_OVERHEAD
	for n in r.nights:
		s += n.seconds + n.overhead
	return s / 60.0


## 每一层水、每一级的鱼：占咬钩的几成、平均祭值、平均处理出几份材料（万能饵，按稀有度咬）。
## 定需求用：某一级的玩家在他钓的那层水里，钓得上的鱼平均值多少
func _print_reference() -> void:
	print("\n每一层水、每一级的鱼（万能饵按稀有度咬，每层抽 %d 口）：占咬钩的几成 / 平均祭值（千）/ 平均几份材料" % REF_BITES)
	print("    水层 | %s | 全部" % " | ".join(range(1, 6).map(func(l: int) -> String: return "%d 级" % l)))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var table_bait := BaitCrafter.make_universal(1)
	for depth in GameDB.DEPTH_NAMES.size():
		var table := BiteCalculator.bite_table(table_bait, depth, _config)
		var count := {}
		var tribute := {}
		var mats := {}
		var bites := 0
		var all_tribute := 0.0
		var all_mats := 0.0
		while bites < REF_BITES:
			var fish := BiteCalculator.roll(table, rng)
			if fish == null:
				continue
			bites += 1
			var c := CatchGenerator.generate(fish, rng, _config, 0, depth)
			var m := 0
			for k in c.materials:
				m += c.materials[k]
			count[c.level] = count.get(c.level, 0) + 1
			tribute[c.level] = tribute.get(c.level, 0.0) + c.tribute
			mats[c.level] = mats.get(c.level, 0.0) + m
			all_tribute += c.tribute
			all_mats += m
		var cells: PackedStringArray = []
		for level in range(1, 6):
			var k: int = count.get(level, 0)
			if k == 0:
				cells.append("        —        ")
			else:
				cells.append("%3.0f%% %5.1f %4.1f" % [k * 100.0 / bites, tribute[level] / k / 1000.0, mats[level] / k])
		print("    %s | %s | %5.1f %4.1f" % [GameDB.DEPTH_NAMES[depth], " | ".join(cells), all_tribute / bites / 1000.0,
			all_mats / bites])


## 每一种（阶段 V 验证名册用；roster=draft 或 species 时打印）：万能饵下各层水里占咬钩的几成；各个时期几级、平均祭值、
## 拆出几份材料（主要是哪一类）、生吞加几点饱腹；带特殊词条的几成。只在某些夜里出的按那种夜（第 1 夜）的数值表算
func _print_species() -> void:
	print("\n每一种（万能饵；只在某些夜里出的按那种夜算；每个时期抽 %d 条）：浅层 / 深水 / 渊底占咬钩的几成 | 幼年 · 成长 · 成年：等级 祭值（千）材料（主要的一类）饱腹 | 特殊词条" % SPECIES_SAMPLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var bait := BaitCrafter.make_universal(1)
	var nights := {"": _config.for_night(1, ""), "eerie": _config.for_night(1, "eerie"), "blood_moon": _config.for_night(1, "", true)}
	for fish: FishData in GameDB.sorted_values(GameDB.fish):
		var when: String = fish.appears_when[0] if not fish.appears_when.is_empty() else ""
		var cfg: BalanceConfig = nights.get(when, nights[""])
		var cells: PackedStringArray = []
		for depth in GameDB.DEPTH_NAMES.size():
			var share := 0.0
			for e in BiteCalculator.bite_table(bait, depth, cfg):
				if e.fish == fish:
					share = e.chance / maxf(1.0 - cfg.universal_nothing, 0.001)
			cells.append(("%3.0f%%" % (share * 100.0)) if share > 0.0 else "   —")
		var stages: PackedStringArray = []
		var special := 0
		for s in 3:
			var levels := fish.stage_levels(s)
			var tribute := 0.0
			var food := 0.0
			var mats := {}
			var total := 0
			for i in SPECIES_SAMPLES:
				var level: int = levels.x if i % 2 == 0 else levels.y
				var c := CatchGenerator.generate(fish, rng, cfg, 0, -1, {"stage": s, "level": level})
				tribute += c.tribute
				food += c.food
				for m in c.materials:
					mats[m] = mats.get(m, 0) + c.materials[m]
					total += c.materials[m]
				if c.affix_ids.any(func(id: String) -> bool: return GameDB.get_affix(id) != null and GameDB.get_affix(id).special):
					special += 1
			var main := Materials.FLESH
			for m in Materials.ALL:
				if mats.get(m, 0) > mats.get(main, 0):
					main = m
			var lv: String = ("%d" % levels.x) if levels.x == levels.y else ("%d–%d" % [levels.x, levels.y])
			stages.append("%s级 %4.1f %3.1f%s %3.0f" % [lv, tribute / SPECIES_SAMPLES / 1000.0, float(total) / SPECIES_SAMPLES,
				(Materials.SHORT[main] as String).substr(0, 1), food / SPECIES_SAMPLES])
		var tag: String = {"eerie": "（异化）", "blood_moon": "（血月）"}.get(when, "")
		print("    %s%s | %s | %s | %3.0f%%" % [fish.display_name, tag, " ".join(cells), " · ".join(stages),
			special * 100.0 / (3 * SPECIES_SAMPLES)])


func _print_outcomes(label: String, results: Array) -> void:
	var counts := {}
	var brands_lost := 0.0
	var cuts := 0.0
	var level := 0.0
	var repaid := 0
	var casts := 0.0
	var bites := 0.0
	var four := 0
	var five := 0
	var can_four := 0
	var seconds := 0.0
	var minutes := 0.0
	var night_count := 0
	for r in results:
		counts[r.outcome] = counts.get(r.outcome, 0) + 1
		minutes += _contract_minutes(r)
		for n in r.nights:
			brands_lost += 1 if n.brand_lost else 0
			cuts += n.cut
			casts += n.casts
			bites += n.bites
			four += 1 if n.bites >= 4 else 0
			five += 1 if n.bites >= 5 else 0
			can_four += 1 if _available(n) >= 4 else 0
			seconds += n.seconds + n.overhead
			night_count += 1
		if r.outcome == "repaid":
			repaid += 1
			level += r.nights[-1].ability
	var pct := func(k: String) -> float: return counts.get(k, 0) * 100.0 / results.size()
	var nights := maxi(night_count, 1)
	print("    %-10s %5.0f%% %5.0f%% %5.0f%% %5.0f%% | %.2f / %.2f / %.1f | %.1f / %.1f / %3.0f%% / %3.0f%% / %3.0f%% | %.1f / %.0f" % [label,
		pct.call("repaid"), pct.call("fall"), pct.call("offering"), pct.call("stalled"), brands_lost / results.size(),
		cuts / results.size(), level / maxi(repaid, 1), casts / nights, bites / nights, four * 100.0 / nights,
		five * 100.0 / nights, can_four * 100.0 / nights, seconds / nights / 60.0, minutes / results.size()])


## 这一夜手里的饵够咬几口：咬了的 + 唤祂时篓里剩的 + 身上的材料还做得出的（留到下一夜的也算这一夜"抛得出"）
static func _available(n: Dictionary) -> int:
	return n.bites + n.baits_end + n.materials_end / 2


## 每一夜的账（只算活到这一夜的契约）。材料、饵都按份；"唤祂"写的是为什么唤：够了 / 饵用完了 / 一夜钓到了上限
func _print_nights(label: String, results: Array) -> void:
	print("\n每一夜的账：%s（%d 份契约里活到这一夜的）" % [label, results.size()])
	print("    夜 份数 | 竿 咬 ≥4口 ≥5口 够4 够5 万能/做的 空 钓上 钓上祭值 | 留 吃 撑 拆 材料入 做饵 | 夜初饵→剩饵 剩材料 | 饱腹 夜初→黄昏 最低 饿着抛 |" +
		" 能力档 剪线 | 需求 船舱 两成/中位 献上倍数中位 够了 超额 丢烙印 | 唤祂：够了/用完/上限 | 带过夜（千）")
	for night in range(1, NIGHTS + 1):
		var rows := []
		for r in results:
			for n in r.nights:
				if n.night == night:
					rows.append(n)
		if rows.is_empty():
			continue
		var avg := func(k: String) -> float:
			var t := 0.0
			for n in rows:
				t += float(n[k])
			return t / rows.size()
		var rate := func(k: String) -> float:
			var t := 0
			for n in rows:
				t += 1 if n[k] else 0
			return t * 100.0 / rows.size()
		var at_least := func(k: int) -> float:
			var t := 0
			for n in rows:
				t += 1 if n.bites >= k else 0
			return t * 100.0 / rows.size()
		var can := func(k: int) -> float:
			var t := 0
			for n in rows:
				t += 1 if _available(n) >= k else 0
			return t * 100.0 / rows.size()
		var summon := func(why: String) -> float:
			var t := 0
			for n in rows:
				t += 1 if n.summon == why else 0
			return t * 100.0 / rows.size()
		var quantile := func(k: String, q: float) -> float:
			var xs: Array = rows.map(func(n) -> float: return float(n[k]))
			xs.sort()
			return xs[mini(xs.size() - 1, int(xs.size() * q))]
		print("    %d %4d | %4.1f %3.1f %3.0f%% %3.0f%% %3.0f%% %3.0f%% %3.1f/%3.1f %3.1f %4.1f %6.1f | %3.1f %3.1f %3.1f %3.1f %5.1f %4.1f | %4.1f→%4.1f %5.1f | %3.0f→%3.0f %3.0f %4.1f | %3.1f %4.2f |" % [
			night, rows.size(), avg.call("casts"), avg.call("bites"), at_least.call(4), at_least.call(5), can.call(4), can.call(5),
			avg.call("universal_used"), avg.call("crafted_used"), avg.call("nothing"),
			avg.call("caught"), avg.call("tribute_caught") / 1000.0, avg.call("kept"), avg.call("eaten"), avg.call("overfull"),
			avg.call("processed"),
			avg.call("materials_in"), avg.call("crafted"), avg.call("baits_start"), avg.call("baits_end"),
			avg.call("materials_end"), avg.call("hunger_start"), avg.call("hunger"), avg.call("min_hunger"),
			avg.call("hungry_casts"), avg.call("ability"), avg.call("cut")] +
			" %5.1f %5.1f/%5.1f %8.2f %4.0f%% %4.0f%% %4.0f%% | %3.0f/%3.0f/%3.0f%% | %5.1f" % [avg.call("demand") / 1000.0,
			quantile.call("hold_tribute", 0.2) / 1000.0, quantile.call("hold_tribute", 0.5) / 1000.0, quantile.call("ratio", 0.5),
			rate.call("met"), rate.call("over"), rate.call("brand_lost"),
			summon.call("target"), summon.call("out"), summon.call("cap"), avg.call("carry") / 1000.0])


## 按这一夜的能力档：一夜咬几口，咬到第 4、第 5、第 8 口的夜占几成（档高了钓得深、拆出来的多，应该更容易多钓几口），饵够咬第 4 口的夜
func _print_by_level(by_player: Dictionary) -> void:
	print("\n按这一夜的能力档：几夜 / 一夜咬几口 / 咬到第 4 口、第 5 口、第 8 口的夜 / 饵够咬第 4 口、第 5 口的夜")
	print("    %-10s %s" % ["玩家", " | ".join(range(1, ABILITY_MAX + 1).map(func(l: int) -> String: return "%d 档" % l))])
	for key in by_player:
		var cells: PackedStringArray = []
		for level in range(1, ABILITY_MAX + 1):
			var rows := []
			for r in by_player[key]:
				for n in r.nights:
					if n.ability == level:
						rows.append(n)
			if rows.is_empty():
				cells.append("                 —                ")
				continue
			var bites := 0.0
			var hits := [0, 0, 0, 0, 0]
			for n in rows:
				bites += n.bites
				hits[0] += 1 if n.bites >= 4 else 0
				hits[1] += 1 if n.bites >= 5 else 0
				hits[2] += 1 if n.bites >= 8 else 0
				hits[3] += 1 if _available(n) >= 4 else 0
				hits[4] += 1 if _available(n) >= 5 else 0
			cells.append("%4d %4.1f %3.0f%% %3.0f%% %3.0f%% %3.0f%% %3.0f%%" % [rows.size(), bites / rows.size(),
				hits[0] * 100.0 / rows.size(), hits[1] * 100.0 / rows.size(), hits[2] * 100.0 / rows.size(),
				hits[3] * 100.0 / rows.size(), hits[4] * 100.0 / rows.size()])
		print("    %-10s %s" % [key, " | ".join(cells)])


## 一夜最长咬几口、一份契约最长几分钟："钓不完"是小概率的事（回合指令：可以有，不能稳定地重复）
func _print_tails(by_player: Dictionary) -> void:
	print("\n一夜咬几口：中位 / 九成的夜不超过 / 九十九成 / 最多 | 咬到 10 口、20 口的夜 | 一份契约几分钟：中位 / 九成 / 最长")
	for key in by_player:
		var bites := []
		var minutes := []
		for r in by_player[key]:
			minutes.append(_contract_minutes(r))
			for n in r.nights:
				bites.append(n.bites)
		bites.sort()
		minutes.sort()
		var share := func(k: int) -> float: return bites.filter(func(b: int) -> bool: return b >= k).size() * 100.0 / bites.size()
		var at := func(xs: Array, q: float): return xs[mini(xs.size() - 1, int(xs.size() * q))]
		print("    %-10s %3d / %3d / %3d / %3d | %4.1f%% %4.1f%% | %4.0f / %4.0f / %4.0f" % [key, at.call(bites, 0.5),
			at.call(bites, 0.9), at.call(bites, 0.99), bites[-1], share.call(10), share.call(20), at.call(minutes, 0.5),
			at.call(minutes, 0.9), minutes[-1]])


## "全拆续钓"会不会钓不完：不留、不饿就拆，只在饵用完、材料也做不出来时唤祂（一夜最多 ContractSim.MAX_CASTS 竿）。
## 每一层水各测一遍（能力档固定成这层水该有的，只在这一层钓：浅层 1 档、深水 2 档、渊底 3 档）：
## 头两夜平均咬几口、最多几口、拆出来的材料每咬一口换回几份饵、咬到 20 口的夜、到上限的夜占几成
func _print_loop_check() -> void:
	print("\n全拆续钓（不留，不饿就拆，饵用完了才唤祂；一夜最多 %d 竿；头两夜）" % ContractSim.MAX_CASTS)
	print("    水层（能力档） | 一夜咬几口 平均 / 最多 | 每咬一口换回几份饵 | 咬到 20 口的夜 | 到上限的夜")
	for row in [[0, 1], [1, 2], [2, 3]]:
		var depth: int = row[0]
		var spec: Dictionary = ContractSim.STRATEGIES["全拆"].duplicate()
		spec.depths = [depth, depth, depth]
		spec.start_ability = row[1]
		var results := _run_many(_config, spec, ContractSim.SKILLS["普通"], false)
		var bites := []
		var mats := 0.0
		var total := 0.0
		var capped := 0
		for r in results:
			for n in r.nights:
				if n.night <= 2:
					bites.append(n.bites)
					mats += n.materials_in
					total += n.bites
					capped += 1 if n.summon == "cap" else 0
		bites.sort()
		var long := bites.filter(func(b: int) -> bool: return b >= 20).size()
		print("    %s（%d 档） | %5.1f / %3d | %5.2f | %4.1f%% | %3.0f%%" % [GameDB.DEPTH_NAMES[depth], row[1],
			total / maxi(bites.size(), 1), bites[-1], mats / 2.0 / maxf(total, 1.0), long * 100.0 / maxi(bites.size(), 1),
			capped * 100.0 / maxi(bites.size(), 1)])


## 结算清单的评价（Settlement.rate）：每种玩家各档占几成；偿清了的，献上的祭值是要的几倍（中位）、剪线和丢的烙印（平均）
func _print_ratings(by_player: Dictionary) -> void:
	var tiers := Settlement.RATINGS.duplicate()
	tiers.reverse()
	tiers.append_array([Settlement.BROKEN, Settlement.DROWNED])
	print("\n结算的评价（%；偿清了的：献上 ÷ 要的 中位 / 剪线 平均 / 丢的烙印 平均）")
	print("    %-10s %s" % ["玩家", " ".join(tiers.map(func(s: String) -> String: return "%5s" % s))])
	for key in by_player:
		var counts := {}
		var ratios := []
		var cut := 0.0
		var lost := 0.0
		var repaid := 0
		for r in by_player[key]:
			var rec: Dictionary = r.record
			if rec.is_empty():
				continue
			counts[rec.rating] = counts.get(rec.rating, 0) + 1
			if rec.cause == "repaid":
				repaid += 1
				ratios.append(float(rec.tribute) / maxf(float(rec.demand), 1.0))
				cut += rec.cuts
				lost += rec.brands_lost
		ratios.sort()
		var cells := tiers.map(func(s: String) -> String: return "%5.0f" % (counts.get(s, 0) * 100.0 / by_player[key].size()))
		print("    %-10s %s | %.2f / %.1f / %.2f" % [key, " ".join(cells), ratios[ratios.size() / 2] if not ratios.is_empty() else 0.0,
			cut / maxi(repaid, 1), lost / maxi(repaid, 1)])


## 奖励卡的账（结算了、还有下一夜的那些夜）：几张候选（0 / 2 / 3 各占几成）、挑了哪张（各占几成）、
## 一份契约里卡的效果触发了几次（引深引上来的、进化长了的、镇魂按高一级打的）
func _print_cards(by_player: Dictionary) -> void:
	var ids: Array = GameDB.sorted_values(GameDB.cards).map(func(c: RewardCard) -> String: return c.id)
	print("\n奖励卡（结算了、还有下一夜的夜）：候选 0 / 2 / 3 张 | 挑了哪张（%%）%s | 一份契约里：引深引上来 / 进化 / 镇魂" % " ".join(
		ids.map(func(id: String) -> String: return GameDB.get_card(id).display_name)))
	for key in by_player:
		var nights := 0
		var counts := {0: 0, 2: 0, 3: 0}
		var picks := {}
		var lured := 0.0
		var evolved := 0.0
		var steadied := 0.0
		for r in by_player[key]:
			for n in r.nights:
				lured += n.lured
				evolved += n.evolved
				steadied += n.steadied
				if n == r.nights[-1] and r.outcome != "stalled":
					continue
				nights += 1
				counts[n.choices] = counts.get(n.choices, 0) + 1
				if n.card != "":
					picks[n.card] = picks.get(n.card, 0) + 1
		var total := maxi(nights, 1)
		var runs := maxi(by_player[key].size(), 1)
		print("    %-10s %3.0f%% %3.0f%% %3.0f%% | %s | %.2f / %.2f / %.2f" % [key, counts[0] * 100.0 / total, counts[2] * 100.0 / total,
			counts[3] * 100.0 / total, " ".join(ids.map(func(id: String) -> String: return "%4.0f" % (picks.get(id, 0) * 100.0 / total))),
			lured / runs, evolved / runs, steadied / runs])


## 海上事件（阶段 IV）：一份契约碰上几件；每一种碰上几次、接了几成；冥市船买了什么
func _print_events(by_player: Dictionary) -> void:
	var ids: Array = SeaEvents.NAMES.keys()
	print("\n海上事件：一份契约碰上几件 | %s：碰上几次（一份契约）/ 接了几成 | 冥市船买了：恩赐 / 饵 / 道具（一份契约）" % " ".join(
		ids.map(func(id: String) -> String: return SeaEvents.NAMES[id])))
	for key in by_player:
		var runs := maxi(by_player[key].size(), 1)
		var seen := {}
		var taken := {}
		var bought := {"boon": 0, "baits": 0, "item": 0}
		var total := 0
		for r in by_player[key]:
			for n in r.nights:
				if n.event == "":
					continue
				total += 1
				seen[n.event] = seen.get(n.event, 0) + 1
				if n.event_choice >= 0:
					taken[n.event] = taken.get(n.event, 0) + 1
					if n.event == "trade":
						var kind := "baits" if n.event_got == "baits" else ("item" if GameDB.get_item(n.event_got) else "boon")
						bought[kind] += 1
		var cells := ids.map(func(id: String) -> String: return "%.2f/%3.0f%%" % [seen.get(id, 0) / float(runs),
			taken.get(id, 0) * 100.0 / maxf(seen.get(id, 0), 1.0)])
		print("    %-10s %.2f | %s | %.2f / %.2f / %.2f" % [key, total / float(runs), " ".join(cells), bought.boon / float(runs),
			bought.baits / float(runs), bought.item / float(runs)])


## 每张卡的强度：三种走法各跑一遍"一张也不挑"，再七张卡各跑一遍"每次结算都直接拿这张"，看结局差多少：
## 偿清、丢的烙印、超额的夜、偿清时献上的是要的几倍（中位）、剪了几次线、一份契约几分钟
func _print_card_strength() -> void:
	var t0 := Time.get_ticks_msec()
	var ids: Array = [""] + GameDB.sorted_values(GameDB.cards).map(func(c: RewardCard) -> String: return c.id)
	print("\n每张卡的强度（每次结算都拿这张；「不挑」是对照）：偿清 / 丢的烙印 / 超额的夜 / 献上倍数中位 / 剪线 / 分钟")
	for p in QUICK_PLAYERS:
		var key := "%s·%s" % p
		print("  %s" % key)
		for id in ids:
			_no_cards = id == ""
			_force_card = id
			var results := _run_many(_config, ContractSim.STRATEGIES[p[0]], ContractSim.SKILLS[p[1]])
			var repaid := 0
			var lost := 0.0
			var over := 0
			var nights := 0
			var level := 0.0
			var minutes := 0.0
			var ratios := []
			for r in results:
				minutes += _contract_minutes(r)
				level += r.record.get("cuts", 0) if not r.record.is_empty() else 0
				for n in r.nights:
					lost += 1 if n.brand_lost else 0
					over += 1 if n.over else 0
					nights += 1
				if r.outcome == "repaid":
					repaid += 1
					var rec: Dictionary = r.record
					ratios.append(float(rec.tribute) / maxf(float(rec.demand), 1.0))
			ratios.sort()
			var name: String = "不挑" if id == "" else GameDB.get_card(id).display_name
			print("    %-4s %4.0f%% %5.2f %4.0f%% %5.2f %4.2f %5.1f" % [name, repaid * 100.0 / results.size(), lost / results.size(),
				over * 100.0 / maxi(nights, 1), ratios[ratios.size() / 2] if not ratios.is_empty() else 0.0, level / results.size(),
				minutes / results.size()])
	_no_cards = false
	_force_card = ""
	print("  （%.0f 秒）" % ((Time.get_ticks_msec() - t0) / 1000.0))
