class_name MoneyRain
extends Node3D
## The Money Rain (MoneyRainSpell) at one spot: a sunlit cloud (smoke_cloud.gdshader puffs, white
## and gold), a shaft of light down to the ground (godray.gdshader on an open cone + a warm spot
## light), banknotes fluttering down out of the cloud (money.gdshader), a golden rune circle
## on the ground and sparkles rising in the light. Heals the local player while they stand in it
## (every client does the same for its own player).

const GOLD := Color(1.0, 0.82, 0.38)
const GLOW := Color(1.0, 0.93, 0.7)
const FADE_TIME := 1.5
const CLOUD_SHADER := preload("res://shaders/vfx/smoke_cloud.gdshader")
const RAY_SHADER := preload("res://shaders/vfx/godray.gdshader")
const MONEY_SHADER := preload("res://shaders/vfx/money.gdshader")

var spell: MoneyRainSpell
var _age := 0.0
var _ray: MeshInstance3D
var _light: SpotLight3D
var _ring: MeshInstance3D
var _emitters: Array[GPUParticles3D] = []
var _ended := false


static func spawn(parent: Node, rain_spell: MoneyRainSpell, at: Vector3) -> MoneyRain:
	var m := MoneyRain.new()
	m.spell = rain_spell
	parent.add_child(m)
	m.global_position = at
	return m


static func prewarm(vp: Node) -> void:
	var m := spawn(vp, load("res://spells/money_rain.tres"), Vector3(0, -2, -8))
	vp.get_tree().create_timer(0.6).timeout.connect(m.queue_free)


func _ready() -> void:
	var h := spell.height
	var r := spell.radius
	# The cloud: big lit puffs churning slowly, already full when it appears (preprocess).
	var cloud := _puffs(40, 3.5, 4.2, Color(1, 1, 1))
	cloud.position.y = h + 0.6
	cloud.preprocess = 3.0
	var cm := cloud.process_material as ParticleProcessMaterial
	cm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	cm.emission_box_extents = Vector3(r * 0.85, 0.5, r * 0.85)
	# Golden underside glow (lit by the shaft).
	var under := _puffs(14, 3.0, 2.6, Color(1.25, 1.0, 0.65))
	under.position.y = h - 0.1
	under.preprocess = 3.0
	var um := under.process_material as ParticleProcessMaterial
	um.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	um.emission_box_extents = Vector3(r * 0.6, 0.2, r * 0.6)
	# The shaft of light: an open cone from the cloud down to the healing circle.
	_ray = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = r * 0.75
	cone.bottom_radius = r
	cone.height = h
	cone.cap_top = false
	cone.cap_bottom = false
	cone.radial_segments = 48
	cone.rings = 1
	var mat := ShaderMaterial.new()
	mat.shader = RAY_SHADER
	mat.set_shader_parameter("height", h)
	mat.set_shader_parameter("color", GLOW)
	cone.material = mat
	_ray.mesh = cone
	_ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ray.position.y = h * 0.5
	add_child(_ray)
	# An inner, brighter core of the shaft.
	var core := MeshInstance3D.new()
	var inner := cone.duplicate() as CylinderMesh
	inner.top_radius = r * 0.35
	inner.bottom_radius = r * 0.55
	core.mesh = inner
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ray.add_child(core)
	_light = SpotLight3D.new()
	_light.light_color = GLOW
	_light.light_energy = 0.0
	_light.spot_range = h + 4.0
	_light.spot_angle = rad_to_deg(atan(r * 1.15 / h))
	_light.light_volumetric_fog_energy = 0.0
	_light.shadow_enabled = false
	_light.position.y = h
	_light.rotation.x = -PI * 0.5
	add_child(_light)
	# Money: banknotes fluttering down.
	_emitters.append(_money(40, Vector2(0.62, 0.29), 3.2))
	# Golden rune circle on the ground and sparkles rising in the light.
	_ring = SpellFx.ring(self, true, r * 2.3, GOLD, GLOW)
	_ring.position.y = 0.08
	_ring.set_instance_shader_parameter("progress", 0.0)
	var sparkles := SpellFx.particles(self, 40, 1.8, false, false, Vector2(0.09, 0.09), GLOW, Color(0.6, 1.0, 0.55))
	var sm := sparkles.process_material as ParticleProcessMaterial
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	sm.emission_ring_axis = Vector3.UP
	sm.emission_ring_radius = r * 0.8
	sm.emission_ring_inner_radius = 0.0
	sm.emission_ring_height = 0.2
	sm.direction = Vector3.UP
	sm.spread = 10.0
	sm.initial_velocity_min = 0.6
	sm.initial_velocity_max = 1.6
	sparkles.position.y = 0.2
	_emitters.append(sparkles)
	_emitters.append(cloud)
	_emitters.append(under)
	# Arrival: a burst of gold.
	var burst := SpellFx.particles(self, 40, 1.0, true, true, Vector2(0.05, 0.5), GLOW, GOLD)
	var bm := burst.process_material as ParticleProcessMaterial
	bm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	bm.emission_sphere_radius = r * 0.5
	bm.direction = Vector3.UP
	bm.spread = 180.0
	bm.initial_velocity_min = 2.0
	bm.initial_velocity_max = 5.0
	bm.damping_min = 2.0
	bm.damping_max = 4.0
	burst.position.y = h


func _puffs(amount: int, lifetime: float, size: float, tint: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-12, -6, -12), Vector3(24, 12, 24))
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3.ZERO
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.3
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.color = tint
	pm.color_ramp = _ramp([0.0, 0.25, 0.75, 1.0], [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := ShaderMaterial.new()
	mat.shader = CLOUD_SHADER
	mat.set_shader_parameter("tint", Color(1.0, 0.99, 0.95))
	mat.set_shader_parameter("shadow_tint", Color(0.85, 0.66, 0.42))
	mat.set_shader_parameter("density", 0.85)
	quad.material = mat
	p.draw_pass_1 = quad
	add_child(p)
	return p


func _money(amount: int, size: Vector2, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-8, -spell.height - 2, -8), Vector3(16, spell.height + 4, 16))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(spell.radius * 0.7, 0.2, spell.radius * 0.7)
	pm.direction = Vector3.DOWN
	pm.spread = 20.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0, -2.2, 0)
	pm.particle_flag_rotate_y = true
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -180.0
	pm.angular_velocity_max = 180.0
	pm.scale_min = 0.8
	pm.scale_max = 1.2
	# Fade out over the last moments (reaching the ground).
	pm.color_ramp = _ramp([0.0, 0.08, 0.85, 1.0], [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = size
	var mat := ShaderMaterial.new()
	mat.shader = MONEY_SHADER
	quad.material = mat
	p.draw_pass_1 = quad
	p.position.y = spell.height - 0.3
	add_child(p)
	return p


static func _ramp(offsets: Array, colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _process(delta: float) -> void:
	_age += delta
	var appear := clampf(_age / 0.8, 0.0, 1.0)
	var fade := clampf((spell.duration + FADE_TIME - _age) / FADE_TIME, 0.0, 1.0)
	var s := appear * fade
	_ray.set_instance_shader_parameter("strength", s)
	(_ray.get_child(0) as MeshInstance3D).set_instance_shader_parameter("strength", s * 0.8)
	_light.light_energy = 2.2 * s
	_ring.set_instance_shader_parameter("progress", lerpf(1.0, 0.25, s))
	_ring.set_instance_shader_parameter("spin", _age * 0.15)
	if not _ended and _age >= spell.duration:
		_ended = true
		for e in _emitters:
			e.emitting = false
	if _age > spell.duration + FADE_TIME + 3.6:
		queue_free()


func _physics_process(delta: float) -> void:
	if _age >= spell.duration or _age < 0.5:
		return
	var me := get_tree().current_scene.get_node_or_null("Player") as Node3D
	if me == null or not me.has_method("heal") or me.is_dead():
		return
	var feet: Vector3 = me.global_position - Vector3.UP * float(me.get("FOOT_OFFSET"))
	var flat := Vector2(feet.x - global_position.x, feet.z - global_position.z).length()
	if flat < spell.radius and feet.y > global_position.y - 3.0 and feet.y < global_position.y + spell.height:
		me.heal(spell.heal_rate * delta)
