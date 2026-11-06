extends Node
## 渔获展示的截图：几条摆好的渔获（不同种类、时期，带「变色」「变异」的）依次在展示画面里亮相（每一张契约者饿的程度不同，
## 看右上的体力、饱腹管和展示里的饱腹、食后成长），
## 再饿着打一场截右上的仪表（体力管饿掉的一截、饱腹管发红），再放进船舱截契约书、截黄昏供奉。
## 一开始还截一张刚签约时的道具栏（三份万能饵、"唤祂"那一格）和唤祂的确认。要出画面跑（不能 --headless）；截图写到 -- out=文件夹（默认 user://catch_capture）：
##   Godot_v4.6.3-stable_win64.exe --path . --resolution 1280x720 res://tests/catch_capture.tscn -- out=D:/tmp/catch
## 签约用模拟按键（和 tests/showcase.gd 一样）；不写试玩日志，契约没结束也不会写名册。

## 名字、种类、等级、时期、特殊词条（"" 没有）、普通词条（"" 没有）、那时契约者的饱腹
const SHOTS := [
	["dace_juvenile", "grey_dace", 1, CatchData.Stage.JUVENILE, "", "", 45.0],
	["eel_adult", "blind_bone_eel", 3, CatchData.Stage.ADULT, "", "soul_dense", 95.0],
	["crone_recolored", "lantern_crone", 2, CatchData.Stage.GROWING, "recolored", "", 20.0],
	["hand_mutated", "drowned_hand", 4, CatchData.Stage.ADULT, "mutated", "blood_rich", 72.0],
]
const HOLD_HUNGER := 25.0  ## 截契约书时的饱腹（饿得发慌）

var fishing: Control
var out_dir := "user://catch_capture"


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
	fishing.set_process(false)
	var who: Contractor = GameState.contractor
	# 刚签约：道具栏上三份万能饵、"唤祂"那一格；再按一下唤祂，截确认（然后取消）
	await _save("hud_start")
	fishing._request_summon()
	await _wait(0.8)
	await _save("summon_prompt")
	fishing._summon.cancel()
	await _wait(0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var catches: Array[CatchData] = []
	for shot in SHOTS:
		var c := _make(shot, rng)
		catches.append(c)
		who.hunger = shot[6]
		print("%s：%s %s %d级 %s 灵魂强度 %d 能量 %d 祭值 %d 饱腹 +%d 词条 %s（契约者饱腹 %.0f）" % [shot[0], c.display_name(),
			c.stage_name(), c.level, c.body_name(), c.soul_strength, c.energy, c.tribute, c.food, c.affix_names(), who.hunger])
		fishing._reveal.show_catch(c, who)
		await _wait(2.2)
		await _save("reveal_" + shot[0])
		await fishing._reveal.play_exit("eat")
		await _wait(0.4)
	# 饿得发慌时打一场：收两秒线，截右上的仪表
	who.hunger = 20.0
	fishing._target = GameDB.get_fish(catches[1].species_id)
	fishing._catch = catches[1]
	fishing._gap = 0
	fishing._depth = 1
	fishing._salvage = ""
	fishing._hook()
	fishing._holding = true
	for i in 40:
		fishing._process_reeling(0.05)
	await _wait(1.2)
	await _save("fight_hungry")
	fishing._holding = false
	fishing._enter_ready()
	await _wait(0.5)
	# 船舱（契约书）和供奉：船舱放大一点装得下这几条
	who.config.hold_capacity = 30
	who.hold.clear()
	who.hunger = HOLD_HUNGER
	for c in catches:
		who.hold.append(c)
	fishing._toggle_contract()
	await _wait(2.0)
	await _save("hold")
	fishing._toggle_contract()
	await _wait(1.0)
	fishing._water.dusk = 1.0
	fishing._god.presence = 1.0
	fishing._set_hud_visible(false)
	fishing._captions.visible = false
	fishing._offering.open(who, rng)
	await _wait(3.0)
	await _save("offering")
	get_tree().quit()


func _process(_delta: float) -> void:
	if fishing and not fishing.is_processing():
		fishing._sync_presentation()


## 按 SHOTS 的一行摆一条渔获：先照常生成，再改成要的等级、时期、词条，重算躯体规模和各项
func _make(shot: Array, rng: RandomNumberGenerator) -> CatchData:
	var species := GameDB.get_fish(shot[1])
	var c := CatchGenerator.generate(species, rng)
	c.level = shot[2]
	c.stage = shot[3]
	c.soul_strength = 30 + 10 * (c.level - 1) + rng.randi_range(-4, 12)
	c.affix_ids = []
	if shot[5] != "":
		c.affix_ids.append(shot[5])
	if shot[4] != "":
		c.affix_ids.append(shot[4])
		if shot[4] == CatchGenerator.RECOLORED:
			c.hue_shift = 0.62
	c.body = CatchGenerator.body_value_at(species, c.stage, c.is_mutated(), rng.randf_range(0.35, 0.75), GameDB.balance)
	CatchGenerator.evaluate(c, species, GameDB.balance)
	return c


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
