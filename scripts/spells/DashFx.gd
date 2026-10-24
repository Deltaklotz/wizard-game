class_name DashFx
extends RefCounted
## Visual effects of the dash spell, shared by the local caster and remote replays:
## a rune circle flaring on the ground and shockwave rings where the dash starts, a spark
## burst and flash, streaks rushing past (DashTrail), afterimages for remote casters, and a
## puff of motes where the dash ends.

const GHOST_SHADER := preload("res://shaders/vfx/dash_ghost.gdshader")


## caster: the dashing body; feet_offset: its origin height above the feet;
## first_person: the local player (streaks around the camera instead of the body).
static func play(caster: Node3D, dir: Vector3, duration: float, color: Color, accent: Color,
		feet_offset: float, first_person: bool, ghost_source: Node3D = null) -> void:
	var scene := caster.get_tree().current_scene
	var up := Vector3.UP
	if caster is CharacterBody3D and (caster as CharacterBody3D).is_on_floor():
		up = (caster as CharacterBody3D).get_floor_normal()
	var feet := caster.global_position - Vector3.UP * feet_offset
	departure(scene, feet, up, dir, color, accent, not first_person)
	if first_person:
		# A ring opening just ahead of the eyes that the caster bursts through.
		var root := SpellFx.effect_root(scene, feet, 0.6)
		var portal := SpellFx.ring(root, false, 2.6, color, accent)
		portal.global_basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
		portal.global_position = feet + Vector3.UP * 1.45 + dir * 2.2
		SpellFx.animate_ring(portal, 0.3, 0.0)
	var trail := DashTrail.new()
	scene.add_child(trail)
	trail.setup(caster, dir, duration, color, accent, feet_offset, first_person, ghost_source)
	caster.get_tree().create_timer(duration + (0.0 if first_person else RemotePlayer.INTERP_DELAY)).timeout.connect(func() -> void:
		if is_instance_valid(caster):
			arrival(scene, caster.global_position - Vector3.UP * feet_offset, dir, color, accent))


## flash: a burst of light (skipped for the local caster, whose book it would blow out).
static func departure(parent: Node, feet: Vector3, up: Vector3, dir: Vector3, color: Color, accent: Color,
		flash: bool = true) -> void:
	var root := SpellFx.effect_root(parent, feet, 1.4)
	# Rune circle on the ground.
	var ground := SpellFx.ring(root, true, 3.4, color, accent)
	ground.global_basis = SpellFx.basis_with_up(up, dir)
	ground.global_position = feet + up * 0.12
	SpellFx.animate_ring(ground, 1.1, 0.8)
	# Shockwaves facing the dash direction, a larger one trailing the first.
	for i in 2:
		var wave := SpellFx.ring(root, false, 2.2 + i * 1.2, color, accent)
		wave.global_basis = Basis.looking_at(dir, up if absf(dir.dot(up)) < 0.95 else Vector3.RIGHT)
		wave.global_position = feet + up * 1.0 - dir * (0.2 + i * 0.5)
		SpellFx.animate_ring(wave, 0.38 + i * 0.12, 0.0, i * 0.05)
	# Spark burst: flung backwards and outwards, drifting up.
	var burst := SpellFx.particles(root, 56, 0.75, true, false, Vector2(0.09, 0.09), color, accent)
	burst.global_position = feet + up * 0.9
	var pm := burst.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.45
	pm.direction = -dir + up * 0.4
	pm.spread = 70.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 7.5
	pm.gravity = Vector3(0, 1.2, 0)
	pm.damping_min = 4.0
	pm.damping_max = 7.0
	pm.scale_min = 0.4
	pm.scale_max = 1.4
	# A few long streak sparks.
	var shards := SpellFx.particles(root, 18, 0.35, true, true, Vector2(0.03, 0.55), color, accent)
	shards.global_position = feet + up * 1.0
	var sm := shards.process_material as ParticleProcessMaterial
	sm.direction = -dir
	sm.spread = 40.0
	sm.initial_velocity_min = 6.0
	sm.initial_velocity_max = 14.0
	sm.damping_min = 10.0
	sm.damping_max = 16.0
	sm.gravity = Vector3.ZERO
	if not flash:
		return
	SpellFx.flash(root, feet + up * 1.1, color.lerp(accent, 0.3), 5.0, 7.0, 0.45)


## Draws every dash effect once in the prewarm viewport (see SpellFx.prewarm).
static func prewarm(vp: Node) -> void:
	var dummy := MeshInstance3D.new()
	dummy.mesh = BoxMesh.new()
	vp.add_child(dummy)
	var c := Color(0.5, 0.6, 1.0)
	departure(vp, Vector3.ZERO, Vector3.UP, Vector3.FORWARD, c, c, true)
	arrival(vp, Vector3.ZERO, Vector3.FORWARD, c, c)
	afterimage(vp, dummy, c, 1.0)
	for first_person in [true, false]:
		var trail := DashTrail.new()
		vp.add_child(trail)
		trail.setup(dummy, Vector3.FORWARD, 0.2, c, c, 0.0, first_person, null)
	var portal := SpellFx.ring(SpellFx.effect_root(vp, Vector3.ZERO, 1.0), false, 2.0, c, c)
	SpellFx.animate_ring(portal, 0.3, 0.0)


static func arrival(parent: Node, feet: Vector3, dir: Vector3, color: Color, accent: Color) -> void:
	var root := SpellFx.effect_root(parent, feet, 1.0)
	var ground := SpellFx.ring(root, true, 2.2, color, accent)
	ground.global_basis = SpellFx.basis_with_up(Vector3.UP, dir)
	ground.global_position = feet + Vector3.UP * 0.12
	SpellFx.animate_ring(ground, 0.6, -0.4)
	var puff := SpellFx.particles(root, 32, 0.8, true, false, Vector2(0.07, 0.07), color, accent)
	puff.global_position = feet + Vector3.UP * 0.8
	var pm := puff.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5
	pm.direction = dir + Vector3.UP * 0.5
	pm.spread = 120.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, 0.8, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.scale_min = 0.4
	pm.scale_max = 1.2


## Glowing afterimage of `source` that fades out where it stands: a frozen copy of the pose
## for a PlayerModel, otherwise the mesh of a MeshInstance3D.
static func afterimage(parent: Node, source: Node3D, color: Color, strength: float) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = GHOST_SHADER
	mat.set_shader_parameter("color", color)
	# The fade is a material parameter here, since a posed copy consists of several meshes.
	mat.set_shader_parameter("fade_all", strength)
	var ghost: Node3D
	if source is PlayerModel:
		ghost = (source as PlayerModel).make_ghost(mat)
		parent.add_child(ghost)
	elif source is MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = (source as MeshInstance3D).mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		mi.global_transform = source.global_transform
		ghost = mi
	else:
		return
	var tw := ghost.create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("fade_all", v), strength, 0.0, 0.45)
	tw.parallel().tween_property(ghost, "scale", ghost.scale * 1.06, 0.45)
	tw.tween_callback(ghost.queue_free)
