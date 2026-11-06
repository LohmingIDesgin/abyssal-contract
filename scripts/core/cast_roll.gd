class_name CastRoll
extends RefCounted
## 抛一竿：挂着这份饵在这层水，要等多久、咬钩的是什么（个体这时就生成好，之后不再变）、
## 或者挂住的是一件东西（道具或附加物，交接文档 §10.1）。FishingView 和整局模拟器（ContractSim）用同一套，
## 所以模拟器里的一竿和游戏里的一竿是一回事。饵在真有生物咬钩时才扣（调用的那边扣；新回合机制第 30 条）：
## 什么也没咬、捞到东西不扣。没有空钩了（第 31 条）。

const CAST_FLIGHT := 0.7           ## 抛竿出手的时刻（与 FirstPersonArms 的 CAST 关键帧对齐），之后浮漂才落水
const WAIT_MIN := 2.5              ## 等咬钩的时间（秒）
const WAIT_MAX := 6.0
const NOTHING_WAIT := 9.0          ## 没有东西会咬钩时，等多久才宣告空钩
const EVENT_WAIT := 2.5            ## 海上事件：浮漂落水以后多久，那件事靠过来
const BITE_WINDOW_BASE := 1.6      ## 提竿窗口（秒），挣扎越强的窗口越短。2026-11-03 从 0.9 加长：原来七成秒上下，来不及反应；
                                   ## 咬钩时屏幕上浮出 [空格] 提竿！和一道收拢的细线（BiteQte）
const START_DISTANCE := 23.0       ## 搏斗的起始距离（米）
## 每深一层多出的距离。2026-11-03 起是 0：强弱只看等级（强弱表），三层水起始距离一样。原来浅滩 15 米、每深一层多 8 米，
## 渊底 31 米时强一级的只剩三成半钓得上、3 级对 5 级四成（强弱表是按 23 米定的五成、七成）
const DISTANCE_PER_DEPTH := 0.0


## 返回 {fish（FishData 或 null）, catch（CatchData 或 null）, gap（它比契约者强几级，BalanceConfig.fight_gap；
## 捞到东西是 −1）, salvage（"" 或 id）, wait（秒）, lured（引深）, blood（血诱换来的）}。
## config 传契约者这一夜的那份数值表（Contractor.night_config：冥海侵蚀、海况）。
## 引深（奖励卡）：契约者带着它，这一竿真有生物咬钩时，换成一条比契约者的能力档高一级的（CatchGenerator.generate_at_level，
## 不看水层，饵照样挑种类），这里就用掉这张卡；调用的那边不用搏斗，提竿就直接钓上来
static func roll(bait: Bait, depth: int, who: Contractor, rng: RandomNumberGenerator,
		config: BalanceConfig = null) -> Dictionary:
	if config == null:
		config = GameDB.balance
	who.casts += 1  ## 这份契约抛了几竿（结算清单的账）
	who.night_casts += 1
	## 海上事件（阶段 IV）：今夜定好在这一竿的，抛下去等来的是那件事，不是咬钩（这一竿不扣饵）
	if not who.event_plan.is_empty() and who.night_casts >= int(who.event_plan.at):
		var id: String = who.event_plan.id
		who.event_plan = {}
		who.events_seen[id] = who.events_seen.get(id, 0) + 1
		return {"fish": null, "catch": null, "gap": 0.0, "salvage": "", "lured": false, "blood": false, "event": id,
			"wait": EVENT_WAIT}
	var fish := BiteCalculator.roll(BiteCalculator.bite_table(bait, depth, config), rng)
	var c := CatchGenerator.generate(fish, rng, config, 0, depth) if fish else null
	var salvage := ""
	if rng.randf() < config.salvage_chance:
		salvage = BalanceConfig.roll_table(config.salvage_table, rng)
		fish = null
		c = null
	var lured := false
	if c and who.has_card("lure"):
		var up := CatchGenerator.generate_at_level(who.ability + 1, bait, rng, config)
		if up:
			who.use_card("lure")
			c = up
			fish = up.species()
			lured = true
	## 血诱（恩赐）：吃了一条以后，这一夜下一次真有生物咬钩时，有 amount 的机会换成比能力档高一级的——照样要搏斗
	var blood := false
	if c and not lured and who.boon_marks.get("blood", false):
		who.boon_marks.erase("blood")
		who.use_boon("blood_lure")
		if rng.randf() < who.boon_amount("blood_lure"):
			var bigger := CatchGenerator.generate_at_level(who.ability + 1, bait, rng, config)
			if bigger:
				c = bigger
				fish = bigger.species()
				blood = true
	## 血月（海上事件）：迎着它钓的，钓上来的祭值多一截；逐浪（恩赐）：躁动、异化的夜里钓上来的多一截
	if c and c.species():
		var extra := 0.0
		if who.blood_moon:
			extra += config.blood_moon_bonus
		if who.has_boon("ride_waves") and who.sea in ["rough", "eerie"]:
			extra += who.boon_amount("ride_waves")
		if extra > 0.0:
			c.bonus += extra
			c.tribute = CatchGenerator.tribute_of(c, c.species(), config)
	var wait := rng.randf_range(WAIT_MIN, WAIT_MAX)
	var gap := config.fight_gap(who.ability, c.level) if c else (-1.0 if salvage != "" else 0.0)
	return {"fish": fish, "catch": c, "gap": gap, "salvage": salvage, "lured": lured, "blood": blood, "event": "",
		"wait": wait if fish or salvage != "" else NOTHING_WAIT}


## 咬钩以后提竿的窗口
static func bite_window(fish: FishData) -> float:
	return BITE_WINDOW_BASE - fish.struggle * 0.4 if fish else BITE_WINDOW_BASE


## 搏斗的起始距离：越深越远
static func start_distance(depth: int) -> float:
	return START_DISTANCE + depth * DISTANCE_PER_DEPTH
