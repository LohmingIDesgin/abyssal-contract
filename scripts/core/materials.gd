class_name Materials
extends RefCounted
## 三类基础材料（交接文档 §4.1）。所有冥海生物处理后都会出这三类，只是比例不同。
## 材料数量、生物的材料比例都用 { 材料id: 数值 } 的 Dictionary 表示。

const FLESH := "flesh"  ## 血肉质：异常的肌肉、脏器和血液
const SHELL := "shell"  ## 矿壳质：吸收海中沉积物长成的骨骼与外壳
const GLOW := "glow"    ## 幽光质：特殊器官里存着的海中异常能量

const ALL: Array[String] = [FLESH, SHELL, GLOW]

const DISPLAY := {FLESH: "血肉质", SHELL: "矿壳质", GLOW: "幽光质"}
const SHORT := {FLESH: "血肉", SHELL: "矿壳", GLOW: "幽光"}
const COLORS := {FLESH: Color("b8352a"), SHELL: Color("b9a27a"), GLOW: Color("4fe0bf")}
## 印在浅色羊皮纸上时用的深一些的颜色
const INK_COLORS := {FLESH: Color("7a1c14"), SHELL: Color("5c4a2a"), GLOW: Color("1d6b5a")}


static func empty() -> Dictionary:
	var result := {}
	for m in ALL:
		result[m] = 0
	return result


## 三类都是 0.0 的比例表
static func empty_ratio() -> Dictionary:
	var result := {}
	for m in ALL:
		result[m] = 0.0
	return result


## 三类各占三分之一
static func even_ratio() -> Dictionary:
	var result := {}
	for m in ALL:
		result[m] = 1.0 / ALL.size()
	return result


## 把比例表归一（总和为 1，负数当 0）；全是 0 时三类平分
static func normalized(ratio: Dictionary) -> Dictionary:
	var total := 0.0
	for m in ALL:
		total += maxf(float(ratio.get(m, 0.0)), 0.0)
	if total <= 0.0:
		return even_ratio()
	var result := {}
	for m in ALL:
		result[m] = maxf(float(ratio.get(m, 0.0)), 0.0) / total
	return result


## "血肉 3 · 矿壳 5 · 幽光 1"
static func format(counts: Dictionary) -> String:
	var parts: PackedStringArray = []
	for m in ALL:
		parts.append("%s %d" % [SHORT[m], counts.get(m, 0)])
	return " · ".join(parts)
