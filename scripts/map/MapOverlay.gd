class_name MapOverlay
extends CanvasLayer
## The world map (default key M): an inked relief map drawn over the blurred, paused game.
## It unrolls, the relief rises out of the paper, and it can be turned and zoomed with the
## mouse. The camera eases slowly towards where it is dragged and the sheet leans a little
## with the turning speed.

@export var player_path: NodePath

const FOCUS := Vector3(0.0, 0.0, 0.3)
## Camera follows the drag target with exponential easing (per second; lower = slower).
const EASE := 5.0
const SWAY := 0.05
const MAX_TILT := 0.16
const UNROLL_SPEED := 0.55
const RELIEF_SPEED := 0.8

var builder: MapBuilder

var _viewport: SubViewport
var _root: Node3D
var _camera: Camera3D
var _hint: Label
var _built := false
var _is_open := false
var _target := 0.0
var _progress := 0.0
var _relief_t := 0.0
var _time := 0.0
var _dragging := false
var _shadow: MeshInstance3D
var _remote_pins := {}  # peer id -> pin Node3D
var _backdrop: TextureRect
var _legend: PanelContainer
## Which kinds of names the map shows (legend, bottom left); kept for the session.
static var show_locations := true
static var show_landmarks := true

var _yaw := 0.0
var _pitch := 0.84
var _dist := 14.0
var _t_yaw := 0.0
var _t_pitch := 0.84
var _t_dist := 14.0
var _v_yaw := 0.0
var _v_pitch := 0.0


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("map_overlay")
	# A blurred still of the game; the live 3D world is switched off while the map is open.
	_backdrop = TextureRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	_backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var blur := ShaderMaterial.new()
	blur.shader = preload("res://shaders/ui_blur_texture.gdshader")
	_backdrop.material = blur
	add_child(_backdrop)

	var container := SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(_viewport)
	_root = Node3D.new()
	_viewport.add_child(_root)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_camera.near = 0.05
	_camera.far = 100.0
	_viewport.add_child(_camera)

	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.position.y -= 24
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Palatino Linotype", "Book Antiqua", "Georgia", "serif"])
	font.font_italic = true
	_hint.add_theme_font_override("font", font)
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_color", Color(0.93, 0.86, 0.7))
	_hint.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.04))
	_hint.add_theme_constant_override("outline_size", 6)
	add_child(_hint)
	_build_legend(font)
	visible = false


## Legend in the bottom-left corner: toggles location names (forests, lake, mountains) and
## landmark names (built places: the Waystone Circle, later the secret village).
func _build_legend(font: Font) -> void:
	_legend = PanelContainer.new()
	_legend.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_legend.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_legend.offset_left = 24
	_legend.offset_bottom = -24
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.91, 0.84, 0.68, 0.94)
	style.border_color = Color(0.18, 0.125, 0.08)
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(12)
	_legend.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_legend.add_child(box)
	var ink := Color(0.18, 0.125, 0.08)
	var title := Label.new()
	title.text = "Legend"
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", ink)
	box.add_child(title)
	for landmark in [false, true]:
		var cb := CheckBox.new()
		cb.text = "Landmark names" if landmark else "Location names"
		cb.button_pressed = show_landmarks if landmark else show_locations
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_override("font", font)
		cb.add_theme_font_size_override("font_size", 19)
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			cb.add_theme_color_override(key, ink)
		cb.toggled.connect(func(on: bool) -> void:
			if landmark:
				MapOverlay.show_landmarks = on
			else:
				MapOverlay.show_locations = on)
		box.add_child(cb)
	add_child(_legend)


## Builds the map from the finished world. Awaitable (renders the inked paper once).
func build(world: Node) -> void:
	builder = MapBuilder.new(world)
	await builder.build_scene(_root, self)
	_add_paper_shadow()
	_built = true


func is_open() -> bool:
	return _is_open


func open() -> void:
	if not _built or _is_open:
		return
	_is_open = true
	var still := get_viewport().get_texture().get_image()
	still.generate_mipmaps()
	_backdrop.texture = ImageTexture.create_from_image(still)
	get_viewport().disable_3d = true
	visible = true
	_target = 1.0
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Online the world keeps running behind the map (the player only loses input).
	get_tree().paused = not Net.is_online()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hint.text = "Drag to turn  ·  Scroll to zoom  ·  %s to close" % Settings.binding_text("toggle_map")


func close() -> void:
	_target = 0.0
	_dragging = false


func _finish_close() -> void:
	_is_open = false
	visible = false
	get_viewport().disable_3d = false
	_backdrop.texture = null
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _can_open() -> bool:
	var player := get_node_or_null(player_path)
	var menu := get_tree().get_first_node_in_group("pause_menu")
	var inv := get_tree().get_first_node_in_group("inventory_ui")
	if inv and inv.is_open():
		return false
	return _built and player != null and player.process_mode != Node.PROCESS_MODE_DISABLED 		and not get_tree().paused and not (menu and menu.is_open())


func _input(event: InputEvent) -> void:
	if not _is_open:
		if event.is_action_pressed("toggle_map") and not event.is_echo() and _can_open():
			open()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouse and not _dragging and _legend.get_global_rect().has_point(event.position):
		return  # the legend's checkboxes
	get_viewport().set_input_as_handled()
	if _target == 0.0:
		return
	if (event.is_action_pressed("toggle_map") or event.is_action_pressed("pause")) and not event.is_echo():
		close()
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_t_dist = clampf(_t_dist * 0.9, 5.0, 20.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_t_dist = clampf(_t_dist / 0.9, 5.0, 20.0)
	elif event is InputEventMouseMotion and _dragging:
		_t_yaw -= event.relative.x * 0.005
		_t_pitch = clampf(_t_pitch + event.relative.y * 0.004, 0.3, 1.45)


func _process(delta: float) -> void:
	if not visible:
		return
	delta = minf(delta, 0.05)
	_time += delta
	_animate_sheet(delta)
	_animate_camera(delta)
	_animate_pieces()


func _animate_sheet(delta: float) -> void:
	# Unroll, then raise the relief; closing does the reverse.
	if _target > 0.5:
		_progress = minf(1.0, _progress + delta * UNROLL_SPEED)
		if _progress >= 1.0:
			_relief_t = minf(1.0, _relief_t + delta * RELIEF_SPEED)
	else:
		_relief_t = maxf(0.0, _relief_t - delta * RELIEF_SPEED * 2.0)
		if _relief_t <= 0.0:
			_progress = maxf(0.0, _progress - delta * UNROLL_SPEED * 1.4)
			if _progress <= 0.0:
				_finish_close()
				return
	var eased := 1.0 - pow(1.0 - _progress, 3.0)
	var relief := _relief_t * _relief_t * (3.0 - 2.0 * _relief_t)
	builder.sheet_material.set_shader_parameter("progress", eased)
	builder.sheet_material.set_shader_parameter("relief_amount", relief)
	builder.tree_material.set_shader_parameter("relief_amount", relief)
	if _shadow:
		_shadow.scale.x = maxf(0.05, eased)
		_shadow.position.x = -MapBuilder.PAPER_W * 0.5 * (1.0 - eased)


func _animate_camera(delta: float) -> void:
	var k := 1.0 - exp(-EASE * delta)
	var yaw := lerpf(_yaw, _t_yaw, k)
	var pitch := lerpf(_pitch, _t_pitch, k)
	# Rates of change drive the sheet's lean; easing never overshoots, so neither does it.
	_v_yaw = (yaw - _yaw) / maxf(delta, 0.0001)
	_v_pitch = (pitch - _pitch) / maxf(delta, 0.0001)
	_yaw = yaw
	_pitch = pitch
	_dist = lerpf(_dist, _t_dist, k)
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	_camera.position = FOCUS + dir * _dist
	_camera.look_at(FOCUS)
	# The sheet leans into the turn, like paper held by its corners.
	var right := _camera.global_basis.x
	right.y = 0.0
	var fwd := Vector3(-dir.x, 0.0, -dir.z).normalized()
	var roll := clampf(_v_yaw * SWAY, -MAX_TILT, MAX_TILT)
	var tilt := clampf(-_v_pitch * SWAY, -MAX_TILT, MAX_TILT)
	_root.basis = Basis(fwd, roll) * Basis(right.normalized(), tilt)
	_root.position.y = sin(_time * 0.7) * 0.03


func _animate_pieces() -> void:
	var relief := _relief_t * _relief_t * (3.0 - 2.0 * _relief_t)
	var shown := relief > 0.01
	for p in builder.pops:
		var node: Node3D = p[0]
		var base: Vector3 = p[1]
		var category: String = p[3] if p.size() > 3 else ""
		node.visible = shown and (category != "location" or show_locations) and (category != "landmark" or show_landmarks)
		node.position = Vector3(base.x, base.y * relief, base.z)
		node.scale = (p[2] as Vector3) * minf(1.0, relief * 1.3)
	for f in builder.floaters:
		var node: Node3D = f.node
		var base: Vector3 = f.base
		node.visible = shown
		node.position = Vector3(base.x, 0.2 + (base.y - 0.2) * relief + sin(_time * 0.8 + f.phase) * 0.06, base.z)
		node.rotation.y = _time * 0.05 + f.phase
		node.scale = Vector3.ONE * maxf(0.001, relief)
		for pb in f.pebbles:
			var pn: Node3D = pb.node
			pn.visible = shown
			var a: float = pb.a + _time * pb.sp
			pn.position = node.position + Vector3(cos(a) * pb.rr * relief, pb.y * relief + sin(_time + pb.a) * 0.03, sin(a) * pb.rr * relief)
	if builder.water:
		builder.water.visible = shown
		builder.water.position.y = (builder.water_relief * MapBuilder.RELIEF_SCALE - 0.012) * relief
	var player := get_node_or_null(player_path) as Node3D
	if builder.pin and player:
		builder.pin.visible = shown
		builder.pin.position = _pin_position(player.global_position, relief, sin(_time * 2.0) * 0.025)
		builder.pin.rotation.y = _time * 0.9
		builder.pin.scale = Vector3.ONE * maxf(0.001, relief)
		if builder.pin_arrow:
			builder.pin_arrow.visible = shown
			builder.pin_arrow.position = _pin_position(player.global_position, relief, 0.0)
			builder.pin_arrow.rotation.y = player.rotation.y
			builder.pin_arrow.scale = Vector3.ONE * maxf(0.001, relief)
	_animate_remote_pins(shown, relief)


## Where a player's pin stands on the map: on the miniature of the floating island they are on
## (or just above), otherwise on the relief.
func _pin_position(world: Vector3, relief: float, bob: float) -> Vector3:
	for f in builder.floaters:
		var isl := f.get("island") as FloatingIsland
		if not is_instance_valid(isl):
			continue
		var local := isl.to_local(world)
		var rim := isl.shape.rim_radius(atan2(local.z, local.x))
		if Vector2(local.x, local.z).length() > rim * 1.05:
			continue
		var top := isl.shape.top_y(local.x, local.z)
		if local.y < top - 3.0 or local.y > top + 30.0:
			continue
		# Island-local position scaled onto the miniature (its top is at radius * 0.1).
		var k: float = f.radius / isl.shape.radius * 0.85
		var node: Node3D = f.node
		return node.transform * Vector3(local.x * k, f.radius * 0.1 + 0.02 / maxf(relief, 0.001) + bob, local.z * k)
	var base := builder.map_to_3d(builder.world_to_map(Vector2(world.x, world.z)))
	return Vector3(base.x, base.y * relief + 0.02 + bob, base.z)


## Pins for the other players, in their colours and with their names.
func _animate_remote_pins(shown: bool, relief: float) -> void:
	var seen := {}
	for a in get_tree().get_nodes_in_group("remote_player"):
		var remote := a as RemotePlayer
		if remote == null or not remote.visible:
			continue
		seen[remote.peer_id] = true
		var p: Node3D = _remote_pins.get(remote.peer_id)
		if p == null:
			p = builder.make_pin(remote.player_color, remote.player_name)
			_root.add_child(p)
			_remote_pins[remote.peer_id] = p
		p.visible = shown
		p.position = _pin_position(remote.global_position, relief, sin(_time * 2.0 + remote.peer_id) * 0.025)
		p.rotation.y = _time * 0.9 + remote.peer_id
		p.scale = Vector3.ONE * maxf(0.001, relief) * 0.85
	for id in _remote_pins.keys():
		if not seen.has(id):
			_remote_pins[id].queue_free()
			_remote_pins.erase(id)


func _add_paper_shadow() -> void:
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.5))
	g.set_color(1, Color(0, 0, 0, 0))
	tex.gradient = g
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	var quad := PlaneMesh.new()
	quad.size = Vector2(MapBuilder.PAPER_W * 1.3, MapBuilder.PAPER_D * 1.35)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.position.y = -0.05
	_root.add_child(mi)
	_shadow = mi
