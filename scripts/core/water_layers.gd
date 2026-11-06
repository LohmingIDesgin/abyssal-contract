class_name WaterLayers
extends RefCounted
## 三层水里出什么（2026-11-03 定的）。每层水出几级的生物是定好的（BalanceConfig.layer_levels）：浅层只出 1 级，
## 深水大多 2、3 级、偶尔 1 级，渊底大多 4、5 级、偶尔 2、3 级、没有 1 级。生物的等级跟着时期走（FishData.stage_levels），
## 所以一层水里出什么种类、什么时期，是按等级挑的：
## - 这层水里的每一级分到它那一份（这一级一种也没有的不算，剩下的重新归一）
## - 这一份再分给这一级的各个"种类 × 时期"：按种类的稀有度 × 时期的比例（stage_share）。只差一级的种类的成长期，
##   两级各分一部分（BalanceConfig.growth_up_chance：灵魂强度过了门槛的算高的那一级）
## 所以挂万能饵时，一层水里各级占的就是 layer_levels 写的比例。挂的饵只看种类（基础材料合不合、附加物的气味），
## 在这上面再乘（BiteCalculator）。全部是静态函数，界面、测试、整局模拟器调用同一套。


## 这一种在第 depth 层水里出现的各个时期：[{stage, level, weight}]。weight 是挂万能饵时咬钩的里面它这个时期占的份额
## （稀有度、时期的比例都算在里面），加起来就是这一种在这层水里占的份额（presence）。这层水里没有它就是空的
static func entries(fish: FishData, depth: int, config: BalanceConfig) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not fish.appears_in(config):  ## 只在某些夜里出的（阶段 V：血月鳗、无面鲂）
		return result
	var shares := level_shares(depth, config)
	var totals := _level_totals(config)
	for part in stage_parts(fish, config):
		var i: int = part.level - 1
		if i < 0 or i >= shares.size() or shares[i] <= 0.0 or totals[i] <= 0.0:
			continue
		result.append({"stage": part.stage, "level": part.level, "weight": shares[i] * fish.rarity_weight * part.part / totals[i]})
	return result


## 挂万能饵时，咬钩的里面这一种占几成（各个时期加起来）；这层水里没有它是 0
static func presence(fish: FishData, depth: int, config: BalanceConfig) -> float:
	var total := 0.0
	for e in entries(fish, depth, config):
		total += e.weight
	return total


## 这一种的各个时期各是几级、占多少（不看水层）：[{stage, level, part}]，part = 时期的比例 × 这一级的份（成长期分成两级时）
static func stage_parts(fish: FishData, config: BalanceConfig) -> Array[Dictionary]:
	var shares := _stage_shares(config)
	var up := config.growth_up_chance()
	var result: Array[Dictionary] = []
	for s in 3:
		var levels := fish.stage_levels(s)
		if levels.x == levels.y:
			result.append({"stage": s, "level": levels.x, "part": shares[s]})
		else:
			result.append({"stage": s, "level": levels.x, "part": shares[s] * (1.0 - up)})
			result.append({"stage": s, "level": levels.y, "part": shares[s] * up})
	return result


## 第 depth 层水里 1–5 级各占的比例（加起来是 1）：layer_levels 的一行，去掉一种生物也没有的那几级再归一
static func level_shares(depth: int, config: BalanceConfig) -> Array[float]:
	var raw := config.levels_at(depth)
	var totals := _level_totals(config)
	var sum := 0.0
	for i in raw.size():
		if totals[i] <= 0.0:
			raw[i] = 0.0
		sum += raw[i]
	for i in raw.size():
		raw[i] = raw[i] / sum if sum > 0.0 else 0.0
	return raw


## 这一种在第 depth 层水里有没有
static func has(fish: FishData, depth: int, config: BalanceConfig) -> bool:
	return not entries(fish, depth, config).is_empty()


## 这一种出现在哪几层水（下标，GameDB.DEPTH_NAMES）
static func depths_of(fish: FishData, config: BalanceConfig) -> Array[int]:
	var result: Array[int] = []
	for d in GameDB.DEPTH_NAMES.size():
		if has(fish, d, config):
			result.append(d)
	return result


## 每一级一共有多少份（所有种类、所有时期：稀有度 × 时期的比例），同一级的按它分
static func _level_totals(config: BalanceConfig) -> Array[float]:
	var totals: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	for fish: FishData in GameDB.fish.values():
		if not fish.appears_in(config):
			continue
		for part in stage_parts(fish, config):
			var i: int = part.level - 1
			if i >= 0 and i < totals.size():
				totals[i] += fish.rarity_weight * part.part
	return totals


static func _stage_shares(config: BalanceConfig) -> Array[float]:
	var sum := 0.0
	for x in config.stage_share:
		sum += maxf(x, 0.0)
	var result: Array[float] = []
	for s in 3:
		var x: float = maxf(config.stage_share[s], 0.0) if s < config.stage_share.size() else 0.0
		result.append(x / sum if sum > 0.0 else 1.0 / 3.0)
	return result
