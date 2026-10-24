extends CanvasLayer
## In-game HUD: ornate mana bar above the health bar in the bottom-left corner, the
## full-screen dash effect (radial blur) driven by the player's dash, the scope overlay of
## aimed spells, a red flash when hit, a hit marker when the player's shot lands, a message
## when struck down, and the spectral chain border (a quick flash at the moment a chain grabs:
## for the caster when theirs catches something, for the one caught by someone else's).

@export var player_path: NodePath

const BAR_SIZE := Vector2(390, 28)
const MARGIN := Vector2(46, 26)
const GAP := 14.0
## The chain grab flash lasts 1 / CHAIN_FLASH_SPEED seconds.
const CHAIN_FLASH_SPEED := 3.2
const HEAT_GAUGE_SIZE := Vector2(150, 150)

var _player: Node
var _grimoire: Grimoire
var _mana: MagicBar
var _health: MagicBar
var _dash_rect: ColorRect
var _dash_mat: ShaderMaterial
var _scope_rect: ColorRect
var _scope_mat: ShaderMaterial
var _damage_rect: ColorRect
var _damage_mat: ShaderMaterial
var _chain_rect: ColorRect
var _chain_mat: ShaderMaterial
var _chain_flash := 0.0
var _hole_rect: ColorRect
var _burn_rect: ColorRect
var _burn_mat: ShaderMaterial
var _burn := 0.0
var _hole_mat: ShaderMaterial
var _inferno_rect: ColorRect
var _inferno_mat: ShaderMaterial
var _inferno := 0.0
var _smoke_rect: ColorRect
var _smoke_mat: ShaderMaterial
var _smoke := 0.0
var _heat_rect: ColorRect
var _heat_mat: ShaderMaterial
var _heat_label: Label
var _hitmarker: Label
## Arcane crosshair (crosshair.gdshader), tinted in the open spell's colour; kicks on a cast.
var _crosshair: ColorRect
var _cross_mat: ShaderMaterial
var _cross_spin := 0.0
var _cross_pulse := 0.0
const CROSSHAIR_SIZE := 72.0
var _message: Label
## Heading strip at the top of the screen.
var _compass: CompassBar
var _root: Control
var _frames := 0
var _damage := 0.0
var _fire_flash := 0.0


func _ready() -> void:
	layer = 5
	add_to_group("hud")
	_player = get_node_or_null(player_path)

	# Full-screen effects; shown (at zero strength) for the first frames so their shaders
	# compile during loading.
	_dash_mat = _screen_material(preload("res://shaders/ui/dash_screen.gdshader"))
	_dash_rect = _screen_rect(_dash_mat)
	_scope_mat = _screen_material(preload("res://shaders/ui/scope.gdshader"))
	_scope_rect = _screen_rect(_scope_mat)
	_damage_mat = _screen_material(preload("res://shaders/ui/damage_screen.gdshader"))
	_damage_rect = _screen_rect(_damage_mat)
	# Black hole edge warp first, so the other overlays and bars stay undistorted on top.
	_hole_mat = _screen_material(preload("res://shaders/ui/black_hole_screen.gdshader"))
	_hole_rect = _screen_rect(_hole_mat)
	move_child(_hole_rect, 0)
	_burn_mat = _screen_material(preload("res://shaders/ui/burn_screen.gdshader"))
	_burn_rect = _screen_rect(_burn_mat)
	move_child(_burn_rect, 1)
	_inferno_mat = _screen_material(preload("res://shaders/ui/inferno_screen.gdshader"))
	_inferno_rect = _screen_rect(_inferno_mat)
	move_child(_inferno_rect, 2)
	_smoke_mat = _screen_material(preload("res://shaders/ui/smoke_screen.gdshader"))
	_smoke_rect = _screen_rect(_smoke_mat)
	move_child(_smoke_rect, 3)
	_chain_mat = _screen_material(preload("res://shaders/ui/chain_screen.gdshader"))
	_chain_rect = _screen_rect(_chain_mat)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_mana = MagicBar.new(Color(0.1, 0.16, 0.72), Color(0.42, 0.76, 1.0), 0.0, BAR_SIZE)
	_health = MagicBar.new(Color(0.5, 0.04, 0.08), Color(1.0, 0.38, 0.3), 3.7, BAR_SIZE)
	_root.add_child(_mana)
	_root.add_child(_health)
	_heat_mat = _screen_material(preload("res://shaders/ui/heat_gauge.gdshader"))
	_heat_rect = ColorRect.new()
	_heat_rect.material = _heat_mat
	_heat_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heat_rect.size = HEAT_GAUGE_SIZE
	_root.add_child(_heat_rect)
	_heat_label = _label("OVERHEATED", 24, Color(1.0, 0.62, 0.88))
	_cross_mat = ShaderMaterial.new()
	_cross_mat.shader = preload("res://shaders/ui/crosshair.gdshader")
	_cross_mat.set_shader_parameter("tint", Color(1.0, 0.85, 0.55))
	_crosshair = ColorRect.new()
	_crosshair.material = _cross_mat
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_crosshair)
	_hitmarker = _label("✕", 44, Color(1.0, 0.3, 0.3))
	_message = _label("", 34, Color(1.0, 0.86, 0.7))
	_compass = CompassBar.new()
	_root.add_child(_compass)
	_root.resized.connect(_layout)
	_layout()

	if _player:
		_grimoire = _player.get("grimoire")
		if _grimoire:
			_grimoire.cast_failed.connect(func(_spell: Spell, reason: Grimoire.CastBlock) -> void:
				if reason == Grimoire.CastBlock.NOT_ENOUGH_MANA:
					_mana.pulse())
			_grimoire.spell_cast.connect(func(_spell: Spell) -> void:
				_cross_pulse = 1.0)
			_grimoire.aim_ended.connect(func(_spell: Spell, fired: bool) -> void:
				if fired:
					_fire_flash = 1.0)
		_player.damaged.connect(func(amount: float, _from: int) -> void:
			# Small hits (rapid fire) flash a little, big ones fully.
			_damage = maxf(_damage, clampf(amount / 25.0, 0.2, 1.0))
			_health.pulse())
		_player.died.connect(_on_died)
		_player.chained.connect(func(_by: int) -> void:
			_chain_flash = 1.0)
		_player.chain_caught.connect(func(_target: int) -> void:
			_chain_flash = 1.0)
		_player.hit_landed.connect(func(_target: int) -> void:
			_hitmarker.modulate.a = 1.0
			_hitmarker.scale = Vector2.ONE * 1.4)


## Heading from the player's view; a marker towards the Waystone Circle.
func _update_compass() -> void:
	_compass.set_heading(CompassBar.heading_from_yaw(_player.rotation.y))
	var world := get_tree().current_scene.get_node_or_null("World")
	var site: StartSite = world.get("start_site") if world else null
	_compass.markers.clear()
	if site:
		var p := Vector3(site.center.x, 0.0, site.center.y)
		if Vector2(_player.global_position.x, _player.global_position.z).distance_to(site.center) > 15.0:
			_compass.markers.append({"bearing": CompassBar.bearing(_player.global_position, p), "color": Color(0.45, 0.72, 1.0)})
	_compass.queue_redraw()


func _screen_material(shader: Shader) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


func _screen_rect(mat: ShaderMaterial) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	add_child(rect)
	return rect


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.theme = UiTheme.make()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.03))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate.a = 0.0
	_root.add_child(l)
	return l


func _layout() -> void:
	# Positions of the capsules themselves; each bar rect has PAD of room around its capsule.
	var view := _root.size
	var x := MARGIN.x - MagicBar.PAD
	_health.position.y = view.y - MARGIN.y - BAR_SIZE.y - MagicBar.PAD
	_mana.position.y = _health.position.y - BAR_SIZE.y - GAP
	_mana.set_base_x(x)
	_health.set_base_x(x)
	var k := clampf(view.y / 1080.0, 0.7, 2.0)
	_crosshair.size = Vector2.ONE * roundf(CROSSHAIR_SIZE * k)
	_crosshair.position = (view * 0.5 - _crosshair.size * 0.5).round()
	_cross_mat.set_shader_parameter("size_px", _crosshair.size.x)
	_cross_mat.set_shader_parameter("px_scale", k)
	_hitmarker.size = Vector2(80, 80)
	_hitmarker.position = view * 0.5 - _hitmarker.size * 0.5
	_hitmarker.pivot_offset = _hitmarker.size * 0.5
	_heat_rect.position = view * 0.5 - HEAT_GAUGE_SIZE * 0.5
	_heat_label.size = Vector2(300, 40)
	_heat_label.position = Vector2(view.x * 0.5 - 150, view.y * 0.5 + HEAT_GAUGE_SIZE.y * 0.5 + 6)
	_compass.scale = Vector2.ONE * clampf(view.y / 1080.0, 0.75, 1.6)
	_compass.position = Vector2((view.x - CompassBar.SIZE.x * _compass.scale.x) * 0.5, 14.0)
	_message.size = Vector2(view.x, 60)
	_message.position = Vector2(0, view.y * 0.3)


## Edge distortion from the strongest black hole nearby.
func _update_black_hole(warm: bool, view: Vector2, aspect: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var best := 0.0
	var focus := Vector2(0.5, 0.5)
	if cam:
		for node in get_tree().get_nodes_in_group("black_hole"):
			var hole := node as BlackHole
			var k := hole.screen_intensity(cam.global_position) if hole else 0.0
			if k > best:
				best = k
				var c := hole.get_center()
				if not cam.is_position_behind(c):
					focus = (cam.unproject_position(c) / view).clamp(Vector2(-0.5, -0.5), Vector2(1.5, 1.5))
	_hole_rect.visible = best > 0.005 or warm
	if _hole_rect.visible:
		_hole_mat.set_shader_parameter("intensity", best)
		_hole_mat.set_shader_parameter("roots", 16 if Settings.get_value("fancy_black_hole") else 6)
		_hole_mat.set_shader_parameter("aspect", aspect)
		_hole_mat.set_shader_parameter("focus", focus)


## Smoke at the screen edges from the strongest Infernal Torrent: the caster's own, or one the
## player is caught in.
func _update_inferno(warm: bool, view: Vector2, aspect: float, delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var best := 0.0
	var focus := Vector2(0.5, 0.5)
	if cam:
		for node in get_tree().get_nodes_in_group("inferno"):
			var beam := node as InfernoBeam
			var k := beam.screen_intensity(cam.global_position) if beam else 0.0
			if k > best:
				best = k
				var c := beam.get_focus_point()
				if not cam.is_position_behind(c):
					focus = (cam.unproject_position(c) / view).clamp(Vector2(0.1, 0.1), Vector2(0.9, 0.9))
	_inferno = move_toward(_inferno, best, delta * (5.0 if best > _inferno else 1.5))
	_inferno_rect.visible = _inferno > 0.005 or warm
	if _inferno_rect.visible:
		_inferno_mat.set_shader_parameter("intensity", _inferno)
		_inferno_mat.set_shader_parameter("aspect", aspect)
		_inferno_mat.set_shader_parameter("focus", focus)


## Big centred banner for a discovered place: "<who>" small above, the name large (group "hud").
func announce(title: String, who: String) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Palatino Linotype", "Book Antiqua", "Georgia", "serif"])
	for part in [[who, 26, Color(0.93, 0.86, 0.7), true], [title, 58, Color(1.0, 0.82, 0.45), false]]:
		var l := Label.new()
		l.text = part[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var f := font.duplicate() as SystemFont
		f.font_italic = part[3]
		l.add_theme_font_override("font", f)
		l.add_theme_font_size_override("font_size", part[1])
		l.add_theme_color_override("font_color", part[2])
		l.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.03, 0.9))
		l.add_theme_constant_override("outline_size", 10)
		box.add_child(l)
	_root.add_child(box)
	box.size = Vector2(_root.size.x, 140)
	box.position = Vector2(0, _root.size.y * 0.18)
	box.modulate.a = 0.0
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.8)
	tw.parallel().tween_property(box, "position:y", _root.size.y * 0.2, 0.8).from(_root.size.y * 0.17)
	tw.tween_interval(3.5)
	tw.tween_property(box, "modulate:a", 0.0, 1.5)
	tw.tween_callback(box.queue_free)


func _on_died(from_id: int) -> void:
	var killer: Dictionary = Net.players.get(from_id, {})
	_message.text = "Struck down by %s" % killer.name if not killer.is_empty() else "You were struck down"
	_message.modulate.a = 1.0
	var tw := _message.create_tween()
	tw.tween_interval(2.5)
	tw.tween_property(_message, "modulate:a", 0.0, 1.2)


func _process(delta: float) -> void:
	if _player == null:
		return
	# Hidden while the pause menu or map is open.
	visible = not _player.is_menu_open()
	_mana.set_values(_player.mana, _player.max_mana)
	_health.set_values(_player.health, _player.max_health)
	_frames += 1
	var warm := _frames < 5
	var s := get_viewport().get_visible_rect().size
	var aspect := s.x / maxf(s.y, 1.0)

	var dash: float = _player.dash_fx
	_dash_rect.visible = dash > 0.01 or warm
	if _dash_rect.visible:
		var cam := get_viewport().get_camera_3d()
		var focus := Vector2(0.5, 0.5)
		var dir: Vector3 = _player.dash_direction
		if cam and not cam.is_position_behind(cam.global_position + dir * 10.0):
			focus = (cam.unproject_position(cam.global_position + dir * 10.0) / s).clamp(Vector2(0.15, 0.2), Vector2(0.85, 0.8))
		_dash_mat.set_shader_parameter("intensity", dash)
		_dash_mat.set_shader_parameter("focus", focus)
		_dash_mat.set_shader_parameter("aspect", aspect)

	var scope: float = _player.scope
	_fire_flash = move_toward(_fire_flash, 0.0, delta * 4.0)
	_scope_rect.visible = scope > 0.001 or warm
	if _scope_rect.visible:
		_scope_mat.set_shader_parameter("amount", scope)
		_scope_mat.set_shader_parameter("aspect", aspect)
		var aiming := _grimoire != null and _grimoire.is_aiming()
		_scope_mat.set_shader_parameter("charge", _grimoire.get_aim_progress() if aiming else 1.0)
		_scope_mat.set_shader_parameter("released", 1.0 if aiming and _grimoire.is_aim_released() else 0.0)
		_scope_mat.set_shader_parameter("fire_flash", _fire_flash)

	_damage = move_toward(_damage, 0.0, delta * 1.5)
	var hp: float = _player.health / _player.max_health
	var low := clampf((0.35 - hp) / 0.35, 0.0, 1.0)
	_damage_rect.visible = _damage > 0.0 or low > 0.0 or warm
	if _damage_rect.visible:
		_damage_mat.set_shader_parameter("intensity", _damage)
		_damage_mat.set_shader_parameter("low_health", low)
		_damage_mat.set_shader_parameter("aspect", aspect)

	_update_black_hole(warm, s, aspect)
	# Flames at the screen edges while burning (fading in fast, out slowly).
	var burning: bool = _player.is_burning()
	_burn = move_toward(_burn, 1.0 if burning else 0.0, delta * (4.0 if burning else 1.2))
	_burn_rect.visible = _burn > 0.005 or warm
	if _burn_rect.visible:
		_burn_mat.set_shader_parameter("intensity", _burn)
		_burn_mat.set_shader_parameter("aspect", aspect)
	_update_inferno(warm, s, aspect, delta)
	# Inside a smoke cloud: the screen drowns in smoke.
	var cam := get_viewport().get_camera_3d()
	var thick := SmokeCloud.density_at(get_tree(), cam.global_position) if cam else 0.0
	_smoke = move_toward(_smoke, thick, delta * 3.0)
	_smoke_rect.visible = _smoke > 0.005 or warm
	if _smoke_rect.visible:
		_smoke_mat.set_shader_parameter("intensity", _smoke)
		_smoke_mat.set_shader_parameter("aspect", aspect)
	_chain_flash = move_toward(_chain_flash, 0.0, delta * CHAIN_FLASH_SPEED)
	_chain_rect.visible = _chain_flash > 0.0 or warm
	if _chain_rect.visible:
		_chain_mat.set_shader_parameter("intensity", _chain_flash)
		_chain_mat.set_shader_parameter("aspect", aspect)

	_update_compass()

	# Minigun heat gauge around the crosshair while the rig is out (or still cooling).
	var rig := _player.get_node_or_null("MinigunRig") as MinigunRig
	var presence := 0.0
	if rig:
		presence = maxf(rig.get_presence(), 1.0 if rig.is_overheated() else 0.0)
	_heat_rect.visible = presence > 0.01 or warm
	if _heat_rect.visible and rig:
		_heat_mat.set_shader_parameter("heat", rig.get_heat_fraction())
		_heat_mat.set_shader_parameter("spin", rig.spin)
		_heat_mat.set_shader_parameter("overheated", 1.0 if rig.is_overheated() else 0.0)
		_heat_mat.set_shader_parameter("presence", presence)
	_heat_label.modulate.a = (0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.015)) if rig and rig.is_overheated() else 0.0

	# Crosshair: hidden while scoped (the lens has its own reticle), dead, or the inventory has
	# the mouse.
	var inv := get_tree().get_first_node_in_group("inventory_ui")
	var show_cross: bool = scope < 0.2 and not _player.is_dead() and not (inv and inv.is_open())
	_crosshair.modulate.a = move_toward(_crosshair.modulate.a, 1.0 if show_cross else 0.0, delta * 8.0)
	_cross_pulse = move_toward(_cross_pulse, 0.0, delta * 3.0)
	_cross_spin += delta * (0.5 + 9.0 * _cross_pulse * _cross_pulse)
	var held: Spell = _grimoire.get_selected_spell() if _grimoire else null
	var tint := held.theme_color if held else Color(1.0, 0.85, 0.55)
	var cur: Color = _cross_mat.get_shader_parameter("tint")
	_cross_mat.set_shader_parameter("tint", cur.lerp(tint, 1.0 - exp(-8.0 * delta)))
	_cross_mat.set_shader_parameter("spin", _cross_spin)
	_cross_mat.set_shader_parameter("pulse", _cross_pulse * _cross_pulse)
	_hitmarker.modulate.a = move_toward(_hitmarker.modulate.a, 0.0, delta * 2.0)
	_hitmarker.scale = _hitmarker.scale.lerp(Vector2.ONE, 1.0 - exp(-12.0 * delta))
