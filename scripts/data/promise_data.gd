class_name PromiseData
extends Resource
## 许汝之物（核心调整 G4，设计对照文档 8.1）：签约时祂答应还给这位契约者的东西。每位契约者随机分到一样，
## 签约的帷幕、契约书里写在契约语下面（英文手写，下面灰色中文批注），偿清时结算清单上写"祂归还了：……"。
## 第一版只是叙事，不改玩法。在 data/promises/ 下新建 .tres 即可添加。

@export var id: String
## 短名：寿数、财富……（名册、日志用）
@export var display_name: String
## 契约上的英文手写句
@export var line: String
## 那样东西（中文），批注和结算里套进句子："被夺走的寿数"
@export var thing: String


## 契约语下面的灰色批注："许汝之物：被夺走的寿数。"
func note() -> String:
	return "许汝之物：%s。" % thing


## 祂的返还（阶段 V，2026-11-04）：偿清时还回来是什么样子，跟着结算的评价走——献心、虔诚、守约、勉强各一句。
## 献心多还一点，虔诚分毫不差，守约还回来了却有点不对，勉强还回来的已经变了样。超额供奉、不丢烙印才拿得到前两种
@export var returns: PackedStringArray = []

## returns 的四句对应的评价
const RETURN_ORDER: Array[String] = ["献心", "虔诚", "守约", "勉强"]


## 偿清时结算清单上的一句：按评价挑 returns 里的那一句；没写、或者评价不在四档里，就是"祂归还了：被夺走的寿数。"
func returned_text(rating := "") -> String:
	var i := RETURN_ORDER.find(rating)
	if i >= 0 and i < returns.size() and returns[i] != "":
		return returns[i]
	return "祂归还了：%s。" % thing
