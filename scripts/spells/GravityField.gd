class_name GravityField
extends Node3D
## A Gravity Field (GravityFieldSpell): an endless column (COLUMN_HEIGHT tall, it looks infinite)
## of crushing force – shaders/vfx/gravity_column.gdshader on two open cylinders, streaks raining
## down inside it, a turning rune circle and a low violet light on the ground, a shockwave when it
## forms. While active, the local player is dragged down if they are inside it at any height
## (Player.slam); a hard landing shakes the view.
##   preview = true: the caster's aiming ghost (faint column + circle, no gameplay).

const COLUMN_HEIGHT := 1500.0
const FADE_TIME := 0.6

var spell: GravityFieldSpell
var preview := false
var _age := 0.0
var _column: MeshInstance3D
var _inner: MeshInstance3D
var _ring: MeshInstance3D
var _rain: GPUParticles3D
var _light: OmniLight3D
var _slammed := false
var _caster: Node3D


static func spawn(parent: Node, field_spell: GravityFieldSpell, at: Vector3, is_preview: bool) -> GravityField:
	var g := GravityField.new()
	g.spell = field_spell
	g.preview = is_preview
	parent.add_child(g)
	g.global_position = at
	return g


static func make_preview(field_spell: GravityFieldSpell, caster: Node3D) -> GravityField:
	var g := GravityField.new()
	g.spell = field_spell
	g.preview = true
	g._caster = caster
	caster.get_tree().current_scene.add_child(g)
	g.global_position = field_spell.find_spot(caster)
	return g


static func prewarm(vp: Node) -> void:
	var g := spawn(vp, load("res://spells/gravity_field.tres"), Vector3(0, -1, -12), true)
	vp.get_tree().create_timer(0.5).timeout.connect(g.queue_free)


func _ready() -> void:
	var r := spell.radius
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/vfx/gravity_column.gdshader")
	mat.set_shader_parameter("color", spell.color)
	mat.set_shader_parameter("accent", spell.accent)
	_column = _cylinder(r, mat)
	var inner_mat := mat.duplicate() as ShaderMaterial
	inner_mat.set_shader_parameter("fall_speed", 34.0)
	inner_mat.set_shader_parameter("band_scale", 0.07)
	inner_mat.set_shader_parameter("energy", 0.9)
	_inner = _cylinder(r * 0.55, inner_mat)
	_ring = SpellFx.ring(self, true, r * 2.25, spell.color, spell.accent)
	_ring.position.y = 0.1
	_ring.set_instance_shader_parameter("progress", 1.0)
	if preview:
		return
	# Streaks pouring down the column.
	_rain = SpellFx.particles(self, 140, 1.4, false, true, Vector2(0.06, 2.2), spell.accent, spell.color)
	_rain.visibility_aabb = AABB(Vector3(-r, -5, -r), Vector3(r * 2.0, 70, r * 2.0))
	var pm := _rain.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(r * 0.8, 18.0, r * 0.8)
	pm.direction = Vector3.DOWN
	pm.spread = 2.0
	pm.initial_velocity_min = 30.0
	pm.initial_velocity_max = 48.0
	_rain.position.y = 30.0
	_rain.emitting = false
	_light = OmniLight3D.new()
	_light.light_color = spell.color
	_light.omni_range = r * 2.0
	_light.light_energy = 0.0
	_light.light_volumetric_fog_energy = 0.0
	_light.shadow_enabled = false
	_light.position.y = 1.5
	add_child(_light)


## Open cylinder of radius r whose mesh-local y runs from 0 (ground) up to COLUMN_HEIGHT.
func _cylinder(r: float, mat: ShaderMaterial) -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = COLUMN_HEIGHT
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 64
	cyl.rings = 1
	var arr := cyl.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y += COLUMN_HEIGHT * 0.5
	arr[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("strength", 0.0)
	add_child(mi)
	return mi


func is_active() -> bool:
	return not preview and _age >= spell.form_time and _age < spell.form_time + spell.duration


func _process(delta: float) -> void:
	if preview:
		if is_instance_valid(_caster):
			global_position = spell.find_spot(_caster)
		_age += delta
		_column.set_instance_shader_parameter("strength", 0.3)
		_inner.set_instance_shader_parameter("strength", 0.15)
		_ring.set_instance_shader_parameter("progress", 0.45)
		_ring.set_instance_shader_parameter("spin", _age * 0.5)
		return
	var was := _age
	_age += delta
	var form := clampf(_age / spell.form_time, 0.0, 1.0)
	var end := spell.form_time + spell.duration
	var fade := clampf((end + FADE_TIME - _age) / FADE_TIME, 0.0, 1.0)
	var s := form * form * fade
	_column.set_instance_shader_parameter("strength", s)
	_inner.set_instance_shader_parameter("strength", s * 0.8)
	_ring.set_instance_shader_parameter("progress", lerpf(1.0, 0.3, s))
	_ring.set_instance_shader_parameter("spin", _age * 0.6)
	_light.light_energy = 2.5 * s
	if was < spell.form_time and _age >= spell.form_time:
		_rain.emitting = true
		_shockwave()
	if was < end and _age >= end:
		_rain.emitting = false
	if _age > end + FADE_TIME + 1.5:
		queue_free()


func _shockwave() -> void:
	var root := SpellFx.effect_root(get_parent(), global_position + Vector3.UP * 0.3, 1.2)
	var ring := SpellFx.ring(root, false, spell.radius * 3.2, spell.color, spell.accent)
	ring.rotation.x = -PI * 0.5
	SpellFx.animate_ring(ring, 0.6, 0.0)
	var dust := SpellFx.particles(root, 40, 0.8, true, true, Vector2(0.06, 0.8), spell.accent, spell.color)
	var pm := dust.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = spell.radius
	pm.emission_ring_inner_radius = spell.radius * 0.8
	pm.emission_ring_height = 0.1
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.0
	SpellFx.flash(root, root.global_position + Vector3.UP, spell.color, 6.0, spell.radius * 3.0, 0.5)


func _physics_process(_delta: float) -> void:
	if not is_active():
		return
	var me := get_tree().current_scene.get_node_or_null("Player") as Node3D
	if me == null or not me.has_method("slam") or me.is_dead():
		return
	var p := me.global_position
	var inside := Vector2(p.x - global_position.x, p.z - global_position.z).length() < spell.radius \
		and p.y > global_position.y - 4.0
	var on_floor: bool = (me as CharacterBody3D).is_on_floor()
	if inside and not on_floor:
		me.slam(spell.slam_speed)
		_slammed = true
	elif _slammed and on_floor:
		# Slammed into the ground.
		_slammed = false
		if me.has_method("add_shake"):
			me.add_shake(0.7)
