extends Node
func _ready() -> void:
	var scene: Node = load("res://scenes/main/prototype_main.tscn").instantiate()
	add_child(scene)
	var fishing: Control = scene.get_node("钓鱼")
	fishing.set_process(false)
	var water: WaterView = fishing._water
	var arms: FirstPersonArms = fishing._arms
	water.view = WaterView.View.REELING
	arms.view = WaterView.View.REELING
	for frame in 100:
		await get_tree().process_frame
	var failures := 0
	for top in [0.64, 0.66, 0.76]:
		fishing.boat_screen_top = top
		for ratio in [1.0, 0.3, 0.0]:
			water.line_ratio = ratio
			for tension_value in [0.0, 0.8]:
				water.tension = tension_value
				arms.tension = tension_value
				for frame in 3:
					await get_tree().process_frame
				var point := water.water_point()
				if not is_equal_approx(point.y, water._project(water._water_world()).y) or water._line.get_index() >= water._boat.get_index():
					failures += 1
				if ratio == 0.0 and tension_value == 0.0 and DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png("res://artifacts/line_near_%s.png" % top)
	print("Projection and boat occlusion checks: ", failures, " failures / 18 cases")
	get_tree().quit(1 if failures else 0)



