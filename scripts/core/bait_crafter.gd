class_name BaitCrafter
extends RefCounted
## 制饵（交接文档 §5）：两份基础材料（血肉 / 矿壳 / 幽光，任选、可以重复）+ 一份附加物 = 一份饵，
## 能挂钩 balance.bait_uses 次（一次）。材料和附加物从契约者身上扣；基础款附加物用不完。
## 万能饵不是做出来的：开局和每次供奉以后直接发（make_universal）。
## 全部是静态函数，界面、测试、整局模拟器调用同一套。

## 六种基础组合的名字（两份基础材料不分先后）
const COMBO_NAMES := {
	"flesh+flesh": "腥糜", "flesh+shell": "血骨", "flesh+glow": "血萤",
	"shell+shell": "骨渣", "shell+glow": "骨萤", "glow+glow": "萤浆",
}


## 按 Materials.ALL 的顺序排好，这样 血肉 + 矿壳 和 矿壳 + 血肉 是同一种
static func normalize(bases: Array) -> Array[String]:
	var result: Array[String] = []
	for m in Materials.ALL:
		for b in bases:
			if b == m:
				result.append(m)
	return result


## 基础组合，例如 "flesh+shell"
static func combo_key(bases: Array) -> String:
	return "+".join(normalize(bases))


## 起名：附加物的字 · 基础组合 + "饵"，例如 "甲·骨渣饵"；基础款没有字，就是 "腥糜饵"
static func name_for(bases: Array, additive: AdditiveData) -> String:
	var combo: String = COMBO_NAMES.get(combo_key(bases), "杂")
	if additive and additive.name_token != "":
		return "%s·%s饵" % [additive.name_token, combo]
	return combo + "饵"


const UNIVERSAL_NAME := "万能饵"


## 几份万能饵叠成一叠（开局、每次供奉以后发的）
static func make_universal(count: int) -> Bait:
	var b := Bait.new()
	b.universal = true
	b.uses = count
	b.display_name = UNIVERSAL_NAME
	return b


## 不扣东西，直接给一份（测试用）
static func make(bases: Array, additive_id: String, config: BalanceConfig = null) -> Bait:
	if config == null:
		config = GameDB.balance
	var b := Bait.new()
	b.bases = normalize(bases)
	b.additive_id = additive_id
	b.uses = config.bait_uses
	b.display_name = name_for(b.bases, GameDB.get_additive(additive_id))
	return b


## 两份基础材料、一份附加物都齐了，契约者身上也够
static func can_craft(who: Contractor, bases: Array, additive_id: String) -> bool:
	if bases.size() != 2 or GameDB.get_additive(additive_id) == null:
		return false
	return who.can_afford(normalize(bases), additive_id)


## 做一份：扣两份基础材料和附加物，返回做好的饵；做不了返回 null，什么也不扣
static func craft(who: Contractor, bases: Array, additive_id: String) -> Bait:
	if not can_craft(who, bases, additive_id):
		return null
	who.spend(normalize(bases), additive_id)
	var bait := make(bases, additive_id, who.config)
	## 饵心（恩赐）：两份相同的基础材料做的，这一夜头一回多给 amount 份
	if bases.size() == 2 and bases[0] == bases[1] and who.boon_ready("bait_heart"):
		who.use_boon("bait_heart")
		bait.uses += roundi(who.boon_amount("bait_heart"))
	return bait
