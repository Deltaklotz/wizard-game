class_name FirePatch
extends Node3D
## The pool of fire a Fireball leaves on the ground (molotov-like), built in layers:
##   - an ember bed draped over the terrain (ember_bed.gdshader: charcoal with glowing cracks and
##     flickering hot spots, ragged burning edge),
##   - flame sheets scattered over the disc (fire_sheet.gdshader: Y-billboards with procedural,
##     temperature-coloured flames; taller towards the middle, soft where they meet the ground),
##   - a column of smoke lit orange from below, embers rising on turbulence, heat haze above,
##   - flickering fire light.
## It catches quickly, burns for `patch_time` and dies down (flames shrink, cracks dim).
## Every client sets its own player ablaze while their feet are in it (Player.ignite).

const SPREAD_TIME := 0.6
const DIE_TIME := 2.0
## Height range above the fire in which a player's feet count as standing in it.
const REACH_UP := 1.6
const SHEET_SHADER := preload("res://shaders/vfx/fire_sheet.gdshader")
const BED_SHADER := preload("res://shaders/vfx/ember_bed.gdshader")
const HAZE_SHADER := preload("res://shaders/vfx/heat_haze.gdshader")
## Draped ember bed: grid resolution across the disc.
const BED_GRID := 20

static var _sheet_mat: ShaderMaterial
static var _haze_mat: ShaderMaterial
static var _quad: QuadMesh

var spell: FireballSpell
var owner_id := -1
var _t := 0.0
var _sheets: Array[MeshInstance3D] = []
var _hazes: Array[MeshInstance3D] = []
var _bed_mat: ShaderMaterial
var _embers: GPUParticles3D
var _smoke: GPUParticles3D
var _licks: GPUParticles3D
var _light: OmniLight3D
var _light2: OmniLight3D


static func spawn(parent: Node, fb: FireballSpell, at: Vector3, owner: int) -> FirePatch:
	var p := FirePatch.new()
	p.spell = fb
	p.owner_id = owner
	parent.add_child(p)
	p.global_position = at
	return p


static func _shared() -> void:
	if _quad:
		return
	_quad = QuadMesh.new()
	_quad.size = Vector2(1.0, 1.0)
	_quad.center_offset = Vector3(0.0, 0.5, 0.0)  # root at the node's origin
	_sheet_mat = ShaderMaterial.new()
	_sheet_mat.shader = SHEET_SHADER
	_haze_mat = ShaderMaterial.new()
	_haze_mat.shader = HAZE_SHADER


func _ready() -> void:
	add_to_group("fire_patch")
	_shared()
	var r := spell.patch_radius
	_build_bed(r)
	_build_sheets(r)
	# Embers rising on turbulence.
	_embers = SpellFx.particles(self, int(14 * r), 2.4, false, true, Vector2(0.03, 0.14), FireFx.HOT, FireFx.FIRE)
	var em := _embers.process_material as ParticleProcessMaterial
	_ring(em, r * 0.9, 0.3)
	em.direction = Vector3.UP
	em.spread = 25.0
	em.initial_velocity_min = 1.5
	em.initial_velocity_max = 4.5
	em.gravity = Vector3(0, 0.6, 0)
	em.turbulence_enabled = true
	em.turbulence_noise_strength = 2.5
	em.turbulence_noise_scale = 3.0
	em.turbulence_influence_min = 0.15
	em.turbulence_influence_max = 0.35
	_embers.visibility_aabb = AABB(Vector3(-r * 2, -1, -r * 2), Vector3(r * 4, 14, r * 4))
	# Small flame licks around the sheets' roots.
	_licks = FireFx.flames(self, int(10 * r), 0.5, 0.55, 1.5)
	var lm := _licks.process_material as ParticleProcessMaterial
	_ring(lm, r * 0.95, 0.1)
	lm.direction = Vector3.UP
	lm.spread = 10.0
	lm.initial_velocity_min = 0.3
	lm.initial_velocity_max = 0.8
	# Smoke column, lit from below.
	_smoke = FireFx.smoke(self, int(14 * r), 5.5, 3.2, 0.9)
	var sm := _smoke.process_material as ParticleProcessMaterial
	_ring(sm, r * 0.6, 0.4)
	sm.direction = Vector3.UP
	sm.spread = 12.0
	sm.initial_velocity_min = 1.4
	sm.initial_velocity_max = 2.6
	_smoke.position.y = 1.8
	_smoke.visibility_aabb = AABB(Vector3(-r * 3, -2, -r * 3), Vector3(r * 6, 22, r * 6))
	# Heat haze above the flames.
	for i in 3:
		var hz := MeshInstance3D.new()
		hz.mesh = _quad
		hz.material_override = _haze_mat
		hz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hz.scale = Vector3(r * 1.6, 4.5, 1.0)
		var a := TAU * i / 3.0
		hz.position = Vector3(cos(a), 0.0, sin(a)) * r * 0.25 + Vector3.UP * 1.6
		add_child(hz)
		_hazes.append(hz)
	_light = FireFx.fire_light(self, 0.0, r * 3.5)
	_light.position.y = 1.2
	_light2 = FireFx.fire_light(self, 0.0, r * 2.0)
	_light2.position = Vector3(r * 0.4, 0.6, -r * 0.3)
	_set_strength(0.0)


func _ring(pm: ParticleProcessMaterial, radius: float, height: float) -> void:
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = radius
	pm.emission_ring_inner_radius = 0.0
	pm.emission_ring_height = height


## Flame sheets: a few big ones in the middle, smaller ones towards the rim (Poisson-ish).
func _build_sheets(r: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	var count := int(6.0 + r * r * 1.4)
	var placed: Array[Vector2] = []
	var tries := 0
	while placed.size() < count and tries < count * 20:
		tries += 1
		var p := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * r * 0.85
		if p.length() > r * 0.85:
			continue
		var ok := true
		for q in placed:
			if q.distance_to(p) < r * 0.21:
				ok = false
				break
		if not ok:
			continue
		placed.append(p)
		var centre := 1.0 - p.length() / r
		var mi := MeshInstance3D.new()
		mi.mesh = _quad
		mi.material_override = _sheet_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var h := lerpf(1.3, 3.4, centre) * rng.randf_range(0.8, 1.2)
		mi.scale = Vector3(h * rng.randf_range(0.7, 0.95), h, 1.0)
		mi.position = Vector3(p.x, _ground_offset(p) - 0.15, p.y)
		mi.set_instance_shader_parameter("seed", rng.randf() * 10.0)
		mi.extra_cull_margin = 2.0
		add_child(mi)
		_sheets.append(mi)


## Height of the ground under a point of the disc, relative to the patch origin.
func _ground_offset(p: Vector2) -> float:
	var from := global_position + Vector3(p.x, 3.0, p.y)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 8.0)
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.position.y - global_position.y) if not hit.is_empty() else 0.0


## The ember bed: a disc mesh whose vertices are dropped onto the ground (follows slopes/steps).
func _build_bed(r: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := BED_GRID
	var size := r * 1.1
	var heights := PackedFloat32Array()
	heights.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var p := Vector2(float(i) / n * 2.0 - 1.0, float(j) / n * 2.0 - 1.0) * size
			heights[j * (n + 1) + i] = _ground_offset(p) + 0.05
	for j in n:
		for i in n:
			var idx := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
			var pts: Array[Vector3] = []
			var uvs: Array[Vector2] = []
			for c in idx:
				var u := Vector2(float(c[0]) / n, float(c[1]) / n)
				var p := (u * 2.0 - Vector2.ONE) * size
				pts.append(Vector3(p.x, heights[c[1] * (n + 1) + c[0]], p.y))
				uvs.append(u)
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_uv(uvs[k])
				st.set_normal(Vector3.UP)
				st.add_vertex(pts[k])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	_bed_mat = ShaderMaterial.new()
	_bed_mat.shader = BED_SHADER
	mi.material_override = _bed_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _set_strength(s: float) -> void:
	for mi in _sheets:
		mi.set_instance_shader_parameter("strength", s)
		mi.visible = s > 0.01
	for hz in _hazes:
		hz.set_instance_shader_parameter("strength", s)
		hz.visible = s > 0.01
	_bed_mat.set_shader_parameter("strength", s)
	if _embers:
		_embers.amount_ratio = s
		_licks.amount_ratio = s
		_smoke.amount_ratio = clampf(s * 1.3, 0.0, 1.0)


func _process(delta: float) -> void:
	_t += delta
	var life := spell.patch_time
	var catch := smoothstep(0.0, SPREAD_TIME, _t)
	var s := catch * (1.0 - smoothstep(life - DIE_TIME, life, _t))
	_set_strength(s)
	# Irregular flicker (sum of incommensurate sines).
	var f := 0.8 + 0.12 * sin(_t * 17.0) + 0.08 * sin(_t * 29.3 + 1.0) + 0.06 * sin(_t * 7.1)
	_light.light_energy = s * 4.5 * f
	_light2.light_energy = s * 2.0 * (1.8 - f)
	if _t >= life:
		for p in [_embers, _licks, _smoke]:
			(p as GPUParticles3D).emitting = false
		_light.visible = false
		_light2.visible = false
		set_process(false)
		set_physics_process(false)
		get_tree().create_timer(4.5).timeout.connect(queue_free)


func _physics_process(_delta: float) -> void:
	if _t < SPREAD_TIME * 0.5 or _t > spell.patch_time - DIE_TIME * 0.5:
		return
	var me := get_tree().current_scene.get_node_or_null("Player") as Node3D
	if me == null or not me.has_method("ignite") or me.is_dead():
		return
	var feet: Vector3 = me.global_position - Vector3.UP * me.FOOT_OFFSET
	var off := feet - global_position
	if Vector2(off.x, off.z).length() < spell.patch_radius and off.y > -0.6 and off.y < REACH_UP:
		me.ignite(spell.burn_time, spell.burn_dps, owner_id)
