extends SceneTree
## Dev tool: loads the game, waits for world generation, then renders views to PNG.
##   VIEWS="x,z,height_above_ground,yaw,pitch;..."  (or "player" for the first-person view)
##   SHOT_DIR=<folder>
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1280x720 --script res://tools/screenshot.gd

var _frame := 0
var _views: PackedStringArray
var _view_index := -1
var _wait := 0
var _cam: Camera3D
var _world: Node
var _fps_samples: Array[float] = []


func _initialize() -> void:
	change_scene_to_file("res://scenes/Main.tscn")
	# Uncapped so the printed fps is meaningful.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_views = OS.get_environment("VIEWS").split(";", false)
	if _views.is_empty():
		_views = PackedStringArray(["player"])


func _process(delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	var player := current_scene.get_node("Player") as Node3D
	if player.process_mode == Node.PROCESS_MODE_DISABLED:
		return false
	if _world == null:
		_world = current_scene.get_node("World")
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		print("world ready at frame ", _frame)
		# Profiling toggles, e.g. TOGGLES="noshadow,notrees,nossao,noislands,nograss,noterrain"
		var toggles := OS.get_environment("TOGGLES").split(",", false)
		if "noshadow" in toggles:
			(current_scene.get_node("DirectionalLight3D") as DirectionalLight3D).shadow_enabled = false
		if "nossao" in toggles:
			(current_scene.get_node("WorldEnvironment") as WorldEnvironment).environment.ssao_enabled = false
		for pair in [["notrees", "Vegetation"], ["noislands", "SkyIslands"], ["nograss", "Grass"], ["noterrain", "Terrain"]]:
			if pair[0] in toggles and _world.has_node(pair[1]):
				(_world.get_node(pair[1]) as Node3D).visible = false
	if _wait > 0:
		_wait -= 1
		if _wait < 20:
			_fps_samples.append(1.0 / maxf(delta, 0.0001))
		if _wait == 0:
			var path := OS.get_environment("SHOT_DIR") + "/shot_%d.png" % _view_index
			root.get_texture().get_image().save_png(path)
			var avg := 0.0
			for f in _fps_samples:
				avg += f
			print("view %d fps %.1f -> %s" % [_view_index, avg / maxf(_fps_samples.size(), 1), path])
		return false
	_view_index += 1
	if _view_index >= _views.size():
		quit()
		return false
	_setup_view(_views[_view_index], player)
	_fps_samples.clear()
	_wait = 45
	return false


func _setup_view(view: String, player: Node3D) -> void:
	if view.begins_with("map"):
		# "map" (animated open) or "map:open[:yaw:pitch:dist]" (skip the unroll)
		var parts := view.split(":")
		(player.get_node("Camera3D") as Camera3D).current = true
		var map = current_scene.get_node("MapOverlay")
		if not map.is_open():
			map.open()
		if parts.size() > 1:
			map._progress = 1.0
			map._relief_t = 1.0
		if parts.size() > 4:
			map._t_yaw = float(parts[2])
			map._t_pitch = float(parts[3])
			map._t_dist = float(parts[4])
		return
	if view.begins_with("menu"):
		# "menu:main" or "menu:settings:<tab index>"
		var parts := view.split(":")
		(player.get_node("Camera3D") as Camera3D).current = true
		var menu = current_scene.get_node("PauseMenu")
		if not menu.is_open():
			menu.open()
		if parts[1] == "settings":
			menu._show_settings()
			menu._tabs.current_tab = int(parts[2])
		else:
			menu._show_main()
		return
	if view == "player":
		(player.get_node("Camera3D") as Camera3D).current = true
		return
	if _cam == null:
		_cam = Camera3D.new()
		_cam.far = 3000.0
		current_scene.add_child(_cam)
	var data: TerrainData = _world.terrain_data
	if view.begins_with("tree"):
		# "tree:<pine 0/1>:<index>" frames the n-th tree of that species from 14 m.
		var parts := view.split(":")
		var veg = _world.get_node("Vegetation")
		var want := int(parts[1])
		var nth := int(parts[2])
		for i in veg.tree_positions.size():
			if veg.tree_is_pine[i] == want:
				nth -= 1
				if nth < 0:
					var p: Vector3 = veg.tree_positions[i]
					var from := p + Vector3(10, 0, 10)
					_cam.global_position = Vector3(from.x, data.height_at(from.x, from.z) + 3.0, from.z)
					_cam.look_at(p + Vector3.UP * 6.0)
					break
		_cam.current = true
		return
	if view.begins_with("lake"):
		# "lake:<distance from center>:<eye height above ground>:<angle deg>:<look height>"
		var parts := view.split(":")
		var lake: LakeShape = data.lakes[0]
		var dist := float(parts[1])
		var ang := deg_to_rad(float(parts[3]))
		var p := lake.center + Vector2.from_angle(ang) * dist
		_cam.global_position = Vector3(p.x, maxf(data.height_at(p.x, p.y), lake.level) + float(parts[2]), p.y)
		var target := lake.center.lerp(p, 0.0 if parts.size() < 5 else 0.3)
		_cam.look_at(Vector3(target.x, lake.level + (float(parts[4]) if parts.size() > 4 else 0.0), target.y))
		_cam.current = true
		print("lake at %s level %.1f radius %.1f" % [lake.center, lake.level, lake.radius])
		return
	if view.begins_with("island"):
		# "island:<index>:<distance factor>:<height factor>" frames an island from the side.
		var parts := view.split(":")
		var field = _world.get_node("SkyIslands")
		var isl: Node3D = field.islands[int(parts[1]) % field.islands.size()]
		var r: float = isl.shape.radius
		var dist := r * (float(parts[2]) if parts.size() > 2 else 3.0) + 10.0
		var hf := float(parts[3]) if parts.size() > 3 else -0.4
		_cam.global_position = isl.global_position + Vector3(dist * 0.8, r * hf, dist * 0.6)
		_cam.look_at(isl.global_position + Vector3.DOWN * r * 0.4)
		_cam.current = true
		print("island %s radius %.1f at %s" % [parts[1], r, isl.global_position])
		return
	var v := view.split_floats(",")
	_cam.global_position = Vector3(v[0], data.height_at(v[0], v[1]) + v[2], v[1])
	_cam.rotation_degrees = Vector3(v[4], v[3], 0.0)
	_cam.current = true
