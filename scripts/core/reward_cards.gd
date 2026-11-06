class_name RewardCards
extends RefCounted
## 供奉后的奖励卡（新回合机制 9.6，H2）：结算了的供奉，只要还有下一夜，左边一张固定的补给（三份万能饵），
## 右边几张候选的效果卡，选一张：不够 0 张、够了 2 张、到超额线 3 张（BalanceConfig.reward_choices、over_ratio）。
## 偿清了、死了直接进结算清单，不选卡。卡池是 data/cards/ 下的全部：七张效果卡，加上三张道具卡（over_only，只有超额时才抽得到；
## 2026-11-04 起祂不再赐道具）。候选不重复、按 id 排好再抽，同一个种子结果一样。
## 界面（RewardScreen）和整局模拟器（ContractSim）用同一套。


## 这一次供奉给几张候选（offer 的结果）
static func choice_count(result: Dictionary, config: BalanceConfig = null) -> int:
	if config == null:
		config = GameDB.balance
	if result.get("repaid", false) or result.get("died", false):
		return 0
	var tier := 0
	if result.met:
		tier = 2 if is_over(result, config) else 1
	return BalanceConfig.pick(config.reward_choices, tier, 0)


## 这一次供奉到了超额线没有（够了，而且献上的到了需求的 over_ratio 倍；Contractor.offer 的结果里有 over 就用它：满溢之献会改线）
static func is_over(result: Dictionary, config: BalanceConfig = null) -> bool:
	if result.has("over"):
		return bool(result.over)
	if config == null:
		config = GameDB.balance
	return result.get("met", false) and result.tribute >= result.demand * config.over_ratio


## 不是永久恩赐的卡（立刻、一夜、道具卡）在候选里的权重（永久恩赐是 1）：恩赐是主菜，它们是应急的
const OTHER_WEIGHT := 0.6
## 身上每有一个同标签的恩赐，候选里这张恩赐的权重多这么多（最多算两个）
const TAG_BONUS := 0.5
## 签约时不出的恩赐（第一夜用不上的：异象收藏要过夜、冥市熟客要碰上冥市船、逐浪要躁动或异化的夜，第一夜都是平静）
const OPENING_SKIP := ["oddity", "regular", "ride_waves"]


## 从卡池里不重复地抽 n 张；over：超额的那一次，道具卡也抽得到；who：身上已经有的永久恩赐不再出，同标签的多一点，
## 两张以上恩赐全是同一条引擎时换掉一张（RewardCards.weight、_keep_variety）
static func draw(n: int, rng: RandomNumberGenerator, over := false, who: Contractor = null) -> Array[RewardCard]:
	var pool: Array = GameDB.sorted_values(GameDB.cards).filter(func(c: RewardCard) -> bool:
		return (over or not c.over_only) and not (who != null and c.permanent and who.boons.has(c.effect)))
	var result: Array[RewardCard] = []
	for i in mini(n, pool.size()):
		var weights: Array = pool.map(func(c: RewardCard) -> float: return weight(c, who))
		result.append(pool.pop_at(CatchGenerator._roll_index(weights, rng)))
	_keep_variety(result, pool, rng)
	return result


## 候选里这张的权重：永久恩赐 1，身上每有一个同标签的恩赐多 TAG_BONUS（最多两个）；别的卡 OTHER_WEIGHT
static func weight(card: RewardCard, who: Contractor = null) -> float:
	if not card.permanent:
		return OTHER_WEIGHT
	var same := 0
	if who != null:
		for e in who.boons:
			for t in who.boons[e].card.tags:
				if t in card.tags:
					same += 1
	return 1.0 + TAG_BONUS * mini(same, 2)


## 两张以上的永久恩赐全是同一条引擎（主标签一样）时，最后一张换成别的引擎的，留一条转型的路
static func _keep_variety(result: Array[RewardCard], pool: Array, rng: RandomNumberGenerator) -> void:
	var boons := result.filter(func(c: RewardCard) -> bool: return c.permanent and not c.tags.is_empty())
	if boons.size() < 2:
		return
	var main: String = boons[0].tags[0]
	if not boons.all(func(c: RewardCard) -> bool: return c.tags[0] == main):
		return
	var others := pool.filter(func(c: RewardCard) -> bool: return c.permanent and not c.tags.is_empty() and c.tags[0] != main)
	if others.is_empty():
		return
	result[result.rfind(boons[-1])] = others[rng.randi_range(0, others.size() - 1)]


## 只从永久恩赐里不重复地抽 n 张（身上有的不出，同标签的多一点）：祂的低语（海上事件）用
static func draw_boons(n: int, rng: RandomNumberGenerator, who: Contractor = null) -> Array[RewardCard]:
	var pool: Array = GameDB.sorted_values(GameDB.cards).filter(func(c: RewardCard) -> bool:
		return c.permanent and not (who != null and who.boons.has(c.effect)))
	var result: Array[RewardCard] = []
	for i in mini(n, pool.size()):
		var weights: Array = pool.map(func(c: RewardCard) -> float: return weight(c, who))
		result.append(pool.pop_at(CatchGenerator._roll_index(weights, rng)))
	return result


## 签约时的开局恩赐（v0.23 第 92 条）：资源、捕获、祭值三条引擎各抽一张永久恩赐（看主标签；OPENING_SKIP 不出）
static func draw_opening(rng: RandomNumberGenerator, who: Contractor = null) -> Array[RewardCard]:
	var result: Array[RewardCard] = []
	for tag in ["resource", "capture", "tribute"]:
		var list: Array = GameDB.sorted_values(GameDB.cards).filter(func(c: RewardCard) -> bool:
			return c.permanent and not c.tags.is_empty() and c.tags[0] == tag and not (c.effect in OPENING_SKIP) \
				and not (who != null and who.boons.has(c.effect)))
		if not list.is_empty():
			result.append(list[rng.randi_range(0, list.size() - 1)])
	return result
