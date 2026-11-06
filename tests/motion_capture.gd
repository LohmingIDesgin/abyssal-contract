extends Node2D
## 动效的截图（2026-11-05）：每一种按自己的动效（CreatureArt、FishData.motion_style）动，隔一小段截一张，
## 连着看得出身子怎么摆、鳍和须怎么抖、手指怎么弯、头灯怎么晃。要出画面跑（不能 --headless）：
##   Godot_v4.6.3-stable_win64.exe --path . --resolution 1280x720 res://tests/motion_capture.tscn -- out=D:/tmp/motion
## 可选：stage=0/1/2（时期，默认成年）frames=6（截几张）step=0.25（隔几秒）only=drowned_hand（只看这一种，画得大）
## mask=0（不用动效遮罩，看老办法）drafts=1（也画名册草案里有插图的）

var out_dir := "user://motion_capture"
var frames := 6
var step := 0.25
var stage := 2
var only := ""
var use_mask := true


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=")
		match kv[0]:
			"out":
				out_dir = kv[1]
			"frames":
				frames = int(kv[1])
			"step":
				step = float(kv[1])
			"stage":
				stage = int(kv[1])
			"only":
				only = kv[1]
			"mask":
				use_mask = kv[1] != "0"
			"drafts":
				if kv[1] == "1":
					GameDB.use_draft_fish()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.09, 0.11)
	bg.size = Vector2(1280, 720)
	add_child(bg)
	var species: Array = []
	for fish: FishData in Codex.species_order():
		if (only == "" or fish.id == only) and fish.stage_icon(stage) != null:
			species.append(fish)
	var cols := 1 if only != "" else 3
	var cell := Vector2(1280.0 / cols, 720.0 / ceili(species.size() / float(cols)))
	for i in species.size():
		var fish: FishData = species[i]
		var tex: Texture2D = fish.stage_icon(stage)
		var box := cell * Vector2(0.9, 0.78)
		var aspect := tex.get_size().x / tex.get_size().y
		var art := Vector2(box.y * aspect, box.y)
		if art.x > box.x:
			art = Vector2(box.x, box.x / aspect)
		var center := Vector2((i % cols + 0.5) * cell.x, (i / cols + 0.5) * cell.y + cell.y * 0.06)
		var mesh := MeshInstance2D.new()
		mesh.mesh = CreatureArt.grid(art)
		mesh.texture = tex
		mesh.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var mat := CreatureArt.make_material()
		CreatureArt.apply(mat, fish, tex, art)
		if not use_mask:
			mat.set_shader_parameter("has_mask", false)
		mesh.material = mat
		mesh.position = center
		add_child(mesh)
		var label := Label.new()
		label.text = "%s · %s%s" % [fish.display_name, CreatureArt.style_of(fish).name, "" if CreatureArt.mask_for(tex) else "（没有遮罩）"]
		label.position = Vector2(center.x - cell.x * 0.45, center.y - cell.y * 0.5)
		label.add_theme_font_size_override("font_size", 16)
		add_child(label)
	await get_tree().create_timer(1.0).timeout
	for f in frames:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := out_dir.path_join("frame_%02d.png" % f)
		img.save_png(path)
		print("saved ", path)
		await get_tree().create_timer(step).timeout
	get_tree().quit()
