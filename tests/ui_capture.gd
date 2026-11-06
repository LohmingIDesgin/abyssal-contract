extends Node
## 2026-11-03 几处界面小改的截图：契约书里选中一条时材料后面的 +N、咬钩时的 QTE（[空格] 提竿！和收拢的细线）、
## 捞上来的东西像渔获一样亮相、收下以后。要出画面跑（不能 --headless）；截图写到 -- out=文件夹（默认 user://ui_capture）：
##   Godot_v4.6.3-stable_win64.exe --path . --resolution 1280x720 res://tests/ui_capture.tscn -- out=D:/tmp/ui
## 签约用模拟按键；咬钩和捞到东西是直接摆好这一竿（不抛竿）。不写试玩日志。跑之前把 APPDATA 指到别的空文件夹。

var fishing: Control
var out_dir := "user://ui_capture"


func _ready() -> void:
	PlayLog._failed = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out_dir = arg.substr(4)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var main: Node = load("res://scenes/main/prototype_main.tscn").instantiate()
	add_child(main)
	fishing = main.get_node("钓鱼")
	fishing.capture_mouse = false
	await _wait(1.0)
	for ch in "Test":
		_key(KEY_NONE, true, ch.unicode_at(0))
		_key(KEY_NONE, false, ch.unicode_at(0))
	await _wait(0.3)
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, false)
	await _take_opening()
	await _wait(6.0)
	var who: Contractor = GameState.contractor
	# 契约书：船舱里放两条，选中第二条，材料后面写处理了能拿到几份
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	who.materials = {"flesh": 1, "shell": 0, "glow": 2}
	who.hold.append(CatchGenerator.generate(GameDB.get_fish("lantern_crone"), rng, null, 0, 0))
	who.hold.append(CatchGenerator.generate(GameDB.get_fish("grey_dace"), rng, null, 0, 0))
	fishing._toggle_contract()
	await _wait(2.5)
	fishing._contract.move_selection(1)
	await _wait(0.6)
	await _save("contract_gain")
	fishing._toggle_contract()
	await _wait(1.0)
	# 咬钩：直接摆好这一竿，等浮漂沉下去，截 QTE
	var dace := GameDB.get_fish("grey_dace")
	_set_up_bite(dace, CatchGenerator.generate(dace, rng, null, 0, 0), "")
	await _wait(0.6)
	await _save("bite_qte")
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	await _wait(0.4)
	fishing._finish("（截图）", Gothic.BONE)
	fishing._enter_ready()
	await _wait(1.0)
	# 捞到东西：浮漂沉下去（QTE 写"拉上来"），提起来以后亮相，空格收下
	_set_up_bite(null, null, "soul_thread")
	await _wait(0.6)
	await _save("salvage_qte")
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	await _wait(2.4)
	await _save("item_reveal")
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	await _wait(1.4)
	await _save("item_taken")
	# 海上事件（阶段 IV）：船舱里放几条，冥市船、祂的低语、残骸各截一张；冥市船买下恩赐，看左下那一行
	var ev_who: Contractor = GameState.contractor
	var ev_rng := RandomNumberGenerator.new()
	ev_rng.seed = 4
	ev_who.night = 3
	for spec in [["grey_dace", 1], ["bloodtooth_pomfret", 1], ["blind_bone_eel", 2]]:
		ev_who.hold.append(CatchGenerator.generate(GameDB.get_fish(spec[0]), ev_rng, GameDB.balance, 0, spec[1]))
	ev_who.changed.emit()
	for id in ["trade", "whisper", "wreck"]:
		fishing._event_id = id
		fishing._open_event()
		await _wait(2.6)
		await _save("event_" + id)
		if id == "trade":
			_key(KEY_1, true)
			_key(KEY_1, false)
			await _wait(1.4)
			await _save("event_trade_done")
		else:
			_key(KEY_SPACE, true)
			_key(KEY_SPACE, false)
			await _wait(1.4)
		fishing._enter_ready()
		await _wait(0.4)
	get_tree().quit()


## 把这一竿摆成"等着咬钩"：fish / c 是咬钩的生物和个体（捞到东西时是 null），salvage 是捞到的东西的 id
func _set_up_bite(fish: FishData, c: CatchData, salvage: String) -> void:
	fishing._bait = fishing._selected_bait()
	fishing._target = fish
	fishing._catch = c
	fishing._gap = 0.0
	fishing._salvage = salvage
	fishing._depth = 0
	fishing._nibbles.clear()
	fishing._cast_flight = 0.0
	fishing._timer = 0.3
	fishing._phase = fishing.Phase.WAITING
	fishing._water.view = WaterView.View.FLOAT


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

## 签约以后的开局恩赐（v0.23）：等它打开，挑第一张收下
func _take_opening() -> void:
	for i in 40:
		if fishing._reward.is_open:
			break
		await _wait(0.15)
	if not fishing._reward.is_open:
		return
	await _wait(0.8)
	_key(KEY_1, true)
	_key(KEY_1, false)
	await _wait(0.4)
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	await _wait(1.2)
