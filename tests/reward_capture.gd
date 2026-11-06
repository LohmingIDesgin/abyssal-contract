extends Node
## H2 奖励卡的截图：挑供品时的超额线、供奉后的补给与奖励卡（三张候选挑中一张、两张、没凑够只有补给）、
## 契约书里"带着「镇魂」"、引深引上来的（咬钩、一路收上来）、进化以后的渔获展示。要出画面跑（不能 --headless）；
## 截图写到 -- out=文件夹（默认 user://reward_capture）：
##   Godot_v4.6.3-stable_win64.exe --path . --resolution 1280x720 res://tests/reward_capture.tscn -- out=D:/tmp/reward
## 签约用模拟按键；黄昏、奖励卡、这一竿都是直接摆好的（不抛竿）。不写试玩日志。跑之前把 APPDATA 指到别的空文件夹。

var fishing: Control
var out_dir := "user://reward_capture"
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	PlayLog._failed = true
	rng.seed = 21
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

	# 黄昏：船舱里三条，挑两条过了超额线
	for spec in [["lantern_crone", 2], ["bloodtooth_pomfret", 1], ["grey_dace", 2]]:
		who.hold.append(CatchGenerator.generate(GameDB.get_fish(spec[0]), rng, null, 0, -1, {"stage": spec[1],
			"level": GameDB.get_fish(spec[0]).stage_levels(spec[1]).x}))
	fishing._enter_dusk()
	await _wait(9.0)
	fishing._offering.toggle(0)
	fishing._offering.toggle(1)
	await _wait(0.6)
	await _save("offering_over")

	# 供奉后的补给与奖励卡：超额三张，挑中第二张
	fishing._offering.visible = false
	fishing._offering.is_open = false
	var over := {"met": true, "tribute": 3200, "demand": 1600, "supply": 3}
	fishing._reward.open(who, over, _cards(["lure", "evolve", "steady"]))
	await _wait(2.6)
	await _save("reward_three")
	fishing._reward.pick(1)
	await _wait(0.6)
	await _save("reward_picked")
	# 够了两张
	fishing._reward.open(who, {"met": true, "tribute": 1700, "demand": 1600, "supply": 3}, _cards(["vigor", "spare_bait"]))
	await _wait(2.6)
	await _save("reward_two")
	# 没凑够：只有补给
	fishing._reward.open(who, {"met": false, "tribute": 0, "demand": 1600, "supply": 3}, _cards([]))
	await _wait(2.4)
	await _save("reward_none")
	fishing._reward.visible = false
	fishing._reward.is_open = false
	fishing._night_falls()
	await _wait(3.5)

	# 契约书：带着「镇魂」
	who.take_card(GameDB.get_card("steady"))
	fishing._toggle_contract()
	await _wait(2.5)
	await _save("contract_card")
	# 右边一列恩赐（2026-11-05）：再拿几样，鼠标放到第二样上看说明
	for id in ["bone_pick", "carcass", "taut_line", "crown_catch", "regular"]:
		if not who.has_boon(id):
			who.take_card(GameDB.get_card(id))
	await _wait(0.4)
	fishing._contract._boon_hover = 1
	await _wait(0.4)
	await _save("contract_boons")
	fishing._contract._boon_hover = -1
	fishing._toggle_contract()
	await _wait(1.0)
	who.card_effects.clear()

	# 引深：咬钩的换成高一级的，提竿以后一路收上来
	who.take_card(GameDB.get_card("lure"))
	var lured := CatchGenerator.generate_at_level(who.ability + 1, null, rng)
	who.use_card("lure")
	_set_up_bite(lured.species(), lured, true)
	await _wait(0.6)
	await _save("lure_bite")
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	await _wait(0.9)
	await _save("lure_reel")
	await _wait(3.2)
	await _save("lure_catch")
	fishing._reveal.decide("dismantle")
	await _wait(1.6)

	# 进化：钓上来的幼年磷灯婆长一个时期
	who.take_card(GameDB.get_card("evolve"))
	fishing._catch = CatchGenerator.generate(GameDB.get_fish("lantern_crone"), rng, null, 0, -1, {"stage": 0, "level": 1})
	fishing._target = fishing._catch.species()
	fishing._show_catch()
	await _wait(2.6)
	await _save("evolve_catch")
	get_tree().quit()


func _cards(ids: Array) -> Array[RewardCard]:
	var list: Array[RewardCard] = []
	for id in ids:
		list.append(GameDB.get_card(id))
	return list


## 把这一竿摆成"等着咬钩"
func _set_up_bite(fish: FishData, c: CatchData, lured: bool) -> void:
	fishing._bait = fishing._selected_bait()
	fishing._target = fish
	fishing._catch = c
	fishing._gap = GameDB.balance.fight_gap(GameState.contractor.ability, c.level)
	fishing._salvage = ""
	fishing._lured = lured
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

## 签约以后的开局恩赐（v0.23）：等它打开，截一张（opening），挑第一张收下
func _take_opening() -> void:
	for i in 40:
		if fishing._reward.is_open:
			break
		await _wait(0.15)
	if not fishing._reward.is_open:
		return
	await _wait(2.4)
	await _save("opening")
	_key(KEY_1, true)
	_key(KEY_1, false)
	await _wait(0.4)
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	await _wait(1.2)
