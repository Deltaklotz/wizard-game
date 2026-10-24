class_name SpellFx
extends RefCounted
## Shared building blocks for spell effects: self-freeing effect roots, animated arcane rings
## (shaders/vfx/spell_ring.gdshader), additive glow particles (spell_particle.gdshader) and
## light flashes.

const PARTICLE_SHADER := preload("res://shaders/vfx/spell_particle.gdshader")
const RING_SHADER := preload("res://shaders/vfx/spell_ring.gdshader")


## Renders every spell effect once in a tiny offscreen viewport, so their shaders and particle
## pipelines are compiled during loading instead of stalling the first cast. Add new spells'
## effects here.
static func prewarm(parent: Node) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	parent.add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.position = Vector3(0, 1.2, 5)
	cam.make_current()
	DashFx.prewarm(vp)
	SniperFx.prewarm(vp)
	ChainFx.prewarm(vp)
	SwordWall.prewarm(vp)
	MagicBolt.prewarm(vp)
	ShieldDome.prewarm(vp)
	BlackHole.prewarm(vp)
	FireFx.prewarm(vp)
	InfernoBeam.prewarm(vp)
	MoneyRain.prewarm(vp)
	SmokeCloud.prewarm(vp)
	Spinjitzu.prewarm(vp)
	Bounceshroom.prewarm(vp)
	GravityField.prewarm(vp)
	Missile.prewarm(vp)
	for path in ["res://spells/dash.tres", "res://spells/black_hole.tres"]:
		var page := WorldItem.create(vp, load(path), Vector3(0, 1, -4), false)
		vp.get_tree().create_timer(0.5).timeout.connect(page.queue_free)
	vp.get_tree().create_timer(2.5).timeout.connect(vp.queue_free)


## A holder that frees itself (and all its effects) after `lifetime` seconds.
static func effect_root(parent: Node, at: Vector3, lifetime: float) -> Node3D:
	var root := Node3D.new()
	root.name = "SpellFx"
	parent.add_child(root)
	root.global_position = at
	root.get_tree().create_timer(lifetime).timeout.connect(root.queue_free)
	return root


static func ring(parent: Node3D, runes: bool, size: float, color: Color, accent: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	mat.set_shader_parameter("runes", runes)
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("accent", accent)
	if runes:
		var plane := PlaneMesh.new()
		plane.size = Vector2(size, size)
		plane.material = mat
		mi.mesh = plane
	else:
		var quad := QuadMesh.new()
		quad.size = Vector2(size, size)
		quad.material = mat
		mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func animate_ring(mi: MeshInstance3D, duration: float, spin: float, delay: float = 0.0) -> void:
	mi.set_instance_shader_parameter("progress", 0.0)
	mi.visible = delay <= 0.0
	var tw := mi.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(mi.show)
	tw.tween_method(func(v: float) -> void:
		mi.set_instance_shader_parameter("progress", v)
		mi.set_instance_shader_parameter("spin", v * spin), 0.0, 1.0, duration)


static func basis_with_up(up: Vector3, forward: Vector3) -> Basis:
	var f := (forward - up * forward.dot(up))
	if f.length_squared() < 0.0001:
		f = Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT
	var z := -f.normalized()
	var x := up.cross(z).normalized()
	return Basis(x, up, z)


## Additive glowing particles; colours vary between `color` and `accent` and fade out.
static func particles(parent: Node3D, amount: int, lifetime: float, one_shot: bool, streak: bool,
		size: Vector2, color: Color, accent: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.explosiveness = 1.0 if one_shot else 0.0
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24))
	if streak:
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var pm := ParticleProcessMaterial.new()
	var tint := Gradient.new()
	tint.set_color(0, color.lightened(0.2))
	tint.set_color(1, accent)
	var tint_tex := GradientTexture1D.new()
	tint_tex.gradient = tint
	pm.color_initial_ramp = tint_tex
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.08, 0.55, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1.4, 1.4, 1.4, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	pm.color_ramp = fade_tex
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.25))
	var shrink_tex := CurveTexture.new()
	shrink_tex.curve = shrink
	pm.scale_curve = shrink_tex
	pm.gravity = Vector3.ZERO
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = size
	var mat := ShaderMaterial.new()
	mat.shader = PARTICLE_SHADER
	mat.set_shader_parameter("streak", streak)
	quad.material = mat
	p.draw_pass_1 = quad
	parent.add_child(p)
	p.emitting = true
	return p


## Omni light that flares up and fades out.
static func flash(parent: Node3D, at: Vector3, color: Color, energy: float, light_range: float, duration: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_volumetric_fog_energy = 0.0
	light.light_color = color
	light.omni_range = light_range
	light.light_energy = energy
	light.shadow_enabled = false
	parent.add_child(light)
	light.global_position = at
	light.create_tween().tween_property(light, "light_energy", 0.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	return light
