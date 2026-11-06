extends Node
## 全局数据库（Autoload: GameDB）。启动时从 data/ 下加载所有 .tres。

## 三层水（2026-11-03 定的：浅滩、中层合成浅层）。每层出几级的生物见 BalanceConfig.layer_levels
const DEPTH_NAMES: Array[String] = ["浅层", "深水", "渊底"]

var additives: Dictionary = {}    ## id → AdditiveData
var fish: Dictionary = {}         ## id → FishData
var affixes: Dictionary = {}      ## id → AffixData
var items: Dictionary = {}        ## id → ItemData
var promises: Dictionary = {}     ## id → PromiseData（许汝之物）
var cards: Dictionary = {}        ## id → RewardCard（供奉后的奖励卡）
## 玩法数值总表（data/balance.tres）
var balance: BalanceConfig


func _init() -> void:
	_load_dir("res://data/additives", additives)
	_load_dir("res://data/fish", fish)
	_load_dir("res://data/affixes", affixes)
	_load_dir("res://data/items", items)
	_load_dir("res://data/promises", promises)
	_load_dir("res://data/cards", cards)
	balance = load("res://data/balance.tres") as BalanceConfig
	## 读进来多少（导出的版本里查数据有没有跟着打进去：2026-11-06 试玩版缺了恩赐）
	var boons := cards.values().filter(func(c) -> bool: return c.permanent).size()
	var tagged := cards.values().filter(func(c) -> bool: return c.permanent and not c.tags.is_empty()).size()
	print("GameDB: 生物 %d 种、卡 %d 张（永久恩赐 %d，有引擎标签的 %d）、道具 %d、附加物 %d、许汝之物 %d" % [fish.size(), cards.size(),
		boons, tagged, items.size(), additives.size(), promises.size()])
	if balance == null:
		push_warning("GameDB: 读不到 data/balance.tres，用默认数值")
		balance = BalanceConfig.new()


func get_additive(id: String) -> AdditiveData:
	return additives.get(id)


## 用不完的基础款附加物（皮屑肉糜混合物）
func basic_additive() -> AdditiveData:
	for a: AdditiveData in sorted_values(additives):
		if a.unlimited:
			return a
	return null


func get_fish(id: String) -> FishData:
	return fish.get(id)


func get_affix(id: String) -> AffixData:
	return affixes.get(id)


func get_item(id: String) -> ItemData:
	return items.get(id)


func get_promise(id: String) -> PromiseData:
	return promises.get(id)


func get_card(id: String) -> RewardCard:
	return cards.get(id)


## 阶段 V 的名册草案（data/fish_draft/，还没有插图）：游戏里不出。整局模拟器（roster=draft）、测试要看加上它们以后的样子时
## 调 use_draft_fish()，用完 use_draft_fish(false) 拿掉。返回草案里有几种。插图到了，挪进 data/fish/、配上插图就是正式的
func use_draft_fish(on := true) -> int:
	var drafts := {}
	_load_dir("res://data/fish_draft", drafts)
	for id in drafts:
		if on:
			fish[id] = drafts[id]
		else:
			fish.erase(id)
	return drafts.size()


## 按 id 排序的列表，保证 UI 顺序稳定
func sorted_values(table: Dictionary) -> Array:
	var keys := table.keys()
	keys.sort()
	return keys.map(func(k): return table[k])


func _load_dir(path: String, target: Dictionary) -> void:
	for file in ResourceLoader.list_directory(path):
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var res := load(path.path_join(file))
		if res == null or not "id" in res or res.id == "":
			push_warning("GameDB: 跳过无效资源 %s" % path.path_join(file))
			continue
		if target.has(res.id):
			push_warning("GameDB: 重复的 id '%s' (%s)" % [res.id, file])
		target[res.id] = res
