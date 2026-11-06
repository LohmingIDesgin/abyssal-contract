extends Node
## 祭值的分布和每夜能献多少（设计对照文档 8.4；祭值本身在 CatchGenerator.tribute_of）：
## 1. 每种、每级、每个时期的祭值：用游戏里的个体生成，挑出这一级、这一时期的个体，看中位和 10%~90%
## 2. 按"均衡·普通"玩家每夜在哪层钓、钓上几条（《测量与预算》的预算表，一夜 6 分钟），每夜挑出船舱装得下的
##    祭值最高的一组，看每夜最多能献多少：载荷按时期（G2 起游戏里用的）和按等级（原来的，对照用）各算一遍，船舱 3 和 6
##   Godot_v4.6.3-stable_win64.exe --headless --path . res://tests/tribute_probe.tscn

const LEVEL_LOAD := [1, 2, 4, 8, 16]     ## 原来按等级算的载荷，对照用（G2 起游戏里按时期：CatchData.load_cost）
## 均衡·普通：每夜的灵魂等级、钓上几条（预算表；契约者 2026-11-03 起只到 3 级）
const NIGHT_LEVEL := [1, 1, 2, 2, 3, 3, 3]
const NIGHT_LANDED := [20, 16, 17, 16, 15, 15, 15]
const DEPTH_BAIT := [["flesh", "flesh"], ["glow", "glow"], ["shell", "shell"]]  ## 浅层、深水、渊底
const RUNS := 400
const PER_CELL := 600                    ## 分布表每一格取多少条

var rng := RandomNumberGenerator.new()
var config: BalanceConfig


func _ready() -> void:
	rng.seed = 2026
	config = GameDB.balance
	_species_table()
	_night_table()
	get_tree().quit()


## 每种、每级、每个时期的祭值：中位（10%~90%）
func _species_table() -> void:
	print("\n== 每种的祭值：中位（10%~90%），按等级、时期 ==")
	for species: FishData in GameDB.sorted_values(GameDB.fish):
		var cells := {}  ## "等级,时期" → 祭值
		var guard := 0
		var full := false
		while not full and guard < 400000:
			guard += 1
			var c := CatchGenerator.generate(species, rng, config)
			var key := "%d,%d" % [c.level, c.stage]
			var list: Array = cells.get(key, [])
			if list.size() < PER_CELL:
				list.append(c.tribute)
				cells[key] = list
			full = true
			for stage in 3:  ## 等级跟着时期走（2026-11-03）：只等这个时期有的那几级
				var levels := species.stage_levels(stage)
				for level in range(levels.x, levels.y + 1):
					full = full and cells.get("%d,%d" % [level, stage], []).size() >= PER_CELL
		for level in range(species.level_min, species.level_max + 1):
			var row := "%s %d级" % [species.display_name, level]
			for stage in 3:
				var values: Array = cells.get("%d,%d" % [level, stage], [])
				values.sort()
				row += "　%s %s" % [CatchData.STAGE_NAMES[stage], _spread(values)]
			print(row)


func _spread(sorted: Array) -> String:
	if sorted.is_empty():
		return "—"
	return "%s（%s~%s）" % [Gothic.grouped(_q(sorted, 0.5)), Gothic.grouped(_q(sorted, 0.1)), Gothic.grouped(_q(sorted, 0.9))]


## 均衡·普通每夜：钓上的渔获（只提高一级以内的），船舱装得下的最好一组
func _night_table() -> void:
	print("\n== 均衡·普通，每夜钓上的祭值；船舱装得下的最好一组（%d 次）==" % RUNS)
	print("载荷按等级（原来）：船舱 3、6；载荷按时期（幼 1 / 成长 2 / 成年 3，现在）：船舱 3、6。各是 10% / 25% / 中位")
	print("夜 | 等级 | 水层 | 每条中位 | 一夜合计中位 | 按等级·3 | 按等级·6 | 按时期·3 | 按时期·6")
	for n in 7:
		var level: int = NIGHT_LEVEL[n]
		var depth := level - 1  ## 和自己相当的那层：浅层、深水、渊底
		var who := Contractor.new(config)
		who.ability_override = level
		var bait := BaitCrafter.make(DEPTH_BAIT[depth], "skin_mince", config)
		var per_catch: Array[int] = []
		var totals: Array[int] = []
		var tables := [[], [], [], []]  ## 按等级·3、按等级·6、按时期·3、按时期·6
		for run in RUNS:
			var night: Array[CatchData] = []
			var guard := 0
			while night.size() < NIGHT_LANDED[n] and guard < 400:
				guard += 1
				var roll := CastRoll.roll(bait, depth, who, rng, config)
				if roll.catch == null or roll.gap > 1:
					continue
				night.append(roll.catch)
				per_catch.append(roll.catch.tribute)
			var total := 0
			for c in night:
				total += c.tribute
			totals.append(total)
			tables[0].append(_best(night, 3, false))
			tables[1].append(_best(night, 6, false))
			tables[2].append(_best(night, 3, true))
			tables[3].append(_best(night, 6, true))
		per_catch.sort()
		totals.sort()
		for table in tables:
			table.sort()
		print("%d | %d | %d | %s | %s | %s | %s | %s | %s" % [n + 1, level, depth, Gothic.grouped(_q(per_catch, 0.5)),
			Gothic.grouped(_q(totals, 0.5)), _three(tables[0]), _three(tables[1]), _three(tables[2]), _three(tables[3])])


func _three(sorted: Array) -> String:
	return "%s / %s / %s" % [Gothic.grouped(_q(sorted, 0.1)), Gothic.grouped(_q(sorted, 0.25)), Gothic.grouped(_q(sorted, 0.5))]


## 载荷不超过 capacity 的一组里祭值最高的（背包，载荷是小整数）；by_stage：载荷按时期算
func _best(night: Array[CatchData], capacity: int, by_stage: bool) -> int:
	var dp: Array[int] = []
	dp.resize(capacity + 1)
	dp.fill(0)
	for c in night:
		var w: int = c.load_cost if by_stage else LEVEL_LOAD[clampi(c.level - 1, 0, LEVEL_LOAD.size() - 1)]
		if w > capacity:
			continue
		for cap in range(capacity, w - 1, -1):
			dp[cap] = maxi(dp[cap], dp[cap - w] + c.tribute)
	return dp[capacity]


func _q(sorted: Array, p: float) -> int:
	return sorted[clampi(int(p * (sorted.size() - 1)), 0, sorted.size() - 1)] if not sorted.is_empty() else 0
