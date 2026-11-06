class_name Contractor
extends RefCounted
## 一位契约者：能力档、饱腹、船舱里留着的渔获、处理出来的材料、制饵用的附加物、道具，以及契约走到了哪一夜。换人时整个换掉。
## 祂许给这一位的东西（许汝之物，promise）和这份契约的账（献上了多少、剪了几次线、抛了几竿……）也记在这里，
## 契约结束时交给 Settlement 写成结算清单（核心调整 G4）。
## 纯逻辑，不碰节点；界面、测试、整局模拟器用的是同一套。
##
## 契约的一个周期（交接文档 §1.1、§9）：黑夜（begin_night）→ 黄昏供奉（offer）→ 下一夜。
## - 一夜没有钟（新回合机制，设计对照文档第 9 节）：玩家自己决定什么时候唤祂来收供奉
## - 每一夜黄昏要多少祭值提前就知道（demand）。祂不再挑今夜想要什么、也不再赐道具（2026-11-04）
## - 供奉够了过这一夜；最后一夜够了就是契约已偿
## - 不够吃掉一枚烙印，没得吃就死；最后一夜不够，再加一夜补偿周期，需求不涨（设计对照文档第 3 条）
## - 结算了的供奉，只要还有下一夜（够没够都算），发 supply_baits 份万能饵（offer 的结果里的 supply，调用的那边放进饵料篓）
## - 再从几张候选的奖励卡里选一张（RewardCards；take_card）：饱餐、余饵、道具卡马上生效，其余的留到下一夜里触发
##   （card_effects：has_card / use_card），没用掉的到再唤祂（offer）时清掉
##
## 烙印（2026-11-04 和灵魂线并成一样）：供奉不够扣一枚，搏斗里剪线也扣一枚（cut_line）；不会自己长回来，续魂丝补得回一枚。
## 能力档（2026-11-04 去掉了玩家等级，生吞不再升级）：体力、收线这些本事是几档，先跟着夜数走（BalanceConfig.ability_by_night），
## 新的机制接进来再换；搏斗的强弱表按它查。
##
## 一条渔获的三个去向（交接文档 §1.2；放生 2026-11-04 删了）：
## - 留下：放进船舱，按时期占载荷（幼年 1 / 成长 2 / 成年 3），放不下就留不了；船舱的上限是 hold_capacity（20）
## - 生吞：加饱腹；不出材料，也不再长什么
## - 处理：得到三类材料
## 生吞、处理对刚钓上来的和船舱里的都一样；船舱里的会顺手移出去。
##
## 饱腹（核心调整 G3，设计对照文档 8.3）：签约时是满的，跟着捕猎行动往下掉（spend_hunger：每抛一竿、搏斗里耗的体力，
## 新回合机制第 36 条），生吞加回来。饿了体力上限下降，最饿时搏斗里体力还掉得快
## （BalanceConfig 的"饱腹"一组；TensionModel 上钩时按它定这一场的体力）

signal changed  ## 船舱、材料、烙印、道具、第几夜、饱腹任一变化

## 名册上的三种样子：活着（名字燃着蓝火）、死了（灰）、契约已偿（盖上封记）
enum Status { ALIVE, DEAD, REPAID }

var config: BalanceConfig
## 第几位契约者：契约上燃着蓝火的编号 No.0001 就是它
var number := 1
## 签约时写下的名字，中文英文都行；契约上只作为编号旁边的灰色小字
var contractor_name := ""
## 许汝之物：祂答应还给这一位的东西（PromiseData 的 id），换人时随机分到（GameState）
var promise := ""
var status := Status.ALIVE
## 第几夜；过了最后一夜还没偿清的是补偿周期
var night := 1
## 邪神给的烙印：供奉不够、剪线各扣一枚
var brands := 3
## 这份契约里供奉不够了几次：祂发怒的程度跟着一次比一次重（OfferingScreen）
var failed_offerings := 0
## 能力档 1–3：体力、收线这些本事是几档。跟着夜数走（ability_by_night）；ability_override > 0 时固定成它（测试、模拟器测各层水用）
var ability: int:
	get:
		return ability_override if ability_override > 0 else config.ability_for(night)
var ability_override := 0
## 饱腹 0–hunger_max
var hunger := 100.0
var boat_level := 1
var hold: Array[CatchData] = []
var materials: Dictionary = Materials.empty()
## 附加物 id → 个数；基础款用不完，不记在这里
var additives: Dictionary = {}
## 道具 id → 个数
var items: Dictionary = {}
## 奖励卡留到下一夜的效果：效果名（RewardCard.effect）→ {card: RewardCard, left: 还能触发几次，-1 = 一整夜都管}
var card_effects: Dictionary = {}
## 永久恩赐（v0.23，2026-11-04）：效果名（RewardCard.effect）→ {card: RewardCard, used: 这一夜触发了几次}。
## 这份契约剩下的每一夜都管，换人就没了；每一夜的次数在 begin_night 清零
var boons: Dictionary = {}
## 恩赐记着的"下一次"：carcass（拆了一条：这一夜下一条留下的加祭值）、fed（吃了：下一场搏斗好打）、
## blood（吃了：这一夜下一口可能高一级）。carcass、blood 天黑时清掉，fed 留到下一场搏斗
var boon_marks: Dictionary = {}
## 这一夜的海况（v0.23：calm 平静 / rough 躁动 / eerie 异化，BalanceConfig.roll_sea）；签约后的第一夜是平静
var sea := "calm"
var _night_cfg: BalanceConfig
var _night_key := ""
## 今夜的海上事件（阶段 IV，SeaEvents.plan）：{id, at（这一夜第几竿）}；没有、已经碰上了是空
var event_plan: Dictionary = {}
## 这一夜抛了几竿（海上事件按它到第几竿；CastRoll.roll 加）
var night_casts := 0
## 血月（海上事件）：迎着它钓了，这一夜剩下的高的几级更多、钓上来的祭值多一截；天黑时清掉
var blood_moon := false
## 暴雨（海上事件，阶段 V）：冒雨钓了，这一夜剩下的每竿多掉饱腹、分解多出材料；天黑时清掉
var storm := false
## 这份契约碰上过的海上事件：id → 几次（日志、结算用）
var events_seen: Dictionary = {}

## 这份契约的账（结算清单用）
var tribute_total := 0           ## 每个黄昏献上的祭值，加起来
var demand_total := 0            ## 每个黄昏要的祭值，加起来
var cuts := 0                    ## 剪了几次线（每次扣一枚烙印）
var offered_kinds := {}          ## 献上过的"种类 id:时期" → 几条
var best_offering: CatchData     ## 献上过的祭值最高的一条；还没献过是 null
var cards_taken: Array[String] = []  ## 选过的奖励卡 id，按先后
var casts := 0                   ## 一共抛了几竿（CastRoll.roll 每抛一竿加一）


func _init(balance: BalanceConfig = null) -> void:
	config = balance if balance else GameDB.balance
	brands = config.brands
	hunger = config.hunger_max
	for m in config.start_materials:
		materials[m] = materials.get(m, 0) + int(config.start_materials[m])
	for id in config.start_additives:
		additives[id] = int(config.start_additives[id])


## 契约编号："No.0001"
func code() -> String:
	return "No.%04d" % number


## 许汝之物；还没分到（或者 id 不认识）是 null
func promise_data() -> PromiseData:
	return GameDB.get_promise(promise) if promise != "" else null


## 丢了几枚烙印（供奉不够、剪线都算；续魂丝补回来的不算）
func brands_lost() -> int:
	return config.brands - brands


# ---------- 契约周期 ----------

## 这一夜黄昏要多少祭值
func demand() -> int:
	return config.demand_for(night)


## 最后一夜没偿清，加出来的补偿周期
func is_compensation() -> bool:
	return night > config.contract_nights


## 捕猎行动耗掉的饱腹（抛一竿 hunger_per_cast；一场搏斗耗的体力 × hunger_per_stamina），到 0 为止
func spend_hunger(amount: float) -> void:
	hunger = clampf(hunger - amount, 0.0, config.hunger_max)
	changed.emit()


## 天黑，一夜开始。first = 签约后的第一夜（不加夜数，海况是平静）。恩赐每一夜的次数清零；掷今夜的海况（rng 不给就是平静）；
## 异象收藏（恩赐）让船舱里带特殊词条的长一截。返回 {night, ability_up（能力档比上一夜高了）, sea, oddities（异象收藏长了几条）}
func begin_night(rng: RandomNumberGenerator = null, first := false) -> Dictionary:
	var before := ability
	if not first:
		night += 1
	for e in boons:
		boons[e].used = 0
	boon_marks.erase("carcass")
	boon_marks.erase("blood")
	sea = config.roll_sea(rng) if rng != null and not first else "calm"
	night_casts = 0
	blood_moon = false
	storm = false
	event_plan = {} if first else SeaEvents.plan(self, rng)
	var grown := 0 if first else _grow_oddities()
	changed.emit()
	return {"night": night, "ability_up": not first and ability > before, "sea": sea, "oddities": grown}


## 异象收藏（恩赐）带着的时候，特殊词条的机会再乘几
const ODDITY_SPECIAL := 1.5


## 这一夜生物怎么出的那一份数值表：总表按第几夜（冥海侵蚀）和海况改过（BalanceConfig.for_night），按夜缓存。
## 抛竿、搏斗用它；图鉴、供奉、饱腹还用 config
func night_config() -> BalanceConfig:
	var oddity := has_boon("oddity")
	var key := "%d:%s:%s:%s" % [night, sea, blood_moon, oddity]
	if _night_cfg == null or _night_key != key:
		_night_cfg = config.for_night(night, sea, blood_moon)
		if oddity:  ## 异象收藏（恩赐）：特殊词条多出五成
			_night_cfg.special_chance_mult *= ODDITY_SPECIAL
		_night_key = key
	return _night_cfg


## 船舱里一共多少祭值
func hold_tribute() -> int:
	var total := 0
	for c in hold:
		total += c.tribute
	return total


## 献上这几条值多少：{base: 祭值加起来, kin: 同族之献, crown: 渔获加冕, hungry: 空腹之献（恩赐多出来的）, total}。同族之献：同一种族每凑满两条
## （祭值高的先配），这两条加 amount，一夜最多加献上总数的 cap
func offer_value(offered: Array) -> Dictionary:
	var base := 0
	for c: CatchData in offered:
		base += c.tribute
	var kin := 0
	if has_boon("kin"):
		var by_species := {}
		for c: CatchData in offered:
			by_species[c.species_id] = by_species.get(c.species_id, []) + [c]
		var paired := 0
		for id in by_species:
			var list: Array = by_species[id]
			list.sort_custom(func(a: CatchData, b: CatchData) -> bool: return a.tribute > b.tribute)
			for i in (list.size() / 2) * 2:
				paired += list[i].tribute
		kin = mini(roundi(paired * boon_amount("kin")), roundi(base * boon_cap("kin")))
	var crown := 0
	if has_boon("crown_catch"):  ## 渔获加冕：献上的最值钱的一条再加一截
		var top := 0
		for c: CatchData in offered:
			top = maxi(top, c.tribute)
		crown = roundi(top * boon_amount("crown_catch"))
	var hungry := 0
	if has_boon("hungry_offer") and hunger < boon_cap("hungry_offer"):  ## 空腹之献：饿着献，祂更满意
		hungry = roundi(base * boon_amount("hungry_offer"))
	return {"base": base, "kin": kin, "crown": crown, "hungry": hungry, "total": base + kin + crown + hungry}


## 超额线是需求的几倍：平常 over_ratio（1.5），带着满溢之献（恩赐）是它的 amount
func over_ratio() -> float:
	return boon_amount("overflow") if has_boon("overflow") else config.over_ratio


## 黄昏供奉（交接文档 §9.1）：offered 是从船舱里挑出来献上的渔获，献上的从船舱里拿走；按祭值算够不够（核心调整 G2）。
## 返回 {tribute（含同族之献）, kin, demand, met, over（到了超额线）, brand_lost, died, repaid,
## supply（下一夜的补给：几份万能饵；偿清了、死了是 0；满溢之献超额时多给）}
func offer(offered: Array, _rng: RandomNumberGenerator = null) -> Dictionary:
	card_effects.clear()  ## 上一张奖励卡没用掉的，到再唤祂时清掉
	var value := offer_value(offered)
	var tribute: int = value.total
	for c: CatchData in offered:
		hold.erase(c)
		var kind := "%s:%d" % [c.species_id, c.stage]
		offered_kinds[kind] = offered_kinds.get(kind, 0) + 1
		if best_offering == null or c.tribute > best_offering.tribute:
			best_offering = c
	var need := demand()
	tribute_total += tribute
	demand_total += need
	var result := {"tribute": tribute, "kin": value.kin, "crown": value.crown, "hungry": value.hungry, "demand": need, "met": tribute >= need,
		"over": tribute >= need and tribute >= need * over_ratio(), "brand_lost": false, "died": false, "repaid": false, "supply": 0}
	if result.met:
		if night >= config.contract_nights:
			status = Status.REPAID
			result.repaid = true
	elif brands > 0:
		failed_offerings += 1
		brands -= 1
		result.brand_lost = true
	else:
		failed_offerings += 1
		status = Status.DEAD
		result.died = true
	result.supply = 0 if result.repaid or result.died else config.supply_baits
	if result.supply > 0 and result.over and has_boon("overflow"):
		result.supply += roundi(boon_cap("overflow"))
	changed.emit()
	return result


# ---------- 烙印和道具 ----------

## 剪线：扣一枚烙印（2026-11-04 起剪线不再用灵魂线）；烙印没了剪不了，返回 false
func cut_line() -> bool:
	if brands <= 0:
		return false
	brands -= 1
	cuts += 1
	changed.emit()
	return true


## 补回一枚烙印（续魂丝），满了补不了
func restore_brand() -> bool:
	if brands >= config.brands:
		return false
	brands += 1
	changed.emit()
	return true


func add_item(id: String, n := 1) -> void:
	items[id] = items.get(id, 0) + n
	changed.emit()


## 用掉一个；没有返回 false
func use_item(id: String) -> bool:
	if items.get(id, 0) <= 0:
		return false
	items[id] -= 1
	if items[id] <= 0:
		items.erase(id)
	changed.emit()
	return true


## 捞上来一件东西：道具进道具栏，附加物进附加物
func add_salvage(id: String) -> void:
	if GameDB.get_additive(id):
		additives[id] = additives.get(id, 0) + 1
		changed.emit()
	else:
		add_item(id)


# ---------- 奖励卡 ----------

## 选了一张奖励卡（RewardCards）：饱餐、余饵、道具卡马上生效，其余的留到下一夜里触发。
## 返回 {baits: 要加几份万能饵}（余饵；调用的那边放进饵料篓，和 offer 的 supply 一样）
func take_card(card: RewardCard) -> Dictionary:
	cards_taken.append(card.id)
	var result := {"baits": 0}
	if card.permanent:
		boons[card.effect] = {"card": card, "used": 0}
		changed.emit()
		return result
	match card.effect:
		"feast":
			hunger = minf(config.hunger_max, hunger + card.amount)
		"spare_bait":
			result.baits = roundi(card.amount)
		"item":
			items[card.item_id] = items.get(card.item_id, 0) + roundi(card.amount)
		_:
			card_effects[card.effect] = {"card": card, "left": card.uses if card.uses > 0 else -1}
	changed.emit()
	return result


## 下一夜里还有没有这种卡的效果
func has_card(effect: String) -> bool:
	return card_effects.has(effect)


## 这种卡的数值（RewardCard.amount）；没有这种卡是 0
func card_amount(effect: String) -> float:
	return card_effects[effect].card.amount if card_effects.has(effect) else 0.0


## 触发一次这种卡（一整夜都管的不扣次数）；没有返回 false
func use_card(effect: String) -> bool:
	if not card_effects.has(effect):
		return false
	var e: Dictionary = card_effects[effect]
	if e.left > 0:
		e.left -= 1
		if e.left == 0:
			card_effects.erase(effect)
	changed.emit()
	return true


## 进化：钓上来的这一条长一个时期（CatchGenerator.evolve）。成年的不算，留给下一条。2026-11-04 起是永久恩赐（每夜一次），
## 旧的一夜卡也还认。长了返回 {from: 原来的时期, to: 现在的时期}，没长返回空
func evolve_catch(c: CatchData, rng: RandomNumberGenerator) -> Dictionary:
	if c == null:
		return {}
	var from_card := has_card("evolve")
	if not from_card and not boon_ready("evolve"):
		return {}
	var before := c.stage
	if not CatchGenerator.evolve(c, rng, config, card_amount("evolve") if from_card else boon_amount("evolve")):
		return {}
	if from_card:
		use_card("evolve")
	else:
		use_boon("evolve")
	return {"from": before, "to": c.stage}


# ---------- 永久恩赐（v0.23） ----------

func has_boon(effect: String) -> bool:
	return boons.has(effect)


## 这张恩赐的数值（RewardCard.amount）；没有是 0
func boon_amount(effect: String) -> float:
	return boons[effect].card.amount if boons.has(effect) else 0.0


## 这张恩赐的上限 / 附带的数（RewardCard.cap）；没有是 0
func boon_cap(effect: String) -> float:
	return boons[effect].card.cap if boons.has(effect) else 0.0


## 这一夜还能不能触发（每夜的次数没用完；uses 0 是不限）
func boon_ready(effect: String) -> bool:
	if not boons.has(effect):
		return false
	var e: Dictionary = boons[effect]
	return e.card.uses <= 0 or e.used < e.card.uses


## 触发一次（记这一夜的次数）
func use_boon(effect: String) -> void:
	if boons.has(effect):
		boons[effect].used += 1
		changed.emit()


## 下一场搏斗按低几级算（骨笛记着的；consume：开打了，用掉）
func fight_steady(consume := false) -> int:
	if not boon_marks.get("flute", false):
		return 0
	if consume:
		boon_marks.erase("flute")
	return 1


## 残躯为饵（恩赐）记着呢：这一夜下一条留下的加祭值
func carcass_ready() -> bool:
	return boon_marks.get("carcass", false) and boon_ready("carcass")


## 这一场搏斗体力多撑多少（TensionModel 的 vigor：消耗 ÷ (1 + vigor)）：壮魂（一夜卡）、韧线（恩赐，一直管）、
## 饱食之勇（恩赐，吃了以后的下一场）、深渊行者（恩赐，在比能力档深的水里，depth 是第几层水）叠在一起是消耗相乘。
## consume：开打了，用掉饱食之勇
func fight_vigor(consume := false, depth := -1) -> float:
	var drain := 1.0 / (1.0 + card_amount("vigor"))
	if has_boon("taut_line"):
		drain *= 1.0 - boon_amount("taut_line")
	if has_boon("abyss_walker") and depth > ability - 1:
		drain *= 1.0 - boon_amount("abyss_walker")
	if boon_marks.get("fed", false):
		drain *= 1.0 - boon_amount("fed_courage")
		if consume:
			boon_marks.erase("fed")
	return 1.0 / maxf(drain, 0.05) - 1.0


## 异象收藏（恩赐）：船舱里带特殊词条的，过一夜祭值多一截（最多到上限）。返回长了几条
func _grow_oddities() -> int:
	if not has_boon("oddity"):
		return 0
	var n := 0
	for c in hold:
		var odd := c.affix_ids.any(func(id: String) -> bool:
			var affix := GameDB.get_affix(id)
			return affix != null and affix.special)
		if odd and c.bonus < boon_cap("oddity") and c.species():
			c.bonus = minf(boon_cap("oddity"), c.bonus + boon_amount("oddity"))
			c.tribute = CatchGenerator.tribute_of(c, c.species(), config)
			n += 1
	return n


# ---------- 饵料 ----------

## 还有几个这种附加物；用不完的返回 -1
func additive_count(id: String) -> int:
	var a := GameDB.get_additive(id)
	if a and a.unlimited:
		return -1
	return additives.get(id, 0)


## 做一份饵的材料够不够：bases 是两份基础材料的 id（可以重复）
func can_afford(bases: Array, additive_id: String) -> bool:
	var need := {}
	for m in bases:
		need[m] = need.get(m, 0) + 1
	for m in need:
		if materials.get(m, 0) < need[m]:
			return false
	var left := additive_count(additive_id)
	return left < 0 or left >= 1


## 扣掉做一份饵的材料（先用 can_afford 查过）
func spend(bases: Array, additive_id: String) -> void:
	for m in bases:
		materials[m] = maxi(0, materials.get(m, 0) - 1)
	if additive_count(additive_id) > 0:
		additives[additive_id] -= 1
	changed.emit()


# ---------- 船舱和三个去向 ----------

## 船舱的载荷上限（2026-11-04 起一样大：20）
func hold_capacity() -> int:
	return config.hold_capacity


func hold_load() -> int:
	var total := 0
	for c in hold:
		total += c.load_cost
	return total


func free_load() -> int:
	return hold_capacity() - hold_load()


func can_keep(c: CatchData) -> bool:
	return not hold.has(c) and c.load_cost <= free_load()


## 放进船舱；放不下返回 false，什么也不变。残躯为饵（恩赐）记着的话，这一条祭值多一截
func keep(c: CatchData) -> bool:
	if not can_keep(c):
		return false
	hold.append(c)
	if carcass_ready() and c.species():
		boon_marks.erase("carcass")
		use_boon("carcass")
		c.bonus += boon_amount("carcass")
		c.tribute = CatchGenerator.tribute_of(c, c.species(), config)
	changed.emit()
	return true


## 饿的档：0 不饿，1 饿了，2 饿得发慌
func hunger_tier() -> int:
	return config.hunger_tier(hunger)


## 现在的体力上限是满的几成
func stamina_cap() -> float:
	return config.stamina_cap(hunger)


## 现在生吞 c 能得到什么：{food: 加上的饱腹, overflow: 装不下、白吃的饱腹}
func eat_gain(c: CatchData) -> Dictionary:
	var room := maxf(config.hunger_max - hunger, 0.0)
	var fit := minf(float(c.food), room)
	return {"food": fit, "overflow": float(c.food) - fit}


## 生吞：加饱腹（装不下的白吃）。饱食之勇、血诱（恩赐）记下"下一次"
func eat(c: CatchData) -> void:
	var gain := eat_gain(c)
	hold.erase(c)
	hunger = minf(config.hunger_max, hunger + gain.food)
	if has_boon("fed_courage"):
		boon_marks["fed"] = true
	if boon_ready("blood_lure"):
		boon_marks["blood"] = true
	changed.emit()


## 现在处理 c 能拿到几份材料（材料id → 份数）：剖腹（一夜卡）还在的话翻倍；剔骨（恩赐）这一夜还有次数的话，
## 多 amount 份它身上最多的那种（一样多的按血肉、矿壳、幽光的顺序）
func dismantle_yield(c: CatchData) -> Dictionary:
	var got: Dictionary = c.materials.duplicate()
	if has_card("dissect"):
		for m in got:
			got[m] = roundi(got[m] * card_amount("dissect"))
	var extra := 0
	if boon_ready("bone_pick"):
		extra += roundi(boon_amount("bone_pick"))
	if storm:  ## 暴雨（海上事件）：鱼被雨打得发软，好拆
		extra += config.storm_materials
	if extra > 0:
		var most: String = Materials.ALL[0]
		for m in Materials.ALL:
			if got.get(m, 0) > got.get(most, 0):
				most = m
		got[most] = got.get(most, 0) + extra
	return got


## 抛一竿掉多少饱腹：平常 hunger_per_cast，暴雨（海上事件）里再多 storm_hunger
func cast_hunger() -> float:
	return config.hunger_per_cast + (config.storm_hunger if storm else 0.0)


## 处理，返回拿到的材料（材料id → 份数）。残躯为饵（恩赐）记下：这一夜下一条留下的加祭值
func dismantle(c: CatchData) -> Dictionary:
	var got := dismantle_yield(c)
	use_card("dissect")
	if boon_ready("bone_pick"):
		use_boon("bone_pick")
	if has_boon("carcass"):
		boon_marks["carcass"] = true
	if c.stage == CatchData.Stage.ADULT and boon_ready("bone_flute"):  ## 骨笛：拆了一条成年的，下一场按低一级算
		use_boon("bone_flute")
		boon_marks["flute"] = true
	hold.erase(c)
	for m in got:
		materials[m] = materials.get(m, 0) + got[m]
	changed.emit()
	return got
