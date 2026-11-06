extends Node3D
## 左手握竿渲染检查：--fixed-fps 60 res://tests/left_grip_preview.tscn
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("cfd8dc")
	add_child(env)
	var arms := FirstPersonArms.new()
	add_child(arms)
	arms.view = WaterView.View.REELING
	arms.tension = 0.5
	for frame in 120:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/left_grip_fixed.png")
	var zoom := get_viewport().get_texture().get_image().get_region(Rect2i(750, 150, 210, 230))
	zoom.resize(630,690)
	zoom.save_png("res://artifacts/left_fingers_zoom.png")
	arms.tension = 1.0
	arms.struggling = true
	arms.holding = true
	for frame in 90:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/left_grip_tension.png")
	arms.view = WaterView.View.IDLE
	arms.play(FirstPersonArms.Action.CAUGHT)
	for sample in 3:
		for frame in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/left_caught_%d.png" % sample)
	get_tree().quit()

