class_name Aspect
extends RefCounted
## 气味。每种附加物带一种气味（AdditiveData.aspect），生物对各种气味有偏好（FishData.preferences，−1~1）；
## 偏好表用 { 气味id: 数值 } 的 Dictionary 表示，id 为下面的字符串常量。

const ROT := "rot"        ## 腐：腐败、发酵
const BLOOD := "blood"    ## 血：鲜活、肉腥
const EYE := "eye"        ## 瞳：窥视、异视
const GRUDGE := "grudge"  ## 怨：亡者执念
const COLD := "cold"      ## 寒：深渊冷意
const FILTH := "filth"    ## 秽：人味、污浊
const GLOW := "glow"      ## 磷：幽光、诱引

const ALL: Array[String] = [ROT, BLOOD, EYE, GRUDGE, COLD, FILTH, GLOW]

const DISPLAY := {
	ROT: "腐", BLOOD: "血", EYE: "瞳", GRUDGE: "怨",
	COLD: "寒", FILTH: "秽", GLOW: "磷",
}

const COLORS := {
	ROT: Color("7a9a3a"), BLOOD: Color("b02a2a"), EYE: Color("d4af37"),
	GRUDGE: Color("7b68c8"), COLD: Color("5fa8d3"), FILTH: Color("8b6f47"),
	GLOW: Color("6fe8c0"),
}


static func display_name(aspect: String) -> String:
	return DISPLAY.get(aspect, aspect)

