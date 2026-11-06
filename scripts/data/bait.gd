class_name Bait
extends Resource
## 一份做好的饵料：两份基础材料 + 一份附加物（交接文档 §5.1），由 BaitCrafter 做出来。继承 Resource 以便之后直接存档。
## 两份基础材料不分先后，一共六种基础组合（§5.2）：基础组合决定大致钓到哪一类，附加物再往喜欢它气味的那边推。
## 万能饵（universal，新回合机制第 33 条）不用材料：开局和每次供奉以后发，哪一层都能用，咬钩的按生物本来的稀有度来。

@export var display_name: String
## 两份基础材料的 id（Materials），按 Materials.ALL 的顺序排好，例如 ["flesh", "shell"]
@export var bases: Array[String] = []
@export var additive_id := ""
## 万能饵：没有基础材料和附加物
@export var universal := false
## 这一叠还剩几份（一份挂一次，真有生物咬钩才扣；新回合机制第 30 条）
@export var uses := 1


func additive() -> AdditiveData:
	return GameDB.get_additive(additive_id)


## 基础材料的占比，例如 血肉 + 矿壳 → {flesh: 0.5, shell: 0.5, glow: 0}
func base_share() -> Dictionary:
	var share := Materials.empty_ratio()
	for m in bases:
		share[m] += 1.0 / bases.size()
	return share


## 同一个配方（基础组合和附加物都一样；万能饵和万能饵），做出来的饵叠在一起
func same_recipe(other: Bait) -> bool:
	return other != null and other.universal == universal and other.bases == bases and other.additive_id == additive_id
