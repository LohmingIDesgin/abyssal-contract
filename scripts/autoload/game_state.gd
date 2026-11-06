extends Node
## 玩家进度（Autoload: GameState）。
## 饵料篓、各种渔获钓上过几条（以后的图鉴用）、名册，以及当前的契约者（灵魂等级、船舱、材料、契约周期，见 Contractor）。
## 契约者死了或者契约已偿，就换下一位：除了名册和图鉴（catches），什么都不留（设计对照文档 3.1 第 1 条）。
## 名册存在 user://roster.json，关了游戏还在（第一版只存名册）；正在进行的那一位不存，下次打开重新签约。
## 名册的每一条是那一位的结算清单（Settlement.record，核心调整 G4）。

signal baits_changed
signal catch_recorded(fish: FishData)
## 换了一位契约者（旧的那位的 changed 信号不会再发，界面要重新连到新的上）
signal contractor_changed

var baits: Array[Bait] = []
var catches: Dictionary = {}  ## 鱼id → 钓上过几条
var contractor: Contractor
## 名册：走了的契约者，按先后。每条是结算清单（Settlement.record）：{number, name, promise, night, status（"dead" / "repaid"）, cause, ……}；
## cause 是 "fall"（落水）、"offering"（供奉不足被吞掉）、"repaid"（契约已偿）
var roster: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()  ## 分许汝之物用

const ROSTER_PATH := "user://roster.json"


func _ready() -> void:
	_rng.randomize()
	roster = Roster.load_from(ROSTER_PATH)
	contractor = _fresh_contractor()
	_give_starter_bait()


## 下一位契约者：编号接着名册往下排；许汝之物随机分一样，和上一位的不一样
func _fresh_contractor() -> Contractor:
	var next := Contractor.new(GameDB.balance)
	next.number = Roster.next_number(roster)
	next.promise = _roll_promise()
	return next


func _roll_promise() -> String:
	var last: String = str(roster[-1].get("promise", "")) if not roster.is_empty() else ""
	var ids: Array = GameDB.promises.keys().filter(func(id: String) -> bool: return id != last)
	ids.sort()
	if ids.is_empty():
		return last
	return ids[_rng.randi_range(0, ids.size() - 1)]


## 开局送几份万能饵（新回合机制第 34 条：三份，对应三次起手的机会）
func _give_starter_bait() -> void:
	add_bait(BaitCrafter.make_universal(GameDB.balance.start_baits))


## 当前的契约者走了：这一位的结算清单（Settlement.record）记进名册并存盘，换下一位。
## 饵料篓清空，重新给一份开局的饵
func next_contractor(record: Dictionary) -> void:
	roster.append(record)
	Roster.save_to(ROSTER_PATH, roster)
	contractor = _fresh_contractor()
	baits.clear()
	_give_starter_bait()
	contractor_changed.emit()


## 放进饵料篓；同一个配方的叠在一起
func add_bait(bait: Bait) -> void:
	for b in baits:
		if b.same_recipe(bait):
			b.uses += bait.uses
			baits_changed.emit()
			return
	baits.append(bait)
	baits_changed.emit()


## 用掉一次，用完从饵料篓移除
func consume_bait(bait: Bait) -> void:
	bait.uses -= 1
	if bait.uses <= 0:
		baits.erase(bait)
	baits_changed.emit()


func record_catch(fish: FishData) -> void:
	catches[fish.id] = catches.get(fish.id, 0) + 1
	catch_recorded.emit(fish)
