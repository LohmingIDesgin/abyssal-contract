class_name ContractSim
extends RefCounted
## 整局模拟器（设计对照文档 5.3；新回合机制 9.7）：不开画面，把一份契约从签约跑到偿清或者死。
## 一竿（CastRoll）、搏斗（TensionModel）、渔获（CatchGenerator）、制饵（BaitCrafter）、契约周期（Contractor）都是游戏里那一套；
## 这里只多了"脚本玩家"：钓哪一层、用什么饵、哪些咬钩不提、渔获怎么分、什么时候唤祂、黄昏献上什么、体力耗尽时剪线还是赌。
## 2026-11-04 起：没有玩家等级（能力档跟着夜数走，Contractor.ability）、生吞只顶饿；剪线扣烙印；祂不挑想要的；船舱 20。
## 一夜没有钟（新回合机制第 9 节）：饵在真有生物咬钩时才扣（什么也没咬、捞到东西不扣）；脚本玩家觉得够了，
## 或者饵用完、材料也做不出来了，就唤祂；结算以后发几份万能饵。饱腹按行动扣：每抛一竿、搏斗里耗的体力（Contractor.spend_hunger）。
## 一夜、一份契约大约花多少真实时间也按真人的节奏估一下（出手、等咬钩、反应、搏斗、看渔获拿主意、制饵、黄昏和供奉），看节奏用。
## 供奉后的奖励卡（H2）：候选和游戏里一样抽（RewardCards），脚本玩家按自己的顺序挑（cards；饿了先挑饱餐）；
## 卡的效果也是游戏里那一套（引深在 CastRoll 里、进化在 Contractor.evolve_catch、剖腹在 dismantle、镇魂和壮魂在搏斗开始时）。
## 测卡的强度：prefer_card 有这张就挑它；force_card 每次结算都直接拿这张；no_cards 一张也不挑（对照）。
## 跑法见 tests/sim_contract.tscn。

## 脚本玩家（回合指令的三种走法，加一种只用来测"全拆续钓"会不会钓不完的）：
## - depths：能力 1、2、3 档时钓哪一层（和自己相当的那层：浅层、深水、渊底）
## - max_gap：比自己强几级以内的才提竿（BalanceConfig.fight_gap；浮漂沉得多猛就看得出来）
## - target：船舱里的祭值到需求的这么多倍就唤祂；饵用完、材料也做不出来了也唤（≥ 99 = 只在用完时唤）
## - keep：船舱里的祭值不到需求的这么多倍就留（0 = 一条也不留）
## - min_share：祭值不到今夜需求的这么多的不留（需求涨了，小鱼就拿去吃或者拆成饵）
## - goal：黄昏挑一组献上时，凑得到需求的这么多倍就凑（追超额），凑不到就只献够
## - eat_below：饱腹低于这个，钓上来的先吃（生吞只顶饿，不长级了）
## - dismantle：够了以后钓上来的都拆；不然留进船舱带到下一夜（放不下才拆）
## - bait_buffer：手里的饵（篓里的 + 材料还做得出的）少于这么多份时，不留的先拆
## - nail：钩上比自己强的，先钉一枚镇魂钉
## - gamble：体力耗尽时，硬撑的机会不低于这个就赌；1 = 有烙印就剪（剪线扣一枚烙印）
## - careful_brands：烙印只剩这么多枚以下时，比自己强的一概不提（剪不起线了；默认 1）
## - start_ability（可选）：一直是几档能力（只给"全拆"测各层水用）
## - cards：供奉后的奖励卡（和签约时的开局恩赐）按这个顺序挑（候选里有哪张挑哪张）；饿了先挑饱餐。
##   永久恩赐排在前面（v0.23）：达标就收偏祭值，先吃再备偏捕获，多拆续钓偏资源。阶段 V 按卡测（cardtest）的强弱重排过：
##   各走法都先挑测出来强的（韧线、进化），再按自己的路子
## - blood_moon：海上事件里碰上血月就迎着钓；whisper：碰上祂的低语，烙印还满着、不到第 6 夜就拿一枚换恩赐（阶段 IV）
const STRATEGIES := {
	"达标就收": {"depths": [0, 1, 2], "max_gap": 1, "target": 1.0, "keep": 1.15, "min_share": 0.2, "goal": 1.0,
		"eat_below": 60.0, "dismantle": false, "bait_buffer": 2, "nail": true, "gamble": 1.0,
		"blood_moon": false, "whisper": false,
		"cards": ["taut_line", "evolve", "overflow", "kin", "crown_catch", "fed_courage", "hungry_offer", "carcass", "abyss_walker",
			"ride_waves", "bone_pick", "bait_heart", "blood_lure", "bone_flute", "regular", "oddity", "lure", "spare_bait", "steady", "vigor", "dissect", "item_soul_thread", "item_soul_nail", "feast", "item_abyss_eye"]},
	"先吃再备": {"depths": [0, 1, 2], "max_gap": 1, "target": 1.0, "keep": 1.15, "min_share": 0.2, "goal": 1.0,
		"eat_below": 80.0, "dismantle": false, "bait_buffer": 1, "nail": true, "gamble": 1.0,
		"blood_moon": true, "whisper": false,
		"cards": ["taut_line", "evolve", "fed_courage", "abyss_walker", "blood_lure", "ride_waves", "hungry_offer", "kin", "overflow",
			"crown_catch", "bone_flute", "carcass", "bone_pick", "bait_heart", "regular", "oddity", "lure", "spare_bait", "steady", "vigor", "dissect", "item_soul_thread", "item_soul_nail", "feast", "item_abyss_eye"]},
	"多拆续钓": {"depths": [0, 1, 2], "max_gap": 1, "target": 1.5, "keep": 1.6, "min_share": 0.25, "goal": 1.5,
		"eat_below": 60.0, "dismantle": true, "bait_buffer": 3, "nail": true, "gamble": 1.0,
		"blood_moon": true, "whisper": true,
		"cards": ["taut_line", "evolve", "overflow", "bone_pick", "bait_heart", "carcass", "bone_flute", "ride_waves", "abyss_walker",
			"regular", "kin", "crown_catch", "fed_courage", "blood_lure", "hungry_offer", "oddity", "lure", "spare_bait", "steady", "vigor", "dissect", "item_soul_thread", "item_soul_nail", "feast", "item_abyss_eye"]},
	"全拆": {"depths": [0, 1, 2], "max_gap": 1, "target": 99.0, "keep": 0.0, "goal": 1.0, "eat_below": 60.0,
		"dismantle": true, "bait_buffer": 99, "nail": true, "gamble": 1.0,
		"cards": ["dissect", "spare_bait", "feast", "vigor", "steady", "lure", "evolve", "item_soul_thread", "item_soul_nail",
			"item_abyss_eye"]},
}
## 搏斗的手：每隔 react 秒才重新判断一次，张力低于 greed 就收线（和 tests/test_fishing 的机器人同一种）
const SKILLS := {
	"熟练": {"react": 0.0, "greed": 0.7},
	"普通": {"react": 0.2, "greed": 0.75},
	"生疏": {"react": 0.3, "greed": 0.8},
}
## 真人的节奏（秒，只用来估一夜、一份契约花多久）：回到准备抛竿以后再按下去、看到咬钩到提竿、看一眼结果按继续、
## 体力耗尽时想一想、看渔获拿定主意怎么分、开制饵台做一份饵；一夜的黄昏（唤祂的确认、天转红、祂出来、挑供品、补给）；
## 一份契约的签约和结算清单。按 2026-11-02 的三份试玩日志校的（tools/playlog_report.py：每竿 25–40 秒，黄昏到下一夜约 30 秒）
const NEXT_CAST := 2.0
const REACT := 0.4
const READ_RESULT := 1.5
## 海上事件：读、想、选一件要多久（秒）
const EVENT_SECONDS := 20.0
const LAST_STAND := 1.5
const DECIDE := 7.0
const CRAFT := 6.0
const NIGHT_OVERHEAD := 30.0
const CONTRACT_OVERHEAD := 60.0
const DT := 1.0 / 30.0
## 一夜最多抛几竿：到了就算"钓不完"（全拆续钓的检查），强行唤祂
const MAX_CASTS := 80
## 引深引上来的：提竿以后一路收上来（和 FishingView.LURE_SECONDS 一样）
const LURE_SECONDS := 1.8
## 挑供品、给新钓上来的腾地方时，一组一组试的最多几条（船舱 20 以后不能全试：2^20 组）
const MAX_SUBSET := 12
## 每一层水配什么饵：按顺序，篓里有就用，没有就做第一个做得起的（照着图鉴里各层水的样子挑）。
## 浅层用万能饵就够（灰鲦、血齿冥鲳都是血肉多），万能饵用完了才做；深水先招磷灯婆、千目窥渊鲶（幽光），渊底先招溺者之手、白鲟（矿壳）
const RECIPES := {
	0: [["flesh", "flesh"], ["flesh", "shell"], ["flesh", "glow"]],
	1: [["glow", "glow"], ["shell", "glow"], ["flesh", "shell"], ["shell", "shell"]],
	2: [["shell", "shell"], ["flesh", "shell"], ["glow", "glow"]],
}
const ALL_COMBOS := [["flesh", "flesh"], ["flesh", "shell"], ["flesh", "glow"], ["shell", "shell"], ["shell", "glow"],
	["glow", "glow"]]

var config: BalanceConfig
var strategy: Dictionary
var skill: Dictionary
var rng := RandomNumberGenerator.new()
var who: Contractor
var baits: Array[Bait] = []
## 奖励卡的测法（见文件头）
var prefer_card := ""
var force_card := ""
var no_cards := false
## 这一份契约签约时挑的开局恩赐（id；没挑是空）
var opening_card := ""
var _night: Dictionary  ## 这一夜的记录


func _init(balance: BalanceConfig, strategy_spec: Dictionary, skill_spec: Dictionary) -> void:
	config = balance
	strategy = strategy_spec
	skill = skill_spec


## 跑一份契约。返回 {outcome: "repaid" / "fall"（落水）/ "offering"（供奉不够被吞）/ "stalled", nights: 每夜的记录,
## record: 结算清单（Settlement.record，有评价；拖延的没有）}
func run(seed_value: int) -> Dictionary:
	rng.seed = seed_value
	who = Contractor.new(config)
	who.contractor_name = "sim"
	who.ability_override = int(strategy.get("start_ability", 0))
	baits.clear()
	_add_bait(BaitCrafter.make_universal(config.start_baits))
	who.begin_night(rng, true)
	## 签约时的开局恩赐（v0.23）：三条引擎各一张，按走法的顺序挑；一张也不挑（no_cards）就没有
	opening_card = ""
	var opening := _pick_card(RewardCards.draw_opening(rng, who))
	if opening:
		who.take_card(opening)
		opening_card = opening.id
	var nights: Array[Dictionary] = []
	while true:
		_night = _new_record()
		_play_night()
		if _night.fell:
			nights.append(_night)
			return {"outcome": "fall", "nights": nights, "record": Settlement.record(who, "fall")}
		_dusk()
		nights.append(_night)
		if who.status == Contractor.Status.DEAD:
			return {"outcome": "offering", "nights": nights, "record": Settlement.record(who, "offering")}
		if who.status == Contractor.Status.REPAID:
			return {"outcome": "repaid", "nights": nights, "record": Settlement.record(who, "repaid")}
		if who.night >= config.contract_nights * 2:
			return {"outcome": "stalled", "nights": nights, "record": {}}
		who.begin_night(rng)
	return {}


func _new_record() -> Dictionary:
	return {"night": who.night, "casts": 0, "bites": 0, "nothing": 0, "declined": 0, "hooked": 0, "caught": 0,
		"slipped": 0, "cut": 0, "gamble_won": 0, "fell": false, "salvage": 0, "fight_s": 0.0, "seconds": 0.0, "overhead": 0.0,
		"universal_used": 0, "crafted_used": 0, "crafted": 0, "tribute_caught": 0, "eaten": 0, "processed": 0, "kept": 0,
		"swapped": 0, "materials_in": 0, "overfull": 0, "food_in": 0.0,
		"baits_start": _bait_stock(), "materials_start": _material_count(), "baits_end": 0, "materials_end": 0,
		"hunger_start": who.hunger, "hunger": 0.0, "min_hunger": who.hunger, "hungry_casts": 0, "hooked_hungry": 0,
		"summon": "", "demand": who.demand(), "hold_tribute": 0, "hold_load": 0, "offered": 0, "offered_load": 0, "carry": 0,
		"event": "", "event_choice": -1, "event_got": "",
		"sea": who.sea,
		"ratio": 0.0, "met": false, "over": false, "brand_lost": false,
		"ability": who.ability, "brands": who.brands,
		"gap_caught": {}, "choices": 0, "card": "", "lured": 0, "evolved": 0, "steadied": 0}


# ---------- 夜里 ----------

## 一竿一竿钓，直到脚本玩家要唤祂（够了，或者饵用完、材料也做不出来了）
func _play_night() -> void:
	while true:
		if who.hold_tribute() >= who.demand() * strategy.target:
			_night.summon = "target"
			return
		if _night.casts >= MAX_CASTS:
			_night.summon = "cap"
			return
		var depth := _depth()
		var bait := _bait_for(depth)
		if bait == null:
			_night.summon = "out"
			return
		_night.casts += 1
		var cast := CastRoll.roll(bait, depth, who, rng, who.night_config())
		_night.seconds += NEXT_CAST + CastRoll.CAST_FLIGHT + cast.wait
		if cast.get("event", "") != "":  ## 海上事件（阶段 IV）：这一竿等来的是一件事，不扣饵，也不算一竿的饱腹
			_night.seconds += EVENT_SECONDS
			_handle_event(cast.event)
			continue
		_spend(who.cast_hunger())
		if who.hunger_tier() >= 1:
			_night.hungry_casts += 1
		if cast.salvage != "":
			_night.seconds += REACT + READ_RESULT
			who.add_salvage(cast.salvage)
			_night.salvage += 1
			_use_soul_thread()
			continue
		if cast.fish == null:
			_night.nothing += 1
			_night.seconds += READ_RESULT
			continue
		_night.bites += 1
		if bait.universal:
			_night.universal_used += 1
		else:
			_night.crafted_used += 1
		_consume(bait)  ## 真有生物咬钩才扣（第 30 条）：之后不提、脱钩、剪线、落水都算用掉了
		if cast.lured:
			## 引深引上来的：不搏斗，提竿就一路收上来
			_night.lured += 1
			_night.hooked += 1
			_night.seconds += REACT + LURE_SECONDS
			_land(cast.catch, cast.gap)
			continue
		## 带着镇魂（奖励卡）的，下一场按高一级算：浮漂沉得猛也敢提
		var effective: float = cast.gap - (1.0 if who.has_card("steady") else 0.0) - who.fight_steady()
		## 烙印只剩 careful_brands 枚以下：剪不起线了，比自己强的一概不提
		var max_gap: float = strategy.max_gap if who.brands > strategy.get("careful_brands", 1) else 0.0
		if effective > max_gap:
			_night.declined += 1
			_night.seconds += CastRoll.bite_window(cast.fish) + READ_RESULT
			continue
		_night.seconds += REACT
		_night.hooked += 1
		var won := _fight(cast, depth)
		if _night.fell:
			return
		if won:
			_land(cast.catch, cast.gap)
		else:
			_night.seconds += READ_RESULT


## 钓上来了（搏斗赢了、硬撑赢了、或者引深引上来的）：带着进化的先长一个时期，再看怎么分
func _land(c: CatchData, gap: float) -> void:
	if not who.evolve_catch(c, rng).is_empty():
		_night.evolved += 1
	_night.caught += 1
	_night.tribute_caught += c.tribute
	var gap_key := "%.1f" % gap
	_night.gap_caught[gap_key] = _night.gap_caught.get(gap_key, 0) + 1
	_night.seconds += DECIDE
	_decide(c)


func _spend(amount: float) -> void:
	who.spend_hunger(amount)
	_night.min_hunger = minf(_night.min_hunger, who.hunger)


## 打一场：手按 skill 收放线；带着镇魂（奖励卡）的这一场按高一级算，钩上比自己强的还可以再钉镇魂钉；
## 带着壮魂的体力多撑两成。打完按耗的体力扣饱腹
func _fight(cast: Dictionary, depth: int) -> bool:
	var gap: float = cast.gap
	if who.use_card("steady"):
		gap -= 1
		_night.steadied += 1
	gap -= who.fight_steady(true)  ## 骨笛（恩赐）
	if strategy.nail and gap >= 0.5 and who.use_item("soul_nail"):
		gap -= 1
	var model := TensionModel.new(cast.fish, gap, CastRoll.start_distance(depth), who.night_config(), rng, cast.catch.stage,
		who.hunger, who.fight_vigor(true, depth))
	if who.hunger_tier() >= 1:
		_night.hooked_hungry += 1
	var timer := 0.0
	var reel := false
	var t := 0.0
	var won := false
	while true:
		timer -= DT
		if timer <= 0.0:
			timer = skill.react
			reel = model.tension < skill.greed
		var result := model.step(DT, reel)
		t += DT
		if result == TensionModel.Result.CAUGHT:
			won = true
			break
		if result == TensionModel.Result.SLIPPED:
			_night.slipped += 1
			break
		if result == TensionModel.Result.EXHAUSTED:
			won = _last_stand(model)
			break
	_night.fight_s += t
	_night.seconds += t
	if not _night.fell:
		_spend(model.spent * config.hunger_per_stamina)
	return won


## 体力耗尽：烙印没了先补一枚（续魂丝）；硬撑的机会够高、或者没烙印可扣就赌，不然剪线（扣一枚烙印）
func _last_stand(model: TensionModel) -> bool:
	_night.seconds += LAST_STAND
	if who.brands == 0:
		_use_soul_thread()
	var chance := model.gamble_chance()
	if who.brands > 0 and chance < strategy.gamble:
		who.cut_line()
		_night.cut += 1
		return false
	if rng.randf() < chance:
		_night.gamble_won += 1
		return true
	_night.fell = true
	return false


## 钓上来的这一条怎么办（看渔获时时间不走）：
## 饱腹低于 eat_below 就先吃；值得占船舱（min_share）而船舱里的祭值还不到"需求 × keep"：留下；放不下就把船舱里祭值加起来比它低的几条换出来。
## 其余的见 _dispose
func _decide(c: CatchData) -> void:
	if who.hunger < strategy.get("eat_below", 60.0):
		_eat(c, who.eat_gain(c))
		return
	var worth: bool = c.tribute >= who.demand() * strategy.get("min_share", 0.0)
	var want: bool = worth and who.hold_tribute() < who.demand() * strategy.keep
	if want:
		if who.keep(c):
			_night.kept += 1
			return
		var out := _evict_for(c)
		if not out.is_empty():
			for k in out:
				_dispose(k)
			who.keep(c)
			_night.kept += 1
			_night.swapped += 1
			return
	_dispose(c)


## 船舱里换出哪几条给 c 腾地方：换完放得下，换出去的祭值加起来比 c 低，挑换出去最少的那一组。
## 船舱大了（20）以后只在最便宜的 MAX_SUBSET 条里一组一组试。换不了返回空
func _evict_for(c: CatchData) -> Array:
	var hold := _cheapest(who.hold, MAX_SUBSET)
	var best: Array = []
	var best_loss := INF
	for mask in range(1, 1 << hold.size()):
		var out: Array = []
		var freed := 0
		var loss := 0
		for i in hold.size():
			if mask & (1 << i):
				var k: CatchData = hold[i]
				out.append(k)
				freed += k.load_cost
				loss += k.tribute
		if who.free_load() + freed >= c.load_cost and loss < c.tribute and loss < best_loss:
			best_loss = loss
			best = out
	return best


## 不留的：饿了就吃；手里的饵不够了、或者多拆续钓的就拆；其余的留进船舱带到下一夜（放不下才拆）
func _dispose(c: CatchData) -> void:
	var need_bait: bool = _bait_stock() + _craftable() < strategy.bait_buffer
	if who.hunger_tier() >= 1:
		_eat(c, who.eat_gain(c))
	elif strategy.dismantle or need_bait or not who.keep(c):
		if who.hold.has(c):
			who.hold.erase(c)
		_dismantle(c)
	else:
		_night.kept += 1


func _eat(c: CatchData, gain: Dictionary) -> void:
	who.eat(c)
	_night.eaten += 1
	_night.food_in += gain.food
	if gain.overflow >= 1.0:
		_night.overfull += 1


func _dismantle(c: CatchData) -> void:
	var got := who.dismantle(c)
	_night.processed += 1
	for m in got:
		_night.materials_in += got[m]


# ---------- 黄昏 ----------

## 唤祂以后：从船舱里挑一组献上（凑得到 goal 倍就凑，不然只献够）；
## 凑不够就一条也不献：反正都要扣烙印，留着下一夜用。结算以后发下一夜的补给
func _dusk() -> void:
	_night.overhead = NIGHT_OVERHEAD
	_night.hunger = who.hunger
	_night.baits_end = _bait_stock()
	_night.materials_end = _material_count()
	_night.hold_tribute = who.hold_tribute()
	_night.hold_load = who.hold_load()
	var need := who.demand()
	var pick := _pick_offering(ceili(need * strategy.goal))
	if pick.is_empty() and strategy.goal > 1.0:
		pick = _pick_offering(need)
	for c in pick:
		_night.offered_load += c.load_cost
	var r := who.offer(pick, rng)
	_night.offered = r.tribute
	_night.ratio = float(r.tribute) / maxf(float(need), 1.0)
	_night.met = r.met
	_night.over = RewardCards.is_over(r, config)
	_night.carry = who.hold_tribute()  ## 献完了还留在船舱里、带到下一夜的祭值
	_night.brand_lost = r.brand_lost
	if r.supply > 0:
		_add_bait(BaitCrafter.make_universal(r.supply))
	if not r.repaid and not r.died:
		## 供奉后的奖励卡：候选和游戏里一样抽，按走法的顺序挑
		var choices := RewardCards.draw(RewardCards.choice_count(r, config), rng, RewardCards.is_over(r, config), who)
		_night.choices = choices.size()
		var card: RewardCard = GameDB.get_card(force_card) if force_card != "" else _pick_card(choices)
		if card:
			_night.card = card.id
			var got := who.take_card(card)
			if got.baits > 0:
				_add_bait(BaitCrafter.make_universal(got.baits))
	_use_soul_thread()


## 海上事件（阶段 IV，SeaEvents）按走法挑，像一个谨慎的人："够不够"按船舱里的祭值，加上手里留够备用（bait_buffer）以后
## 多出来的饵还能钓上来的（每份按这一夜钓上来的平均打六折，还没钓上来过的按需求的三分之一），要够今夜需求的 1.1 倍：
## - 冥市船：付了钱以后还够，就买恩赐（最后一夜不买）；饵快没了（两份以下）、付了还够，买饵；道具不买
## - 溺者之手：交出最不值钱的一条以后还够，就换一份饵
## - 残骸：手里的饵比备用多两份以上，才花一份去钩
## - 血月：走法里 blood_moon 的，烙印还有两枚以上就迎着钓
## - 祂的低语：走法里 whisper 的，烙印还满着、这份契约还没剪过线也没供奉不够过、不到第 5 夜，才拿一枚换恩赐（按 cards 的顺序挑）
func _handle_event(id: String) -> void:
	var ev := SeaEvents.start(id, who, rng)
	var baits := _bait_stock()
	var opts := SeaEvents.options(ev, who, baits)
	var per_bite: float = _night.tribute_caught / float(_night.caught) if _night.caught > 0 else who.demand() / 3.0
	var spare := maxi(baits - int(strategy.get("bait_buffer", 1)) - 1, 0)
	var surplus := who.hold_tribute() + spare * per_bite * 0.6 - who.demand() * 1.1
	var pick := -1
	match id:
		"trade":
			for i in opts.size():
				var offer: Dictionary = ev.offers[i]
				if not opts[i].enabled or surplus < offer.price:
					continue
				if offer.kind == "boon" and who.night < config.contract_nights:
					pick = i
					break
				if offer.kind == "baits" and baits < 2:
					pick = i
		"hand":
			var worst := SeaEvents._poorest(who)
			if opts.size() > 1 and opts[1].enabled and worst != null and surplus >= worst.tribute:
				pick = 1
		"wreck":
			if opts[0].enabled and baits >= int(strategy.get("bait_buffer", 1)) + 2:
				pick = 0
		"blood_moon":
			if strategy.get("blood_moon", false) and who.brands >= 2:
				pick = 0
		"whisper":
			if opts[0].enabled and strategy.get("whisper", false) and who.brands >= config.brands and who.cuts == 0 \
					and who.failed_offerings == 0 and who.night <= 4:
				pick = 0
		"ghost":  ## 饱腹还有一半以上就接
			if who.hunger >= 50.0:
				pick = 0
		"storm":  ## 拆得多的走法、饱腹够的时候冒雨钓
			if strategy.get("dismantle", false) and who.hunger >= 60.0:
				pick = 0
		"gambler":  ## 敢冒险的走法（whisper 的那种），多出来的够，就押最不值钱的一条
			var cheap := SeaEvents._poorest(who)
			if strategy.get("whisper", false) and opts.size() > 1 and opts[1].enabled and cheap != null and surplus >= cheap.tribute:
				pick = 1
	var r := SeaEvents.resolve(ev, pick, who, rng, baits)
	if r.spend_bait > 0:
		var b := _bait_for(_depth())
		if b:
			_consume(b)
	if r.baits > 0:
		_add_bait(BaitCrafter.make_universal(r.baits))
	if not r.choose_boon.is_empty():
		var card := _pick_card(r.choose_boon)
		if card:
			who.take_card(card)
	_night.event = id
	_night.event_choice = pick
	_night.event_got = r.got


## 挑哪张奖励卡：prefer_card 有就挑它；饿了先挑饱餐；其余按走法的顺序（cards）。一张也不挑（no_cards）返回 null
func _pick_card(choices: Array[RewardCard]) -> RewardCard:
	if choices.is_empty() or no_cards:
		return null
	var order: Array = strategy.get("cards", []).duplicate()
	if who.hunger_tier() >= 1:
		order.push_front("feast")
	if prefer_card != "":
		order.push_front(prefer_card)
	for id in order:
		for c in choices:
			if c.id == id:
				return c
	return choices[0]


## 船舱里祭值加起来到 need、多出来的（按比例）最少的一组。船舱里多于 MAX_SUBSET 条时，只在最值钱的那几条里挑。凑不到返回空
func _pick_offering(need: int) -> Array:
	var hold := who.hold.duplicate()
	if hold.size() > MAX_SUBSET:
		hold.sort_custom(func(a: CatchData, b: CatchData) -> bool: return a.tribute > b.tribute)
		hold = hold.slice(0, MAX_SUBSET)
	var best: Array = []
	var best_score := INF
	for mask in range(1, 1 << hold.size()):
		var tribute := 0
		var pick: Array = []
		for i in hold.size():
			if mask & (1 << i):
				pick.append(hold[i])
				tribute += hold[i].tribute
		if tribute < need:
			continue
		var score := float(tribute - need) / maxf(need, 1.0) * 1000.0 + pick.size()
		if score < best_score:
			best_score = score
			best = pick
	return best


## 船舱里祭值最低的 n 条
static func _cheapest(hold: Array, n: int) -> Array:
	var sorted := hold.duplicate()
	sorted.sort_custom(func(a: CatchData, b: CatchData) -> bool: return a.tribute < b.tribute)
	return sorted.slice(0, n)


# ---------- 饵 ----------

## 钓哪一层：和自己相当的那层；带着一整夜都管的镇魂、壮魂（奖励卡；走法的 deeper 可以改）时，这一夜按高一级挑，往深一层去
func _depth() -> int:
	var depths: Array = strategy.depths
	var deeper := false
	for effect in strategy.get("deeper", ["steady", "vigor", "abyss_walker"]):
		deeper = deeper or (who.has_card(effect) and who.card_effects[effect].left < 0) or who.has_boon(effect)
	var level := who.ability + (1 if deeper else 0)
	return depths[clampi(level - 1, 0, depths.size() - 1)]


## 这一竿挂什么：浅层先用万能饵；深一点先用这层水的配方（篓里有就用，没有就做），做不出来再用万能饵；
## 万能饵也没了就随便做一份做得起的。都没有返回 null（该唤祂了）
func _bait_for(depth: int) -> Bait:
	if depth > 0:
		var crafted := _recipe_bait(depth)
		if crafted:
			return crafted
	for b in baits:
		if b.universal:
			return b
	if depth == 0:
		var shallow := _recipe_bait(0)
		if shallow:
			return shallow
	for b in baits:
		return b
	for combo in ALL_COMBOS:
		var made := _craft(combo, depth)
		if made:
			return made
	return null


## 这层水的配方：篓里有就用，没有就按顺序做第一个做得起的
func _recipe_bait(depth: int) -> Bait:
	for recipe in RECIPES[depth]:
		var bases := BaitCrafter.normalize(recipe)
		for b in baits:
			if not b.universal and b.bases == bases:
				return b
	for recipe in RECIPES[depth]:
		var made := _craft(recipe, depth)
		if made:
			return made
	return null


func _craft(recipe: Array, depth: int) -> Bait:
	var additive := _additive_for(depth)
	var made := BaitCrafter.craft(who, recipe, additive)
	if made == null and additive != GameDB.basic_additive().id:
		made = BaitCrafter.craft(who, recipe, GameDB.basic_additive().id)
	if made:
		_night.crafted += 1
		_night.seconds += CRAFT
		_add_bait(made)
	return made


## 用哪种附加物：基础款（原来按今夜祂想要的挑，2026-11-04 祂不再挑了）
func _additive_for(_depth: int) -> String:
	return GameDB.basic_additive().id  ## 祂不再挑想要的（2026-11-04），附加物就用基础款


func _add_bait(bait: Bait) -> void:
	for b in baits:
		if b.same_recipe(bait):
			b.uses += bait.uses
			return
	baits.append(bait)


func _consume(bait: Bait) -> void:
	bait.uses -= 1
	if bait.uses <= 0:
		baits.erase(bait)


## 续魂丝：烙印没满就补一枚
func _use_soul_thread() -> void:
	if who.brands < config.brands and who.items.get("soul_thread", 0) > 0:
		who.use_item("soul_thread")
		who.restore_brand()


## 篓里一共还剩几份饵
func _bait_stock() -> int:
	var n := 0
	for b in baits:
		n += b.uses
	return n


## 身上的基础材料一共几份
func _material_count() -> int:
	var n := 0
	for m in Materials.ALL:
		n += who.materials.get(m, 0)
	return n


## 身上的材料还能做几份饵（两份一份，附加物用基础款）
func _craftable() -> int:
	return _material_count() / 2
