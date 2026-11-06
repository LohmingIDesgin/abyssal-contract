class_name FishData
extends Resource
## 冥海里能钓上来的一种生物（种类）。在 data/fish/ 下新建 .tres 即可添加。
## 钓上来的每一条都是一个个体（CatchData），时期、重量、灵魂强度、词条在下面的范围里随机；灵魂等级跟着时期走（stage_levels）。
## 出没在哪层水不再单写：每层水出几级的生物是定好的（BalanceConfig.layer_levels），这一种哪个时期是几级，就在出那一级的水里出现（WaterLayers）。

@export var id: String
@export var display_name: String
@export_multiline var description: String
## 渔获卡片和图鉴上的插图（成长期），可以不填；幼年期、成年期另有一张，没有就用这张
@export var icon: Texture2D
@export var icon_juvenile: Texture2D
@export var icon_adult: Texture2D

@export_group("上钩")
## 气味（Aspect 的 id）→ 偏好 −1~1。负数表示讨厌：附加物带着这种气味时，喜欢的更容易咬钩，讨厌的躲开（BiteCalculator）
@export var preferences: Dictionary = {}
## 基础出现权重，越小越稀有（和同一层水里同一级的别的种类比）
@export var rarity_weight := 1.0
## 只在这些夜里出（阶段 V）：海况 "calm" / "rough" / "eerie"、"blood_moon"（迎着血月钓的那一夜）；空的是哪一夜都在。
## 看的是契约者这一夜的数值表（BalanceConfig.night_sea、night_blood_moon）；总表（图鉴）里这一种不出
@export var appears_when: PackedStringArray = []

@export_group("搏斗")
## 挣扎强度 0~1，供张力小游戏使用
@export_range(0.0, 1.0) var struggle := 0.3
## 鱼的耐力（不显示），张力保持在甜区时每秒约消耗 1 点；耗尽后不再挣扎。和契约者的体力不是一回事
@export var endurance := 6.0

@export_group("个体")
## 灵魂等级范围：幼年期是下限，成年期是上限，成长期在中间（stage_levels，2026-11-03 定的）
## 特殊词条（变色、变异）的机会再乘几（阶段 V：无面鲂）
@export var special_mult := 1.0
@export_range(1, 9) var level_min := 1
@export_range(1, 9) var level_max := 1
## 成年期的躯体规模（这一种的上限，2026-11-04 你定的）：0 小型、1 中型、2 大型、3 巨型、4 畸变。成长期小一档、幼年期再小一档，
## 最小到小型；带「变异」的再大一档（CatchGenerator.body_class_for）。每一档的数值范围见 BalanceConfig.body_lines
@export_enum("小型", "中型", "大型", "巨型", "畸变") var adult_body := 2

@export_group("用途")
## 1 级、中等个头时处理出来的材料总份数
@export var yield_base := 4.0
## 处理时三类材料的比例：材料id → 份额，自动归一（Materials）
@export var material_ratio: Dictionary = {"flesh": 1.0, "shell": 1.0, "glow": 1.0}

@export_group("祭值")
## 种类基础值：祭值 = 基础值 × 时期系数 × 能量 ÷ 10 × (1.5 + 灵魂强度 × 0.05) × 词条加成（CatchGenerator.tribute_of）。
## 2026-11-03 起原来的"种族加成"去掉了；2026-11-04 起等级通过能量算进祭值（BalanceConfig.energy_by_level）
@export var tribute_base := 300.0

@export_group("展示")
## 插图怎么动（2026-11-05，CreatureArt.STYLES）：fish 鱼、eel 鳗、lantern 灯笼（头灯）、hand 手、jelly 水母、puffer 鲀、
## crab 蟹、flat 扁的（鳐、鲽，从上往下看）、shell 螺、whale 鲸。鳍、须、手指、头灯这些附肢在哪，是 tools/bake_motion_masks.py
## 从插图烘出来的（assets/creatures/motion/），新加的插图跑一遍那个工具
@export_enum("fish", "eel", "lantern", "hand", "jelly", "puffer", "crab", "flat", "shell", "whale") var motion_style: String = "fish"
## 头上细长的东西（须、头灯的柄）单独摆（千目窥渊鲶、磷灯婆）。会游的种类头上别的（嘴、吻、牙）都不单独摆，
## 光看形状分不出须和尖嘴，所以由种类自己说。改了要重跑 tools/bake_motion_masks.py
@export var motion_head_limbs := false
## 身子摆动的幅度（占插图高度的比例；鱼、鳗、鲸是尾部，灯笼、鲀是尾巴，扁的是两侧的边）
@export var motion_amplitude := 0.03
## 每秒摆几下
@export var motion_speed := 1.2
## 摆动的波长，按身长算：越小身上同时出现的弯越多（鳗）
@export var motion_wavelength := 1.3


## 这个时期（CatchData.Stage：0 幼年、1 成长、2 成年）是哪一档躯体规模（不算「变异」）：成年期是 adult_body，
## 往前每个时期小一档，最小到小型
func stage_body(stage: int) -> int:
	return clampi(adult_body - (2 - stage), 0, 4)


## 这个时期（CatchData.Stage）是几级：[低, 高]，一样就是定的。幼年期是最低等级，成年期是最高等级，成长期在中间：
## 灰鲦 1 级三个时期都是 1 级；磷灯婆 1–3 级是 1、2、3；只差一级的（血齿冥鲳 1–2）成长期两级都有可能（[1, 2]：
## 灵魂强度过了门槛的是 2 级，CatchGenerator）
func stage_levels(stage: int) -> Vector2i:
	if stage <= 0:
		return Vector2i(level_min, level_min)
	if stage >= 2:
		return Vector2i(level_max, level_max)
	var span := level_max - level_min
	var low := level_min + span / 2
	return Vector2i(low, low + span % 2)


## 这一夜（契约者这一夜的数值表）它在不在：appears_when 里有一条对得上就在，空的一直在
func appears_in(config: BalanceConfig) -> bool:
	if appears_when.is_empty():
		return true
	for w in appears_when:
		if (w == "blood_moon" and config.night_blood_moon) or (w != "blood_moon" and w == config.night_sea):
			return true
	return false


## 这个时期（CatchData.Stage）的插图；没有单独画的用成长期那张
func stage_icon(stage: int) -> Texture2D:
	if stage == 0 and icon_juvenile:
		return icon_juvenile
	if stage == 2 and icon_adult:
		return icon_adult
	return icon


## 对一种气味的偏好，没写就是 0
func preference(aspect: String) -> float:
	return float(preferences.get(aspect, 0.0))
