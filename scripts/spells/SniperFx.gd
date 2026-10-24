class_name SniperFx
extends RefCounted
## Visuals of the sniper beam (local shot and remote replays): a white-hot core inside a
## crimson glow with two spiralling energy strands (shaders/vfx/sniper_beam.gdshader) that
## punches in and thins out, motes shed along its whole length, streaks racing down it, rings
## at the muzzle, and an impact burst (rune ring on the surface, shockwave, sparks, flash) that
## is scaled up with distance so far hits stay readable.

const BEAM_SHADER := preload("res://shaders/vfx/sniper_beam.gdshader")
const CROSSHAIR_SHADER := preload("res://shaders/vfx/sniper_crosshair.gdshader")
const BEAM_TIME := 0.9
## Radii of the core, glow and strand cylinders.
const RADII := [0.045, 0.2, 0.32]


## first_person: the shooter's own view (no rings or light at the muzzle).
static func fire(parent: Node, from: Vector3, to: Vector3, normal: Vector3, color: Color, accent: Color,
		hit_player: bool, first_person: bool, viewer: Vector3) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.01:
		return
	dir /= length
	var root := SpellFx.effect_root(parent, from, BEAM_TIME + 1.2)
	_beam(root, from, dir, length, color, accent)
	_along(root, from, dir, length, color, accent)
	_muzzle(root, from + dir * (0.6 if first_person else 0.3), dir, color, accent, not first_person)
	# Impact effects grow with the distance to the viewer so a far hit is still visible.
	var scale := clampf(viewer.distance_to(to) / 40.0, 1.0, 5.0)
	_impact(root, to, normal, dir, color, accent, hit_player, scale)


## Spinning red reticle shown in front of a player who is aiming (for everyone else).
static func make_crosshair(size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := ShaderMaterial.new()
	mat.shader = CROSSHAIR_SHADER
	quad.material = mat
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Draws each effect once so shaders and particle pipelines compile during loading.
static func prewarm(vp: Node) -> void:
	var c := Color(1.0, 0.2, 0.2)
	fire(vp, Vector3(0, 1, 0), Vector3(0, 1, -20), Vector3.BACK, c, c, true, false, Vector3(0, 1.2, 5))
	var cross := make_crosshair(1.0)
	vp.add_child(cross)
	cross.position = Vector3(0, 1, 0)
	vp.get_tree().create_timer(0.5).timeout.connect(cross.queue_free)


static func _beam(root: Node3D, from: Vector3, dir: Vector3, length: float, color: Color, accent: Color) -> void:
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(dir).normalized()
	var z := x.cross(dir).normalized()
	var mid := from + dir * length * 0.5
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	mesh.radial_segments = 16
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	var parts: Array[MeshInstance3D] = []
	var mats: Array[ShaderMaterial] = []
	for layer in 3:
		var mat := ShaderMaterial.new()
		mat.shader = BEAM_SHADER
		mat.set_shader_parameter("layer", layer)
		mat.set_shader_parameter("color", color)
		mat.set_shader_parameter("accent", accent)
		mat.set_shader_parameter("length_m", length)
		mat.set_shader_parameter("intensity", 0.0)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 4.0
		root.add_child(mi)
		parts.append(mi)
		mats.append(mat)
	var shape := func(t: float) -> void:
		# Punch in over 40 ms (wide), hold briefly, then fade and thin out.
		var intensity: float
		var width: float
		if t < 0.045:
			intensity = t / 0.045
			width = lerpf(2.2, 1.4, t / 0.045)
		else:
			var u := clampf((t - 0.045) / (BEAM_TIME - 0.045), 0.0, 1.0)
			intensity = pow(1.0 - u, 1.6)
			width = lerpf(1.4, 0.15, pow(u, 0.7))
		for layer in 3:
			var r: float = RADII[layer] * width * (1.0 if layer == 0 else lerpf(1.0, 1.6, t / BEAM_TIME))
			parts[layer].global_transform = Transform3D(Basis(x * r, dir * length, z * r), mid)
			mats[layer].set_shader_parameter("intensity", intensity)
	shape.call(0.0)
	root.create_tween().tween_method(shape, 0.0, BEAM_TIME, BEAM_TIME)
	SpellFx.flash(root, mid, color, 2.0, minf(length * 0.5, 30.0), 0.3)


## Motes shed along the whole beam, and streaks racing down it.
static func _along(root: Node3D, from: Vector3, dir: Vector3, length: float, color: Color, accent: Color) -> void:
	var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
	var motes := SpellFx.particles(root, clampi(int(length * 2.5), 40, 700), 1.1, true, false, Vector2(0.06, 0.06), color, accent)
	motes.global_transform = Transform3D(basis, from + dir * length * 0.5)
	var half := length * 0.5
	motes.visibility_aabb = AABB(-Vector3(3, 3, half + 3), Vector3(6, 6, length + 6))
	var pm := motes.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.12, 0.12, half)
	pm.direction = Vector3(1, 0, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 0.4, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	pm.scale_min = 0.4
	pm.scale_max = 1.3
	var streaks := SpellFx.particles(root, 26, minf(0.45, length / 120.0 + 0.1), true, true, Vector2(0.05, 3.0), color, accent)
	streaks.global_transform = Transform3D(basis, from)
	streaks.visibility_aabb = AABB(-Vector3(4, 4, length + 4), Vector3(8, 8, length + 8))
	streaks.explosiveness = 0.6
	var sm := streaks.process_material as ParticleProcessMaterial
	sm.direction = Vector3(0, 0, -1)
	sm.spread = 0.6
	sm.initial_velocity_min = minf(length * 2.0, 120.0)
	sm.initial_velocity_max = minf(length * 3.0, 260.0)


## first_person skips the rings and light: seen through the 4x scope they fill the whole view.
static func _muzzle(root: Node3D, at: Vector3, dir: Vector3, color: Color, accent: Color, third_person: bool) -> void:
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	for i in (3 if third_person else 0):
		var ring := SpellFx.ring(root, false, 0.9 + i * 0.8, color, accent)
		ring.global_basis = Basis.looking_at(dir, up)
		ring.global_position = at + dir * (i * 0.6)
		SpellFx.animate_ring(ring, 0.28 + i * 0.1, 0.0, i * 0.03)
	var sparks := SpellFx.particles(root, 24, 0.35, true, true, Vector2(0.03, 0.4), color, accent)
	sparks.global_position = at
	var sm := sparks.process_material as ParticleProcessMaterial
	sm.direction = dir
	sm.spread = 35.0
	sm.initial_velocity_min = 4.0
	sm.initial_velocity_max = 12.0
	sm.damping_min = 8.0
	sm.damping_max = 14.0
	if third_person:
		SpellFx.flash(root, at, color.lerp(accent, 0.3), 6.0, 8.0, 0.35)


static func _impact(root: Node3D, at: Vector3, normal: Vector3, dir: Vector3, color: Color, accent: Color,
		hit_player: bool, s: float) -> void:
	var n := normal if normal.length_squared() > 0.01 else -dir
	var ground := SpellFx.ring(root, true, 2.6 * s, color, accent)
	ground.global_basis = SpellFx.basis_with_up(n, dir)
	ground.global_position = at + n * 0.08
	SpellFx.animate_ring(ground, 1.1, 1.2)
	for i in 2:
		var wave := SpellFx.ring(root, false, (2.4 + i * 2.0) * s, color, accent)
		wave.global_basis = Basis.looking_at(n, Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT)
		wave.global_position = at + n * (0.3 + i * 0.2) * s
		SpellFx.animate_ring(wave, 0.35 + i * 0.15, 0.0, i * 0.05)
	var sparks := SpellFx.particles(root, 60 if hit_player else 44, 0.7, true, true, Vector2(0.05, 0.7) * s, color, accent)
	sparks.global_position = at + n * 0.1
	sparks.visibility_aabb = AABB(-Vector3.ONE * 20.0 * s, Vector3.ONE * 40.0 * s)
	var pm := sparks.process_material as ParticleProcessMaterial
	pm.direction = dir.bounce(n).normalized() * 0.5 + n
	pm.spread = 65.0
	pm.initial_velocity_min = 6.0 * s
	pm.initial_velocity_max = 18.0 * s
	pm.gravity = Vector3(0, -9.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	var embers := SpellFx.particles(root, 36, 1.4, true, false, Vector2(0.1, 0.1) * s, color, accent)
	embers.global_position = at + n * 0.2
	embers.visibility_aabb = AABB(-Vector3.ONE * 20.0 * s, Vector3.ONE * 40.0 * s)
	var em := embers.process_material as ParticleProcessMaterial
	em.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	em.emission_sphere_radius = 0.4 * s
	em.direction = n
	em.spread = 80.0
	em.initial_velocity_min = 0.5 * s
	em.initial_velocity_max = 3.0 * s
	em.gravity = Vector3(0, 1.0, 0)
	em.damping_min = 1.5
	em.damping_max = 3.0
	SpellFx.flash(root, at + n * 0.5, color.lerp(accent, 0.2), 10.0 if hit_player else 7.0, 10.0 * s, 0.6)
