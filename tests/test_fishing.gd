extends Node
## 搏斗自检 + 强弱表的测量。命令行运行：
##   Godot_v4.6.3-stable_win64.exe --headless --path . res://tests/test_fishing.tscn
## 规则自检用两个机器人：合格玩家（张力低于 0.7 就收线），迟钝玩家（每 0.3 秒才重新判断一次，而且贪心到 0.8）。
## 测量按强弱表（BalanceConfig.fight_gaps，2026-11-03 定的）：能力档 1–3（2026-11-04 起玩家没有等级了）各对上 1–5 级的生物；每一级的生物按它们
## 在水里出现的样子抽（WaterLayers.stage_parts：哪几种、哪个时期是这一级，按稀有度），体力耗尽就硬撑，钓上率算上硬撑赢的。
## 搏斗的手和整局模拟器的三种一样（ContractSim.SKILLS）：熟练（不用反应时间）、普通（0.2 秒反应一次，算"操作得当"，
## 目标按它定）、生疏（0.3 秒、更贪）。
## 调参：-- drain=1.35 pull=0.25 reel=0.15 endurance=0.15 seeds=24（BalanceConfig"搏斗"一组的对应几项）、gap35=0.8（强弱表的一格）

const DT := 1.0 / 60.0
const MAX_TIME := 120.0
const START := 23.0  ## 起始距离：三层水都是 23 米（CastRoll.start_distance；-- start=31 看原来渊底的）
## 定下的目标（普通的手的钓上率，算上硬撑）：[能力档, 生物等级, 下限, 上限]
## 1 档：1 级相当，2 级较强五成上下，3 级以上钓不上；2 档：2、3 级相当，4 级五成，5 级钓不上；3 档：4 级相当，5 级七成
const TARGETS := [[1, 1, 0.9, 1.0], [1, 2, 0.38, 0.62], [1, 3, 0.0, 0.0], [2, 2, 0.9, 1.0], [2, 3, 0.9, 1.0],
	[2, 4, 0.38, 0.62], [2, 5, 0.0, 0.0], [3, 4, 0.9, 1.0], [3, 5, 0.6, 0.86]]  ## 阶段 V：5 级多了冥河蜃螺（挣扎轻），平均好钓一点

var _failures := 0
var _config: BalanceConfig
var _seeds := 24
var _start := START


func _ready() -> void:
	_config = GameDB.balance.duplicate()
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"drain":
				_config.level_drain_factor = float(kv[1])
			"pull":
				_config.level_pull_step = float(kv[1])
			"reel":
				_config.level_reel_step = float(kv[1])
			"endurance":
				_config.level_endurance_step = float(kv[1])
			"seeds":
				_seeds = int(kv[1])
			"start":
				_start = float(kv[1])
			_:
				if kv[0].begins_with("gap") and kv[0].length() == 5:  ## gap35=0.8：契约者 3 级对 5 级算差几级
					_config.fight_gaps[(int(kv[0][3]) - 1) * 5 + int(kv[0][4]) - 1] = float(kv[1])
	_test_rules()
	_test_policies()
	_measure()
	print("\n==== %s（失败 %d 项）====" % ["全部通过" if _failures == 0 else "存在失败", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	print(("  [OK]   " if cond else "  [FAIL] ") + msg)
	if not cond:
		_failures += 1


## 用给定策略打一场，返回 {result, time, stamina, min_stamina, gamble}
func _simulate(fish: FishData, gap: float, seed_value: int, policy: Callable, stage := CatchData.Stage.GROWING) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var model := TensionModel.new(fish, gap, _start, _config, rng, stage)
	var t := 0.0
	var result := TensionModel.Result.ONGOING
	while t < MAX_TIME and result == TensionModel.Result.ONGOING:
		result = model.step(DT, policy.call(model))
		t += DT
	return {"result": result, "time": t, "stamina": model.stamina, "min_stamina": model.min_stamina,
		"gamble": model.gamble_chance()}


func _always(_m: TensionModel) -> bool:
	return true


func _never(_m: TensionModel) -> bool:
	return false


func _skilled(m: TensionModel) -> bool:
	return m.tension < 0.7


func _make_sluggish() -> Callable:
	return _make_hand(0.3, 0.8)


## 每隔 react 秒才重新判断一次、张力低于 greed 就收线的手（和整局模拟器的 SKILLS 一样）
func _make_hand(react: float, greed: float) -> Callable:
	var state := {"t": 0.0, "hold": false}
	return func(m: TensionModel) -> bool:
		state.t -= DT
		if state.t <= 0.0:
			state.t = react
			state.hold = m.tension < greed
		return state.hold


func _test_rules() -> void:
	print("规则")
	var eel := GameDB.get_fish("blind_bone_eel")
	var m := TensionModel.new(eel, 1.0, START, _config)
	_check(is_equal_approx(m.stamina, _config.stamina_max), "上钩时体力是满的")
	_check(TensionModel.tier_of(-3.0) == 0 and TensionModel.tier_of(-1.0) == 0 and TensionModel.tier_of(0.0) == 1
		and TensionModel.tier_of(0.6) == 2 and TensionModel.tier_of(1.0) == 2 and TensionModel.tier_of(2.0) == 3
		and TensionModel.tier_of(6.0) == 3, "强弱分档：弱一级以上 = 弱，相当 = 相当，强不到两级 = 强，强两级以上 = 极强")
	var fresh := m.gamble_chance()
	m.endurance = 0.0
	var tired := m.gamble_chance()
	var stronger := TensionModel.new(eel, 2.0, START, _config)
	stronger.endurance = 0.0
	_check(tired > fresh, "硬撑：它越累机会越大（%.2f → %.2f）" % [fresh, tired])
	_check(stronger.gamble_chance() == 0.0, "硬撑：强两级（远超自己）的必输（%.2f）" % stronger.gamble_chance())
	_check(fresh >= _config.gamble_min and tired <= _config.gamble_max, "硬撑的概率夹在上下限之间")
	_check(TensionModel.gamble_phrase(0.05) == "九死一生" and TensionModel.gamble_phrase(0.4) == "尚有一线", "硬撑只给一句话")
	var cfg := _config
	_check(cfg.fight_gap(1, 1) == 0.0 and cfg.fight_gap(1, 2) == 1.0 and cfg.fight_gap(1, 3) >= 2.0
		and cfg.fight_gap(2, 2) == 0.0 and cfg.fight_gap(2, 3) == 0.0 and cfg.fight_gap(2, 4) == 1.0 and cfg.fight_gap(2, 5) >= 2.0
		and cfg.fight_gap(3, 4) == 0.0 and cfg.fight_gap(3, 5) > 0.0 and cfg.fight_gap(3, 5) < 1.0,
		"强弱表（按能力档）：1 档对 1 级相当、2 级强一级、3 级以上远超；2 档对 2、3 级相当，4 级强一级，5 级远超；3 档对 4 级相当，5 级强一点")
	# 自动垂钓（2026-11-04）：相当的 85%，每弱一级 +7%，最多 99%；饿了打折。耗的体力：相当的多、弱一级以上少，饿得发慌掉得快
	var even := cfg.auto_success(0.0, 100.0)
	var weak := cfg.auto_success(-1.0, 100.0)
	var weakest := cfg.auto_success(-3.0, 100.0)
	_check(is_equal_approx(even, 0.85) and is_equal_approx(weak, 0.92) and is_equal_approx(weakest, 0.99),
		"自动垂钓钓上来的机会：相当 %.0f%%、弱一级 %.0f%%、弱三级 %.0f%%（最多 99%%）" % [even * 100.0, weak * 100.0, weakest * 100.0])
	var hungry := cfg.auto_success(0.0, 45.0)
	var starving := cfg.auto_success(0.0, 15.0)
	_check(hungry < even and starving < hungry, "自动垂钓：饿了 %.0f%%、饿得发慌 %.0f%%，比不饿的低" % [hungry * 100.0, starving * 100.0])
	var tiring := cfg.auto_stamina(0.0, 100.0)
	var easy := cfg.auto_stamina(-1.0, 100.0)
	_check(tiring > easy and easy == cfg.auto_stamina(-3.0, 100.0) and cfg.auto_stamina(0.0, 15.0) > tiring,
		"自动垂钓耗的体力：相当 %.0f、弱一级以上 %.0f，饿得发慌 %.0f" % [tiring, easy, cfg.auto_stamina(0.0, 15.0)])


func _test_policies() -> void:
	print("策略（盲眼噬骸鳗）")
	var eel := GameDB.get_fish("blind_bone_eel")
	_check(_simulate(eel, 0.0, 1, _always).result == TensionModel.Result.EXHAUSTED, "一直按住 → 线不断，体力耗尽")
	var same := Tally.new()
	var strong := Tally.new()
	for s in 40:
		same.add(_simulate(eel, 0.0, s, _never))
		strong.add(_simulate(eel, 3.0, s, _never))
	_check(same.rate(TensionModel.Result.SLIPPED) >= 90.0, "相当的一直不按 → 脱钩（%.0f%%）" % same.rate(TensionModel.Result.SLIPPED))
	_check(strong.rate(TensionModel.Result.SLIPPED) >= 15.0 and strong.rate(TensionModel.Result.EXHAUSTED) >= 30.0,
		"强三级的一直不按 → 等它脱钩是一场赌：脱钩 %.0f%%，线放到头被拽到体力耗尽 %.0f%%" % [
		strong.rate(TensionModel.Result.SLIPPED), strong.rate(TensionModel.Result.EXHAUSTED)])
	_check(_simulate(eel, 0.0, 1, _skilled).result == TensionModel.Result.CAUGHT, "相当的、张力控制在 0.7 以下 → 钓上")


## 一组模拟的汇总（每一场带权重：这一种、这个时期在这一级里占多少）
class Tally:
	var n := 0.0
	var counts := {}
	var gamble := 0.0          ## 耗尽的那几场，硬撑钓上的机会加起来（带权重）

	func add(r: Dictionary, w := 1.0) -> void:
		n += w
		counts[r.result] = counts.get(r.result, 0.0) + w
		if r.result == TensionModel.Result.EXHAUSTED:
			gamble += r.gamble * w

	func rate(result: int) -> float:
		return counts.get(result, 0.0) * 100.0 / maxf(n, 0.001)

	## 钓上率算上硬撑：直接钓上的 + 耗尽以后硬撑赢的
	func landed() -> float:
		return (counts.get(TensionModel.Result.CAUGHT, 0.0) + gamble) / maxf(n, 0.001)


## 能力档 1–3 × 生物 1–5 级：每一格是普通的手的钓上率（熟练 / 生疏），算上硬撑；后面是普通的手直接钓上、耗尽的比例
func _measure() -> void:
	print("\n强弱表（%d 个随机种子 × 这一级的每一种、每个时期，起始 %.0f 米；钓上率算上硬撑）" % [_seeds, _start])
	print("  收线耗体力每级 ×%.2f、拉力每级 +%.0f%%、收线速度每级 −%.0f%%、它的耐力每级掉得慢 %.0f%%" % [
		_config.level_drain_factor, _config.level_pull_step * 100.0, _config.level_reel_step * 100.0,
		_config.level_endurance_step * 100.0])
	var parts := _parts_by_level()
	var results := {}
	for p in range(1, 4):
		var row := "  契约者 %d 档 |" % p
		for level in range(1, 6):
			var gap := _config.fight_gap(p, level)
			var hands := {}
			for hand in ["熟练", "普通", "生疏"]:
				var spec: Dictionary = ContractSim.SKILLS[hand]
				hands[hand] = Tally.new()
				for part in parts[level]:
					for s in _seeds:
						hands[hand].add(_simulate(part.fish, gap, s, _make_hand(spec.react, spec.greed), part.stage), part.w)
			var normal: Tally = hands["普通"]
			results["%d:%d" % [p, level]] = normal
			row += " %d 级(差%+.1f) %3.0f%%（%3.0f / %3.0f）直接 %3.0f%% 耗尽 %3.0f%% |" % [level, gap, normal.landed() * 100.0,
				hands["熟练"].landed() * 100.0, hands["生疏"].landed() * 100.0, normal.rate(TensionModel.Result.CAUGHT),
				normal.rate(TensionModel.Result.EXHAUSTED)]
		print(row)
	for t in TARGETS:
		var tally: Tally = results["%d:%d" % [t[0], t[1]]]
		var landed := tally.landed()
		var ok: bool = landed >= t[2] - 0.0001 and landed <= t[3] + 0.0001
		if t[3] == 0.0:
			ok = ok and tally.rate(TensionModel.Result.CAUGHT) == 0.0
		_check(ok, "能力 %d 档对 %d 级：普通的手钓上 %.0f%%（要 %.0f%%–%.0f%%）" % [t[0], t[1], landed * 100.0, t[2] * 100.0,
			t[3] * 100.0])


## 每一级的生物：[{fish, stage, w}]，w 是它在这一级里占的份（稀有度 × 时期的比例，成长期分两级时各算一部分）
func _parts_by_level() -> Dictionary:
	var result := {1: [], 2: [], 3: [], 4: [], 5: []}
	for fish: FishData in GameDB.sorted_values(GameDB.fish):
		for part in WaterLayers.stage_parts(fish, _config):
			if result.has(part.level):
				result[part.level].append({"fish": fish, "stage": part.stage, "w": fish.rarity_weight * part.part})
	return result
