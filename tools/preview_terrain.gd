extends SceneTree
## Debug tool: runs the terrain pipeline and writes a hillshade + control map preview.
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/preview_terrain.gd
## Output goes to the folder in the PREVIEW_DIR environment variable (default user://).

func _initialize() -> void:
	var settings := TerrainSettings.new()
	if OS.get_environment("NO_EROSION") == "1":
		settings.droplets = 0
		settings.thermal_iterations = 0
	# Quick overrides for tuning, e.g. SET="droplets=0,talus=1.2"
	for pair in OS.get_environment("SET").split(",", false):
		var kv := pair.split("=")
		settings.set(kv[0], str_to_var(kv[1]))
	var data := TerrainGenerator.generate(settings)
	var out := OS.get_environment("PREVIEW_DIR")
	if out.is_empty():
		out = OS.get_user_data_dir()
	var res := data.resolution
	var img := Image.create(res, res, false, Image.FORMAT_RGB8)
	var light := Vector3(-1, 1.2, -0.6).normalized()
	for z in res:
		for x in res:
			var i := z * res + x
			var hl := data.heights[i - 1] if x > 0 else data.heights[i]
			var hr := data.heights[i + 1] if x < res - 1 else data.heights[i]
			var hd := data.heights[i - res] if z > 0 else data.heights[i]
			var hu := data.heights[i + res] if z < res - 1 else data.heights[i]
			var n := Vector3(hl - hr, 2.0, hd - hu).normalized()
			var shade := clampf(n.dot(light), 0.0, 1.0) * 0.85 + 0.15
			var t := inverse_lerp(data.min_height, data.max_height, data.heights[i])
			var base := Color(0.35, 0.5, 0.25).lerp(Color(0.55, 0.5, 0.45), smoothstep(0.25, 0.6, t)).lerp(Color.WHITE, smoothstep(0.75, 0.95, t))
			img.set_pixel(x, z, base * shade)
	img.save_png(out + "/terrain_hillshade.png")
	data.control.save_png(out + "/terrain_control.png")
	data.rock.save_png(out + "/terrain_rock.png")
	var rock_bytes := data.rock.get_data()
	var hi := 0
	var over := 0
	for b in rock_bytes:
		hi = maxi(hi, b)
		if b > 128:
			over += 1
	print("rock max %d, %.1f%% above half" % [hi, 100.0 * over / rock_bytes.size()])
	print("preview written to ", out)
	quit()
