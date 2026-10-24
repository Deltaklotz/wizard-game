extends Control
## Title screen: Start / Settings / Quit over an animated night-sky backdrop. Start opens
## the connect page, where players pick a nickname and robe colour (with a turning
## preview of their wizard) and enter the server's address. Once the server has sent the
## world (or asked us to shape it), the game scene loads.

const GAME_SCENE := "res://scenes/Main.tscn"
const SWATCHES := ["c9483a", "e08a2c", "e3c34a", "6aa84f", "2f9e8f", "3d7fd6", "6b54c9", "b04fb3", "d9d4c7", "3b3540"]

var _backdrop: ColorRect
var _title_box: VBoxContainer
var _menu: VBoxContainer
var _connect: PanelContainer
var _settings: PauseMenu
var _name_edit: LineEdit
var _address_edit: LineEdit
var _status: Label
var _progress: ProgressBar
var _connect_button: Button
var _back_button: Button
var _swatch_group := ButtonGroup.new()
var _custom_color: ColorPickerButton
var _color := Color.WHITE
var _preview_root: Node3D
var _preview_model: Node3D
var _busy := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.make()

	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/ui/title_backdrop.gdshader")
	_backdrop.material = mat
	add_child(_backdrop)

	_build_title()
	_build_menu()
	_build_connect()
	_settings = PauseMenu.new()
	_settings.title_mode = true
	add_child(_settings)

	Net.status_changed.connect(_on_status)
	Net.connection_failed.connect(_on_failed)
	Net.world_ready.connect(_on_world_ready)
	Net.world_progress.connect(_on_progress)
	get_viewport().size_changed.connect(_on_resized)
	_on_resized()

	if not Net.last_error.is_empty():
		_show_connect()
		_set_status(Net.last_error, true)
		Net.last_error = ""
	else:
		_show_menu()


func _on_resized() -> void:
	(_backdrop.material as ShaderMaterial).set_shader_parameter("resolution", get_viewport_rect().size)


# --- Title & main menu ----------------------------------------------------------------

func _build_title() -> void:
	_title_box = VBoxContainer.new()
	_title_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_title_box.anchor_top = 0.3
	_title_box.anchor_bottom = 0.3
	_title_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Label.new()
	title.text = str(ProjectSettings.get_setting("application/config/name", "Wizard Game"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 92)
	title.add_theme_color_override("font_color", Color(0.98, 0.86, 0.58))
	title.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.16))
	title.add_theme_constant_override("outline_size", 18)
	title.add_theme_color_override("font_shadow_color", Color(0.9, 0.6, 0.25, 0.35))
	title.add_theme_constant_override("shadow_outline_size", 30)
	_title_box.add_child(title)
	var sub := Label.new()
	sub.text = "Gather at the Waystone Circle"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var italic := SystemFont.new()
	italic.font_names = PackedStringArray(["Palatino Linotype", "Book Antiqua", "Georgia", "serif"])
	italic.font_italic = true
	sub.add_theme_font_override("font", italic)
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", Color(UiTheme.TEXT, 0.8))
	_title_box.add_child(sub)
	add_child(_title_box)


func _build_menu() -> void:
	_menu = VBoxContainer.new()
	_menu.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_menu.anchor_top = 0.58
	_menu.anchor_bottom = 0.58
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.custom_minimum_size.x = 320
	_menu.add_theme_constant_override("separation", 14)
	_menu.add_child(_button("Start", _show_connect))
	_menu.add_child(_button("Settings", func() -> void: _settings.open_settings()))
	_menu.add_child(_button("Quit", func() -> void:
		Settings.save_settings()
		get_tree().quit()))
	add_child(_menu)


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(action)
	return b


func _show_menu() -> void:
	_title_box.visible = true
	_menu.visible = true
	_connect.visible = false
	(_menu.get_child(0) as Button).grab_focus()


func _show_connect() -> void:
	_title_box.visible = false
	_menu.visible = false
	_connect.visible = true
	_set_status("", false)
	_progress.visible = false
	if _name_edit.text.is_empty():
		_name_edit.grab_focus()
	else:
		_connect_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and _connect.visible and not _busy:
		_show_menu()
		get_viewport().set_input_as_handled()


# --- Connect page --------------------------------------------------------------------

func _build_connect() -> void:
	_connect = PanelContainer.new()
	_connect.set_anchors_preset(Control.PRESET_CENTER)
	_connect.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_connect.grow_vertical = Control.GROW_DIRECTION_BOTH
	_connect.custom_minimum_size = Vector2(860, 0)
	add_child(_connect)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_connect.add_child(box)
	var heading := Label.new()
	heading.text = "Join a Game"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 34)
	heading.add_theme_color_override("font_color", UiTheme.GOLD)
	box.add_child(heading)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	box.add_child(cols)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 8)
	cols.add_child(form)

	form.add_child(_field_label("Nickname"))
	_name_edit = LineEdit.new()
	_name_edit.max_length = 16
	_name_edit.placeholder_text = "Wizard"
	_name_edit.text = Settings.get_value("player_name")
	_name_edit.text_changed.connect(func(_t: String) -> void: _refresh_preview_name())
	form.add_child(_name_edit)

	form.add_child(_field_label("Robe colour"))
	var swatches := GridContainer.new()
	swatches.columns = 6
	swatches.add_theme_constant_override("h_separation", 8)
	swatches.add_theme_constant_override("v_separation", 8)
	form.add_child(swatches)
	var saved := Color.html(Settings.get_value("player_color"))
	var matched := false
	for hex in SWATCHES:
		var c := Color.html(hex)
		var b := _swatch(c)
		swatches.add_child(b)
		if c.to_html(false) == saved.to_html(false):
			b.button_pressed = true
			matched = true
	_custom_color = ColorPickerButton.new()
	_custom_color.custom_minimum_size = Vector2(48, 40)
	_custom_color.edit_alpha = false
	_custom_color.color = saved
	_custom_color.tooltip_text = "Any colour"
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := UiTheme.box(Color(0.1, 0.07, 0.1), UiTheme.GOLD if state == "hover" else Color(0.45, 0.36, 0.22), 1, 6, 5)
		sb.content_margin_left = 5
		sb.content_margin_right = 5
		if state == "focus":
			sb.draw_center = false
		_custom_color.add_theme_stylebox_override(state, sb)
	_custom_color.color_changed.connect(func(c: Color) -> void:
		var pressed := _swatch_group.get_pressed_button()
		if pressed:
			pressed.button_pressed = false
		_set_color(c))
	swatches.add_child(_custom_color)

	form.add_child(_field_label("Server address"))
	_address_edit = LineEdit.new()
	_address_edit.placeholder_text = "e.g. 192.168.0.12  (port %d unless given as ip:port)" % Net.DEFAULT_PORT
	_address_edit.text = Settings.get_value("server_address")
	_address_edit.text_submitted.connect(func(_t: String) -> void: _on_connect())
	form.add_child(_address_edit)
	var hint := Label.new()
	hint.text = "The host starts run_server.bat; its window lists the addresses to use."
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(hint)

	cols.add_child(_build_preview())

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size.y = 28
	box.add_child(_status)
	_progress = ProgressBar.new()
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 8
	box.add_child(_progress)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	_back_button = _button("Back", _on_back)
	_back_button.custom_minimum_size.x = 180
	footer.add_child(_back_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_connect_button = _button("Connect", _on_connect)
	_connect_button.custom_minimum_size.x = 220
	footer.add_child(_connect_button)
	box.add_child(footer)
	_set_color(saved)
	if not matched:
		_custom_color.color = saved


func _field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", UiTheme.GOLD)
	l.add_theme_font_size_override("font_size", 15)
	return l


func _swatch(c: Color) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = _swatch_group
	b.custom_minimum_size = Vector2(48, 40)
	b.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := UiTheme.box(c, Color(0.1, 0.07, 0.1), 2, 6, 0)
		if state.begins_with("hover"):
			sb.border_color = UiTheme.GOLD.lightened(0.2)
		if state.ends_with("pressed"):
			sb.border_color = Color(1.0, 0.92, 0.7)
			sb.set_border_width_all(4)
		b.add_theme_stylebox_override(state, sb)
	b.toggled.connect(func(on: bool) -> void:
		if on:
			_set_color(c))
	return b


func _build_preview() -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiTheme.box(Color(0.04, 0.03, 0.06, 0.8), Color(0.4, 0.32, 0.2), 1, 8, 4))
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(250, 330)
	container.stretch = true
	frame.add_child(container)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	container.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.65)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.position = Vector3(0, 1.25, 4.4)
	cam.rotation.x = -0.06
	vp.add_child(cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_color = Color(1.0, 0.92, 0.8)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_color = Color(0.6, 0.7, 1.0)
	rim.light_energy = 0.8
	vp.add_child(rim)
	_preview_root = Node3D.new()
	vp.add_child(_preview_root)
	var tag := Label3D.new()
	tag.name = "Tag"
	tag.font_size = 48
	tag.pixel_size = 0.005
	tag.outline_size = 10
	tag.position.y = 2.35
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	vp.add_child(tag)
	return frame


func _set_color(c: Color) -> void:
	_color = c
	if _preview_root == null:
		return
	if _preview_model:
		_preview_model.queue_free()
	_preview_model = PlayerModel.new(c)
	_preview_root.add_child(_preview_model)
	_refresh_preview_name()


func _refresh_preview_name() -> void:
	var tag := _preview_root.get_parent().get_node("Tag") as Label3D
	tag.text = _nickname()
	tag.modulate = _color.lightened(0.45)
	tag.outline_modulate = Color(0.05, 0.03, 0.06)


func _nickname() -> String:
	var n := _name_edit.text.strip_edges()
	return n if not n.is_empty() else "Wizard"


func _process(delta: float) -> void:
	if _preview_root and _connect.visible:
		_preview_root.rotation.y += delta * 0.6


# --- Connecting -------------------------------------------------------------------------

func _on_connect() -> void:
	if _busy:
		return
	Settings.set_value("player_name", _name_edit.text.strip_edges())
	Settings.set_value("player_color", _color.to_html(false))
	Settings.set_value("server_address", _address_edit.text.strip_edges())
	_set_busy(true)
	_progress.visible = false
	Net.connect_to_host(_address_edit.text, _nickname(), _color)


func _on_back() -> void:
	if _busy:
		Net.leave()
		_set_busy(false)
		_set_status("Cancelled.", false)
		return
	_show_menu()


func _set_busy(on: bool) -> void:
	_busy = on
	_connect_button.disabled = on
	_name_edit.editable = not on
	_address_edit.editable = not on
	_back_button.text = "Cancel" if on else "Back"


func _set_status(text: String, error: bool) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45) if error else UiTheme.TEXT)


func _on_status(text: String) -> void:
	_set_status(text, false)


func _on_failed(reason: String) -> void:
	_set_busy(false)
	_progress.visible = false
	_set_status(reason, true)


func _on_progress(f: float) -> void:
	_progress.visible = true
	_progress.value = f


func _on_world_ready() -> void:
	_set_status("Entering the world…", false)
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)
