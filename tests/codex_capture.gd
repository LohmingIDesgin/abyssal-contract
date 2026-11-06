extends Node
## 图鉴的截图：签约时的"翻看图鉴"、准备抛竿时右下的按键提示（身上放了三样道具，看道具栏的图标）、
## 选去处时按 C（钓上来的是浅层的磷灯婆幼年，图鉴翻到它、立绘是幼年）、"各层水域"三层水各一张、七种生物各一张（成年的立绘），
## 溺者之手的另外两页和另外两个时期；关掉"测试期间全开"看没收录的样子（只钓上过灰鲦和血齿冥鲳）；
## 名册草案加进来以后的二十格和渊底的排行；最后开制饵台看深水的上钩倾向。要出画面跑（不能 --headless）；
## 截图写到 -- out=文件夹（默认 user://codex_capture）：
##   Godot_v4.6.3-stable_win64.exe --path . --resolution 1280x720 res://tests/codex_capture.tscn -- out=D:/tmp/codex
## 签约用模拟按键。不写试玩日志。跑之前把 APPDATA 指到别的空文件夹（签约不存名册，但别碰真的 user://）。

var fishing: Control
var out_dir := "user://codex_capture"


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
	await _wait(2.5)
	await _save("signing")
	fishing._open_codex_from_signing()
	await _wait(1.2)
	await _save("from_signing")
	fishing._codex.close()
	await _wait(0.8)
	for ch in "Test":
		_key(KEY_NONE, true, ch.unicode_at(0))
		_key(KEY_NONE, false, ch.unicode_at(0))
	await _wait(0.3)
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, false)
	await _take_opening()
	await _wait(6.0)
	GameState.contractor.items = {"soul_thread": 1, "soul_nail": 1, "abyss_eye": 2}
	GameState.contractor.changed.emit()
	await _wait(0.6)
	await _save("hud_ready")
	# 选去处的时候按 C：翻到刚钓上来的那一种；合上以后渔获浮回来，接着选
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var crone := GameDB.get_fish("lantern_crone")
	fishing._target = crone
	fishing._catch = CatchGenerator.generate(crone, rng, null, 0, 0)
	fishing._show_catch()
	await _wait(2.6)
	await _save("decide_reveal")
	_key(KEY_C, true)
	_key(KEY_C, false)
	await _wait(1.0)
	await _save("decide_codex")
	_key(KEY_C, true)
	_key(KEY_C, false)
	await _wait(1.0)
	await _save("decide_back")
	fishing._reveal.decide("dismantle")
	await _wait(2.0)
	_key(KEY_C, true)
	_key(KEY_C, false)
	await _wait(1.2)
	var codex: CodexScreen = fishing._codex
	# 各层水域（Tab）：三层水各一张
	codex.set_mode("layers")
	for d in 3:
		codex.set_layer(d)
		await _wait(0.6)
		await _save("layers_%d" % d)
	codex.set_mode("species")
	var species := Codex.species_order()
	for i in species.size():
		codex.select(i)
		codex.set_stage(2)
		codex.set_page(0)
		await _wait(0.7)
		await _save("species_%d_%s" % [i + 1, species[i].id])
	# 一种生物的另外两页、另外两个时期（溺者之手）
	codex.select(species.find(GameDB.get_fish("drowned_hand")))
	for p in [1, 2]:
		codex.set_page(p)
		await _wait(0.6)
		await _save("hand_page_%d" % p)
	codex.set_page(0)
	for s in [0, 1]:
		codex.set_stage(s)
		await _wait(0.7)
		await _save("hand_stage_%d" % s)
	codex.set_stage(2)
	# 关掉全开：只钓上过灰鲦和血齿冥鲳
	Codex.reveal_all = false
	var saved := GameState.catches.duplicate()
	GameState.catches = {"grey_dace": 3, "bloodtooth_pomfret": 1}
	codex.close()
	await _wait(0.6)
	codex.open()
	codex.set_mode("layers")
	await _wait(1.2)
	await _save("locked_overview")
	codex.set_mode("species")
	codex.select(4)
	await _wait(0.6)
	await _save("locked_species")
	Codex.reveal_all = true
	GameState.catches = saved
	# 名册草案加进来（二十种，草案还没有插图）：格子排得下、各层水域的排行
	codex.close()
	await _wait(0.6)
	GameDB.use_draft_fish()
	codex.open()
	codex.set_mode("species")
	codex.select(0)
	await _wait(1.2)
	await _save("drafts_grid")
	codex.set_mode("layers")
	codex.set_layer(2)
	await _wait(0.6)
	await _save("drafts_layers")
	codex.close()
	await _wait(0.6)
	GameDB.use_draft_fish(false)
	_key(KEY_C, true)
	_key(KEY_C, false)
	await _wait(0.8)
	await _save("closed")
	# 制饵台在深水：萤浆饵的上钩倾向，每种写它在这层水里出的那几级，比自己强的标颜色
	GameState.contractor.materials = {"flesh": 2, "shell": 2, "glow": 4}
	fishing._rack.depth = 1
	fishing._open_bench()
	await _wait(0.8)
	fishing._bench.pick_key(2)
	fishing._bench.pick_key(2)
	await _wait(0.8)
	await _save("bench_deep")
	get_tree().quit()


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
