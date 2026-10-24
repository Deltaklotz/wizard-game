extends Node
## Global settings (autoload "Settings"): stores, saves, loads and applies every option,
## and owns the rebindable input actions. Scene objects read values with
## Settings.get_value() and listen to `setting_changed` to react live.

signal setting_changed(key: String, value: Variant)
signal keybinds_changed

const PATH := "user://settings.cfg"

## Rebindable actions: [action, label, default event].
## Keys are stored as physical keycodes so the layout (QWERTY/QWERTZ/...) doesn't matter.
const ACTIONS := [
	["move_forward", "Move forward", {"key": KEY_W}],
	["move_back", "Move back", {"key": KEY_S}],
	["move_left", "Move left", {"key": KEY_A}],
	["move_right", "Move right", {"key": KEY_D}],
	["jump", "Jump", {"key": KEY_SPACE}],
	["sprint", "Sprint", {"key": KEY_SHIFT}],
	["cast", "Cast spell", {"mouse": MOUSE_BUTTON_LEFT}],
	["next_page", "Next grimoire page", {"mouse": MOUSE_BUTTON_WHEEL_DOWN}],
	["prev_page", "Previous grimoire page", {"mouse": MOUSE_BUTTON_WHEEL_UP}],
	["toggle_map", "Open map", {"key": KEY_M}],
	["inventory", "Inventory", {"key": KEY_TAB}],
	["interact", "Pick up", {"key": KEY_E}],
	["page_1", "Grimoire page 1", {"key": KEY_1}],
	["page_2", "Grimoire page 2", {"key": KEY_2}],
	["page_3", "Grimoire page 3", {"key": KEY_3}],
	["page_4", "Grimoire page 4", {"key": KEY_4}],
	["page_5", "Grimoire page 5", {"key": KEY_5}],
	["page_6", "Grimoire page 6", {"key": KEY_6}],
	["page_7", "Grimoire page 7", {"key": KEY_7}],
	["page_8", "Grimoire page 8", {"key": KEY_8}],
	["page_9", "Grimoire page 9", {"key": KEY_9}],
	["page_10", "Grimoire page 10", {"key": KEY_0}],
]

const WINDOW_MODES := ["Windowed", "Borderless fullscreen", "Exclusive fullscreen"]
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160)]
const MAX_FPS := [0, 30, 60, 75, 120, 144, 165, 240]
const ANTIALIASING := ["Off", "FXAA", "MSAA 2x", "MSAA 4x", "TAA"]
const SHADOWS := ["Off", "Low", "Medium", "High", "Ultra"]
const AMBIENT_OCCLUSION := ["Off", "Ambient occlusion", "AO + bounce light"]
const UPSCALERS := ["FSR 2 (steadier)", "FSR 1 (fastest)", "Bilinear"]
const GRASS := ["Off", "Low", "Medium", "High"]
const VIEW_DISTANCE := ["Near", "Medium", "Far"]
const CLOUD_QUALITY := ["Off", "Low", "Medium", "High"]
## Per cloud quality: [cumulus layers, sun samples per layer].
const CLOUD_STEPS := [[0, 0], [1, 3], [2, 4], [3, 5]]

const DEFAULTS := {
	# Controls
	"mouse_sensitivity": 1.0,
	"invert_y": false,
	# Gameplay
	"fov": 75.0,
	"view_bob": 1.0,
	"show_fps": false,
	# Graphics
	"window_mode": 0,
	"resolution": 0,
	"vsync": true,
	"max_fps": 0,
	"render_scale": 1.0,
	"upscaler": 0,
	"antialiasing": 1,
	"shadows": 3,
	"performance_shaders": false,
	"fancy_black_hole": true,
	"ambient_occlusion": 2,
	"volumetric_fog": true,
	"cloud_quality": 2,
	"glow": true,
	"fog": true,
	"brightness": 1.0,
	"grass_density": 3,
	"view_distance": 2,
	"resource_pack": "",
	# Audio
	"master_volume": 1.0,
	"music_volume": 0.8,
	"sfx_volume": 1.0,
	# Multiplayer profile (connect screen); kept by "Reset to defaults".
	"player_name": "",
	"player_color": "c9483a",
	"server_address": "127.0.0.1",
}
const PROFILE_KEYS := ["player_name", "player_color", "server_address"]

## Graphics presets (Settings → Graphics). "Very Low" / "Low" are for weak and integrated
## GPUs: performance shaders, 2 shadow cascades, a coarser grass grid, shorter vegetation
## range, a lower render scale with the cheap FSR 1 upscaler and the simple black hole – the
## world keeps its grass, shadows, clouds and bloom.
const PRESETS := {
	"Very Low": {"performance_shaders": true, "shadows": 1, "grass_density": 1, "view_distance": 0,
		"cloud_quality": 1, "volumetric_fog": false, "ambient_occlusion": 0, "glow": true, "fog": true,
		"antialiasing": 1, "render_scale": 0.7, "upscaler": 1, "fancy_black_hole": false},
	"Low": {"performance_shaders": true, "shadows": 1, "grass_density": 2, "view_distance": 1,
		"cloud_quality": 1, "volumetric_fog": false, "ambient_occlusion": 0, "glow": true, "fog": true,
		"antialiasing": 1, "render_scale": 0.85, "upscaler": 1, "fancy_black_hole": false},
	"Medium": {"performance_shaders": false, "shadows": 2, "grass_density": 2, "view_distance": 1,
		"cloud_quality": 2, "volumetric_fog": false, "ambient_occlusion": 1, "glow": true, "fog": true,
		"antialiasing": 1, "render_scale": 1.0, "upscaler": 0, "fancy_black_hole": true},
	"High": {"performance_shaders": false, "shadows": 3, "grass_density": 3, "view_distance": 2,
		"cloud_quality": 2, "volumetric_fog": true, "ambient_occlusion": 2, "glow": true, "fog": true,
		"antialiasing": 1, "render_scale": 1.0, "upscaler": 0, "fancy_black_hole": true},
	"Ultra": {"performance_shaders": false, "shadows": 4, "grass_density": 3, "view_distance": 2,
		"cloud_quality": 3, "volumetric_fog": true, "ambient_occlusion": 2, "glow": true, "fog": true,
		"antialiasing": 4, "render_scale": 1.0, "upscaler": 0, "fancy_black_hole": true},
}

var _values := {}
var _fps_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_buses()
	_values = DEFAULTS.duplicate()
	_reset_keybinds()
	load_settings()
	_build_fps_label()
	apply_all()
	# Scene-dependent settings (environment, light, camera...) once a scene is loaded.
	get_tree().node_added.connect(_on_node_added)


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	_values[key] = value
	_apply(key)
	setting_changed.emit(key, value)
	save_settings()


func reset_to_defaults() -> void:
	var profile := {}
	for key in PROFILE_KEYS:
		profile[key] = get_value(key)
	_values = DEFAULTS.duplicate()
	_values.merge(profile, true)
	_reset_keybinds()
	apply_all()
	for key in _values:
		setting_changed.emit(key, _values[key])
	keybinds_changed.emit()
	save_settings()


func apply_preset(preset: String) -> void:
	var values: Dictionary = PRESETS.get(preset, {})
	for key in values:
		_values[key] = values[key]
		_apply(key)
		setting_changed.emit(key, values[key])
	save_settings()


func apply_all() -> void:
	for key in _values:
		_apply(key)


# --- Keybinds ---------------------------------------------------------------

func action_label(action: String) -> String:
	for a in ACTIONS:
		if a[0] == action:
			return a[1]
	return action


func binding_text(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "Unbound"
	return event_text(events[0])


static func event_text(event: InputEvent) -> String:
	if event is InputEventKey:
		var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		var local := DisplayServer.keyboard_get_keycode_from_physical(code) if event.physical_keycode != KEY_NONE else code
		return OS.get_keycode_string(local)
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT: return "Left mouse"
			MOUSE_BUTTON_RIGHT: return "Right mouse"
			MOUSE_BUTTON_MIDDLE: return "Middle mouse"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel down"
			MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
		return "Mouse %d" % event.button_index
	return "?"


## Binds `event` to `action`. If another action already used it, the two swap bindings.
func rebind(action: String, event: InputEvent) -> void:
	var clean := _clean_event(event)
	var previous := InputMap.action_get_events(action)
	for other in ACTIONS:
		if other[0] == action:
			continue
		for e in InputMap.action_get_events(other[0]):
			if _same_input(e, clean):
				InputMap.action_erase_event(other[0], e)
				if not previous.is_empty():
					InputMap.action_add_event(other[0], previous[0])
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, clean)
	keybinds_changed.emit()
	save_settings()


func _reset_keybinds() -> void:
	for a in ACTIONS:
		var action: String = a[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, _event_from_dict(a[2]))
	if not InputMap.has_action("pause"):
		InputMap.add_action("pause")
		var esc := InputEventKey.new()
		esc.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event("pause", esc)


func _event_from_dict(d: Dictionary) -> InputEvent:
	if d.has("key"):
		var e := InputEventKey.new()
		e.physical_keycode = d.key
		return e
	var m := InputEventMouseButton.new()
	m.button_index = d.mouse
	return m


func _event_to_dict(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		return {"key": e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode}
	return {"mouse": (e as InputEventMouseButton).button_index}


func _clean_event(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var e := InputEventKey.new()
		e.physical_keycode = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		return e
	var m := InputEventMouseButton.new()
	m.button_index = (event as InputEventMouseButton).button_index
	return m


func _same_input(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return a.physical_keycode == b.physical_keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return a.button_index == b.button_index
	return false


# --- Persistence -------------------------------------------------------------

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in _values:
		cfg.set_value("settings", key, _values[key])
	for a in ACTIONS:
		var events := InputMap.action_get_events(a[0])
		cfg.set_value("keybinds", a[0], _event_to_dict(events[0]) if not events.is_empty() else {})
	cfg.save(PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	# Old saves: shadow_quality 0..3 (Low..Ultra) became shadows 1..4 (0 = Off).
	if not cfg.has_section_key("settings", "shadows") and cfg.has_section_key("settings", "shadow_quality"):
		cfg.set_value("settings", "shadows", int(cfg.get_value("settings", "shadow_quality")) + 1)
	# ssao (bool: SSAO + SSIL) became ambient_occlusion (off / AO / AO + bounce light).
	if not cfg.has_section_key("settings", "ambient_occlusion") and cfg.has_section_key("settings", "ssao"):
		cfg.set_value("settings", "ambient_occlusion", 2 if cfg.get_value("settings", "ssao") else 0)
	for key in DEFAULTS:
		var v: Variant = cfg.get_value("settings", key, DEFAULTS[key])
		if typeof(v) == typeof(DEFAULTS[key]) or (DEFAULTS[key] is float and v is int):
			_values[key] = v
	for a in ACTIONS:
		var d: Dictionary = cfg.get_value("keybinds", a[0], {})
		if d.is_empty():
			continue
		InputMap.action_erase_events(a[0])
		InputMap.action_add_event(a[0], _event_from_dict(d))


# --- Applying ----------------------------------------------------------------

func _apply(key: String) -> void:
	var v: Variant = _values[key]
	match key:
		"window_mode":
			var modes := [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
			DisplayServer.window_set_mode(modes[clampi(v, 0, 2)])
			if v == 0:
				_apply("resolution")
		"resolution":
			if get_value("window_mode") == 0:
				var size: Vector2i = RESOLUTIONS[clampi(v, 0, RESOLUTIONS.size() - 1)]
				var screen := DisplayServer.screen_get_usable_rect()
				size = size.min(screen.size)
				DisplayServer.window_set_size(size)
				DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if v else DisplayServer.VSYNC_DISABLED)
		"max_fps":
			Engine.max_fps = MAX_FPS[clampi(v, 0, MAX_FPS.size() - 1)]
		"render_scale", "upscaler":
			var vp := get_viewport()
			var scale: float = get_value("render_scale")
			vp.scaling_3d_scale = scale
			# FSR 2 (temporal) by default: FSR 1's sharpening made the alpha-tested leaves crawl and
			# flicker whenever the view moved; FSR 2 also antialiases them. But FSR 2 itself costs
			# a few ms on weak GPUs, so FSR 1 / plain bilinear are offered too.
			var modes := [Viewport.SCALING_3D_MODE_FSR2, Viewport.SCALING_3D_MODE_FSR, Viewport.SCALING_3D_MODE_BILINEAR]
			vp.scaling_3d_mode = modes[clampi(get_value("upscaler"), 0, 2)] if scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
		"antialiasing":
			var vp := get_viewport()
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if v == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
			vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_DISABLED][v]
			vp.use_taa = v == 4
		"shadows":
			var level := clampi(v, 0, SHADOWS.size() - 1)
			var sizes := [1024, 2048, 4096, 4096, 8192]
			var filters := [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
				RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH]
			RenderingServer.directional_shadow_atlas_set_size(sizes[level], true)
			RenderingServer.directional_soft_shadow_filter_set_quality(filters[level])
			for light in _scene_nodes("DirectionalLight3D"):
				GraphicsQuality.apply_light(light as DirectionalLight3D, level)
			GraphicsQuality.apply_vegetation(get_tree().current_scene)
		"view_distance":
			GraphicsQuality.apply_vegetation(get_tree().current_scene)
		"performance_shaders":
			GraphicsQuality.refresh_shaders()
			for we in _scene_nodes("WorldEnvironment"):
				GraphicsQuality.apply_sky((we as WorldEnvironment).environment)
		"cloud_quality":
			for we in _scene_nodes("WorldEnvironment"):
				var env := (we as WorldEnvironment).environment
				if env and env.sky and env.sky.sky_material is ShaderMaterial:
					var steps: Array = CLOUD_STEPS[clampi(v, 0, CLOUD_STEPS.size() - 1)]
					env.sky.sky_material.set_shader_parameter("cloud_layers", steps[0])
					env.sky.sky_material.set_shader_parameter("light_steps", steps[1])
		"ambient_occlusion", "glow", "fog", "brightness", "volumetric_fog":
			for we in _scene_nodes("WorldEnvironment"):
				var env := (we as WorldEnvironment).environment
				if env == null:
					continue
				match key:
					"ambient_occlusion":
						# SSIL (bounce light) costs several times more than SSAO.
						env.ssao_enabled = v >= 1
						env.ssil_enabled = v >= 2
					"volumetric_fog": env.volumetric_fog_enabled = v
					"glow": env.glow_enabled = v
					"fog": env.fog_enabled = v
					"brightness":
						env.adjustment_enabled = true
						env.adjustment_brightness = v
		"show_fps":
			if _fps_label:
				_fps_label.visible = v
		"master_volume", "music_volume", "sfx_volume":
			var bus: String = {"master_volume": "Master", "music_volume": "Music", "sfx_volume": "SFX"}[key]
			var idx := AudioServer.get_bus_index(bus)
			if idx >= 0:
				AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
				AudioServer.set_bus_mute(idx, v <= 0.001)


func _scene_nodes(type_name: String) -> Array[Node]:
	var scene := get_tree().current_scene
	if scene == null:
		return []
	return scene.find_children("*", type_name, true, false)


func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment:
		_apply_deferred.call_deferred(["ambient_occlusion", "glow", "fog", "brightness", "volumetric_fog", "cloud_quality", "performance_shaders"])
	elif node is DirectionalLight3D:
		_apply_deferred.call_deferred(["shadows"])


func _apply_deferred(keys: Array) -> void:
	for k in keys:
		_apply(k)


func _ensure_audio_buses() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")


func _build_fps_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fps_label = Label.new()
	_fps_label.position = Vector2(12, 8)
	_fps_label.add_theme_font_size_override("font_size", 16)
	_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_fps_label)


func _process(_delta: float) -> void:
	if _fps_label and _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
