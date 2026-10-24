class_name PauseMenu
extends CanvasLayer
## Escape menu: Continue / Settings / Leave Game / Quit Game, plus a tabbed settings
## screen (controls & key bindings, gameplay, graphics, audio). Pauses the game while open –
## offline only: on a server the world keeps running and only the player's input is blocked.
## With `title_mode` it only provides the settings screen for the title menu.

@export var player_path: NodePath
@export var title_mode := false

const TITLE_SCENE := "res://scenes/Title.tscn"

const GOLD := UiTheme.GOLD
const TEXT := UiTheme.TEXT
const TEXT_DIM := UiTheme.TEXT_DIM

var _backdrop: ColorRect
var _main: PanelContainer
var _settings: PanelContainer
var _tabs: TabContainer
var _continue_button: Button
var _listening := ""
var _key_buttons := {}  # action -> Button
var _pack_apply: Button
var _pack_info: Label


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not title_mode:
		add_to_group("pause_menu")
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.make()
	add_child(root)

	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	var blur := ShaderMaterial.new()
	blur.shader = preload("res://shaders/ui_blur.gdshader")
	_backdrop.material = blur
	root.add_child(_backdrop)

	_main = _build_main()
	root.add_child(_main)
	_settings = _build_settings()
	root.add_child(_settings)
	Settings.keybinds_changed.connect(_refresh_key_buttons)
	visible = false


# --- Open / close ----------------------------------------------------------------

func is_open() -> bool:
	return visible


func open() -> void:
	if title_mode:
		open_settings()
		return
	visible = true
	get_tree().paused = not Net.is_online()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_main()


## Opens straight into the settings screen (title menu).
func open_settings() -> void:
	visible = true
	_show_settings()


func close() -> void:
	_listening = ""
	visible = false
	if title_mode:
		return
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _can_pause() -> bool:
	if title_mode:
		return false
	var player := get_node_or_null(player_path)
	var map := get_tree().get_first_node_in_group("map_overlay")
	if map and map.is_open():
		return false
	var inv := get_tree().get_first_node_in_group("inventory_ui")
	if inv and inv.is_open():
		return false
	return player != null and player.process_mode != Node.PROCESS_MODE_DISABLED


func _show_main() -> void:
	_main.visible = true
	_settings.visible = false
	_continue_button.grab_focus()


func _show_settings() -> void:
	_main.visible = false
	_settings.visible = true
	_tabs.get_tab_bar().grab_focus()


func _input(event: InputEvent) -> void:
	if title_mode and not visible:
		return
	if not _listening.is_empty():
		_capture_binding(event)
		return
	if event.is_action_pressed("pause") and not event.is_echo():
		if not visible:
			if _can_pause():
				open()
		elif _settings.visible and not title_mode:
			_show_main()
		else:
			close()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# Alt-tabbing out pauses the game.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not visible and _can_pause():
		open()


# --- Main panel ----------------------------------------------------------------------

func _build_main() -> PanelContainer:
	var panel := _centered_panel(Vector2(380, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var title := _title("Paused")
	box.add_child(title)
	box.add_child(_separator())
	_continue_button = _menu_button("Continue", close)
	box.add_child(_continue_button)
	box.add_child(_menu_button("Reset View", _reset_view))
	box.add_child(_menu_button("Settings", _show_settings))
	box.add_child(_menu_button("Leave Game" if Net.is_online() else "Title Screen", _leave))
	box.add_child(_menu_button("Quit Game", _quit))
	return panel


## Levels the camera and stops leftover motion where the player stands (no teleport).
func _reset_view() -> void:
	var player := get_node_or_null(player_path)
	if player and player.has_method("reset_view"):
		player.reset_view()
	close()


func _leave() -> void:
	Net.leave()
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE_SCENE)


func _quit() -> void:
	Settings.save_settings()
	get_tree().quit()


# --- Settings panel ------------------------------------------------------------------

func _build_settings() -> PanelContainer:
	var panel := _centered_panel(Vector2(820, 600))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(_title("Settings"))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	_fill_tabs()

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	var reset := _menu_button("Reset to defaults", _reset_defaults)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	footer.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var back := _menu_button("Back", close if title_mode else _show_main)
	back.custom_minimum_size.x = 160
	footer.add_child(back)
	box.add_child(footer)
	return panel


func _fill_tabs() -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	_key_buttons.clear()

	var controls := _tab("Controls")
	controls.add_child(_header("Mouse"))
	controls.add_child(_slider_row("Mouse sensitivity", "mouse_sensitivity", 0.1, 3.0, 0.05, func(v): return "%.2fx" % v))
	controls.add_child(_check_row("Invert vertical look", "invert_y"))
	controls.add_child(_header("Key bindings"))
	var hint := Label.new()
	hint.text = "Click a binding, then press a key or mouse button. Esc cancels."
	hint.add_theme_color_override("font_color", TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 15)
	controls.add_child(hint)
	for a in Settings.ACTIONS:
		controls.add_child(_keybind_row(a[0]))

	var gameplay := _tab("Gameplay")
	gameplay.add_child(_header("Camera"))
	gameplay.add_child(_slider_row("Field of view", "fov", 60.0, 110.0, 1.0, func(v): return "%d°" % v))
	gameplay.add_child(_slider_row("Grimoire sway & head bob", "view_bob", 0.0, 1.5, 0.05, func(v): return "%d%%" % roundi(v * 100)))
	gameplay.add_child(_header("Interface"))
	gameplay.add_child(_check_row("Show FPS counter", "show_fps"))

	var graphics := _tab("Graphics")
	graphics.add_child(_header("Presets"))
	graphics.add_child(_preset_row())
	graphics.add_child(_header("Textures"))
	graphics.add_child(_pack_row())
	graphics.add_child(_pack_info)
	graphics.add_child(_header("Display"))
	graphics.add_child(_option_row("Window mode", "window_mode", Settings.WINDOW_MODES))
	var res_names: Array = []
	for r in Settings.RESOLUTIONS:
		res_names.append("%d × %d" % [r.x, r.y])
	graphics.add_child(_option_row("Resolution (windowed)", "resolution", res_names))
	graphics.add_child(_check_row("V-Sync", "vsync"))
	var fps_names: Array = []
	for f in Settings.MAX_FPS:
		fps_names.append("Unlimited" if f == 0 else str(f))
	graphics.add_child(_option_row("Frame rate limit", "max_fps", fps_names))
	graphics.add_child(_slider_row("Render scale", "render_scale", 0.4, 1.0, 0.05, func(v): return "%d%%" % roundi(v * 100)))
	graphics.add_child(_option_row("Upscaler (render scale below 100 %)", "upscaler", Settings.UPSCALERS))
	graphics.add_child(_option_row("Anti-aliasing", "antialiasing", Settings.ANTIALIASING))
	graphics.add_child(_header("Quality"))
	graphics.add_child(_check_row("Performance shaders (weak / integrated GPUs)", "performance_shaders"))
	graphics.add_child(_option_row("Shadows", "shadows", Settings.SHADOWS))
	graphics.add_child(_option_row("Grass density", "grass_density", Settings.GRASS))
	graphics.add_child(_option_row("View distance", "view_distance", Settings.VIEW_DISTANCE))
	graphics.add_child(_option_row("Clouds", "cloud_quality", Settings.CLOUD_QUALITY))
	graphics.add_child(_check_row("Light shafts (volumetric fog)", "volumetric_fog"))
	graphics.add_child(_option_row("Ambient occlusion", "ambient_occlusion", Settings.AMBIENT_OCCLUSION))
	graphics.add_child(_check_row("Bloom", "glow"))
	graphics.add_child(_check_row("Atmospheric fog", "fog"))
	graphics.add_child(_check_row("Fancy black hole (ray-traced lensing)", "fancy_black_hole"))
	graphics.add_child(_slider_row("Brightness", "brightness", 0.6, 1.4, 0.02, func(v): return "%d%%" % roundi(v * 100)))

	var audio := _tab("Audio")
	audio.add_child(_header("Volume"))
	for pair in [["Master", "master_volume"], ["Music", "music_volume"], ["Effects", "sfx_volume"]]:
		audio.add_child(_slider_row(pair[0], pair[1], 0.0, 1.0, 0.01, func(v): return "%d%%" % roundi(v * 100)))


## Texture resource pack picker. Materials are built with the world, so in game the new
## pack is applied by reloading the world.
func _pack_row() -> HBoxContainer:
	var row := _row("Texture pack")
	var ids: Array[String] = [""]
	var option := OptionButton.new()
	option.custom_minimum_size.x = 260
	option.add_item("Default")
	for p in ResourcePacks.list():
		ids.append(p.id)
		option.add_item(p.name)
	option.selected = maxi(ids.find(Settings.get_value("resource_pack")), 0)
	_pack_apply = Button.new()
	_pack_apply.text = "Apply now"
	_pack_apply.tooltip_text = "Reloads the world with the new textures."
	_pack_apply.pressed.connect(_apply_pack)
	_pack_info = Label.new()
	_pack_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pack_info.add_theme_color_override("font_color", TEXT_DIM)
	_pack_info.add_theme_font_size_override("font_size", 15)
	option.item_selected.connect(func(i: int) -> void:
		Settings.set_value("resource_pack", ids[i])
		_refresh_pack_info())
	row.add_child(_pack_apply)
	row.add_child(option)
	_refresh_pack_info()
	return row


func _refresh_pack_info() -> void:
	var id: String = Settings.get_value("resource_pack")
	var text := "Procedural textures baked with the game."
	for p in ResourcePacks.list():
		if p.id == id:
			text = p.description
	var pending := not title_mode and id != ResourcePacks.loaded_id
	_pack_apply.visible = pending
	_pack_info.text = text + (" Applies when the world is next loaded." if pending else "")


func _apply_pack() -> void:
	close()
	get_tree().reload_current_scene()


## One button per Settings.PRESETS entry; the tabs are rebuilt so every row shows the new values.
func _preset_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for preset in Settings.PRESETS:
		var b := Button.new()
		b.text = preset
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 38)
		b.pressed.connect(func() -> void:
			var current := _tabs.current_tab
			Settings.apply_preset(preset)
			_fill_tabs()
			_set_tab_deferred.call_deferred(current))
		row.add_child(b)
	return row


func _reset_defaults() -> void:
	var current := _tabs.current_tab
	Settings.reset_to_defaults()
	_fill_tabs()
	_set_tab_deferred.call_deferred(current)


func _set_tab_deferred(index: int) -> void:
	_tabs.current_tab = index


# --- Key binding capture --------------------------------------------------------------

func _start_listening(action: String) -> void:
	_listening = action
	var b: Button = _key_buttons[action]
	b.text = "Press a key…"
	b.release_focus()


func _capture_binding(event: InputEvent) -> void:
	var done := false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode != KEY_ESCAPE and event.keycode != KEY_ESCAPE:
			Settings.rebind(_listening, event)
		done = true
	elif event is InputEventMouseButton and event.pressed:
		Settings.rebind(_listening, event)
		done = true
	if done:
		get_viewport().set_input_as_handled()
		_listening = ""
		_refresh_key_buttons()


func _refresh_key_buttons() -> void:
	for action in _key_buttons:
		(_key_buttons[action] as Button).text = Settings.binding_text(action)


# --- Row builders -------------------------------------------------------------------

func _tab(tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(box)
	scroll.add_child(margin)
	_tabs.add_child(scroll)
	return box


func _row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


func _slider_row(label_text: String, key: String, lo: float, hi: float, step: float, fmt: Callable) -> HBoxContainer:
	var row := _row(label_text)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = Settings.get_value(key)
	slider.custom_minimum_size = Vector2(260, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 64
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", GOLD)
	value_label.text = fmt.call(slider.value)
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = fmt.call(v)
		Settings.set_value(key, v))
	row.add_child(slider)
	row.add_child(value_label)
	return row


func _check_row(label_text: String, key: String) -> HBoxContainer:
	var row := _row(label_text)
	var check := CheckButton.new()
	check.button_pressed = Settings.get_value(key)
	check.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	row.add_child(check)
	return row


func _option_row(label_text: String, key: String, items: Array) -> HBoxContainer:
	var row := _row(label_text)
	var option := OptionButton.new()
	option.custom_minimum_size.x = 260
	for item in items:
		option.add_item(item)
	option.selected = Settings.get_value(key)
	option.item_selected.connect(func(i: int) -> void: Settings.set_value(key, i))
	row.add_child(option)
	return row


func _keybind_row(action: String) -> HBoxContainer:
	var row := _row(Settings.action_label(action))
	var b := Button.new()
	b.custom_minimum_size = Vector2(260, 0)
	b.text = Settings.binding_text(action)
	b.pressed.connect(_start_listening.bind(action))
	_key_buttons[action] = b
	row.add_child(b)
	return row


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", GOLD)
	l.add_theme_font_size_override("font_size", 15)
	return l


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", GOLD)
	return l


func _separator() -> HSeparator:
	var s := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color(GOLD, 0.5)
	line.thickness = 1
	s.add_theme_stylebox_override("separator", line)
	return s


func _menu_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.pressed.connect(action)
	return b


func _centered_panel(min_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	return panel
