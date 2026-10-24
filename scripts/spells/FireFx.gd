class_name FireFx
extends RefCounted
## Fire effects shared by the Fireball, its fire pool (FirePatch) and burning players: flame and
## smoke particles (shaders/vfx/fire_flame.gdshader, fire_smoke.gdshader), the explosion, a
## procedural scorch mark (Decal) and flickering fire light.

const FLAME_SHADER := preload("res://shaders/vfx/fire_flame.gdshader")
const SMOKE_SHADER := preload("res://shaders/vfx/fire_smoke.gdshader")
const FIRE := Color(1.0, 0.55, 0.12)
const HOT := Color(1.0, 0.9, 0.55)

static var _scorch: ImageTexture
static var _flame_mat: ShaderMaterial
static var _smoke_mat: ShaderMaterial


## Flame particles: born yellow-white, turning orange then red, rising and fading.
## size = particle size (m), rise = upward acceleration.
static func flames(parent: Node3D, amount: int, lifetime: float, size: float, rise: float) -> GPUParticles3D:
	var p := _particles(parent, amount, lifetime, false)
	var pm := p.process_material as ParticleProcessMaterial
	pm.gravity = Vector3(0, rise, 0)
	pm.color_ramp = _ramp([0.0, 0.1, 0.4, 0.75, 1.0], [Color(1, 0.7, 0.3, 0), Color(1, 0.6, 0.18, 1),
		Color(1, 0.36, 0.06, 0.9), Color(0.65, 0.1, 0.02, 0.5), Color(0.25, 0.04, 0.02, 0)])
	pm.scale_curve = _curve([Vector2(0, 0.6), Vector2(0.25, 1.0), Vector2(1, 0.35)])
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.angle_min = -15.0
	pm.angle_max = 15.0
	p.draw_pass_1 = _quad(size, _flame_material())
	return p


static func smoke(parent: Node3D, amount: int, lifetime: float, size: float, rise: float) -> GPUParticles3D:
	var p := _particles(parent, amount, lifetime, false)
	var pm := p.process_material as ParticleProcessMaterial
	pm.gravity = Vector3(0, rise, 0)
	# Lit orange by the fire at first, cooling to dark grey as it rises.
	pm.color_ramp = _ramp([0.0, 0.15, 0.45, 1.0], [Color(0.55, 0.28, 0.12, 0), Color(0.38, 0.22, 0.13, 0.85),
		Color(0.16, 0.14, 0.13, 0.7), Color(0.12, 0.115, 0.11, 0)])
	pm.scale_curve = _curve([Vector2(0, 0.5), Vector2(1, 1.6)])
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	p.draw_pass_1 = _quad(size, _smoke_material())
	return p


## Explosion at `at` (normal = surface it hit): fireball burst, smoke, shockwave, embers, flash.
static func explosion(parent: Node, at: Vector3, normal: Vector3, radius: float) -> void:
	var root := SpellFx.effect_root(parent, at + normal * 0.2, 4.0)
	var burst := flames(root, 70, 0.75, 1.3 * radius / 4.0, 2.0)
	burst.one_shot = true
	burst.explosiveness = 0.95
	var bm := burst.process_material as ParticleProcessMaterial
	bm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	bm.emission_sphere_radius = 0.4
	bm.direction = normal
	bm.spread = 180.0
	bm.initial_velocity_min = radius * 1.2
	bm.initial_velocity_max = radius * 2.6
	bm.damping_min = radius * 2.0
	bm.damping_max = radius * 3.0
	var puff := smoke(root, 26, 2.6, 1.8 * radius / 4.0, 1.2)
	puff.one_shot = true
	puff.explosiveness = 0.8
	var pm := puff.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius * 0.4
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.0
	var embers := SpellFx.particles(root, 40, 1.2, true, true, Vector2(0.04, 0.35), HOT, FIRE)
	var em := embers.process_material as ParticleProcessMaterial
	em.direction = normal
	em.spread = 75.0
	em.initial_velocity_min = 6.0
	em.initial_velocity_max = 14.0
	em.gravity = Vector3(0, -9.0, 0)
	em.damping_min = 0.5
	em.damping_max = 1.5
	var ring := SpellFx.ring(root, false, radius * 3.0, FIRE, HOT)
	ring.global_basis = Basis.looking_at(-normal, Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT)
	SpellFx.animate_ring(ring, 0.45, 0.0)
	var light := SpellFx.flash(root, at + normal * 0.8, FIRE, 10.0, radius * 5.0, 0.7)
	light.light_volumetric_fog_energy = 0.0


## Burnt ground under an explosion / fire pool (lasts `seconds`, then fades).
static func scorch(parent: Node, at: Vector3, radius: float, seconds: float) -> Decal:
	var d := Decal.new()
	d.size = Vector3(radius * 2.0, 3.0, radius * 2.0)
	d.texture_albedo = _scorch_texture()
	d.modulate = Color(1, 1, 1, 0.9)
	d.cull_mask = 1
	parent.add_child(d)
	d.global_position = at
	d.rotation.y = randf() * TAU
	var tw := d.create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(d, "modulate:a", 0.0, 3.0)
	tw.tween_callback(d.queue_free)
	return d


## Flickering fire light.
static func fire_light(parent: Node3D, energy: float, light_range: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = FIRE
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	l.light_volumetric_fog_energy = 0.0
	parent.add_child(l)
	return l


## Renders every effect once so the shaders compile during loading.
static func prewarm(vp: Node) -> void:
	explosion(vp, Vector3(0, 0, -8), Vector3.UP, 3.0)
	var root := SpellFx.effect_root(vp, Vector3(0, 0, -6), 0.6)
	flames(root, 8, 0.5, 0.5, 2.0)
	smoke(root, 4, 0.5, 0.5, 1.0)
	scorch(root, Vector3(0, 0, -6), 2.0, 0.1)
	var patch := FirePatch.spawn(vp, load("res://spells/fireball.tres"), Vector3(0, -0.5, -8), -99)
	patch.set("_t", 1.0)
	vp.get_tree().create_timer(0.6).timeout.connect(patch.queue_free)


static func _particles(parent: Node3D, amount: int, lifetime: float, local: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = local
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-15, -5, -15), Vector3(30, 25, 30))
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3.ZERO
	p.process_material = pm
	parent.add_child(p)
	p.emitting = true
	return p


static func _quad(size: float, mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	return q


static func _flame_material() -> ShaderMaterial:
	if _flame_mat == null:
		_flame_mat = ShaderMaterial.new()
		_flame_mat.shader = FLAME_SHADER
	return _flame_mat


static func _smoke_material() -> ShaderMaterial:
	if _smoke_mat == null:
		_smoke_mat = ShaderMaterial.new()
		_smoke_mat.shader = SMOKE_SHADER
	return _smoke_mat


static func _ramp(offsets: Array, colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for pt in points:
		c.add_point(pt)
	var t := CurveTexture.new()
	t.curve = c
	return t


## Soot-black blot with ragged edges and ember-red speckles near the middle (drawn once).
static func _scorch_texture() -> ImageTexture:
	if _scorch:
		return _scorch
	var n := FastNoiseLite.new()
	n.frequency = 0.04
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := Vector2(x, y) / (size - 1) * 2.0 - Vector2.ONE
			var r := u.length() + n.get_noise_2d(x, y) * 0.35
			var a := 1.0 - smoothstep(0.45, 0.95, r)
			var ember := smoothstep(0.55, 0.8, n.get_noise_2d(x * 3.1, y * 3.1) * 0.5 + 0.5) * (1.0 - smoothstep(0.0, 0.5, r))
			var c := Color(0.05, 0.035, 0.03).lerp(Color(0.45, 0.1, 0.02), ember * 0.6)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a * 0.92))
	_scorch = ImageTexture.create_from_image(img)
	return _scorch
