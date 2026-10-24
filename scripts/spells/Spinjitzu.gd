class_name Spinjitzu
extends Node3D
## A Spinjitzu tornado around one player (SpinjitzuSpell): LAYERS shallow funnel-lip rings stacked
## up the funnel, each covered in the simple black hole disk's streaming filaments
## (shaders/vfx/spinjitzu.gdshader), widening upwards, every one swaying and tilting on its own
## so it reads as a whirl of streaks rather than a shape; inside them an open funnel of the same
## streaks (spinjitzu_core.gdshader, CORE_SCALE of the funnel radius, ending below the top
## rings) gives it density without more layers; plus rings of motes whirled round at
## three heights, streaks whipped round the foot and a soft light – all in the player's colour.
## The layers turn with the player's yaw; on the middle ones a "window" (thin filaments, bright
## seams) shows where the player faces.
##   Local (the caster's own): Grimoire channel (cast again → cancel()), speeds the player up
##     (Player.move_boost), drains mana, every TICK hits players it touches ({"kind": "hit"} with
##     damage + push) and ends on death / no mana; seen from inside (dimmed, wider window).
##   Remote: follows the avatar, ends on {"kind": "spin_end"} or the avatar's death.

const TICK := 0.2
const SPIN_UP := 0.25
const SPIN_DOWN := 0.35
const LAYERS := 26
## Inner edge of a layer ring (outer = 1, mesh units) and how far its outer edge is raised.
const INNER := 0.35
const LIP := 0.4
const SEGMENTS := 64
const SHADER := preload("res://shaders/vfx/spinjitzu.gdshader")
const CORE_SHADER := preload("res://shaders/vfx/spinjitzu_core.gdshader")
## Inner funnel: share of the funnel radius and of the height (stays inside / below the rings).
const CORE_SCALE := 0.72
const CORE_HEIGHT := 0.86

static var _mesh: ArrayMesh
static var _core_meshes := {}

var spell: SpinjitzuSpell
var owner_id := -1
var is_local := false
var _player: Node3D
var _avatar: RemotePlayer
var _strength := 0.0
var _ending := false
var _tick := 0.0
var _age := 0.0
var _layers: Array[MeshInstance3D] = []
var _core: MeshInstance3D
var _spinner: Node3D
var _sparkles: Array[GPUParticles3D] = []
var _dust: GPUParticles3D
var _light: OmniLight3D
var _color := Color.WHITE
## Prewarm copy: stands still, never ends by itself.
var _static := false


static func start_local(spin_spell: SpinjitzuSpell, player: Node3D) -> Spinjitzu:
	var s := _make(spin_spell, Net.my_id, true, Net.my_color if Net.is_online() else spin_spell.theme_color)
	s._player = player
	player.get_tree().current_scene.add_child(s)
	player.grimoire.begin_channel(s)
	player.move_boost = spin_spell.speed_factor
	return s


static func start_remote(spin_spell: SpinjitzuSpell, avatar: RemotePlayer) -> Spinjitzu:
	for node in avatar.get_tree().get_nodes_in_group("spinjitzu"):
		var old := node as Spinjitzu
		if old and old.owner_id == avatar.peer_id:
			old.stop(false)
	var s := _make(spin_spell, avatar.peer_id, false, avatar.player_color)
	s._avatar = avatar
	avatar.get_tree().current_scene.add_child(s)
	return s


static func _make(spin_spell: SpinjitzuSpell, owner: int, local: bool, color: Color) -> Spinjitzu:
	var s := Spinjitzu.new()
	s.spell = spin_spell
	s.owner_id = owner
	s.is_local = local
	# Keep it bright and saturated whatever colour the player picked.
	var c := color
	c.s = maxf(c.s, 0.55)
	c.v = maxf(c.v, 0.85)
	s._color = c
	return s


static func prewarm(vp: Node) -> void:
	var s := _make(load("res://spells/spinjitzu.tres"), -1, false, Color(1.0, 0.75, 0.25))
	s._static = true
	vp.add_child(s)
	s.position = Vector3(0, 0, -6)
	vp.get_tree().create_timer(0.5).timeout.connect(s.queue_free)


func _ready() -> void:
	add_to_group("spinjitzu")
	top_level = true
	var accent := _color.lerp(Color.WHITE, 0.7)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("color", _color)
	mat.set_shader_parameter("accent", accent)
	mat.set_shader_parameter("inner", INNER)
	for i in LAYERS:
		var mi := MeshInstance3D.new()
		mi.mesh = _ring_mesh()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var v := float(i) / (LAYERS - 1)
		mi.set_instance_shader_parameter("speed", lerpf(1.6, 1.0, v) * (1.0 + 0.15 * sin(i * 2.3)))
		mi.set_instance_shader_parameter("seed", float(i) * 3.17)
		mi.set_instance_shader_parameter("inside", 1.0 if is_local else 0.0)
		mi.set_instance_shader_parameter("window", smoothstep(0.15, 0.35, v) * (1.0 - smoothstep(0.7, 0.9, v)))
		mi.set_instance_shader_parameter("strength", 0.0)
		add_child(mi)
		_layers.append(mi)
	_core = MeshInstance3D.new()
	_core.mesh = _core_mesh(spell)
	var core_mat := ShaderMaterial.new()
	core_mat.shader = CORE_SHADER
	core_mat.set_shader_parameter("color", _color)
	core_mat.set_shader_parameter("accent", accent)
	_core.material_override = core_mat
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.set_instance_shader_parameter("inside", 1.0 if is_local else 0.0)
	_core.set_instance_shader_parameter("strength", 0.0)
	add_child(_core)
	# Motes whirled round with the funnel (local coordinates of a turning node) at three heights.
	_spinner = Node3D.new()
	add_child(_spinner)
	for h in [0.35, 1.4, 2.5]:
		var p := SpellFx.particles(_spinner, 30 if is_local else 50, 0.8, false, false, Vector2(0.07, 0.07), accent, _color)
		p.local_coords = true
		var pm := p.process_material as ParticleProcessMaterial
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = spell.radius_at(h) * 1.05
		pm.emission_ring_inner_radius = spell.radius_at(h) * 0.6
		pm.emission_ring_height = 0.5
		pm.direction = Vector3.UP
		pm.spread = 25.0
		pm.initial_velocity_min = 0.8
		pm.initial_velocity_max = 2.0
		p.position.y = h
		_sparkles.append(p)
	# Dust and streaks whipped round the foot.
	_dust = SpellFx.particles(_spinner, 24, 0.5, false, true, Vector2(0.04, 0.6), _color, accent)
	_dust.local_coords = true
	_dust.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var dm := _dust.process_material as ParticleProcessMaterial
	dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	dm.emission_ring_axis = Vector3.UP
	dm.emission_ring_radius = spell.bottom_radius + 0.6
	dm.emission_ring_inner_radius = spell.bottom_radius + 0.2
	dm.emission_ring_height = 0.1
	dm.direction = Vector3(1, 0.3, 0)
	dm.spread = 15.0
	dm.initial_velocity_min = 3.0
	dm.initial_velocity_max = 6.0
	_dust.position.y = 0.15
	_light = OmniLight3D.new()
	_light.light_color = _color
	_light.omni_range = 6.0
	_light.light_energy = 0.0
	_light.light_volumetric_fog_energy = 0.0
	_light.shadow_enabled = false
	_light.position.y = 1.4
	add_child(_light)
	# Spin-up burst.
	var root := SpellFx.effect_root(get_parent(), _feet(), 1.0)
	var ring := SpellFx.ring(root, true, spell.top_radius * 2.6, _color, accent)
	SpellFx.animate_ring(ring, 0.6, 2.0)
	_follow()
	if not is_local:
		Net.event_received.connect(_on_net_event)


## Cast pressed again: spin down.
func cancel() -> void:
	stop(true)


func stop(send: bool) -> void:
	if _ending:
		return
	_ending = true
	for p in _sparkles:
		p.emitting = false
	_dust.emitting = false
	if is_local:
		if is_instance_valid(_player):
			_player.grimoire.end_channel(self)
			_player.move_boost = 1.0
		if send:
			Net.send_event({"kind": "spin_end"})


func _on_net_event(id: int, ev: Dictionary) -> void:
	if id == owner_id and str(ev.get("kind", "")) == "spin_end":
		stop(false)


func _feet() -> Vector3:
	if is_local and is_instance_valid(_player):
		return _player.global_position - Vector3.UP * float(_player.get("FOOT_OFFSET"))
	if is_instance_valid(_avatar):
		return _avatar.global_position
	return global_position


func _follow() -> void:
	var yaw := 0.0
	if is_local and is_instance_valid(_player):
		yaw = _player.rotation.y
	elif is_instance_valid(_avatar):
		yaw = _avatar.rotation.y
	global_transform = Transform3D(Basis(Vector3.UP, yaw), _feet())


func _process(delta: float) -> void:
	_age += delta
	if not _ending and not _static:
		var gone := false
		if is_local:
			gone = not is_instance_valid(_player) or _player.is_dead()
		else:
			gone = not is_instance_valid(_avatar) or _avatar.is_dead()
		if gone:
			stop(true)
		elif is_local:
			var cost := spell.drain * delta
			if not _player.has_mana(cost):
				_player.spend_mana(_player.mana)
				stop(true)
			else:
				_player.spend_mana(cost)
	_strength = move_toward(_strength, 0.0 if _ending else 1.0, delta / (SPIN_DOWN if _ending else SPIN_UP))
	if _ending and _strength <= 0.0:
		queue_free()
		return
	_follow()
	_animate_layers()
	_spinner.rotation.y += delta * TAU * 1.6
	_light.light_energy = 1.4 * _strength
	if is_local and not _ending:
		_tick -= delta
		if _tick <= 0.0:
			_tick = TICK
			_hit_touching()


## Every player inside the funnel takes a tick of damage and is flung outwards and round.
func _hit_touching() -> void:
	var base := global_position
	for node in get_tree().get_nodes_in_group("remote_player"):
		var a := node as RemotePlayer
		if a == null or not a.visible or a.is_dead():
			continue
		if a is Decoy and (a as Decoy).owner_id == owner_id:
			continue
		var h := a.global_position.y - base.y
		if h < -1.6 or h > spell.height:
			continue
		var flat := Vector3(a.global_position.x - base.x, 0.0, a.global_position.z - base.z)
		if flat.length() > spell.radius_at(maxf(h, 0.0) + 0.9) + 0.4:
			continue
		var away := flat.normalized() if flat.length_squared() > 0.0001 else -global_basis.z
		var push := away * spell.fling + Vector3.UP.cross(away) * spell.fling * 0.5 + Vector3.UP * 3.5
		Net.send_event({"kind": "hit", "target": a.peer_id, "damage": spell.dps * TICK, "push": Net._vec(push)})
		if _player.has_method("confirm_hit"):
			_player.confirm_hit(a.peer_id)


## Each layer: its height and radius on the funnel, swaying sideways (more towards the top)
## and tilting a little on its own, so the stack never looks like a rigid shape.
func _animate_layers() -> void:
	var t := _age
	for i in _layers.size():
		var mi := _layers[i]
		var v := float(i) / (LAYERS - 1)
		var h := v * spell.height
		var r := spell.radius_at(h) * 1.15
		var axis := Vector3(cos(t * 1.3 + i * 0.9), 0.0, sin(t * 1.3 + i * 0.9))
		var tilt := 0.07 + 0.05 * sin(t * 2.1 + i * 1.7)
		var sway := Vector3(sin(h * 1.7 + t * 3.1), 0.0, cos(h * 1.3 + t * 2.6)) * 0.06 * h
		# Each layer swells and shrinks a little as it spins.
		r *= 1.0 + 0.06 * sin(t * 5.0 + i * 2.4)
		mi.transform = Transform3D(Basis(axis, tilt).scaled(Vector3.ONE * r), sway + Vector3.UP * (h - LIP * r * 0.3))
		mi.set_instance_shader_parameter("strength", _strength * (0.75 + 0.25 * sin(t * 7.0 + i)))
	# The inner funnel leans with the sway of the stack.
	_core.rotation = Vector3(sin(t * 2.6) * 0.05, 0.0, cos(t * 3.1) * 0.05)
	_core.set_instance_shader_parameter("strength", _strength)


## Inner funnel: open tube, UV.x = angle (0 at -Z), UV.y = height 0..1, radius CORE_SCALE of the
## funnel's up to CORE_HEIGHT of its height.
static func _core_mesh(spin_spell: SpinjitzuSpell) -> ArrayMesh:
	var key := spin_spell.get_instance_id()
	if _core_meshes.has(key):
		return _core_meshes[key]
	const RINGS := 14
	const SEG := 48
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := spin_spell.height * CORE_HEIGHT
	for j in RINGS + 1:
		var v := float(j) / RINGS
		var y := v * top
		var r := spin_spell.radius_at(y) * CORE_SCALE
		for i in SEG + 1:
			var u := float(i) / SEG
			var dir := Vector3(sin(u * TAU), 0.0, -cos(u * TAU))
			st.set_uv(Vector2(u, v))
			st.set_normal(dir)
			st.add_vertex(dir * r + Vector3.UP * y)
	for j in RINGS:
		for i in SEG:
			var a0 := j * (SEG + 1) + i
			var b0 := a0 + SEG + 1
			st.add_index(a0)
			st.add_index(b0)
			st.add_index(a0 + 1)
			st.add_index(a0 + 1)
			st.add_index(b0)
			st.add_index(b0 + 1)
	var mesh := st.commit()
	_core_meshes[key] = mesh
	return mesh


## Shallow funnel-lip ring: radius INNER..1, the outer edge raised by LIP × (r − INNER).
static func _ring_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const RADIAL := 5
	for j in RADIAL + 1:
		var r := lerpf(INNER, 1.0, float(j) / RADIAL)
		for i in SEGMENTS + 1:
			var a := TAU * i / SEGMENTS
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(sin(a) * r, LIP * (r - INNER), -cos(a) * r))
	for j in RADIAL:
		for i in SEGMENTS:
			var a0 := j * (SEGMENTS + 1) + i
			var b0 := a0 + SEGMENTS + 1
			st.add_index(a0)
			st.add_index(b0)
			st.add_index(a0 + 1)
			st.add_index(a0 + 1)
			st.add_index(b0)
			st.add_index(b0 + 1)
	_mesh = st.commit()
	return _mesh
