class_name Codex
extends RefCounted
## 图鉴的数据（交接文档 §11：邪神、渔获生物、道具三类，已确认；先做渔获生物，界面是 CodexScreen，C 键）。
## 只读 data/ 和数值总表，什么都不存：改了生物的 .tres 或 data/balance.tres，图鉴跟着变。
## - 等级跟着时期走（FishData.stage_levels，2026-11-03 定的）：幼年期是最低等级、成年期是最高等级、成长期在中间；
##   只差一级的种类的成长期两级都有可能（灵魂强度过了门槛的是高的那一级）
## - 一层水里出什么：按这层水出几级的生物挑（WaterLayers；浅层只出 1 级，深水大多 2、3 级，渊底大多 4、5 级）
## - 常见的一条（typical）：躯体规模在这个时期那一档的中间、这一级这一时期的平均灵魂强度（成长期分两级时，是门槛那一边的平均）、
##   这一级的平均能量、没有词条。祭值是灵魂强度和能量的一次式，所以这一条的祭值就是平均数（不算词条：带词条的平均多 4–5%）。
##   处理材料要取整份、又跟着个头的平方根走，平均数按躯体规模的分布取几个分位算（cell_materials），图鉴的格子里写最小到最大的那几份
## - 上钩：万能饵下咬钩的里面它占几成（这层水本来的样子），以及哪一份饵最招它（六种基础组合 × 各种附加物里它占得最多的）
## 测试期间全开（reveal_all，用户 2026-11-03）：没钓上来过的也全显示。关掉以后按 GameState.catches 解锁，
## 没钓上来过的只剩剪影（GameState.catches 还不存盘，关了游戏就没了）。

## 测试期间图鉴全开：没钓上来过的种类也显示全部内容。导出的试玩版（导出预设带 "demo" 这个特性，export_presets.cfg）不全开：
## 钓上来过的才收录，跟正式玩的时候一样
static var reveal_all := not OS.has_feature("demo")

const BODY_STEPS := 16


## 图鉴里的顺序：从弱到强（先按最低等级，再按最高等级）：灰鲦、血齿冥鲳、磷灯婆、盲眼噬骸鳗、溺者之手、千目窥渊鲶、渡魂白鲟
static func species_order() -> Array:
	var list: Array = GameDB.fish.values()
	list.sort_custom(func(a: FishData, b: FishData) -> bool:
		return [a.level_min, a.level_max, a.id] < [b.level_min, b.level_max, b.id])
	return list


## 收录了没有：测试期间全开；以后是钓上来过的
static func known(fish: FishData) -> bool:
	return reveal_all or GameState.catches.has(fish.id)


static func known_count() -> int:
	return species_order().filter(func(f: FishData) -> bool: return known(f)).size()


## 它出没的几层水（下标，GameDB.DEPTH_NAMES）
static func depths(fish: FishData, config: BalanceConfig = null) -> Array[int]:
	return WaterLayers.depths_of(fish, config if config else GameDB.balance)


## "浅层 · 深水"
static func depth_text(fish: FishData, config: BalanceConfig = null) -> String:
	var names: PackedStringArray = []
	for d in depths(fish, config):
		names.append(GameDB.DEPTH_NAMES[d])
	return " · ".join(names)


## "1–3 级" / "1 级"
static func level_text(fish: FishData) -> String:
	if fish.level_min == fish.level_max:
		return "%d 级" % fish.level_min
	return "%d–%d 级" % [fish.level_min, fish.level_max]


## 这个时期是几级："2 级" / "1–2 级"（只差一级的种类的成长期）
static func stage_level_text(fish: FishData, stage: int) -> String:
	var levels := fish.stage_levels(stage)
	return "%d 级" % levels.x if levels.x == levels.y else "%d–%d 级" % [levels.x, levels.y]


## 成长期分两级时，灵魂强度的门槛（这一种成长期的平均 + growth_up_soul）；不分两级的是 -1
static func growth_line(fish: FishData, config: BalanceConfig) -> float:
	var levels := fish.stage_levels(CatchData.Stage.GROWING)
	if levels.x == levels.y:
		return -1.0
	return config.soul_base + config.soul_per_level * (levels.x - 1) \
		+ BalanceConfig.pick(config.stage_soul_offset, CatchData.Stage.GROWING, 0.0) + config.growth_up_soul


## 这一种在第 depth 层水里钓上来是什么：[{stage, level, share}]，share 是在它里面占几成（加起来是 1）；这层水里没有它是空的
static func stage_entries(fish: FishData, depth: int, config: BalanceConfig) -> Array[Dictionary]:
	var entries := WaterLayers.entries(fish, depth, config)
	var total := 0.0
	for e in entries:
		total += e.weight
	var result: Array[Dictionary] = []
	for e in entries:
		result.append({"stage": e.stage, "level": e.level, "share": e.weight / total if total > 0.0 else 0.0})
	return result


## 常见的一条：躯体规模在那一档的中间、这一级这一时期的平均灵魂强度、没有词条；各项用途照常算好（CatchGenerator.evaluate）。
## 成长期分两级的，灵魂强度取门槛那一边的平均（截断正态分布的均值）
static func typical(fish: FishData, level: int, stage: int, config: BalanceConfig) -> CatchData:
	var c := CatchData.new()
	c.species_id = fish.id
	c.level = level
	c.stage = stage as CatchData.Stage
	c.body = CatchGenerator.typical_body(fish, stage, config)
	c.soul_strength = roundi(clampf(mean_soul(fish, level, stage, config), 5.0, 100.0))
	c.energy = roundi(config.energy_for(level))
	CatchGenerator.evaluate(c, fish, config)
	return c


## 这一级、这一时期的平均灵魂强度（和 CatchGenerator._roll_soul 一样掷）
static func mean_soul(fish: FishData, level: int, stage: int, config: BalanceConfig) -> float:
	var levels := fish.stage_levels(stage)
	var offset: float = BalanceConfig.pick(config.stage_soul_offset, stage, 0.0)
	if levels.x == levels.y:
		return config.soul_base + config.soul_per_level * (level - 1) + offset
	var mean := config.soul_base + config.soul_per_level * (levels.x - 1) + offset
	var sd := maxf(config.soul_spread, 0.001)
	var z := config.growth_up_soul / sd
	var pdf := exp(-0.5 * z * z) / sqrt(TAU)
	var below := BalanceConfig.normal_cdf(z)
	if level > levels.x:
		return mean + sd * pdf / maxf(1.0 - below, 0.0001)
	return mean - sd * pdf / maxf(below, 0.0001)


## 在第 depth 层钓上来的平均祭值（按这层水里它各个时期、各级的机会，常见的那一条；不算词条）
static func mean_tribute(fish: FishData, depth: int, config: BalanceConfig) -> float:
	var total := 0.0
	for e in stage_entries(fish, depth, config):
		total += e.share * typical(fish, e.level, e.stage, config).tribute
	return total


## 平均处理出来的材料 {flesh, shell, glow}（份，按这层水里它各个时期、各级的机会，没有词条）
static func mean_materials(fish: FishData, depth: int, config: BalanceConfig) -> Dictionary:
	var result := Materials.empty_ratio()
	for e in stage_entries(fish, depth, config):
		var cell := cell_materials(fish, e.level, e.stage, config)
		for m in Materials.ALL:
			result[m] += e.share * cell[m]
	return result


## 这一级、这一时期平均处理出的材料 {flesh, shell, glow}（没有词条）。份数要取整、又跟着个头的平方根走，
## 不能只看中间的那一条：躯体规模按生成时的分布取 BODY_STEPS 个分位平均
static func cell_materials(fish: FishData, level: int, stage: int, config: BalanceConfig) -> Dictionary:
	var result := Materials.empty_ratio()
	for u in _body_quantiles():
		var c := _at_quantile(fish, level, stage, u, config)
		for m in Materials.ALL:
			result[m] += c.materials.get(m, 0) / float(BODY_STEPS)
	return result


## 这一级、这一时期处理出来最少、最多几份（躯体规模最小的和最大的；没有词条）
static func materials_range(fish: FishData, level: int, stage: int, config: BalanceConfig) -> Vector2i:
	var low := 0
	var high := 0
	for m in Materials.ALL:
		low += _at_quantile(fish, level, stage, 0.0, config).materials.get(m, 0)
		high += _at_quantile(fish, level, stage, 1.0, config).materials.get(m, 0)
	return Vector2i(low, high)


static func _body_quantiles() -> Array[float]:
	var result: Array[float] = []
	for k in BODY_STEPS:
		result.append((k + 0.5) / BODY_STEPS)
	return result


## 常见的那一条，只是躯体规模换成分布里第 u 分位的（0 最小、1 最大：和 CatchGenerator.generate 一样按 body_quantile 掷）
static func _at_quantile(fish: FishData, level: int, stage: int, u: float, config: BalanceConfig) -> CatchData:
	var c := typical(fish, level, stage, config)
	c.body = CatchGenerator.body_value_at(fish, stage, false, BalanceConfig.body_quantile(u), config)
	CatchGenerator.evaluate(c, fish, config)
	return c


## 挂这份饵在第 depth 层，咬钩的里面它占几成（"什么也没咬"不算：不扣饵）；这层水里没有它是 0
static func bite_share(fish: FishData, bait: Bait, depth: int, config: BalanceConfig) -> float:
	var table := BiteCalculator.bite_table(bait, depth, config)
	var nothing := 0.0
	var mine := 0.0
	for e in table:
		if e.fish == null:
			nothing = e.chance
		elif e.fish == fish:
			mine = e.chance
	return mine / (1.0 - nothing) if nothing < 1.0 else 0.0


## 能挂的饵：万能饵，加上六种基础组合 × 每种附加物（按附加物 id、基础组合排好）
static func all_baits(config: BalanceConfig) -> Array[Bait]:
	var baits: Array[Bait] = [BaitCrafter.make_universal(1)]
	var combos := []
	for i in Materials.ALL.size():
		for j in range(i, Materials.ALL.size()):
			combos.append([Materials.ALL[i], Materials.ALL[j]])
	for additive: AdditiveData in GameDB.sorted_values(GameDB.additives):
		for bases in combos:
			baits.append(BaitCrafter.make(bases, additive.id, config))
	return baits


## 在第 depth 层最招它的饵：{bait, share, nothing}（咬钩的里面它占得最多的那一份，一样多时取靠前的；
## nothing 是挂这份饵什么也没咬的机会：不扣饵，但白等一回、照样扣饱腹）
static func best_bait(fish: FishData, depth: int, config: BalanceConfig) -> Dictionary:
	var best := {"bait": null, "share": -1.0, "nothing": 0.0}
	for bait in all_baits(config):
		var share := bite_share(fish, bait, depth, config)
		if share > best.share + 0.0001:
			best = {"bait": bait, "share": share, "nothing": nothing_chance(bait, depth, config)}
	return best


## 挂这份饵在第 depth 层，什么也没咬的机会
static func nothing_chance(bait: Bait, depth: int, config: BalanceConfig) -> float:
	for e in BiteCalculator.bite_table(bait, depth, config):
		if e.fish == null:
			return e.chance
	return 0.0


## 一层水的概况（挂万能饵）：{species: [{fish, share, entries（stage_entries）, tribute（平均祭值）}]（按占的多少排），
## levels（1–5 级各占几成，WaterLayers.level_shares）, stages（幼年、成长、成年各占几成）, nothing（什么也没咬的机会）,
## salvage（捞到东西的机会）, tribute（每咬一口的平均祭值）, materials（每咬一口平均处理出的材料 {flesh, shell, glow}）}
static func layer(depth: int, config: BalanceConfig) -> Dictionary:
	var universal := BaitCrafter.make_universal(1)
	var table := BiteCalculator.bite_table(universal, depth, config)
	var nothing := 0.0
	for e in table:
		if e.fish == null:
			nothing = e.chance
	var rows: Array[Dictionary] = []
	var tribute := 0.0
	var mats := Materials.empty_ratio()
	var stages: Array[float] = [0.0, 0.0, 0.0]
	for e in table:
		if e.fish == null:
			continue
		var share: float = e.chance / (1.0 - nothing) if nothing < 1.0 else 0.0
		var entries := stage_entries(e.fish, depth, config)
		for x in entries:
			stages[x.stage] += share * x.share
		var mean := mean_tribute(e.fish, depth, config)
		rows.append({"fish": e.fish, "share": share, "entries": entries, "tribute": mean})
		tribute += share * mean
		var m := mean_materials(e.fish, depth, config)
		for id in Materials.ALL:
			mats[id] += share * m[id]
	return {"species": rows, "levels": WaterLayers.level_shares(depth, config), "stages": stages, "nothing": nothing,
		"salvage": config.salvage_chance, "tribute": tribute, "materials": mats}


## 偏好写成几段：[[气味id, 偏好], ……]，喜欢的在前（从大到小），讨厌的在后
static func preferences(fish: FishData) -> Array:
	var likes := []
	var dislikes := []
	for aspect in Aspect.ALL:
		var v := fish.preference(aspect)
		if v > 0.0:
			likes.append([aspect, v])
		elif v < 0.0:
			dislikes.append([aspect, v])
	likes.sort_custom(func(a, b) -> bool: return a[1] > b[1])
	dislikes.sort_custom(func(a, b) -> bool: return a[1] < b[1])
	return likes + dislikes


## 带这种气味的附加物（没有就是 null：这种气味现在还招不来）
static func additive_for(aspect: String) -> AdditiveData:
	for a: AdditiveData in GameDB.sorted_values(GameDB.additives):
		if a.aspect == aspect:
			return a
	return null
