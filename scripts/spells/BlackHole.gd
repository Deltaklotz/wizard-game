class_name BlackHole
extends Node3D
## One black hole (BlackHoleSpell), the same on every client:
##   SPARK    – a twinkling star leaves the caster's hand and drifts up in a lazy spiral, trailing
##              motes, to the summoning point (SPARK_TIME).
##   CHARGE   – at the top it swells and spins ever faster, then shrinks to nothing – and in that
##              instant the hole manifests with a flash (CHARGE_TIME).
##   ACTIVE   – `duration` seconds: lensing + accretion disk (black_hole.gdshader on the inside of a
##              sphere – or, with "Fancy black hole" off, the cheap lens quad + flat disk of
##              black_hole_lens / black_hole_disk.gdshader), matter and debris spiralling in, a
##              warm light; it swells slowly and pulls
##              harder over time. The local player (unless they cast it) is pulled via
##              Player.set_pull and dies at the horizon.
##   COLLAPSE – it shrinks to nothing with a last flash and a burst of light.
## The HUD reads screen_intensity() for its edge distortion.

enum Phase { SPARK, CHARGE, ACTIVE, COLLAPSE }

const SPARK_TIME := 3.2
const CHARGE_TIME := 1.5
## The last part of the charge in which the spark shrinks away.
const SHRINK_TIME := 0.22
## Seconds for the hole to open to full size after it manifests.
const FORM_TIME := 0.45
const COLLAPSE_TIME := 1.6
## Lensing sphere and disk sizes in horizon radii.
const INFLUENCE := 22.0
const DISK_OUTER := 20.0
## Viewing angle of the disk, the same for every viewer: seen this far from above its plane,
## and rolled this far around the line of sight.
const DISK_INCLINATION := deg_to_rad(8.0)
const DISK_ROLL := deg_to_rad(-16.0)
## The simple look's flat disk has no thickness, so it is shown a little more from above.
const LITE_INCLINATION := deg_to_rad(14.0)
const HOLE_SHADER := preload("res://shaders/vfx/black_hole.gdshader")
const LENS_SHADER := preload("res://shaders/vfx/black_hole_lens.gdshader")
const DISK_SHADER := preload("res://shaders/vfx/black_hole_disk.gdshader")
## Simple variant: the lens quad's half size and the flat disk's outer radius (horizon radii).
const LITE_LENS := 11.0
const LITE_DISK := 22.0
const SPARK_SHADER := preload("res://shaders/vfx/bh_spark.gdshader")
const INFALL_SHADER := preload("res://shaders/vfx/bh_infall.gdshader")
const SPARK_COLOR := Color(0.78, 0.6, 1.0)
const LIGHT_COLOR := Color(1.0, 0.62, 0.32)

var spell: BlackHoleSpell
var owner_id := -1
var phase := Phase.SPARK

var _from := Vector3.ZERO
var _target := Vector3.ZERO
var _t := 0.0
var _seed := 0.0
var _spark: Node3D
var _spark_mesh: MeshInstance3D
var _spark_trail: GPUParticles3D
var _spark_light: OmniLight3D
## Fancy: the ray-marched sphere. Simple: _hole = lens quad, _lite_disk = the flat disk.
var _hole: MeshInstance3D
var _hole_mat: ShaderMaterial
var _lite_disk: MeshInstance3D
var _lite_disk_mat: ShaderMaterial
var _fancy := true
## -1 = follow the "fancy_black_hole" setting, 0/1 = forced (prewarm builds both).
var _variant := -1
var _disk_basis := Basis.IDENTITY
var _infall: GPUParticles3D
var _debris: GPUParticles3D
var _light: OmniLight3D
var _rs := 0.0
var _spin := 0.0
var _view_up := Vector3.UP
var _disk_n := Vector3.ZERO
var _prewarm := false


static func spawn(parent: Node, bh: BlackHoleSpell, from: Vector3, target: Vector3, owner: int,
		warm_up := false) -> BlackHole:
	var hole := BlackHole.new()
	hole.spell = bh
	hole.owner_id = owner
	hole._from = from
	hole._target = target
	hole._prewarm = warm_up
	parent.add_child(hole)
	return hole


## Runs the whole sequence quickly in the loading viewport so every shader compiles.
## Both looks are warmed up, so switching the setting later doesn't stall either.
static func prewarm(vp: Node) -> void:
	var bh := load("res://spells/black_hole.tres") as BlackHoleSpell
	for variant in 2:
		var hole := spawn(vp, bh, Vector3(0, 0, -10), Vector3(0, 1, -12), -99, true)
		hole._variant = variant
		hole._t = SPARK_TIME - 0.05


## 0..1 edge-distortion strength for a viewer at `pos`.
func screen_intensity(pos: Vector3) -> float:
	if phase == Phase.SPARK or _rs <= 0.0:
		return 0.0
	var d := pos.distance_to(_target)
	var near := clampf(1.0 - (d - _rs * 1.5) / (spell.reach * 0.75), 0.0, 1.0)
	return near * clampf(_rs / spell.horizon, 0.0, 1.0)


func get_center() -> Vector3:
	return _target


func _ready() -> void:
	if not _prewarm:
		add_to_group("black_hole")
	top_level = true
	global_position = _from
	# The same disk tilt on every client: derived from the summoning point.
	_seed = fmod(absf(sin(_target.x * 12.9898 + _target.z * 78.233) * 43758.5453), 1.0)
	var tilt_axis := Vector3(cos(_seed * TAU), 0.0, sin(_seed * TAU))
	_disk_basis = Basis(tilt_axis, deg_to_rad(14.0 + _seed * 10.0))
	_build_spark()
	if not _prewarm:
		Settings.setting_changed.connect(_on_setting_changed)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "fancy_black_hole" and _hole:
		_build_visual()


# --- Building ---------------------------------------------------------------------------

func _build_spark() -> void:
	_spark = Node3D.new()
	add_child(_spark)
	_spark_mesh = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := ShaderMaterial.new()
	mat.shader = SPARK_SHADER
	quad.material = mat
	_spark_mesh.mesh = quad
	_spark_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spark_mesh.scale = Vector3.ONE * 0.9
	_spark.add_child(_spark_mesh)
	_spark_trail = SpellFx.particles(self, 80, 1.4, false, false, Vector2(0.09, 0.09), SPARK_COLOR, Color(1, 0.95, 1))
	_spark_trail.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var pm := _spark_trail.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3(0, -0.3, 0)
	_spark_light = OmniLight3D.new()
	_spark_light.light_volumetric_fog_energy = 0.0
	_spark_light.light_color = SPARK_COLOR
	_spark_light.omni_range = 7.0
	_spark_light.light_energy = 1.5
	_spark.add_child(_spark_light)


func _flash() -> void:
	var root := SpellFx.effect_root(get_parent(), _target, 3.0)
	SpellFx.flash(root, _target, Color(0.9, 0.8, 1.0), 9.0, 60.0, 1.0)
	var burst := SpellFx.particles(root, 160, 1.4, true, true, Vector2(0.08, 1.4), SPARK_COLOR, Color(1, 0.9, 1))
	burst.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	var pm := burst.process_material as ParticleProcessMaterial
	pm.spread = 180.0
	pm.initial_velocity_min = 10.0
	pm.initial_velocity_max = 30.0
	pm.damping_min = 8.0
	pm.damping_max = 14.0
	for i in 2:
		var ring := SpellFx.ring(root, false, 40.0 + i * 25.0, SPARK_COLOR, Color(1, 0.9, 1))
		ring.global_basis = _disk_basis * Basis(Vector3.RIGHT, PI * 0.5)
		SpellFx.animate_ring(ring, 0.9 + i * 0.4, 0.0, i * 0.12)
	_shake_local(0.9, 80.0)


func _form_hole() -> void:
	_build_visual()
	_infall = _particles(false, 260, 5.0)
	_debris = _particles(true, 120, 4.0)
	_light = OmniLight3D.new()
	_light.light_volumetric_fog_energy = 0.0
	_light.light_color = LIGHT_COLOR
	_light.omni_range = 55.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)
	_light.global_position = _target


## (Re)builds the hole itself in the look the setting asks for.
func _build_visual() -> void:
	for node in [_hole, _lite_disk]:
		if node:
			node.queue_free()
	_hole = null
	_lite_disk = null
	_fancy = bool(Settings.get_value("fancy_black_hole")) if _variant < 0 else _variant == 1
	var max_rs := spell.horizon * (1.0 + spell.growth)
	if _fancy:
		var sphere := SphereMesh.new()
		sphere.radius = max_rs * INFLUENCE
		sphere.height = sphere.radius * 2.0
		sphere.radial_segments = 48
		sphere.rings = 24
		_hole_mat = ShaderMaterial.new()
		_hole_mat.shader = HOLE_SHADER
		_hole_mat.set_shader_parameter("influence", sphere.radius)
		_hole_mat.set_shader_parameter("disk_normal", _disk_basis.y)
		_hole_mat.set_shader_parameter("lens_fade", 3.0)
		_hole_mat.set_shader_parameter("disk_outer", DISK_OUTER)
		_hole_mat.render_priority = 10
		sphere.material = _hole_mat
		_hole = _visual_mesh(sphere, sphere.radius)
	else:
		# Lens quad first, the disk drawn over it (its far half is cut where the quad shows
		# the lensed arc instead).
		var quad := QuadMesh.new()
		quad.size = Vector2(2.0, 2.0)
		_hole_mat = ShaderMaterial.new()
		_hole_mat.shader = LENS_SHADER
		_hole_mat.set_shader_parameter("lens_radius", LITE_LENS)
		_hole_mat.render_priority = -1
		quad.material = _hole_mat
		_hole = _visual_mesh(quad, max_rs * LITE_LENS * 1.5)
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE * LITE_DISK * 2.0
		# Fine enough for the far side to bend smoothly round the shadow (vertex lensing).
		plane.subdivide_width = 240
		plane.subdivide_depth = 240
		_lite_disk_mat = ShaderMaterial.new()
		_lite_disk_mat.shader = DISK_SHADER
		_lite_disk_mat.set_shader_parameter("disk_outer", LITE_DISK)
		plane.material = _lite_disk_mat
		_lite_disk = _visual_mesh(plane, max_rs * LITE_DISK)
	for mat in _materials():
		mat.set_shader_parameter("rs", 0.0)
		mat.set_shader_parameter("disk_strength", 0.0)
	if _rs > 0.0:
		_update_hole(1.0 if phase == Phase.ACTIVE else 0.5)
		_orient_disk()


func _visual_mesh(mesh: Mesh, margin: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = margin
	add_child(mi)
	mi.global_position = _target
	return mi


func _materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = [_hole_mat]
	if _lite_disk:
		out.append(_lite_disk_mat)
	return out


func _particles(debris: bool, amount: int, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-60, -60, -60), Vector3(120, 120, 120))
	var pm := ShaderMaterial.new()
	pm.shader = INFALL_SHADER
	pm.set_shader_parameter("debris", debris)
	pm.set_shader_parameter("rs", spell.horizon)
	pm.set_shader_parameter("start_radius", spell.horizon * DISK_OUTER * 0.95)
	pm.set_shader_parameter("shell", spell.horizon * 22.0)
	pm.set_shader_parameter("size", 0.28 if debris else 0.2)
	if debris:
		pm.set_shader_parameter("cold", Color(0.55, 0.4, 0.9))
		pm.set_shader_parameter("hot", Color(1.0, 0.85, 1.0))
	p.process_material = pm
	var quad := QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = SpellFx.PARTICLE_SHADER
	mat.set_shader_parameter("energy", 3.0)
	quad.material = mat
	p.draw_pass_1 = quad
	add_child(p)
	p.global_transform = Transform3D(_disk_basis if not debris else Basis.IDENTITY, _target)
	p.emitting = true
	return p


# --- Running ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if _hole:
		_orient_disk()
	match phase:
		Phase.SPARK:
			_update_spark(clampf(_t / SPARK_TIME, 0.0, 1.0))
			if _t >= SPARK_TIME:
				phase = Phase.CHARGE
				_t = 0.0
		Phase.CHARGE:
			_update_charge()
			if _t >= CHARGE_TIME:
				phase = Phase.ACTIVE
				_t = 0.0
				_spark.visible = false
				_spark_light.visible = false
				_flash()
				_form_hole()
		Phase.ACTIVE:
			var life := _t / (0.6 if _prewarm else spell.duration)
			var form := smoothstep(0.0, FORM_TIME, _t)
			_rs = spell.horizon * (1.0 + spell.growth * life) * (1.0 - pow(1.0 - form, 3.0))
			_update_hole(form)
			if life >= 1.0:
				phase = Phase.COLLAPSE
				_t = 0.0
		Phase.COLLAPSE:
			var u := clampf(_t / COLLAPSE_TIME, 0.0, 1.0)
			# Shrinks slowly, then snaps shut.
			_rs = spell.horizon * (1.0 + spell.growth) * (1.0 - u * u * u)
			_update_hole(1.0 - smoothstep(0.6, 1.0, u))
			if _t >= COLLAPSE_TIME * 0.9 and _infall:
				_infall.emitting = false
				_debris.emitting = false
			if _t >= COLLAPSE_TIME:
				_final_flash()
				queue_free()


func _update_spark(u: float) -> void:
	# Eases up along a lazy, narrowing spiral with a little flutter, like a drifting fairy light.
	var e := u * u * (3.0 - 2.0 * u)
	var base := _from.lerp(_target, e)
	var swirl := (1.0 - e) * 2.2 * sin(u * PI)
	var ang := u * TAU * 2.3 + _seed * TAU
	var flutter := Vector3(sin(u * 37.0), sin(u * 23.0 + 1.0), cos(u * 29.0)) * 0.25 * sin(u * PI)
	var pos := base + Vector3(cos(ang), 0.0, sin(ang)) * swirl + flutter
	_spark.global_position = pos
	_spark_trail.global_position = pos
	_spin = _t * 1.8
	_spark_mesh.set_instance_shader_parameter("spin", _spin)
	_spark_mesh.scale = Vector3.ONE * lerpf(1.2, 2.6, e)
	_spark_light.light_energy = 1.2 + e * 2.0


## At the top: swells, spins up faster and faster, then shrinks to a point.
func _update_charge() -> void:
	var u := clampf(_t / CHARGE_TIME, 0.0, 1.0)
	var shrink_from := CHARGE_TIME - SHRINK_TIME
	var swell := smoothstep(0.0, shrink_from, _t)
	var size := lerpf(2.6, 7.5, swell * swell)
	if _t > shrink_from:
		var k := (_t - shrink_from) / SHRINK_TIME
		size *= 1.0 - k * k
	_spin += (2.0 + 70.0 * u * u * u) * get_process_delta_time()
	_spark_mesh.scale = Vector3.ONE * maxf(size, 0.001)
	_spark_mesh.set_instance_shader_parameter("spin", _spin)
	_spark_mesh.set_instance_shader_parameter("flare", swell)
	_spark_light.light_energy = 3.0 + swell * 5.0
	_spark_trail.emitting = u < 0.6
	# A faint tremble while it charges.
	_spark.global_position = _target + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.06 * swell


## Keeps the disk at the same cinematic angle for the local viewer: seen slightly from above
## and tilted. (Each player orients it for their own camera.) The screen-up reference is world
## up, but when looking steeply up or down at it (where world up lies nearly along the view and
## would whip the disk round) it holds on to the reference of the previous frame; and the disk
## turns towards its target smoothly instead of snapping.
func _orient_disk() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var view := _target - cam.global_position
	if view.length_squared() < 0.01:
		return
	view = view.normalized()
	var world_up := (Vector3.UP - view * view.dot(Vector3.UP)).normalized()
	var held := _view_up - view * view.dot(_view_up)
	held = held.normalized() if held.length_squared() > 0.0001 else world_up
	var steep := smoothstep(0.55, 0.9, absf(view.y))
	var up := world_up * (1.0 - steep) + held * steep
	if up.length_squared() < 0.0001:
		up = held
	up = up.normalized()
	_view_up = up
	# Tip the disk plane's normal towards the viewer, then roll it around the line of sight.
	var incl := DISK_INCLINATION if _fancy else LITE_INCLINATION
	var target_n := (up * cos(incl) - view * sin(incl)).normalized()
	target_n = target_n.rotated(view, DISK_ROLL)
	var dt := get_process_delta_time()
	var n := target_n if _disk_n == Vector3.ZERO else _disk_n.slerp(target_n, 1.0 - exp(-2.5 * dt)).normalized()
	_disk_n = n
	var x := n.cross(view)
	if x.length_squared() < 0.0001:
		x = n.cross(Vector3.RIGHT)
	x = x.normalized()
	_disk_basis = Basis(x, n, x.cross(n).normalized())
	if _fancy:
		_hole_mat.set_shader_parameter("disk_normal", n)
	else:
		# The flat disk lies in the plane; the lens quad thickens its lensed arc on the side the
		# disk's normal points to on screen.
		_lite_disk.global_transform = Transform3D(_disk_basis.scaled(Vector3.ONE * maxf(_rs, 0.001)), _target)
		var cb := cam.global_basis
		var up2 := Vector2(n.dot(cb.x), n.dot(cb.y))
		_hole_mat.set_shader_parameter("disk_up", up2.normalized() if up2.length_squared() > 1e-6 else Vector2.UP)
	if _infall:
		_infall.global_basis = _disk_basis


func _update_hole(strength: float) -> void:
	for mat in _materials():
		mat.set_shader_parameter("rs", _rs)
		mat.set_shader_parameter("disk_strength", strength)
		mat.set_shader_parameter("presence", clampf(strength * 3.0, 0.0, 1.0))
	_light.light_energy = 4.0 * strength * (0.9 + 0.1 * sin(_t * 3.0))
	for p in [_infall, _debris]:
		(p.process_material as ShaderMaterial).set_shader_parameter("rs", maxf(_rs, 0.2))
		# Simple look: the shadow hides what's behind it (the fancy one draws over everything).
		var draw := (p.draw_pass_1 as Mesh).surface_get_material(0) as ShaderMaterial
		draw.set_shader_parameter("hole", Vector4(_target.x, _target.y, _target.z, 0.0 if _fancy else _rs * 2.6))


func _final_flash() -> void:
	var root := SpellFx.effect_root(get_parent(), _target, 3.0)
	SpellFx.flash(root, _target, Color(1.0, 0.85, 0.7), 20.0, 70.0, 1.0)
	var burst := SpellFx.particles(root, 120, 1.6, true, true, Vector2(0.1, 1.8), LIGHT_COLOR, Color(1, 0.95, 0.9))
	burst.visibility_aabb = AABB(Vector3(-50, -50, -50), Vector3(100, 100, 100))
	var pm := burst.process_material as ParticleProcessMaterial
	pm.spread = 180.0
	pm.initial_velocity_min = 15.0
	pm.initial_velocity_max = 40.0
	pm.damping_min = 10.0
	pm.damping_max = 18.0
	var ring := SpellFx.ring(root, false, 70.0, LIGHT_COLOR, Color(1, 0.95, 0.9))
	ring.global_basis = _disk_basis * Basis(Vector3.RIGHT, PI * 0.5)
	SpellFx.animate_ring(ring, 1.2, 0.0)
	_shake_local(1.0, 90.0)


# --- Gameplay -----------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _prewarm or phase != Phase.ACTIVE:
		return
	var me := get_tree().current_scene.get_node_or_null("Player") as Node3D
	if me == null or not me.has_method("set_pull") or me.is_dead():
		return
	var d := me.global_position.distance_to(_target)
	# Rumble for everyone near, caster included.
	if me.has_method("add_shake"):
		me.add_shake(screen_intensity(me.global_position) * 0.35)
	if owner_id == Net.my_id:
		return
	if d < _rs * spell.kill_factor:
		me.take_damage(1e6, owner_id)
		return
	if d > spell.reach:
		return
	var life := clampf(_t / spell.duration, 0.0, 1.0)
	var power := lerpf(spell.pull_start, spell.pull_end, life * life * (3.0 - 2.0 * life))
	var fall := 1.0 - d / spell.reach
	# Stronger the closer, with a sharp rise near the horizon.
	var speed := power * (fall * fall + 0.6 * clampf(_rs * 3.0 / d, 0.0, 1.0) * fall)
	me.set_pull("black_hole_%d" % get_instance_id(), _target, speed)


func _shake_local(amount: float, radius: float) -> void:
	var me := get_tree().current_scene.get_node_or_null("Player") as Node3D
	if me and me.has_method("add_shake") and not _prewarm:
		var d := me.global_position.distance_to(_target)
		if d < radius:
			me.add_shake(amount * (1.0 - d / radius))
