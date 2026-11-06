class_name Settlement
extends RefCounted
## 契约结算清单（核心调整 G4，设计对照文档 8.5）：一位契约者走了（偿清、落水、被吞），把这份契约的账写成一条记录。
## 记录是能直接存进名册（user://roster.json）的字典；结算的帷幕（SettlementScreen）、名册、试玩日志、整局模拟器用的都是它：
##   {number, name, promise, night, status（"repaid" / "dead"）, cause（"repaid" / "fall" / "offering"）,
##    tribute（献上的祭值加起来）, demand（要的加起来）, brands_lost（供奉不够、剪线都算）, cuts（剪了几次线）, kinds（"种类:时期"）,
##    best（最珍贵的一件：species, stage, level, tribute, body（躯体规模，2026-11-04 以前是 weight 公斤）, affixes, hue_shift；没献过是空字典）, ability（最后是几档能力）, rating,
##    casts（一共抛了几竿）, cards（选过的奖励卡 id，按先后）}
## G4 以前的名册条目只有 number、name、night、status、cause；H3 以前的没有 casts、cards；2026-11-04 以前的还有 wishes、gifts、
## soul_level（合心意、祂赐下的道具、灵魂等级，这些机制删了，结算清单不再写）。
##
## 评价（第 28 条）：偿清了的分四档，看两样：献上的祭值是要的多少倍、丢了几枚烙印（剪线扣的也算）。祂不再挑想要的，合心意不算了
## （2026-11-04）。阈值按整局模拟器定，见 docs/测量与预算.md。死了的不评：被吞写"背约"，落水写"殒于冥海"。回报（插图、称号）以后再加。

const RATINGS: Array[String] = ["勉强", "守约", "虔诚", "献心"]
const BROKEN := "背约"        ## 供奉不够，被祂吞了
const DROWNED := "殒于冥海"   ## 硬撑输了，落水
## 阈值按整局模拟器定（见 docs/测量与预算.md"评价的阈值"）。祂不再挑想要的以后只看献上的倍数和丢的烙印
## 虔诚：一枚烙印也没丢，献上的有要的 PIOUS_RATIO 倍
const PIOUS_RATIO := 1.45
## 献心：一枚烙印也没丢，献上的有要的 DEVOTED_RATIO 倍
const DEVOTED_RATIO := 1.7
## 守约：最多丢了这么多枚烙印（剪线扣的也算）；再多就是勉强。2026-11-04 剪线也扣烙印以后从 1 改成 2：
## 达标就收·普通大约 4% 献心、23% 虔诚、61% 守约、8% 勉强（只按 1 枚算，勉强有两成多）。
## 2026-11-04 接上永久恩赐以后献得多了，献心、虔诚的线从 1.45、1.25 提到 1.5、1.3：达标就收 5 / 24 / 65 / 4%。
## 阶段 V 多了渔获加冕、空腹之献这些供奉时加祭值的恩赐，献上的倍数中位从 1.26 涨到 1.38，再提到 1.7、1.45：达标就收 5 / 20 / 66 / 4%
const KEPT_BRANDS := 2
## 每一档下面的一句话
const RATING_NOTES := {
	"勉强": "契约是偿清了。祂吃掉的烙印，祂都记着。",
	"守约": "七夜之约，你守住了。",
	"虔诚": "你的供奉，祂很满意。",
	"献心": "你把心也献了上来。祂会记得你。",
	"背约": "供奉断了，祂把你吞了下去。",
	"殒于冥海": "线没能把你拉回来。",
}
const OUTCOMES := {"repaid": "契约已偿", "fall": "坠入冥海", "offering": "被祂吞噬"}


## who 走了（cause："repaid" 偿清、"fall" 落水、"offering" 被吞）：这份契约的账
static func record(who: Contractor, cause: String) -> Dictionary:
	var kinds: Array = who.offered_kinds.keys()
	kinds.sort()
	var best := {}
	if who.best_offering:
		var c := who.best_offering
		best = {"species": c.species_id, "stage": c.stage, "level": c.level, "tribute": c.tribute, "body": c.body,
			"affixes": Array(c.affix_ids), "hue_shift": c.hue_shift}
	return {
		"number": who.number, "name": who.contractor_name, "promise": who.promise, "night": who.night,
		"status": "repaid" if cause == "repaid" else "dead", "cause": cause,
		"tribute": who.tribute_total, "demand": who.demand_total, "brands_lost": who.brands_lost(),
		"cuts": who.cuts, "kinds": kinds, "best": best,
		"ability": who.ability, "cards": Array(who.cards_taken), "casts": who.casts,
		"rating": rate(cause, who.tribute_total, who.demand_total, who.brands_lost()),
	}


## 评价：偿清了的四档之一；死了的是"背约"（被吞）或"殒于冥海"（落水）
static func rate(cause: String, tribute: int, demand: int, brands_lost: int) -> String:
	if cause == "fall":
		return DROWNED
	if cause != "repaid":
		return BROKEN
	var ratio := float(tribute) / maxf(float(demand), 1.0)
	if brands_lost == 0 and ratio >= DEVOTED_RATIO:
		return "献心"
	if brands_lost == 0 and ratio >= PIOUS_RATIO:
		return "虔诚"
	if brands_lost <= KEPT_BRANDS:
		return "守约"
	return "勉强"


## "契约已偿 · 第 7 夜"
static func outcome_text(entry: Dictionary) -> String:
	return "%s · 第 %d 夜" % [OUTCOMES.get(entry.get("cause", ""), "死于冥海"), int(entry.get("night", 1))]


## 下一位签约时，名册下面写的那句话
static func farewell(entry: Dictionary) -> String:
	var code := "No.%04d" % int(entry.get("number", 0))
	match entry.get("cause", ""):
		"repaid":
			return "%s 偿清了契约，离开了冥海。" % code
		"fall":
			return "%s 坠入了冥海。" % code
	return "%s 被祂吞噬了。" % code


## 最珍贵的那一件，还原成一条渔获（画插图、上色用）；没有是 null
static func best_catch(entry: Dictionary) -> CatchData:
	var best: Dictionary = entry.get("best", {})
	if best.is_empty() or not GameDB.get_fish(best.get("species", "")):
		return null
	var c := CatchData.new()
	c.species_id = best.species
	c.stage = int(best.get("stage", CatchData.Stage.GROWING)) as CatchData.Stage
	c.level = int(best.get("level", 1))
	c.tribute = int(best.get("tribute", 0))
	c.body = float(best.get("body", 1.0))
	for id in best.get("affixes", []):
		c.affix_ids.append(str(id))
	c.hue_shift = float(best.get("hue_shift", 0.0))
	return c


## 这条记录有没有结算（阶段 G4 以前的名册条目没有）
static func has_ledger(entry: Dictionary) -> bool:
	return entry.has("rating")
