class_name TensionModel
extends RefCounted
## 收线阶段的搏斗（纯逻辑，不依赖节点，方便测试和调参）。数值在 BalanceConfig 的"搏斗""硬撑"两组。
##
## 规则（设计对照文档 3.1 第 5、6 条，3.2 第 10 条）：
## - 按住收线：张力上升，线变短；它挣扎时张力涨得更快、线几乎收不动
## - 松手：张力回落；它慢慢往外游，挣扎时把线往外拖；线放到头，就直接拽着人
## - 张力保持在甜区时，它的耐力掉得最快；耐力耗尽后不再挣扎，收线变快
## - 线拉不断：张力进了红区，改成大量消耗契约者的体力；收线、被拽着也耗体力，松手歇着能回一点
## - 线松着超过 SLACK_GRACE 秒以后，每秒有一定概率挣脱。线放到头以后线是绷着的，不会再挣脱：
##   想等它自己跑掉，剩下的线就是倒计时、挣脱的概率就是赔率（设计对照文档第 6 条）
## - 对手比契约者强几级（等级差，BalanceConfig.fight_gap 查表：契约者 1–3 级对上 1–5 级的生物，可以是小数），
##   它的拉力、游速，契约者收线的速度、耗的体力、它耐力掉的速度、挣脱的概率都跟着变
## - 它的时期（幼年、成长、成年）改它的挣扎和耐力：幼年弱一些、撑得短，成年猛一些、撑得久（BalanceConfig 的"时期"一组）
## - 契约者饿着上钩的：这一场的体力上限低一截，最饿时体力还掉得快（BalanceConfig 的"饱腹"一组，核心调整 G3）
## - 带着壮魂（奖励卡）：体力掉得慢，多撑 vigor 那么多（0.2 = 两成）
## - 体力耗尽时停下来，剪线还是硬撑由界面决定（硬撑钓上的机会见 gamble_chance；远超自己的硬撑必输）

enum Result { ONGOING, CAUGHT, SLIPPED, EXHAUSTED }

const SLACK_TENSION := 0.08
const SLACK_GRACE := 0.5           ## 线松了这么久以后才开始有挣脱的概率，偶尔松一下不算
const SWEET_MIN := 0.35
const SWEET_MAX := 0.85
const MAX_TENSION := 1.3

const REEL_TENSION_RATE := 0.55    ## 收线时张力每秒上升
const RELAX_RATE := 0.7            ## 松手时张力每秒回落
const PULL_TENSION_REELING := 1.0  ## 收线时它的挣扎对张力的放大
const PULL_TENSION_IDLE := 0.6     ## 松手时它的挣扎对张力的放大
const LINE_OUT_TENSION := 1.0      ## 线放到头时，往外的力直接转成张力
const DRAG_TENSION := 0.4          ## 线放到头、被拽着时张力至少这么大：线绷着，不会松，也就不会挣脱
const SWIM_PULL := 0.3             ## 不挣扎、只是往外游时，每米/秒的游速算多大的拉力
const REEL_SPEED := 3.0            ## 米/秒
const PULL_SPEED := 2.5            ## 挣扎拖线的速度（米/秒 × 拉力）
const EXTRA_LINE := 10.0           ## 起始距离之外还能放出的线
const TIER_NAMES: Array[String] = ["弱", "相当", "强", "极强"]

var fish: FishData
var struggle: float                 ## 挣扎强度 0~1：种类的挣扎 × 时期的倍率
var endurance_max: float            ## 耐力上限：种类的耐力 × 时期的倍率
var config: BalanceConfig
var level_gap := 0.0               ## 对手比契约者强几级（BalanceConfig.fight_gap）
var tension := 0.3
var distance: float
var start_distance: float
var max_distance: float
var endurance: float               ## 它的耐力（不显示）
var stamina: float                 ## 契约者的体力，每次上钩回满（回到这一场的上限）
var stamina_limit: float           ## 这一场的体力上限：饿了比 stamina_max 低
var drain_mult := 1.0              ## 体力消耗的倍率：饿得发慌时掉得快
var min_stamina: float             ## 这一场最低到过多少（试玩日志用）
var spent := 0.0                   ## 这一场一共耗了多少体力（回过来的不扣）：打完按它扣饱腹（新回合机制第 36 条）
var struggling := false
var dragged := false               ## 线放到了头，正被它直接拽着

var _struggle_timer := 0.0  ## 挣扎中 = 本次挣扎剩余时间；平静中 = 距下次挣扎的时间
var _slack_time := 0.0
var _rng: RandomNumberGenerator


## stage：钓上来的这条是什么时期（CatchData.Stage），改它的挣扎和耐力；hunger：上钩时契约者的饱腹（不传就是不饿）；
## vigor：壮魂（奖励卡）让体力多撑几成
func _init(target: FishData, gap: float, start: float, balance: BalanceConfig = null,
		rng: RandomNumberGenerator = null, stage := CatchData.Stage.GROWING, hunger := INF, vigor := 0.0) -> void:
	fish = target
	level_gap = gap
	config = balance if balance else GameDB.balance
	struggle = clampf(fish.struggle * BalanceConfig.pick(config.stage_struggle_mult, stage, 1.0), 0.0, 1.0)
	endurance_max = fish.endurance * BalanceConfig.pick(config.stage_endurance_mult, stage, 1.0)
	start_distance = start
	distance = start
	max_distance = start + EXTRA_LINE
	endurance = endurance_max
	stamina_limit = config.stamina_max * config.stamina_cap(hunger)
	drain_mult = config.stamina_drain_mult(hunger) / (1.0 + maxf(vigor, 0.0))
	stamina = stamina_limit
	min_stamina = stamina
	_rng = rng if rng else RandomNumberGenerator.new()
	_struggle_timer = _calm_duration()


## 相对强弱的档位：0 弱、1 相当、2 强、3 极强（上钩时就显示，准确等级要钓上来才知道）
static func tier_of(gap: float) -> int:
	if gap < -0.5:
		return 0
	if gap < 0.5:
		return 1
	return 2 if gap < 1.5 else 3


func tier() -> int:
	return tier_of(level_gap)


func is_spent() -> bool:
	return endurance <= 0.0


## 体力占满格（stamina_max）的几成；饿了的时候到不了 1
func stamina_ratio() -> float:
	return clampf(stamina / config.stamina_max, 0.0, 1.0)


## 这一场的体力上限占满格的几成
func stamina_cap() -> float:
	return clampf(stamina_limit / config.stamina_max, 0.0, 1.0)


## 张力在红区：线拉不断，力气全压在人身上
func is_straining() -> bool:
	return tension >= config.red_tension


## 线松着有多危险 0~1（过了宽限期就是 1），供界面提示
func slack_danger() -> float:
	return clampf(_slack_time / SLACK_GRACE, 0.0, 1.0)


## 它累到什么程度 0~1
func fatigue() -> float:
	return 1.0 - clampf(endurance / maxf(endurance_max, 0.01), 0.0, 1.0)


## 硬撑把它钓上来的概率：它越累、等级差越小，机会越大（设计对照文档 3.1 第 5 条）；
## 远超自己的（等级差超过 gamble_max_gap）硬撑必输，只能剪线
func gamble_chance() -> float:
	if level_gap > config.gamble_max_gap:
		return 0.0
	var c := config.gamble_base + fatigue() * config.gamble_fatigue - level_gap * config.gamble_per_level
	return clampf(c, config.gamble_min, config.gamble_max)


## 不显示数字，只给一句话
static func gamble_phrase(chance: float) -> String:
	if chance < 0.1:
		return "九死一生"
	if chance < 0.25:
		return "凶多吉少"
	return "尚有一线"


func step(delta: float, reeling: bool) -> Result:
	_update_struggle(delta)
	var pull := struggle * _pull_factor() if struggling else 0.0
	var swim := config.swim_speed * _swim_factor() * (0.3 if is_spent() else 1.0)

	if reeling:
		tension += (REEL_TENSION_RATE + pull * PULL_TENSION_REELING) * delta
		var speed := REEL_SPEED * _reel_factor() * (0.3 if pull > 0.0 else 1.0) * (1.5 if is_spent() else 1.0)
		distance -= speed * delta
	else:
		tension += (pull * PULL_TENSION_IDLE - RELAX_RATE) * delta
		distance += (PULL_SPEED * pull if struggling else swim) * delta
	dragged = distance >= max_distance
	var outward := pull if struggling else swim * SWIM_PULL
	if dragged:
		distance = max_distance
		tension = maxf(tension + outward * LINE_OUT_TENSION * delta, DRAG_TENSION)
	tension = clampf(tension, 0.0, MAX_TENSION)

	# 它的耐力：甜区里掉得最快
	var wear := _endurance_factor() * delta
	if tension >= SWEET_MIN and tension <= SWEET_MAX:
		endurance -= wear * (1.5 if struggling else 1.0)
	elif tension > SLACK_TENSION:
		endurance -= wear * 0.3

	# 契约者的体力：收线、红区、被拽着都耗；什么都不耗的时候松手歇着能回一点
	var drain := 0.0
	if reeling:
		drain += config.reel_drain * _drain_factor()
	if is_straining():
		drain += config.red_drain
	if dragged:
		drain += config.drag_drain * outward
	if drain > 0.0:
		stamina -= drain * drain_mult * delta
		spent += drain * drain_mult * delta
	else:
		stamina = minf(stamina + config.recover_rate * _recover_factor() * delta, stamina_limit)
	min_stamina = minf(min_stamina, maxf(stamina, 0.0))

	if distance <= 0.0:
		return Result.CAUGHT
	if stamina <= 0.0:
		stamina = 0.0
		return Result.EXHAUSTED
	if tension <= SLACK_TENSION:
		_slack_time += delta
		var chance := config.slip_chance * _slip_factor()
		if _slack_time > SLACK_GRACE and _rng.randf() < 1.0 - pow(1.0 - chance, delta):
			return Result.SLIPPED
	else:
		_slack_time = 0.0
	return Result.ONGOING


# ---------- 等级差 ----------
# 对手每高一级（低级则反过来），两头都有上下限，差得再多也不至于完全没法打或者白送

## 挣扎的拉力
func _pull_factor() -> float:
	return clampf(1.0 + config.level_pull_step * level_gap, 0.6, 2.0)


## 收线的速度
func _reel_factor() -> float:
	return clampf(1.0 - config.level_reel_step * level_gap, 0.45, 1.3)


## 收线耗的体力（按倍数涨）
func _drain_factor() -> float:
	return clampf(pow(config.level_drain_factor, level_gap), 0.5, 4.0)


## 它的耐力掉的速度
func _endurance_factor() -> float:
	return clampf(1.0 - config.level_endurance_step * level_gap, 0.45, 1.3)


## 歇着回体力的速度：每高一级减半，高两级以上不再回
func _recover_factor() -> float:
	return clampf(1.0 - 0.5 * level_gap, 0.0, 1.5)


## 线松着时挣脱的概率：越强的越不肯走，想等它自己跑掉更难
func _slip_factor() -> float:
	return clampf(1.0 - 0.15 * level_gap, 0.4, 1.3)


## 往外游的速度：每高一级快 40%
func _swim_factor() -> float:
	return clampf(1.0 + 0.4 * level_gap, 0.4, 2.2)


func _update_struggle(delta: float) -> void:
	if is_spent():
		struggling = false
		return
	_struggle_timer -= delta
	if _struggle_timer > 0.0:
		return
	struggling = not struggling
	_struggle_timer = _struggle_duration() if struggling else _calm_duration()


func _calm_duration() -> float:
	return _rng.randf_range(1.5, 3.5) * (1.2 - struggle)


func _struggle_duration() -> float:
	return _rng.randf_range(0.8, 1.6) * (0.5 + struggle)
