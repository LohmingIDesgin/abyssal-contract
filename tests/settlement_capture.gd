extends Node
## 契约结算的截图（核心调整 G4）：签约的帷幕（契约语下面的许汝之物、名册上的评价）、契约书（第四行许汝之物）、
## 偿清了的结算清单、从名册里点开看一位死了的。要出画面跑（不能 --headless）；截图写到 -- out=文件夹（默认 user://settlement_capture）：
##   Godot_v4.6.3-stable_win64.exe --path . --resolution 1280x720 res://tests/settlement_capture.tscn -- out=D:/tmp/settle
## 名册是摆出来的几位（只在内存里）；签约用模拟按键。不写试玩日志。跑之前把 APPDATA 指到别的空文件夹，
## 偿清以后会照常把名册存进 user://roster.json。

var fishing: Control
var out_dir := "user://settlement_capture"


func _ready() -> void:
	PlayLog._failed = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out_dir = arg.substr(4)
	DirAccess.make_dir_recursive_absolute(out_dir)
	GameState.roster.assign(_fake_roster())
	GameState.contractor = GameState._fresh_contractor()
	GameState.contractor.promise = "beloved"
	var main: Node = load("res://scenes/main/prototype_main.tscn").instantiate()
	add_child(main)
	fishing = main.get_node("钓鱼")
	fishing.capture_mouse = false
	await _wait(2.5)
	fishing._signing._hover = 2
	await _wait(0.3)
	await _save("signing")
	fishing._signing._hover = -1
	for ch in "Test":
		_key(KEY_NONE, true, ch.unicode_at(0))
		_key(KEY_NONE, false, ch.unicode_at(0))
	await _wait(0.3)
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, false)
	await _wait(5.5)
	fishing._toggle_contract()
	await _wait(3.5)
	await _save("contract")
	fishing._toggle_contract()
	await _wait(1.0)
	# 偿清：摆一份账，出结算清单
	var who: Contractor = GameState.contractor
	who.night = 7
	who.brands = who.config.brands
	who.tribute_total = 45300
	who.demand_total = 35500
	who.cuts = 1
	who.casts = 27
	who.cards_taken.assign(["spare_bait", "dissect", "evolve", "lure", "steady", "feast"])
	who.night = 7
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for kind in ["grey_dace:0", "grey_dace:1", "bloodtooth_pomfret:1", "bloodtooth_pomfret:2", "lantern_crone:1",
			"blind_bone_eel:0", "blind_bone_eel:2", "drowned_hand:1", "thousand_eye_catfish:2"]:
		who.offered_kinds[kind] = 1
	var best := CatchGenerator.generate(GameDB.get_fish("thousand_eye_catfish"), rng, null, 0, 2)
	best.stage = CatchData.Stage.ADULT
	best.level = 4
	best.affix_ids.assign(["soul_dense"])
	CatchGenerator.evaluate(best, GameDB.get_fish("thousand_eye_catfish"), GameDB.balance)
	who.best_offering = best
	fishing._settle("repaid")
	await _wait(2.6)
	await _save("settlement_mid")
	await _wait(5.0)
	await _save("settlement_repaid")
	fishing._settlement.confirm()
	await _wait(3.0)
	# 名册里点开一位死了的
	fishing._on_roster_opened(GameState.roster[1])
	await _wait(3.5)
	await _save("settlement_dead")
	get_tree().quit()


## 摆出来的名册：一位旧的（G4 以前，没有账）、一位落水的、一位被吞的、一位偿清了的
func _fake_roster() -> Array[Dictionary]:
	var old := {"number": 1, "name": "亚瑟", "night": 3, "status": "dead", "cause": "fall"}
	var fell := {"number": 2, "name": "Morrow", "promise": "fortune", "night": 4, "status": "dead", "cause": "fall",
		"tribute": 7900, "demand": 10000, "brands_lost": 2, "cuts": 1, "casts": 15, "cards": ["spare_bait", "lure", "steady"],
		"kinds": ["grey_dace:0", "grey_dace:1", "bloodtooth_pomfret:0", "blind_bone_eel:1"],
		"best": {"species": "blind_bone_eel", "stage": 1, "level": 2, "tribute": 9120, "body": 4.1, "affixes": [], "hue_shift": 0.0},
		"ability": 2, "rating": Settlement.DROWNED}
	var eaten := {"number": 3, "name": "伊芙", "promise": "years", "night": 5, "status": "dead", "cause": "offering",
		"tribute": 9200, "demand": 15500, "brands_lost": 3, "cuts": 0, "casts": 19, "cards": ["feast"],
		"kinds": ["grey_dace:0", "grey_dace:1"], "best": {}, "ability": 3, "rating": Settlement.BROKEN}
	var repaid := {"number": 4, "name": "Hollis", "promise": "memory", "night": 7, "status": "repaid", "cause": "repaid",
		"tribute": 43100, "demand": 35500, "brands_lost": 1, "cuts": 1, "casts": 28, "cards": ["evolve", "dissect", "vigor"],
		"kinds": ["grey_dace:1", "lantern_crone:2", "drowned_hand:2"],
		"best": {"species": "drowned_hand", "stage": 2, "level": 4, "tribute": 68400, "body": 18.6, "affixes": ["mutated"], "hue_shift": 0.0},
		"ability": 3, "rating": "守约"}
	return [old, fell, eaten, repaid]


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out_dir, name]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _key(keycode: int, pressed: bool, unicode := 0) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = pressed
	e.unicode = unicode
	Input.parse_input_event(e)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
