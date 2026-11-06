class_name AffixData
extends Resource
## 生物个体身上的词条（交接文档 §4.2）。在 data/affixes/ 下新建 .tres 即可添加。
## 词条只改变用途上的数值，不改变捕猎难度（§4.3：好吃的、值钱的不必更难钓）。
## 普通词条（额外词条）按 weight 抽，一条最多一个；特殊词条（special：变色、变异）不参加抽取，各按自己的 chance 单独掷，
## 插图跟着变（shaders/creature_display.gdshader）。

@export var id: String
@export var display_name: String
@export_multiline var description: String
## 出现权重，越小越少见（普通词条）
@export var weight := 1.0
## 生吞时加的饱腹的倍率（多肉 1.4、枯瘦 0.6）
@export var food_mult := 1.0
## 能量的倍率（2026-11-04：原来的成长倍率；能量只用来算祭值）。现在都是 1，「魂蕴」靠多加的灵魂强度（soul_bonus）值钱
@export var energy_mult := 1.0
## 处理时各类材料的倍率：材料id → 倍率，没写的按 1
@export var material_mults: Dictionary = {}
## 祭值加成：0.12 = +12%
@export var tribute_bonus := 0.0
## 灵魂强度多加多少（魂蕴 +20）
@export var soul_bonus := 0.0
## 特殊词条：不参加普通词条的抽取，每条渔获按 chance 单独掷
@export var special := false
@export_range(0.0, 1.0) var chance := 0.0
