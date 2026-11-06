class_name CatchGenerator
extends RefCounted
## 生成生物个体，并一次算好它的几种用途（交接文档 §4.3，分开算、不合成一个总分）：
## - 时期和灵魂等级一起定（2026-11-03 定的）：等级跟着时期走（FishData.stage_levels：幼年是最低等级、成年是最高等级、
##   成长期在中间），按钓上来的那层水出几级的生物挑（WaterLayers：浅层只出 1 级，深水大多 2、3 级，渊底大多 4、5 级）
## - 只差一级的种类的成长期两级都有可能：灵魂强度过了门槛（这一种成长期的平均 + growth_up_soul）就是高的那一级
## - 躯体规模（2026-11-04 你定的，原来的重量）：成年期是这一种的那一档（FishData.adult_body），成长期小一档、幼年期再小一档
##   （最小到小型），带「变异」的再大一档；数值在那一档里掷（BalanceConfig.body_lines：小型 0.1–0.5、中型 –2.0、大型 –5.0、
##   巨型 –15.0、畸变 15.0 以上）
## - 灵魂强度（0–100）：按等级和时期，上下浮动；带「魂蕴」再加
## - 能量（2026-11-04，原来的"食后成长"）：这一级的平均能量（BalanceConfig.energy_by_level）上下浮动，再乘词条的倍率；只用来算祭值
## - 词条：普通词条一条最多一个（按权重抽）；特殊词条「变色」「变异」各按自己的机会单独掷
## - 祭值：种类基础值 × 时期系数 × 能量 ÷ 10 × (1.5 + 灵魂强度 × 0.05) × Π(1 + 词条加成)（tribute_of）：只看种族、时期、灵魂强度、能量，
##   躯体规模不算（2026-11-04）
## - 饱腹（生吞时加多少，交接文档里的食粮值）：12 × 躯体规模^0.6，再乘词条（多肉 1.4、枯瘦 0.6）。只看躯体规模，
##   不看等级：巨型的成年个体最顶饿（核心调整 G3，设计对照文档 8.3）
## - 材料：种类的材料总份数 × 总缩放 × 等级 × √个头（比它那一档的平均大多少，不算时期）× 时期的倍率，再按种类的比例和词条分到三类，
##   总数四舍五入（幼年期至少 1 份，成长期、成年期至少 2 份），按零头大小分（新回合机制第 42 条）。一条都拆得出东西；拆了能换回饵、多钓几竿，
##   但全拆也不能稳定地一直钓下去：成年的大个、白鲟、带铁骨 / 血旺 / 磷腺的多几份
## - 载荷：只看时期（幼年 1 / 成长 2 / 成年 3，核心调整第 25 条）
## 全部是静态函数，界面、测试、整局模拟器调用同一套。

const RECOLORED := "recolored"  ## 「变色」：插图转一个色相（CatchData.hue_shift）

## species：种类；rng：随机数（测试和模拟器传固定种子）；config 不传就用 GameDB.balance；
## max_level > 0 时等级最多到这一级（挑得出来的话）；depth：在哪层水钓上来的（按这层水出几级的生物挑时期），
## −1 或者这层水里没有它：不看水层，时期按 stage_share 挑；forced（{stage, level}）：直接定好时期和等级（引深）
static func generate(species: FishData, rng: RandomNumberGenerator, config: BalanceConfig = null, max_level := 0,
		depth := -1, forced := {}) -> CatchData:
	if config == null:
		config = GameDB.balance
	var c := CatchData.new()
	c.species_id = species.id
	var options: Array = WaterLayers.entries(species, depth, config) if depth >= 0 else []
	if not forced.is_empty():
		options = [{"stage": forced.stage, "level": forced.level, "weight": 1.0}]
	if options.is_empty():
		options = WaterLayers.stage_parts(species, config).map(func(p: Dictionary) -> Dictionary:
			return {"stage": p.stage, "level": p.level, "weight": p.part})
	if max_level > 0:
		var capped := options.filter(func(e: Dictionary) -> bool: return e.level <= max_level)
		if not capped.is_empty():
			options = capped
	var pick: Dictionary = options[_roll_index(options.map(func(e: Dictionary) -> float: return e.weight), rng)]
	c.stage = pick.stage as CatchData.Stage
	c.level = pick.level
	var body_u := rng.randf()  ## 躯体规模在那一档里的位置；是哪一档要等词条掷完（「变异」大一档）
	if rng.randf() < config.affix_chance:
		var id := _roll_affix(rng)
		if id != "":
			c.affix_ids = [id]
	for special: AffixData in _specials():
		if rng.randf() < special.chance * config.special_chance_mult * species.special_mult:
			c.affix_ids.append(special.id)
			if special.id == RECOLORED:
				c.hue_shift = rng.randf_range(0.12, 0.88)
			break
	c.body = body_value_at(species, c.stage, c.is_mutated(), BalanceConfig.body_quantile(body_u), config)
	var soul := _roll_soul(species, c, config, rng)
	for id in c.affix_ids:
		var affix := GameDB.get_affix(id)
		if affix:
			soul += affix.soul_bonus
	c.soul_strength = roundi(clampf(soul, 5.0, 100.0))
	c.energy = _roll_energy(c, config, rng)
	evaluate(c, species, config)
	return c


## 能量：这一级的平均能量 × 个体的浮动（正态，夹在 0.6–1.5 倍之间）× 词条的倍率
static func _roll_energy(c: CatchData, config: BalanceConfig, rng: RandomNumberGenerator) -> int:
	var mult := 1.0
	for id in c.affix_ids:
		var affix := GameDB.get_affix(id)
		if affix:
			mult *= affix.energy_mult
	var spread := clampf(rng.randfn(1.0, config.energy_spread), 0.6, 1.5)
	return maxi(1, roundi(config.energy_for(c.level) * spread * mult))


## 引深（奖励卡）：一条 level 级的生物，不看水层——level 级的各个"种类 × 时期"按稀有度、时期的比例，再乘饵的倍率挑一个
## （WaterLayers.stage_parts、BiteCalculator.bait_factor）。一种也没有返回 null
static func generate_at_level(level: int, bait: Bait, rng: RandomNumberGenerator, config: BalanceConfig = null) -> CatchData:
	if config == null:
		config = GameDB.balance
	var options: Array = []
	for fish: FishData in GameDB.sorted_values(GameDB.fish):
		if not fish.appears_in(config):  ## 只在某些夜里出的（阶段 V）
			continue
		var factor := BiteCalculator.bait_factor(fish, bait, config)
		for part in WaterLayers.stage_parts(fish, config):
			if part.level == level:
				options.append({"fish": fish, "stage": part.stage, "level": level, "weight": fish.rarity_weight * part.part * factor})
	if options.is_empty():
		return null
	var pick: Dictionary = options[_roll_index(options.map(func(e: Dictionary) -> float: return e.weight), rng)]
	return generate(pick.fish, rng, config, 0, -1, {"stage": pick.stage, "level": level})


## 进化（奖励卡）：长一个时期，幼年的有 jump 的机会直接长成年；成年的长不了，返回 false。
## 等级跟着时期走（FishData.stage_levels；只差一级的种类的成长期，按灵魂强度过没过门槛定）。
## 躯体规模、灵魂强度按它在原来那个时期里的位置换到新的时期（大个的还是大个，魂浓的还是魂浓）；词条不变，各项用途重算
static func evolve(c: CatchData, rng: RandomNumberGenerator, config: BalanceConfig = null, jump := 0.0) -> bool:
	if config == null:
		config = GameDB.balance
	var species := c.species()
	if species == null or c.stage >= CatchData.Stage.ADULT:
		return false
	var steps := 2 if c.stage == CatchData.Stage.JUVENILE and rng.randf() < jump else 1
	var stage := mini(c.stage + steps, CatchData.Stage.ADULT)
	var bonus := 0.0
	for id in c.affix_ids:
		var affix := GameDB.get_affix(id)
		if affix:
			bonus += affix.soul_bonus
	var raw := c.soul_strength - bonus - _soul_mean(species, c.stage, config) + _soul_mean(species, stage, config)
	var levels := species.stage_levels(stage)
	var level := levels.x
	if levels.y > levels.x and raw >= _soul_mean(species, stage, config) + config.growth_up_soul:
		level = levels.y
	var place := config.body_position(c.body)
	## 能量按它在原来那一级里的位置换到新的一级
	c.energy = maxi(1, roundi(c.energy * config.energy_for(level) / maxf(config.energy_for(c.level), 0.001)))
	c.stage = stage as CatchData.Stage
	c.level = level
	c.body = body_value_at(species, stage, c.is_mutated(), place, config)
	c.soul_strength = roundi(clampf(raw + bonus, 5.0, 100.0))
	evaluate(c, species, config)
	return true


## 这一种这个时期的平均灵魂强度（不算词条）：只差一级的种类的成长期按低的那一级算（_roll_soul 的门槛就从这里量）
static func _soul_mean(species: FishData, stage: int, config: BalanceConfig) -> float:
	var offset: float = BalanceConfig.pick(config.stage_soul_offset, stage, 0.0)
	return config.soul_base + config.soul_per_level * (species.stage_levels(stage).x - 1) + offset


## 灵魂强度：平均是 soul_base + soul_per_level × (等级 − 1) + 时期的偏移，上下浮动 soul_spread。
## 只差一级的种类的成长期：按低的那一级的平均掷，过了门槛（平均 + growth_up_soul）的是高的那一级——挑到哪一级，
## 就只在门槛的那一边掷（钓上来的是几级先按水层定好了）
static func _roll_soul(species: FishData, c: CatchData, config: BalanceConfig, rng: RandomNumberGenerator) -> float:
	var levels := species.stage_levels(c.stage)
	var offset: float = BalanceConfig.pick(config.stage_soul_offset, c.stage, 0.0)
	if levels.x == levels.y:
		return rng.randfn(config.soul_base + config.soul_per_level * (c.level - 1) + offset, config.soul_spread)
	var mean := config.soul_base + config.soul_per_level * (levels.x - 1) + offset
	var line := mean + config.growth_up_soul
	var above := c.level > levels.x
	for i in 64:
		var x := rng.randfn(mean, config.soul_spread)
		if (x >= line) == above:
			return x
	return line + (0.5 if above else -0.5) * config.soul_spread


## 按个体的等级、时期、躯体规模、灵魂强度、能量、词条算各项用途，结果写回 c
static func evaluate(c: CatchData, species: FishData, config: BalanceConfig) -> void:
	var food_mult := 1.0
	var material_mults := {}
	for id in c.affix_ids:
		var affix := GameDB.get_affix(id)
		if affix == null:
			continue
		food_mult *= affix.food_mult
		for m in affix.material_mults:
			material_mults[m] = material_mults.get(m, 1.0) * affix.material_mults[m]

	c.size = c.body / maxf(config.body_mean(config.body_class_of(c.body)), 0.0001)
	c.tribute = tribute_of(c, species, config)
	c.food = config.hunger_for(c.body, food_mult)
	c.load_cost = config.load_for_stage(c.stage)

	## 材料按个头（比它那一档的平均大多少）算，时期另有倍率：档本身不多给，饵料的预算照旧
	var stage_k: float = BalanceConfig.pick(config.stage_yield, c.stage, 1.0)
	var total := species.yield_base * config.yield_scale * (1.0 + config.yield_per_level * (c.level - 1)) * sqrt(c.size) * stage_k
	var ratio_sum := 0.0
	for m in Materials.ALL:
		ratio_sum += maxf(species.material_ratio.get(m, 0.0), 0.0)
	var raw := {}
	var raw_sum := 0.0
	for m in Materials.ALL:
		var share: float = maxf(species.material_ratio.get(m, 0.0), 0.0) / ratio_sum if ratio_sum > 0.0 else 1.0 / Materials.ALL.size()
		raw[m] = total * share * material_mults.get(m, 1.0)
		raw_sum += raw[m]
	c.materials = _split(raw, maxi(BalanceConfig.pick(config.min_materials, c.stage, 1), roundi(raw_sum)))


## 把 n 份分到三类：按 raw 的比例取整，剩下的零头按小数部分从大到小一份一份补（一样大的按 Materials.ALL 的顺序）
static func _split(raw: Dictionary, n: int) -> Dictionary:
	var result := Materials.empty()
	var total := 0.0
	for m in Materials.ALL:
		total += raw.get(m, 0.0)
	if n <= 0 or total <= 0.0:
		return result
	var fractions := []
	var given := 0
	for m in Materials.ALL:
		var x: float = raw.get(m, 0.0) / total * n
		result[m] = floori(x)
		given += result[m]
		fractions.append([x - floorf(x), Materials.ALL.find(m), m])
	fractions.sort_custom(func(a, b) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	for i in n - given:
		result[fractions[i % fractions.size()][2]] += 1
	return result


## 祭值（设计对照文档 8.4；2026-11-04 改）：种类基础值 × 时期系数（stage_tribute）× 能量 ÷ 10
## × (tribute_soul_base + 灵魂强度 × tribute_soul_weight) × Π(1 + 词条加成) × (1 + 恩赐加的 bonus)。等级通过能量算进去，躯体规模不算
static func tribute_of(c: CatchData, species: FishData, config: BalanceConfig) -> int:
	var bonus := 1.0
	for id in c.affix_ids:
		var affix := GameDB.get_affix(id)
		if affix:
			bonus *= 1.0 + affix.tribute_bonus
	var stage_coef: float = BalanceConfig.pick(config.stage_tribute, c.stage, 1.0)
	var soul := config.tribute_soul_base + c.soul_strength * config.tribute_soul_weight
	return maxi(1, roundi(species.tribute_base * stage_coef * c.energy / 10.0 * soul * bonus * (1.0 + c.bonus)))


## 这一种这个时期是哪一档躯体规模：成年期是 adult_body，往前每个时期小一档（最小到小型）；带「变异」的再大一档
static func body_class_for(species: FishData, stage: int, mutated: bool) -> int:
	return mini(species.stage_body(stage) + (1 if mutated else 0), CatchData.BODY_NAMES.size() - 1)


## 这一种这个时期（带不带「变异」）那一档里位置 t 处的躯体规模，取两位小数；落在下限上的往上挪一点（每一档不含下限）
static func body_value_at(species: FishData, stage: int, mutated: bool, t: float, config: BalanceConfig) -> float:
	var cls := body_class_for(species, stage, mutated)
	var v := snappedf(config.body_at(cls, t), 0.01)
	if config.body_class_of(v) < cls:
		v = snappedf(config.body_range(cls).x + 0.01, 0.01)
	return v


## 这一种这个时期中间的那个躯体规模（图鉴的"常见的一条"、测试用；不带「变异」）
static func typical_body(species: FishData, stage: int, config: BalanceConfig) -> float:
	return body_value_at(species, stage, false, 0.5, config)


static func _roll_index(weights, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(w, 0.0)
	var r := rng.randf() * total
	for i in weights.size():
		r -= maxf(weights[i], 0.0)
		if r < 0.0:
			return i
	return maxi(0, weights.size() - 1)


## 普通词条（不含特殊词条）按权重抽一个
static func _roll_affix(rng: RandomNumberGenerator) -> String:
	var list: Array = GameDB.sorted_values(GameDB.affixes).filter(func(a: AffixData) -> bool: return not a.special)
	if list.is_empty():
		return ""
	var weights: Array = list.map(func(a: AffixData) -> float: return a.weight)
	return list[_roll_index(weights, rng)].id


## 特殊词条（变色、变异），按 id 排好
static func _specials() -> Array:
	return GameDB.sorted_values(GameDB.affixes).filter(func(a: AffixData) -> bool: return a.special)
