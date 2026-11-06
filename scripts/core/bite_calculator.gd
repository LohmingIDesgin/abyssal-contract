class_name BiteCalculator
extends RefCounted
## 上钩表：这一竿可能咬钩的是什么、各多大概率（交接文档 §5.2）。只算这个水层里有的生物：
## 每种生物先按这层水出几级的生物、它哪个时期是几级定一个份额（WaterLayers.presence，稀有度算在里面），再乘饵的倍率（bait_factor）。
## 做的饵：倍率 = 吻合度^bait_match_power × e^(附加物的强度 × 它对附加物气味的偏好)：
## - 吻合度：饵的基础材料占比和它的材料比例逐项相乘再相加（0~1）。矿壳饵招壳多的东西，处理出来的矿壳也多
## - 附加物带一种气味，喜欢的被推上来、讨厌的被拉开；基础款不带气味
## 万能饵：倍率都是 1（这层水里本来的样子，不偏向哪一种；新回合机制第 33 条）。
## "什么也没咬"（第 32 条）单独定，不再和生物的权重放在一起抽：万能饵固定 universal_nothing；做的饵是 nothing_chance，
## 这层水里最合它的那种生物也不太合时再往上加，最多加 mismatch_nothing（合的程度见 suitability）。
## 空竿不扣饵，但白等一回、照样扣饱腹，所以对路的饵不该空得比万能饵多。没有空钩了（第 31 条）：bait 是 null 时按万能饵算。


## 返回按概率降序排列的 [{ "fish": FishData 或 null（什么也没咬）, "chance": float }]
static func bite_table(bait: Bait, depth: int, config: BalanceConfig = null) -> Array[Dictionary]:
	if config == null:
		config = GameDB.balance
	var entries: Array[Dictionary] = []
	var total := 0.0
	var suit := 0.0
	for fish: FishData in GameDB.sorted_values(GameDB.fish):
		var w := WaterLayers.presence(fish, depth, config) * bait_factor(fish, bait, config)
		if w <= 0.0:
			continue
		entries.append({"fish": fish, "chance": w})
		total += w
		suit = maxf(suit, suitability(fish, bait))
	var nothing := nothing_chance(bait, suit, config) if total > 0.0 else 1.0
	for e in entries:
		e.chance = e.chance / total * (1.0 - nothing)
	entries.append({"fish": null, "chance": nothing})
	entries.sort_custom(func(a, b): return a.chance > b.chance)
	return entries


## 这份饵合这种生物的程度 0~1：吻合度 ÷ 它最多的那类材料的比例（全是那一类材料的饵合它的程度就是 1）。万能饵算 1
static func suitability(fish: FishData, bait: Bait) -> float:
	if bait == null or bait.universal:
		return 1.0
	var share := bait.base_share()
	var ratio := Materials.normalized(fish.material_ratio)
	var fit := 0.0
	var best := 0.0
	for m in Materials.ALL:
		fit += share.get(m, 0.0) * ratio.get(m, 0.0)
		best = maxf(best, ratio.get(m, 0.0))
	return clampf(fit / maxf(best, 0.001), 0.0, 1.0)


## "什么也没咬"的机会：万能饵固定；做的饵看这层水里最合它的那种生物（suit），越不合空得越多
static func nothing_chance(bait: Bait, suit: float, config: BalanceConfig) -> float:
	if bait == null or bait.universal:
		return config.universal_nothing
	return clampf(config.nothing_chance + config.mismatch_nothing * (1.0 - suit), 0.0, 1.0)


## 这份饵把一种生物往上推多少（倍率，不含"什么也没咬"，也不看水层）；万能饵是 1
static func bait_factor(fish: FishData, bait: Bait, config: BalanceConfig) -> float:
	if bait == null or bait.universal:
		return 1.0
	var share := bait.base_share()
	var ratio := Materials.normalized(fish.material_ratio)
	var fit := 0.0
	for m in Materials.ALL:
		fit += share.get(m, 0.0) * ratio.get(m, 0.0)
	var w := pow(fit, config.bait_match_power)
	var additive := bait.additive()
	if additive and additive.aspect != "":
		w *= exp(additive.strength * fish.preference(additive.aspect))
	return w


## 按概率表随机抽一个结果，返回 FishData 或 null（什么也没咬）
static func roll(table: Array[Dictionary], rng: RandomNumberGenerator = null) -> FishData:
	var r := rng.randf() if rng else randf()
	for e in table:
		r -= e.chance
		if r <= 0.0:
			return e.fish
	return null
