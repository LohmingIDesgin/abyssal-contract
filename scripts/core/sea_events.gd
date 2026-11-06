class_name SeaEvents
extends RefCounted
## 海上事件和冥市交易（阶段 IV，计划文档第 101 条，2026-11-04）。中期变强的另一条路：在夜里碰上的事。
## - 什么时候：第 event_min_night 夜起，每夜开始时按 event_chance 定今夜有没有一件、在第几竿（Contractor.event_plan，plan）。
##   到了那一竿，抛下去等来的不是咬钩，是这件事（CastRoll.roll 的 event）：这一竿不扣饵。一夜最多一件，签约后的第一夜没有；
##   唤祂之前没抛到那一竿，今夜就没有了。
## - 每一件都有选择或代价，不白送，也刷不了：
##   trade 冥市船：用船舱里的渔获换东西（按祭值，自动挑凑够价钱、多出来最少的几条）：一张恩赐、两份万能饵、一件道具里换一样。
##     祭值从此多了一个用法：献给祂，还是换成力量。价钱按今夜的需求算（trade_boon、trade_baits、trade_items）
##   hand 溺者之手：给它船舱里最值钱的一条，换它攥着的一件道具；或者最不值钱的一条，换一份万能饵
##   wreck 漂来的残骸：花一份饵去钩它：四成一件道具、四成三份材料、两成什么也没有（wreck_odds）
##   blood_moon 血月：迎着它钓——这一夜剩下的，高的几级更多（blood_moon_tilt），钓上来的祭值 +20%（blood_moon_bonus）
##   whisper 祂的低语（烙印还有两枚以上才出）：献上一枚烙印，换一张恩赐（三选一）。丢的烙印照算进评价
##   ghost 亡魂（阶段 V）：溺死的契约者（名册上死了的那一位）递来生前没用上的东西：一件道具，寒气透骨，饱腹 −15
##   storm 暴雨（阶段 V）：冒雨钓——这一夜剩下的，每抛一竿多掉饱腹，分解每条多一份材料
##   gambler 冥市的赌徒（阶段 V）：押一条渔获，一半的机会祭值翻倍，一半输掉
## 纯逻辑：start 定好这一件（冥市船的三样货），options 列出现在能选什么，resolve 结算；
## 界面（EventScreen、FishingView）和整局模拟器（ContractSim）用同一套。

const NAMES := {"trade": "冥市船", "hand": "溺者之手", "wreck": "漂来的残骸", "blood_moon": "血月", "whisper": "祂的低语",
	"ghost": "亡魂", "storm": "暴雨", "gambler": "冥市的赌徒"}
## 这件事的样子（两行，展示时一行一行浮出来）
const LINES := {
	"trade": ["一条挂着幽灯的小船贴了过来，船头的影子朝你伸出手。", "\"拿渔获来换。一样东西，一个价。\""],
	"hand": ["一只泡得发白的手从水里伸出来，攥着什么东西，", "又朝你的船舱张了张。"],
	"wreck": ["一截缠满水草的残骸从雾里漂过来，", "上面挂着什么，看不清。"],
	"blood_moon": ["云裂开了。月亮是红的。", "水下的东西开始往上浮。"],
	"whisper": ["雾里有声音贴着你的耳朵。", "祂在等你答话。"],
	"ghost": ["一个溺死的契约者扶着船舷浮上来，", "攥着生前没用上的东西，朝你递过来。"],
	"storm": ["雨砸下来了，海面一片白。", "水下的东西被打得发懵。"],
	"gambler": ["一条小船上坐着个没有脸的人，面前摆着一只骰盅：", "\"押一条。翻一倍，或者归我。\""],
}
## 祂的低语：祂说的话（英文手写 + 灰色批注，和供奉、奖励屏一样）
const WHISPER_WORDS := "A brand, for one more gift."
const WHISPER_NOTE := "一枚烙印，换多给你一样。"
## 不选（空格）时按钮上写的
const LEAVE := {"trade": "不换", "hand": "不理它", "wreck": "由它漂走", "blood_moon": "低下头，不看它", "whisper": "不应",
	"ghost": "别过头去", "storm": "收竿避雨", "gambler": "不赌"}


## 这件事的两行样子：亡魂知道是谁的（ev.ghost_name，名册上死了的那一位）就写出来
static func lines(ev: Dictionary) -> Array:
	if ev.get("id", "") == "ghost" and str(ev.get("ghost_name", "")) != "":
		return ["%s 的亡魂扶着船舷浮上来，" % ev.ghost_name, "攥着生前没用上的东西，朝你递过来。"]
	return LINES.get(ev.get("id", ""), [])


## 每夜开始时定今夜的事：{id, at（这一夜第几竿）}；没有返回空。按 event_weights 抽；祂的低语要烙印还有两枚以上
static func plan(who: Contractor, rng: RandomNumberGenerator) -> Dictionary:
	var config := who.config
	if rng == null or who.night < config.event_min_night or rng.randf() >= config.event_chance:
		return {}
	var weights := {}
	for id in config.event_weights:
		if id == "whisper" and who.brands < 2:
			continue
		weights[id] = config.event_weights[id]
	if weights.has("trade") and who.has_boon("regular"):  ## 冥市熟客：冥市船来得勤
		weights.trade *= who.boon_cap("regular")
	if weights.is_empty():
		return {}
	return {"id": BalanceConfig.roll_table(weights, rng), "at": rng.randi_range(config.event_cast_min, config.event_cast_max)}


## 碰上了：定好这一件（冥市船的三样货在 offers 里）。返回 {id, offers}
static func start(id: String, who: Contractor, rng: RandomNumberGenerator) -> Dictionary:
	var ev := {"id": id, "offers": []}
	if id == "trade":
		ev.offers = trade_offers(who, rng)
	return ev


## 冥市船的三样货：一张身上没有的永久恩赐、两份万能饵、一件道具；价钱是今夜需求的几成，取整到百
static func trade_offers(who: Contractor, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var config := who.config
	var need := roundi(who.demand() * (1.0 - who.boon_amount("regular")))  ## 冥市熟客：便宜一截
	var result: Array[Dictionary] = []
	var boons: Array = GameDB.sorted_values(GameDB.cards).filter(func(c: RewardCard) -> bool:
		return c.permanent and not who.boons.has(c.effect))
	if not boons.is_empty():
		result.append({"kind": "boon", "card": boons[rng.randi_range(0, boons.size() - 1)], "price": price(need, config.trade_boon)})
	result.append({"kind": "baits", "count": config.trade_bait_count, "price": price(need, config.trade_baits)})
	var items: Array = config.trade_items.keys()
	items.sort()
	var item: String = items[rng.randi_range(0, items.size() - 1)]
	result.append({"kind": "item", "item": item, "price": price(need, float(config.trade_items[item]))})
	return result


static func price(need: int, ratio: float) -> int:
	return maxi(100, roundi(need * ratio / 100.0) * 100)


## 付 price 祭值要拿走船舱里的哪几条：凑够、多出来最少（单独一条就够的里面最小的那条，或者从小往大加够、再去掉多余的那一组，
## 挑多出来少的）；船舱里加起来都不够返回空
static func payment(who: Contractor, need: int) -> Array[CatchData]:
	var sorted: Array[CatchData] = who.hold.duplicate()
	sorted.sort_custom(func(a: CatchData, b: CatchData) -> bool: return a.tribute < b.tribute)
	var single: CatchData = null
	for c in sorted:
		if c.tribute >= need:
			single = c
			break
	var group: Array[CatchData] = []
	var total := 0
	for c in sorted:
		if total >= need:
			break
		group.append(c)
		total += c.tribute
	if total < need:
		group.clear()
	else:
		for c in group.duplicate():
			if total - c.tribute >= need:
				group.erase(c)
				total -= c.tribute
	if single != null and (group.is_empty() or single.tribute <= total):
		return [single]
	return group


## 现在能选什么：[{label, detail（代价、会拿走哪几条，灰字）, enabled}]，不含"离开"。baits：手里还有几份饵（残骸要花一份）
static func options(ev: Dictionary, who: Contractor, baits := 1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match ev.id:
		"trade":
			for offer: Dictionary in ev.offers:
				var pay := payment(who, offer.price)
				var detail := "价 %s 祭值：" % Gothic.grouped(offer.price)
				detail += _names(pay) if not pay.is_empty() else "船舱里的不够"
				result.append({"label": _offer_name(offer), "detail": detail, "enabled": not pay.is_empty()})
		"hand":
			var best := _richest(who)
			var worst := _poorest(who)
			result.append({"label": "给它最值钱的一条，换它攥着的东西",
				"detail": ("交出%s（%s）：换一件道具" % [best.display_name(), Gothic.grouped(best.tribute)]) if best else "船舱是空的",
				"enabled": best != null})
			result.append({"label": "给它最不值钱的一条，换一份万能饵",
				"detail": ("交出%s（%s）" % [worst.display_name(), Gothic.grouped(worst.tribute)]) if worst else "船舱是空的",
				"enabled": worst != null})
		"wreck":
			var odds: Dictionary = who.config.wreck_odds
			result.append({"label": "花一份饵去钩它",
				"detail": ("%d 成一件道具、%d 成 %d 份材料、%d 成什么也没有" % [roundi(odds.get("item", 0.0) * 10),
					roundi(odds.get("materials", 0.0) * 10), who.config.wreck_materials, roundi(odds.get("nothing", 0.0) * 10)])
					if baits > 0 else "手里没有饵了",
				"enabled": baits > 0})
		"blood_moon":
			result.append({"label": "迎着血月钓",
				"detail": "这一夜剩下的：深处的东西更多，钓上来的祭值 +%d%%" % roundi(who.config.blood_moon_bonus * 100.0), "enabled": true})
		"ghost":
			result.append({"label": "接过它递来的东西",
				"detail": "一件道具；寒气透骨，饱腹 −%d" % roundi(who.config.ghost_hunger), "enabled": true})
		"storm":
			result.append({"label": "冒雨钓",
				"detail": "这一夜剩下的：每抛一竿多掉 %d 饱腹，分解每条多 %d 份材料" % [roundi(who.config.storm_hunger),
					who.config.storm_materials], "enabled": true})
		"gambler":
			var best := _richest(who)
			var worst := _poorest(who)
			var odds := roundi(who.config.gambler_win * 100.0)
			result.append({"label": "押最值钱的一条",
				"detail": ("%s（%s）：%d%% 翻一倍，不然输掉" % [best.display_name(), Gothic.grouped(best.tribute), odds]) if best else "船舱是空的",
				"enabled": best != null})
			result.append({"label": "押最不值钱的一条",
				"detail": ("%s（%s）：%d%% 翻一倍，不然输掉" % [worst.display_name(), Gothic.grouped(worst.tribute), odds]) if worst else "船舱是空的",
				"enabled": worst != null})
		"whisper":
			result.append({"label": "献上一枚烙印，换一样恩赐",
				"detail": "烙印 %d → %d（照算进评价）；从三张恩赐里挑一张" % [who.brands, who.brands - 1], "enabled": who.brands >= 2})
	return result


## 选了第 index 个（−1 = 不选）。返回 {text（左下写的一行）, baits（给几份万能饵）, spend_bait（要扣几份饵：残骸）,
## choose_boon（祂的低语：从这几张里挑一张，调用的那边打开 RewardScreen）, paid（交出去的祭值）, got（得到了什么，id）}
static func resolve(ev: Dictionary, index: int, who: Contractor, rng: RandomNumberGenerator, baits := 1) -> Dictionary:
	var r := {"text": "", "baits": 0, "spend_bait": 0, "choose_boon": [], "paid": 0, "got": ""}
	var opts := options(ev, who, baits)
	if index < 0 or index >= opts.size() or not opts[index].enabled:
		r.text = "%s：%s。" % [NAMES.get(ev.id, ev.id), LEAVE.get(ev.id, "离开")]
		return r
	match ev.id:
		"trade":
			var offer: Dictionary = ev.offers[index]
			var pay := payment(who, offer.price)
			r.paid = _give(who, pay)
			match offer.kind:
				"boon":
					who.take_card(offer.card)
					r.got = offer.card.id
				"baits":
					r.baits = int(offer.count)
					r.got = "baits"
				"item":
					who.add_item(offer.item)
					r.got = offer.item
			r.text = "冥市船：交出%s，换了%s。" % [_paid_text(pay), _offer_name(offer)]
		"hand":
			var c := _richest(who) if index == 0 else _poorest(who)
			r.paid = _give(who, [c])
			if index == 0:
				var items: Array = who.config.trade_items.keys()
				items.sort()
				var item: String = items[rng.randi_range(0, items.size() - 1)]
				who.add_item(item)
				r.got = item
				r.text = "溺者之手收下了%s，松开手，留下一件%s。" % [c.display_name(), GameDB.get_item(item).display_name]
			else:
				r.baits = 1
				r.got = "baits"
				r.text = "溺者之手收下了%s，丢回来一份万能饵。" % c.display_name()
		"wreck":
			r.spend_bait = 1
			var roll := BalanceConfig.roll_table(who.config.wreck_odds, rng)
			match roll:
				"item":
					var items: Array = who.config.trade_items.keys()
					items.sort()
					var item: String = items[rng.randi_range(0, items.size() - 1)]
					who.add_item(item)
					r.got = item
					r.text = "残骸上钩下来一件%s。" % GameDB.get_item(item).display_name
				"materials":
					var got := Materials.empty()
					for i in who.config.wreck_materials:
						var m: String = Materials.ALL[rng.randi_range(0, Materials.ALL.size() - 1)]
						got[m] += 1
					for m in got:
						who.materials[m] = who.materials.get(m, 0) + got[m]
					who.changed.emit()
					r.got = "materials"
					r.text = "残骸上刮下来%s。" % Materials.format(got)
				_:
					r.text = "钩子刮过残骸，什么也没带上来。饵没了。"
		"blood_moon":
			who.blood_moon = true
			who.changed.emit()
			r.got = "blood_moon"
			r.text = "你迎着血月下竿。深处的东西浮上来了。"
		"ghost":
			var items: Array = who.config.trade_items.keys()
			items.sort()
			var item: String = items[rng.randi_range(0, items.size() - 1)]
			who.add_item(item)
			who.spend_hunger(who.config.ghost_hunger)
			r.got = item
			r.text = "亡魂把一件%s放进你手里，沉了下去。你冷得发抖。" % GameDB.get_item(item).display_name
		"storm":
			who.storm = true
			who.changed.emit()
			r.got = "storm"
			r.text = "你冒着雨下竿。雨点砸在脸上，像冰碴。"
		"gambler":
			var c := _richest(who) if index == 0 else _poorest(who)
			if rng.randf() < who.config.gambler_win:
				c.bonus = 2.0 * (1.0 + c.bonus) - 1.0  ## 翻一倍：带着别的加成（残躯为饵、血月……）也是整整两倍
				c.tribute = CatchGenerator.tribute_of(c, c.species(), who.config) if c.species() else c.tribute * 2
				who.changed.emit()
				r.got = "win"
				r.text = "骰子停了。你的%s祭值翻了一倍（%s）。" % [c.display_name(), Gothic.grouped(c.tribute)]
			else:
				r.paid = _give(who, [c])
				r.got = "lose"
				r.text = "骰子停了。没有脸的人收走了你的%s。" % c.display_name()
		"whisper":
			who.brands -= 1
			who.changed.emit()
			r.choose_boon = RewardCards.draw_boons(3, rng, who)
			r.got = "boon"
			r.text = "祂收下了一枚烙印。"
	return r


## 冥市船的一样货写成字："恩赐「韧线」"、"两份万能饵"、"一卷续魂丝"
static func _offer_name(offer: Dictionary) -> String:
	match offer.kind:
		"boon":
			return "恩赐「%s」（%s）" % [offer.card.display_name, offer.card.duration]
		"baits":
			return "%d 份万能饵" % offer.count
		"item":
			return "一件%s" % GameDB.get_item(offer.item).display_name
	return ""


## 交出去：从船舱里拿走，返回祭值加起来
static func _give(who: Contractor, catches: Array) -> int:
	var total := 0
	for c: CatchData in catches:
		total += c.tribute
		who.hold.erase(c)
	who.changed.emit()
	return total


## 交出去的写成字：一条是"灰鲦（1,617 祭值）"，几条是"灰鲦、血齿冥鲳（共 3,200 祭值）"
static func _paid_text(catches: Array) -> String:
	var total := 0
	for c: CatchData in catches:
		total += c.tribute
	if catches.size() == 1:
		return "%s（%s 祭值）" % [catches[0].display_name(), Gothic.grouped(total)]
	return "%s（共 %s 祭值）" % ["、".join(catches.map(func(c: CatchData) -> String: return c.display_name())), Gothic.grouped(total)]


static func _names(catches: Array) -> String:
	return "、".join(catches.map(func(c: CatchData) -> String: return "%s（%s）" % [c.display_name(), Gothic.grouped(c.tribute)]))


static func _richest(who: Contractor) -> CatchData:
	var best: CatchData = null
	for c in who.hold:
		if best == null or c.tribute > best.tribute:
			best = c
	return best


static func _poorest(who: Contractor) -> CatchData:
	var worst: CatchData = null
	for c in who.hold:
		if worst == null or c.tribute < worst.tribute:
			worst = c
	return worst
