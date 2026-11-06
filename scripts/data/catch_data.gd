class_name CatchData
extends Resource
## 钓上来的一条具体的生物（个体）。咬钩那一刻由 CatchGenerator 生成，之后各项都不再变：
## 搏斗里的临时削弱不会改变最后钓上来的东西（交接文档 §4.3）。继承 Resource 以便之后存档。

## 时期（核心调整，设计对照文档 8.2）：插图、躯体规模、灵魂强度、祭值都跟着变
enum Stage { JUVENILE, GROWING, ADULT }
const STAGE_NAMES: Array[String] = ["幼年期", "成长期", "成年期"]

@export var species_id: String
## 本体灵魂等级：决定降服难度
@export var level := 1
@export var stage := Stage.GROWING
## 躯体规模（2026-11-04 你定的，原来的重量）：一个数值，按 BalanceConfig.body_lines 分五档（body_class）。成年期是这一种的
## FishData.adult_body 那一档，成长期小一档、幼年期再小一档；带「变异」的再大一档。管饱腹和分解的材料，不管祭值
@export var body := 1.0
## 个头：躯体规模 ÷ 它那一档的平均数（约 0.4–2.1），只看这一条在这一档里长得大不大；分解的材料跟着它的平方根走
@export var size := 1.0
## 灵魂强度 0–100：越高祭值越高
@export var soul_strength := 30
@export var affix_ids: Array[String] = []
## 带「变色」时插图转到的色相（0–1，0 = 不变）
@export var hue_shift := 0.0

## 以下几项生成时一次算好，各管各的用途，不合成一个总分（§4.3）
## 祭值：献给祂值多少，黄昏供奉收的就是它（核心调整，设计对照文档 8.4；CatchGenerator.tribute_of）
@export var tribute := 0
## 生吞加多少饱腹：只看躯体规模和词条（核心调整 G3；交接文档里叫食粮值，G2 以前是供奉的货币）
@export var food := 1
## 能量（2026-11-04，原来的"食后成长"）：一个纯数值，只用来算祭值；等级越高越多，个体上下浮动（CatchGenerator）
@export var energy := 10
## 处理所得：材料id → 份数
@export var materials: Dictionary = {}
## 恩赐加的祭值比例（残躯为饵、异象收藏；v0.23）：祭值 × (1 + bonus)
@export var bonus := 0.0
## 留在船上占多少载荷（按时期）
@export var load_cost := 1


func species() -> FishData:
	return GameDB.get_fish(species_id)


func display_name() -> String:
	var s := species()
	return s.display_name if s else species_id


func stage_name() -> String:
	return STAGE_NAMES[clampi(stage, 0, STAGE_NAMES.size() - 1)]


## 这一条的插图（按时期）；种类没有插图时是 null
func art() -> Texture2D:
	var s := species()
	return s.stage_icon(stage) if s else null


## 带「变异」吗
func is_mutated() -> bool:
	return affix_ids.has("mutated")


## 躯体规模的五档（2026-11-04 你定的）：数值 0.1–0.5 小型、0.5–2.0 中型、2.0–5.0 大型、5.0–15.0 巨型、15.0 以上畸变
const BODY_NAMES: Array[String] = ["小型", "中型", "大型", "巨型", "畸变"]


## 躯体规模是哪一档（0 小型 … 4 畸变），按数值分（BalanceConfig.body_class_of）
func body_class(config: BalanceConfig = null) -> int:
	if config == null:
		config = GameDB.balance
	return config.body_class_of(body)


func body_name() -> String:
	return BODY_NAMES[clampi(body_class(), 0, BODY_NAMES.size() - 1)]


## 躯体规模的数值写成字："0.23"、"1.40"、"3.2"、"26.4"（2 以下写两位小数）
func body_text() -> String:
	return "%.2f" % body if body < 2.0 else "%.1f" % body


func affix_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for id in affix_ids:
		var affix := GameDB.get_affix(id)
		names.append(affix.display_name if affix else id)
	return names


## 写日志用的扁平字典
func summary() -> Dictionary:
	return {
		"species": species_id, "level": level, "stage": stage, "body": snappedf(body, 0.01), "size": snappedf(size, 0.01),
		"soul": soul_strength, "affixes": Array(affix_ids), "tribute": tribute, "food": food,
		"energy": energy, "body_class": body_class(), "materials": materials.duplicate(), "load": load_cost, "bonus": bonus,
	}
