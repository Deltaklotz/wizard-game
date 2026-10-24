class_name InfernoBeam
extends Node3D
## The Infernal Torrent (InfernoSpell): a widening cone of crimson fire and black smoke poured
## out along the caster's view.
##
## Phases: CHARGE (embers and dark wisps are sucked into a turning sigil before the book, crescent
## slashes whirl round it, the light swells) → FIRE (it erupts – flash, shockwaves, a spark burst –
## and the head shoots out at GROW_SPEED to the first surface or max_range; for `duration`
## seconds it follows the caster's aim) → FADE (the muzzle closes, the tail flies off, the shapes
## erode away).
##
## Look (hand-drawn anime hellfire): three nested cel-shaded cone shells
## (shaders/vfx/inferno_shell.gdshader: black smoke with indigo patches and burning red edges,
## crimson flame, white-pink core), a soft additive haze (inferno_glow), cel billows of smoke and
## flame streaming out in world space (inferno_puff – they bend away as the caster sweeps it), pale
## rose crescent slashes whirling round it (inferno_slash, a MultiMesh), dashed white sparks
## (inferno_spark), red lights along it, and where it strikes a surface a splash of fire, smoke and
## sparks plus scorch marks.
##
## Local: the caster's client checks the cone every TICK and sends hit events (damage, burning,
## a shove) to the players inside it with a clear line from the muzzle; a shield in the way takes
## the hit instead. Remote: follows the avatar's hand and look direction; ends on
## {"kind": "inferno_end"} or when the caster dies / leaves.

enum Phase { CHARGE, FIRE, FADE }

const SHELL_SHADER := preload("res://shaders/vfx/inferno_shell.gdshader")
const GLOW_SHADER := preload("res://shaders/vfx/inferno_glow.gdshader")
const SLASH_SHADER := preload("res://shaders/vfx/inferno_slash.gdshader")
const PUFF_SHADER := preload("res://shaders/vfx/inferno_puff.gdshader")
const SPARK_SHADER := preload("res://shaders/vfx/inferno_spark.gdshader")

const CRIMSON := Color(1.0, 0.06, 0.1)
const ROSE := Color(1.0, 0.68, 0.76)
## m/s the head shoots out at, and the tail flies off at when it ends.
const GROW_SPEED := 230.0
const TAIL_SPEED := 120.0
const FADE_TIME := 0.8
## Seconds between damage checks.
const TICK := 0.2
const CHEST := 1.1
## Cone shells: [layer, radius scale, near fade (m), local inside erosion].
const SHELLS := [[0, 1.0, Vector2(2.5, 9.0), 0.22], [1, 0.74, Vector2(1.2, 5.0), 0.12],
	[2, 0.28, Vector2(0.25, 0.9), 0.0]]
const SLASH_COUNT := 26
const SLASH_RATE := 11.0
const SLASH_SEGMENTS := 96
const SLASH_SPAN := PI * 1.25

static var _tube: ArrayMesh
static var _arc: ArrayMesh

var spell: InfernoSpell
var owner_id := -1
var is_local := false
var phase := Phase.CHARGE
## Current beam direction (eased towards the aim) and reach (m).
var direction := Vector3.FORWARD
var length := 0.0
## 0..1 strength of the visuals.
var strength := 0.0

var _player: Node3D
var _avatar: RemotePlayer
var _static := false
var _origin := Vector3.ZERO
var _t := 0.0
var _target_len := 1.0
var _hit_surface := false
var _hit_point := Vector3.ZERO
var _hit_normal := Vector3.UP
var _hit_shield: Shield
var _cut := 0.0
var _tick := 0.0
var _seed := 0.0

var _shell_mats: Array[ShaderMaterial] = []
var _glow_mat: ShaderMaterial
var _shell_nodes: Array[MeshInstance3D] = []
var _slash_mm: MultiMesh
var _slashes: Array[Dictionary] = []
var _slash_accum := 0.0
var _smoke: GPUParticles3D
var _flames: GPUParticles3D
var _sparks: GPUParticles3D
var _gather: GPUParticles3D
var _sigil: MeshInstance3D
var _muzzle_light: OmniLight3D
var _beam_lights: Array[OmniLight3D] = []
var _impact: Node3D
var _impact_flames: GPUParticles3D
var _impact_smoke: GPUParticles3D
var _impact_sparks: GPUParticles3D
var _impact_light: OmniLight3D
var _scorch_timer := 0.0
var _last_scorch := Vector3(INF, INF, INF)


static func start_local(inferno: InfernoSpell, player: Node3D) -> InfernoBeam:
	var b := _make(inferno, Net.my_id, true)
	b._player = player
	b._origin = player.grimoire.get_cast_origin().origin
	b.direction = b._aim_direction()
	player.get_tree().current_scene.add_child(b)
	player.grimoire.begin_channel(b)
	return b


static func start_remote(inferno: InfernoSpell, avatar: RemotePlayer, from: Vector3, dir: Vector3) -> InfernoBeam:
	var b := _make(inferno, avatar.peer_id, false)
	b._avatar = avatar
	b._origin = from
	b.direction = dir if dir.length_squared() > 0.01 else avatar.get_look_direction()
	avatar.get_tree().current_scene.add_child(b)
	return b


## Renders a torrent mid-blast so every shader and particle pipeline compiles during loading.
static func prewarm(vp: Node) -> void:
	var b := _make(load("res://spells/inferno.tres"), -99, false)
	b._static = true
	b._origin = Vector3(0, 1, 0)
	b.direction = Vector3(0.3, 0, -1).normalized()
	vp.add_child(b)
	b._erupt()
	b._t = 0.5
	b.length = 20.0
	b._target_len = 20.0
	b._hit_surface = true
	b._hit_point = b._origin + b.direction * 20.0
	vp.get_tree().create_timer(1.0).timeout.connect(b.queue_free)


static func _make(inferno: InfernoSpell, owner: int, local: bool) -> InfernoBeam:
	var b := InfernoBeam.new()
	b.spell = inferno
	b.owner_id = owner
	b.is_local = local
	return b


func _ready() -> void:
	add_to_group("inferno")
	top_level = true
	_seed = randf() * 100.0
	_place()
	_build_shells()
	_build_slashes()
	_build_impact()
	_build_particles()
	_sigil = SpellFx.ring(self, true, 1.5 if is_local else 2.4, CRIMSON, ROSE)
	_sigil.rotation = Vector3(PI * 0.5, 0, 0)
	_sigil.position = Vector3(0, 0, -(1.1 if is_local else 0.5))
	_sigil.set_instance_shader_parameter("progress", 0.0)
	_muzzle_light = _light(CRIMSON, 0.0, 9.0)
	_muzzle_light.position = Vector3(0, 0, -(2.5 if is_local else 0.6))
	for i in 3:
		_beam_lights.append(_light(CRIMSON.lerp(ROSE, 0.15), 0.0, 10.0))
	if not is_local and not _static:
		Net.event_received.connect(_on_net_event)


func _light(color: Color, energy: float, light_range: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	l.light_volumetric_fog_energy = 0.0
	add_child(l)
	return l


# --- building --------------------------------------------------------------------------------

func _build_shells() -> void:
	var far := spell.radius_at(spell.max_range) * 1.6
	var aabb := AABB(Vector3(-far, -far, -spell.max_range - far), Vector3(far * 2.0, far * 2.0, spell.max_range + far * 2.0))
	for s in SHELLS:
		var mat := ShaderMaterial.new()
		mat.shader = SHELL_SHADER
		mat.set_shader_parameter("layer", s[0])
		mat.set_shader_parameter("radius_scale", s[1])
		mat.set_shader_parameter("near_fade", s[2] if is_local else Vector2(1.5, 7.0))
		mat.set_shader_parameter("inside_erode", s[3] if is_local else 0.1)
		mat.set_shader_parameter("aim_clear", 0.4 if is_local and s[0] < 2 else 0.0)
		mat.set_shader_parameter("r0", spell.muzzle_radius)
		mat.set_shader_parameter("spread", spell.spread)
		mat.set_shader_parameter("seed", _seed)
		_shell_mats.append(mat)
		_shell_nodes.append(_tube_instance(mat, aabb))
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = GLOW_SHADER
	_glow_mat.set_shader_parameter("r0", spell.muzzle_radius)
	_glow_mat.set_shader_parameter("spread", spell.spread)
	_shell_nodes.append(_tube_instance(_glow_mat, aabb))
	_set_shells()


func _tube_instance(mat: Material, aabb: AABB) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _tube_mesh()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = aabb
	mi.visible = false
	add_child(mi)
	return mi


## Unit tube: UV.x = angle 0..1, UV.y = 0..1 along (rings packed towards the muzzle, where the
## cone is narrow and changes fastest). The shaders shape it.
static func _tube_mesh() -> ArrayMesh:
	if _tube:
		return _tube
	var rings := 72
	var segs := 36
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in rings + 1:
		var s := pow(float(i) / rings, 1.35)
		for j in segs + 1:
			var a := float(j) / segs * TAU
			verts.append(Vector3(cos(a), sin(a), -s))
			normals.append(Vector3(cos(a), sin(a), 0))
			uvs.append(Vector2(float(j) / segs, s))
	for i in rings:
		for j in segs:
			var a := i * (segs + 1) + j
			var b := a + segs + 1
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	_tube = ArrayMesh.new()
	_tube.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _tube


## One crescent: a centre line along SLASH_SPAN of the unit circle, rising a little along -Z (a
## stretch of helix). Each point is doubled (UV.y = side 0 / 1) and NORMAL holds the tangent;
## inferno_slash.gdshader spreads the sides apart facing the camera.
static func _arc_mesh() -> ArrayMesh:
	if _arc:
		return _arc
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var rise := 0.45
	for i in SLASH_SEGMENTS + 1:
		var x := float(i) / SLASH_SEGMENTS
		var a := x * SLASH_SPAN
		var p := Vector3(cos(a), sin(a), -x * rise)
		var tangent := Vector3(-sin(a) * SLASH_SPAN, cos(a) * SLASH_SPAN, -rise).normalized()
		for side in 2:
			verts.append(p)
			normals.append(tangent)
			uvs.append(Vector2(x, side))
	for i in SLASH_SEGMENTS:
		var a := i * 2
		idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	_arc = ArrayMesh.new()
	_arc.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _arc


func _build_slashes() -> void:
	_slash_mm = MultiMesh.new()
	_slash_mm.transform_format = MultiMesh.TRANSFORM_3D
	_slash_mm.use_custom_data = true
	_slash_mm.mesh = _arc_mesh()
	_slash_mm.instance_count = SLASH_COUNT
	for i in SLASH_COUNT:
		_slash_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
		_slash_mm.set_instance_custom_data(i, Color(1, 0, 0, 0))
		_slashes.append({"alive": false})
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _slash_mm
	var mat := ShaderMaterial.new()
	mat.shader = SLASH_SHADER
	mat.set_shader_parameter("near_fade", Vector2(0.6, 2.2) if is_local else Vector2(0.3, 1.5))
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var far := spell.radius_at(spell.max_range) * 1.8
	mmi.custom_aabb = AABB(Vector3(-far, -far, -spell.max_range - far), Vector3(far * 2.0, far * 2.0, spell.max_range + far * 2.0))
	add_child(mmi)


func _build_particles() -> void:
	var aabb := AABB(Vector3(-40, -40, -spell.max_range - 30), Vector3(80, 80, spell.max_range + 60))
	# Smoke billows: start small at the muzzle, swell as they fly, slow down and rise a little.
	_smoke = _puffs(self, false, 120, 1.35, 17.0, aabb)
	var pm := _smoke.process_material as ParticleProcessMaterial
	pm.spread = 12.5
	pm.initial_velocity_min = 52.0
	pm.initial_velocity_max = 72.0
	pm.damping_min = 10.0
	pm.damping_max = 18.0
	pm.gravity = Vector3(0, 2.5, 0)
	pm.scale_curve = _curve([[0.0, 0.07], [0.35, 0.5], [1.0, 1.0]])
	# Flame billows: faster and tighter.
	_flames = _puffs(self, true, 130, 0.85, 11.0, aabb)
	var fm := _flames.process_material as ParticleProcessMaterial
	fm.spread = 8.0
	fm.initial_velocity_min = 70.0
	fm.initial_velocity_max = 95.0
	fm.damping_min = 6.0
	fm.damping_max = 12.0
	fm.scale_curve = _curve([[0.0, 0.05], [0.4, 0.45], [1.0, 0.85]])
	# Dashed sparks racing down it.
	_sparks = _streaks(self, 170, 0.75, Vector2(0.07, 4.2), aabb)
	var sm := _sparks.process_material as ParticleProcessMaterial
	sm.spread = 11.0
	sm.initial_velocity_min = 95.0
	sm.initial_velocity_max = 140.0
	for p in [_smoke, _flames, _sparks]:
		(p as GPUParticles3D).position = Vector3(0, 0, -0.8)
		(p as GPUParticles3D).emitting = false
	if is_local:
		for p in [_smoke, _flames, _impact_flames, _impact_smoke]:
			((p as GPUParticles3D).draw_pass_1.surface_get_material(0) as ShaderMaterial).set_shader_parameter("aim_clear", 0.4)
	# The wind-up: embers and wisps sucked into the sigil.
	_gather = SpellFx.particles(self, 70, 0.5, false, true, Vector2(0.04, 0.6), CRIMSON, ROSE)
	_gather.local_coords = true
	_gather.position = Vector3(0, 0, -(1.1 if is_local else 0.5))
	var gm := _gather.process_material as ParticleProcessMaterial
	gm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	gm.emission_sphere_radius = 1.6
	gm.radial_accel_min = -40.0
	gm.radial_accel_max = -25.0
	gm.initial_velocity_min = 0.0
	gm.initial_velocity_max = 0.0


func _build_impact() -> void:
	_impact = Node3D.new()
	_impact.top_level = true
	add_child(_impact)
	var aabb := AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	# Fire splashing out over the surface (the impact node's -Z is the surface normal).
	# Sizes are set per frame from the cone's radius where it strikes (quads are 1 m).
	_impact_flames = _puffs(_impact, true, 90, 0.7, 1.0, aabb)
	var fm := _impact_flames.process_material as ParticleProcessMaterial
	fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fm.emission_sphere_radius = 2.0
	fm.spread = 80.0
	fm.initial_velocity_min = 10.0
	fm.initial_velocity_max = 24.0
	fm.damping_min = 10.0
	fm.damping_max = 20.0
	fm.scale_curve = _curve([[0.0, 0.25], [0.3, 0.8], [1.0, 0.6]])
	# Smoke boiling up from it.
	_impact_smoke = _puffs(_impact, false, 40, 2.2, 1.0, aabb)
	var sm := _impact_smoke.process_material as ParticleProcessMaterial
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sm.emission_sphere_radius = 2.0
	sm.spread = 60.0
	sm.initial_velocity_min = 3.0
	sm.initial_velocity_max = 9.0
	sm.gravity = Vector3(0, 5.0, 0)
	sm.damping_min = 1.0
	sm.damping_max = 2.0
	sm.scale_curve = _curve([[0.0, 0.2], [0.5, 0.75], [1.0, 1.0]])
	_impact_sparks = _streaks(_impact, 80, 0.9, Vector2(0.06, 1.6), aabb)
	var km := _impact_sparks.process_material as ParticleProcessMaterial
	km.spread = 75.0
	km.initial_velocity_min = 18.0
	km.initial_velocity_max = 42.0
	km.gravity = Vector3(0, -12.0, 0)
	for p in [_impact_flames, _impact_smoke, _impact_sparks]:
		(p as GPUParticles3D).emitting = false
	_impact_light = OmniLight3D.new()
	_impact_light.light_color = CRIMSON.lerp(ROSE, 0.2)
	_impact_light.light_energy = 0.0
	_impact_light.omni_range = 20.0
	_impact_light.shadow_enabled = false
	_impact_light.light_volumetric_fog_energy = 0.0
	_impact.add_child(_impact_light)


## Cel billows (inferno_puff) flying along the emitter's -Z in world space.
func _puffs(parent: Node3D, flame: bool, amount: int, lifetime: float, size: float, aabb: AABB) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.fixed_fps = 60
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = aabb
	p.randomness = 0.3
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.gravity = Vector3.ZERO
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := ShaderMaterial.new()
	mat.shader = PUFF_SHADER
	mat.set_shader_parameter("flame", flame)
	mat.set_shader_parameter("near_fade", Vector2(1.5, 7.0) if is_local else Vector2(2.0, 9.0))
	quad.material = mat
	p.draw_pass_1 = quad
	parent.add_child(p)
	return p


## Dashed spark streaks (inferno_spark), aligned to their velocity.
func _streaks(parent: Node3D, amount: int, lifetime: float, size: Vector2, aabb: AABB) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.fixed_fps = 60
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = aabb
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.gravity = Vector3.ZERO
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var tint := Gradient.new()
	tint.set_color(0, Color(1.0, 0.92, 0.95))
	tint.set_color(1, Color(1.0, 0.45, 0.55))
	var tint_tex := GradientTexture1D.new()
	tint_tex.gradient = tint
	pm.color_initial_ramp = tint_tex
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.1, 0.6, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	pm.color_ramp = fade_tex
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = size
	var mat := ShaderMaterial.new()
	mat.shader = SPARK_SHADER
	quad.material = mat
	p.draw_pass_1 = quad
	parent.add_child(p)
	return p


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for pt in points:
		c.add_point(Vector2(pt[0], pt[1]))
	var tex := CurveTexture.new()
	tex.curve = c
	return tex


# --- running ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if not _static and phase != Phase.FADE and _caster_gone():
		_end(false)
	_follow(delta)
	match phase:
		Phase.CHARGE:
			var k := clampf(_t / spell.charge_time, 0.0, 1.0)
			_sigil.set_instance_shader_parameter("progress", 0.3 * k)
			_muzzle_light.light_energy = 3.0 * k * k
			_spawn_slashes(delta, 26.0, true)
			if is_local:
				_player.add_shake(0.15 + 0.3 * k)
			if _t >= spell.charge_time:
				_erupt()
		Phase.FIRE:
			strength = minf(1.0, strength + delta * 8.0)
			_sigil.set_instance_shader_parameter("progress", minf(1.0, 0.3 + _t * 1.6))
			length = move_toward(length, _target_len, GROW_SPEED * delta) if length < _target_len else _target_len
			_spawn_slashes(delta, SLASH_RATE, false)
			if is_local:
				_player.add_shake(0.22)
				# The torrent pushes its caster back (horizontally; -INF leaves the vertical speed).
				var back := -Vector3(direction.x, 0.0, direction.z) * 7.0 * delta
				_player.add_knockback(Vector3(back.x, -INF, back.z))
				# Aimed at the ground it lifts its caster like a rocket: nothing when aimed
				# level, strongest straight down (more than gravity, so they rise).
				var down := clampf(-direction.y, 0.0, 1.0)
				if down > 0.0:
					_player.add_lift(spell.lift * pow(down, 1.5) * delta, spell.lift_max_speed)
				_tick -= delta
				if _tick <= 0.0:
					_tick += TICK
					_damage_tick()
			if not _static and _t >= spell.duration:
				_end(is_local)
		Phase.FADE:
			strength = maxf(0.0, strength - delta / FADE_TIME)
			_cut = minf(_cut + TAIL_SPEED * delta, length)
			if _t > FADE_TIME + 1.6:
				queue_free()
	_shake_nearby()
	_update_slashes(delta)
	_set_shells()
	_update_lights()
	_update_impact(delta)


func _caster_gone() -> bool:
	if is_local:
		return not is_instance_valid(_player) or _player.is_dead()
	return not is_instance_valid(_avatar) or not _avatar.visible or _avatar.is_dead()


## Origin at the book / hand, direction eased towards the aim, reach from a ray.
func _follow(delta: float) -> void:
	var aim := direction
	if is_local and is_instance_valid(_player):
		_origin = _player.grimoire.get_cast_origin().origin
		aim = _aim_direction()
	elif is_instance_valid(_avatar):
		_origin = _avatar.get_hand_position()
		aim = _avatar.get_look_direction()
	if phase == Phase.CHARGE:
		direction = aim
	elif phase == Phase.FIRE:
		direction = direction.slerp(aim, 1.0 - exp(-spell.turn_rate * delta)).normalized()
	_place()
	if phase != Phase.FADE:
		_trace()


func _place() -> void:
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	global_transform = Transform3D(Basis.looking_at(direction, up), _origin)


## The local caster aims from the book at the crosshair point.
func _aim_direction() -> Vector3:
	var cam: Camera3D = _player.camera
	var from := cam.global_position
	var view := -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + view * spell.max_range)
	var exclude := Shield.excludes_for(_player.get_tree(), Net.my_id, true)
	exclude.append((_player as CollisionObject3D).get_rid())
	q.exclude = exclude
	var r := _player.get_world_3d().direct_space_state.intersect_ray(q)
	var target: Vector3 = r.position if not r.is_empty() and from.distance_to(r.position) > 4.0 else from + view * spell.max_range
	var origin: Vector3 = _player.grimoire.get_cast_origin().origin
	return (target - origin).normalized()


## Where the axis meets the world or a shield.
func _trace() -> void:
	var end := _origin + direction * spell.max_range
	var q := PhysicsRayQueryParameters3D.create(_origin, end)
	q.collision_mask = 1 | Shield.LAYER
	var exclude := Shield.excludes_for(get_tree(), owner_id)
	if is_local and is_instance_valid(_player):
		exclude.append((_player as CollisionObject3D).get_rid())
	q.exclude = exclude
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	_target_len = spell.max_range
	_hit_surface = false
	_hit_shield = null
	if not r.is_empty():
		_target_len = maxf(_origin.distance_to(r.position), 1.0)
		_hit_surface = true
		_hit_point = r.position
		_hit_normal = r.normal
		_hit_shield = Shield.from_collider(r.collider)
	var dome := Shield.dome_exit(get_tree(), _origin, _origin + direction * _target_len)
	if not dome.is_empty():
		_target_len = maxf(dome.dist, 1.0)
		_hit_surface = true
		_hit_point = dome.point
		_hit_normal = dome.normal
		_hit_shield = dome.shield


func _erupt() -> void:
	phase = Phase.FIRE
	_t = 0.0
	length = 0.5
	_tick = 0.05
	_gather.emitting = false
	for p in [_smoke, _flames, _sparks]:
		(p as GPUParticles3D).emitting = true
	for mi in _shell_nodes:
		mi.visible = true
	var root := SpellFx.effect_root(get_parent(), _origin, 1.5)
	var up := Vector3.UP if absf(direction.y) < 0.95 else Vector3.RIGHT
	# Shockwaves punched out along the first metres.
	for i in 4:
		var d := 1.5 + i * i * 2.2 + (1.0 if is_local else 0.0)
		var wave := SpellFx.ring(root, false, spell.radius_at(d) * 2.0 + 2.0 + i * 1.5, CRIMSON, ROSE)
		wave.global_basis = Basis.looking_at(direction, up)
		wave.global_position = _origin + direction * d
		SpellFx.animate_ring(wave, 0.32 + i * 0.08, 0.0, i * 0.035)
	var burst := SpellFx.particles(root, 70, 0.6, true, true, Vector2(0.06, 1.4), ROSE, CRIMSON)
	burst.global_position = _origin + direction * 1.5
	var bm := burst.process_material as ParticleProcessMaterial
	bm.direction = direction
	bm.spread = 40.0
	bm.initial_velocity_min = 20.0
	bm.initial_velocity_max = 60.0
	bm.damping_min = 20.0
	bm.damping_max = 40.0
	SpellFx.flash(root, _origin + direction * (4.0 if is_local else 1.0), CRIMSON.lerp(ROSE, 0.3),
		6.0 if is_local else 12.0, 25.0, 0.5)
	if is_local and not _static:
		_player.add_recoil(0.03)
		_player.add_shake(0.8)


## Cast pressed again: cut it short.
func cancel() -> void:
	_end(true)


func _end(send: bool) -> void:
	if phase == Phase.FADE:
		return
	if phase == Phase.CHARGE:
		for mi in _shell_nodes:
			mi.visible = true
		length = 0.5
	phase = Phase.FADE
	_t = 0.0
	_gather.emitting = false
	for p in [_smoke, _flames, _sparks, _impact_flames, _impact_smoke, _impact_sparks]:
		(p as GPUParticles3D).emitting = false
	if is_local:
		if send:
			Net.send_event({"kind": "inferno_end"})
		if is_instance_valid(_player):
			_player.grimoire.end_channel(self)


func _on_net_event(from_id: int, event: Dictionary) -> void:
	if from_id == owner_id and str(event.get("kind", "")) == "inferno_end":
		_end(false)


## Damage to everyone inside the cone with a clear line from the muzzle (decided here, by the
## caster), and to a shield the axis pours onto.
func _damage_tick() -> void:
	var amount := spell.dps * TICK
	if _hit_shield and length >= _target_len - 1.0:
		_hit_shield.report_hit(amount, _hit_point)
	var space := get_world_3d().direct_space_state
	var exclude := Shield.excludes_for(get_tree(), Net.my_id)
	exclude.append((_player as CollisionObject3D).get_rid())
	for node in get_tree().get_nodes_in_group("remote_player"):
		var a := node as RemotePlayer
		if a == null or not a.visible or a.is_dead():
			continue
		var chest := a.global_position + Vector3.UP * CHEST
		var v := chest - _origin
		var along := v.dot(direction)
		if along < 0.0 or along > length + 1.0:
			continue
		if (v - direction * along).length() > spell.radius_at(along) * 0.8 + 0.45:
			continue
		var q := PhysicsRayQueryParameters3D.create(_origin, chest)
		q.collision_mask = 1 | Shield.LAYER
		q.exclude = exclude
		var r := space.intersect_ray(q)
		if not r.is_empty():
			continue
		if not Shield.dome_exit(get_tree(), _origin, chest).is_empty():
			continue
		var shove := direction * spell.push
		shove.y = maxf(shove.y, 1.5)
		Net.send_event({"kind": "hit", "target": a.peer_id, "damage": amount, "spell": spell.resource_path,
			"burn": spell.burn_time, "bdps": spell.burn_dps, "push": Net._vec(shove)})
		if _player.has_method("confirm_hit"):
			_player.confirm_hit(a.peer_id)


## The ground trembles for the local player near a torrent (the caster shakes in _process).
func _shake_nearby() -> void:
	if is_local or _static or phase != Phase.FIRE:
		return
	var me := get_tree().current_scene.get_node_or_null("Player") as Node3D
	if me == null or not me.has_method("add_shake"):
		return
	var d := _distance_to_axis(me.global_position + Vector3.UP * CHEST)
	me.add_shake(clampf(1.0 - d / 30.0, 0.0, 1.0) * 0.45 * strength)


## Distance from `p` to the cone's surface (negative inside).
func _distance_to_axis(p: Vector3) -> float:
	var v := p - _origin
	var along := clampf(v.dot(direction), 0.0, length)
	return (v - direction * along).length() - spell.radius_at(along)


## 0..1 strength of the HUD effect for a camera at `cam`: a viewer caught inside / right beside
## someone's torrent (the caster's own view stays clear).
func screen_intensity(cam: Vector3) -> float:
	if phase == Phase.CHARGE:
		return 0.0
	if is_local:
		return 0.0
	var v := cam - _origin
	var along := v.dot(direction)
	if along < 0.0 or along > length + 3.0:
		return 0.0
	var d := _distance_to_axis(cam)
	var k := clampf(1.0 - d / 6.0, 0.0, 1.0) * strength
	if k <= 0.0 or _sheltered(cam, along):
		return 0.0
	return k


## A shield (or wall) stands between the torrent and the viewer at `cam`: the viewer is
## protected, so no smoke on their screen. Tested from the nearest point of the axis (pulled
## back a little from where it strikes, so the ray doesn't start inside the surface).
func _sheltered(cam: Vector3, along: float) -> bool:
	var from := _origin + direction * clampf(along, 0.0, maxf(length - 0.6, 0.0))
	var q := PhysicsRayQueryParameters3D.create(from, cam)
	q.collision_mask = 1 | Shield.LAYER
	var exclude := Shield.excludes_for(get_tree(), owner_id)
	var me := get_tree().current_scene.get_node_or_null("Player") as CollisionObject3D
	if me:
		exclude.append(me.get_rid())
	q.exclude = exclude
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return true
	return not Shield.dome_exit(get_tree(), from, cam).is_empty()


## Point the HUD effect streams towards.
func get_focus_point() -> Vector3:
	return _origin + direction * minf(length, 30.0)


# --- visuals ---------------------------------------------------------------------------------

func _set_shells() -> void:
	var open := 0.0 if _hit_surface and length >= _target_len - 0.5 else 1.0
	# While the head is still flying the tip stays closed (open_end eases it away).
	for mat in _shell_mats:
		mat.set_shader_parameter("length_m", maxf(length, 0.5))
		mat.set_shader_parameter("intensity", strength)
		mat.set_shader_parameter("cut", _cut)
		mat.set_shader_parameter("open_end", open * (1.0 if phase != Phase.FIRE or length >= _target_len - 0.5 else 0.3))
	_glow_mat.set_shader_parameter("length_m", maxf(length, 0.5))
	_glow_mat.set_shader_parameter("intensity", strength)
	_glow_mat.set_shader_parameter("cut", _cut)
	_glow_mat.set_shader_parameter("open_end", open)
	# Billows and sparks stop where the beam does (a shield, wall or the ground).
	if phase != Phase.FADE and _sparks:
		for p in [_smoke, _flames, _sparks]:
			var mat := (p as GPUParticles3D).draw_pass_1.surface_get_material(0) as ShaderMaterial
			mat.set_shader_parameter("beam_origin", _origin)
			mat.set_shader_parameter("beam_dir", direction)
			mat.set_shader_parameter("beam_len", maxf(length, 0.5) if phase == Phase.FIRE else 1e9)


func _spawn_slashes(delta: float, rate: float, charging: bool) -> void:
	_slash_accum += delta * rate
	while _slash_accum >= 1.0:
		_slash_accum -= 1.0
		for s in _slashes:
			if s.alive:
				continue
			var spin := randf_range(5.0, 11.0) * (1.0 if randf() < 0.5 else -1.0)
			s.alive = true
			s.age = 0.0
			s.seed = randf()
			s.ang = randf() * TAU
			s.spin = spin
			s.tilt = randf_range(-0.45, 0.45)
			s.tilt_axis = randf() * TAU
			if charging:
				s.life = randf_range(0.25, 0.4)
				s.d = randf_range(0.0, 0.6) + (1.1 if is_local else 0.5)
				s.speed = randf_range(-1.0, 1.0)
				s.radius = randf_range(0.5, 1.1) * (1.0 if is_local else 1.4)
				s.spin *= 1.6
			else:
				s.life = randf_range(0.6, 1.0)
				s.d = randf_range(0.5, 4.0)
				s.speed = randf_range(45.0, 85.0)
				s.radius = -randf_range(1.05, 1.4)  # negative = a share of the cone radius
			break


func _update_slashes(delta: float) -> void:
	var fade := 1.0 if phase != Phase.FADE else strength
	for i in _slashes.size():
		var s: Dictionary = _slashes[i]
		if not s.alive:
			continue
		s.age += delta
		s.d += s.speed * delta
		s.ang += s.spin * delta
		if s.age >= s.life or (s.radius < 0.0 and s.d > length + 2.0):
			s.alive = false
			_slash_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
			continue
		var r: float = s.radius if s.radius > 0.0 else -s.radius * spell.radius_at(s.d)
		var tilt_axis := Vector3(cos(s.tilt_axis), sin(s.tilt_axis), 0.0)
		var b := Basis(tilt_axis, s.tilt) * Basis(Vector3.BACK, s.ang)
		if s.spin > 0.0:
			b = b * Basis.from_scale(Vector3(1, -1, 1))
		_slash_mm.set_instance_transform(i, Transform3D(b.scaled(Vector3.ONE * r), Vector3(0, 0, -s.d)))
		_slash_mm.set_instance_custom_data(i, Color(s.age / s.life, s.seed, fade, 0.0))


func _update_lights() -> void:
	var k := strength if phase != Phase.CHARGE else 0.0
	if phase != Phase.CHARGE:
		var flick := 0.85 + 0.15 * sin(_t * 37.0) * sin(_t * 23.0 + 1.0)
		_muzzle_light.light_energy = (2.5 if is_local else 5.0) * k * flick
	var fractions := [0.15, 0.42, 0.78]
	for i in _beam_lights.size():
		var d: float = length * fractions[i]
		var l := _beam_lights[i]
		l.position = Vector3(0, 0, -d)
		l.omni_range = spell.radius_at(d) * 2.2 + 8.0
		l.light_energy = 5.0 * k * (0.85 + 0.15 * sin(_t * 19.0 + i * 2.0)) if d > _cut else 0.0


func _update_impact(delta: float) -> void:
	var active := phase == Phase.FIRE and _hit_surface and length >= _target_len - 1.0
	for p in [_impact_flames, _impact_smoke, _impact_sparks]:
		if (p as GPUParticles3D).emitting != active:
			(p as GPUParticles3D).emitting = active
	_impact_light.light_energy = move_toward(_impact_light.light_energy, 8.0 * strength if active else 0.0, delta * 30.0)
	if not active:
		return
	var n := _hit_normal if _hit_normal.length_squared() > 0.01 else -direction
	var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT
	_impact.global_transform = Transform3D(Basis.looking_at(n, up), _hit_point + n * 0.4)
	var r := spell.radius_at(length)
	var fm := _impact_flames.process_material as ParticleProcessMaterial
	fm.emission_sphere_radius = r * 0.45
	fm.scale_min = r * 0.8
	fm.scale_max = r * 1.4
	fm.initial_velocity_min = 4.0 + r * 1.0
	fm.initial_velocity_max = 8.0 + r * 2.0
	var sm := _impact_smoke.process_material as ParticleProcessMaterial
	sm.emission_sphere_radius = r * 0.5
	sm.scale_min = r * 1.2
	sm.scale_max = r * 2.0
	(_impact_sparks.process_material as ParticleProcessMaterial).emission_sphere_radius = r * 0.3
	_impact_light.omni_range = r * 2.5 + 10.0
	# Scorch the ground it sweeps over.
	_scorch_timer -= delta
	if _scorch_timer <= 0.0 and _hit_shield == null and _hit_point.distance_to(_last_scorch) > r * 0.4:
		_scorch_timer = 0.2
		_last_scorch = _hit_point
		FireFx.scorch(get_parent(), _hit_point, clampf(r * 0.6, 1.5, 7.0), 14.0)
