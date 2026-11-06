class_name Weather
extends RefCounted
## 一夜的天气（只是表现，不影响上钩、搏斗和供奉）：天黑时定好今夜下不下雨、雨从第几秒下到第几秒、多大，
## 远处天上那群大鸟今夜飞不飞、第几秒飞过（一夜最多一次）。
## 一夜没有钟了（新回合机制第 40 条）：秒数按这一夜钓了多久算（FishingView._night_clock；契约书、制饵开着，看渔获时不走），
## 按一夜大约 NOMINAL_NIGHT 秒来排；唤祂、黄昏一到雨就停，没下完的就不下了。
## FishingView 用单独的随机数（_sky_rng）定天气，不碰游戏的随机数：同一个种子钓到什么、结局都不变。

const RAIN_CHANCE := 0.35                ## 一夜下雨的机会
const RAIN_START := Vector2(0.0, 0.5)    ## 雨在这一夜的哪一段开始（占一夜的比例）
const RAIN_LENGTH := Vector2(0.3, 0.7)   ## 下多久（占一夜的比例），下不过黄昏
const RAIN_PEAK := Vector2(0.55, 1.0)    ## 最大的时候多大（0~1）
const RAIN_RAMP := Vector2(6.0, 15.0)    ## 渐大、渐停各用多少秒：一夜的 8%，夹在这个范围里
const BIRDS_CHANCE := 0.5                ## 一夜飞过一回大鸟的机会
const BIRDS_WINDOW := Vector2(0.1, 0.65) ## 在这一夜的哪一段飞过
## 排天气时当一夜有多长（秒）：一夜五到七竿，两三分钟
const NOMINAL_NIGHT := 150.0

var night_seconds := NOMINAL_NIGHT   ## 排的时候按多长排
var rain_start := -1.0   ## 秒；< 0 = 今夜不下雨
var rain_end := -1.0
var rain_peak := 0.0
var rain_ramp := 10.0
var birds_at := -1.0     ## 秒；< 0 = 今夜不飞


static func plan(rng: RandomNumberGenerator, seconds: float) -> Weather:
	var w := Weather.new()
	w.night_seconds = seconds
	w.rain_ramp = clampf(seconds * 0.08, RAIN_RAMP.x, RAIN_RAMP.y)
	if rng.randf() < RAIN_CHANCE:
		w.rain_start = seconds * rng.randf_range(RAIN_START.x, RAIN_START.y)
		w.rain_end = minf(seconds, w.rain_start + seconds * rng.randf_range(RAIN_LENGTH.x, RAIN_LENGTH.y))
		w.rain_peak = rng.randf_range(RAIN_PEAK.x, RAIN_PEAK.y)
	if rng.randf() < BIRDS_CHANCE:
		w.birds_at = seconds * rng.randf_range(BIRDS_WINDOW.x, BIRDS_WINDOW.y)
	return w


func rains() -> bool:
	return rain_start >= 0.0


## 这一夜过了 elapsed 秒时雨多大（0~1）：渐大、下着、渐停
func rain_at(elapsed: float) -> float:
	if not rains():
		return 0.0
	var up := clampf((elapsed - rain_start) / rain_ramp, 0.0, 1.0)
	var down := clampf((rain_end - elapsed) / rain_ramp, 0.0, 1.0)
	var k := minf(up, down)
	return rain_peak * k * k * (3.0 - 2.0 * k)
