class_name SwordWall
extends Node3D
## One giant sword of the Sword Wall spell (local and remote casts alike): falls from the sky
## with a golden trail, buries itself point first (impact rune ring, sparks, flash, a shake for
## players nearby, a short vibration), stands as a wall with collision for the spell's lifetime
## and then dissolves into glowing motes.
##
## Node frame: origin on the ground, +Z = facing (away from the caster; the blade's faces look
## along ±Z), the blade's width along X. The sword mesh sits VISIBLE_BLADE above the origin.

enum Phase { FALL, STAND, DISSOLVE }

const FALL_TIME := 0.9
const FALL_HEIGHT := 140.0
const DISSOLVE_TIME := 1.8
## Blade height above the ground (the rest is buried).
const VISIBLE_BLADE := 3.8
## Collision half thickness of the blade.
const HALF_DEPTH := 0.6
const WOBBLE_TIME := 1.0
## Players within this distance of the impact get a camera shake.
const SHAKE_RANGE := 30.0
const GHOST_SHADER := preload("res://shaders/vfx/sword_ghost.gdshader")
const COLOR := Color(1.0, 0.8, 0.4)
const ACCENT := Color(1.0, 0.95, 0.75)

var _spell: SwordSpell
var _caster_id := -1
var _caster: Node
var _phase := Phase.FALL
var _t := 0.0
var _ground := Vector3.ZERO
var _pivot: Node3D
var _sword: MeshInstance3D
var _body: StaticBody3D
var _trail: GPUParticles3D
var _light: OmniLight3D


## caster: the local caster (hit markers), or null for other players' swords.
static func spawn(parent: Node, spell: SwordSpell, point: Vector3, facing: Vector3, caster_id: int,
		caster: Node) -> SwordWall:
	var wall := SwordWall.new()
	wall._spell = spell
	wall._caster_id = caster_id
	wall._caster = caster
	wall._ground = point
	parent.add_child(wall)
	wall.global_transform = Transform3D(ground_basis(facing), point + Vector3.UP * FALL_HEIGHT)
	return wall


static func ground_basis(facing: Vector3) -> Basis:
	var z := Vector3(facing.x, 0.0, facing.z).normalized()
	return Basis(Vector3.UP.cross(z), Vector3.UP, z)


## The sword mesh, placed in the wall frame (ghost = preview look).
static func make_sword(ghost: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = SwordModel.mesh()
	mi.position.y = VISIBLE_BLADE
	if ghost:
		var mat := ShaderMaterial.new()
		mat.shader = GHOST_SHADER
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Draws the sword, trail and impact once so their shaders compile during loading.
static func prewarm(vp: Node) -> void:
	var ghost := make_sword(true)
	vp.add_child(ghost)
	ghost.position = Vector3(0, -2, -30)
	vp.get_tree().create_timer(0.5).timeout.connect(ghost.queue_free)
	var wall := SwordWall.new()
	wall._spell = SwordSpell.new()
	vp.add_child(wall)
	wall._ground = Vector3(0, -3, -30)
	wall.global_transform = Transform3D(Basis.IDENTITY, wall._ground + Vector3.UP * 3.0)
	wall._t = FALL_TIME * 0.95
	wall._spell.lifetime = 0.6
	wall._prewarm = true


var _prewarm := false


func _ready() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	_sword = make_sword(false)
	_pivot.add_child(_sword)
	_trail = SpellFx.particles(self, 140, 0.6, false, true, Vector2(0.12, 1.6), COLOR, ACCENT)
	_trail.position.y = VISIBLE_BLADE - 4.0
	_trail.visibility_aabb = AABB(Vector3(-20, -40, -20), Vector3(40, 200, 40))
	var pm := _trail.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(SwordModel.HALF_WIDTH, 6.0, 0.3)
	pm.direction = Vector3.UP
	pm.spread = 8.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 6.0
	_light = OmniLight3D.new()
	_light.light_volumetric_fog_energy = 0.0
	_light.light_color = COLOR
	_light.omni_range = 14.0
	_light.light_energy = 2.0
	_light.position.y = VISIBLE_BLADE
	add_child(_light)
	# Sparkles around the collar gem, as in the reference art.
	var sparkle := SpellFx.particles(_pivot, 8, 1.2, false, false, Vector2(0.18, 0.18), Color(0.7, 1.0, 0.95), ACCENT)
	sparkle.position = Vector3(0, VISIBLE_BLADE + 0.75, 0)
	var sm := sparkle.process_material as ParticleProcessMaterial
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sm.emission_sphere_radius = 0.9
	sparkle.local_coords = true
	_landing_marker()


## Everyone sees where it will strike while it falls: a rune circle and its footprint
## flaring up on the ground.
func _landing_marker() -> void:
	var root := SpellFx.effect_root(get_parent(), _ground + Vector3.UP * 0.1, FALL_TIME + 0.2)
	root.global_basis = global_basis
	var ring := SpellFx.ring(root, true, 9.0, COLOR, ACCENT)
	SpellFx.animate_ring(ring, FALL_TIME + 0.2, 0.8)
	var decal := Decal.new()
	decal.size = Vector3(SwordModel.HALF_WIDTH * 2.0 + 1.6, 8.0, 2.4)
	decal.texture_albedo = SwordPreview.footprint_texture()
	decal.texture_emission = decal.texture_albedo
	decal.emission_energy = 3.0
	decal.modulate = COLOR
	root.add_child(decal)
	decal.create_tween().tween_property(decal, "emission_energy", 8.0, FALL_TIME)


func _process(delta: float) -> void:
	_t += delta
	match _phase:
		Phase.FALL:
			var u := clampf(_t / FALL_TIME, 0.0, 1.0)
			global_position = _ground + Vector3.UP * FALL_HEIGHT * (1.0 - u * u)
			if u >= 1.0:
				_impact()
		Phase.STAND:
			# A heavy vibration after striking the ground.
			var w := 0.04 * exp(-_t * 5.0) * sin(_t * 32.0) if _t < WOBBLE_TIME else 0.0
			_pivot.rotation = Vector3(w, 0.0, w * 0.4)
			_sword.set_instance_shader_parameter("glow", exp(-_t * 1.5))
			_light.light_energy = 3.0 * exp(-_t * 3.0)
			if _t >= _spell.lifetime:
				_start_dissolve()
		Phase.DISSOLVE:
			var d := clampf(_t / DISSOLVE_TIME, 0.0, 1.0)
			_sword.set_instance_shader_parameter("dissolve", d)
			if d >= 1.0:
				queue_free()


func _impact() -> void:
	_phase = Phase.STAND
	_t = 0.0
	global_position = _ground
	_trail.emitting = false
	_build_collision()
	_impact_fx()
	if not _prewarm:
		_strike()
		_shatter_domes()


func _build_collision() -> void:
	_body = StaticBody3D.new()
	_body.add_to_group("sword_wall")
	add_child(_body)
	var blade := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SwordModel.HALF_WIDTH * 2.04, VISIBLE_BLADE + 2.0, HALF_DEPTH * 2.0)
	blade.shape = box
	blade.position.y = (VISIBLE_BLADE - 2.0) * 0.5
	_body.add_child(blade)
	var guard := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(8.6, 1.4, 1.1)
	guard.shape = gbox
	guard.position.y = VISIBLE_BLADE + 0.4
	_body.add_child(guard)
	var hilt := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.6
	cyl.height = SwordModel.HILT_TOP - 1.0
	hilt.shape = cyl
	hilt.position.y = VISIBLE_BLADE + 1.0 + cyl.height * 0.5
	_body.add_child(hilt)


func _impact_fx() -> void:
	var root := SpellFx.effect_root(get_parent(), _ground + Vector3.UP * 0.15, 3.0)
	root.global_basis = global_basis
	var runes := SpellFx.ring(root, true, 16.0, COLOR, ACCENT)
	SpellFx.animate_ring(runes, 1.6, 1.2)
	var wave := SpellFx.ring(root, true, 26.0, ACCENT, COLOR)
	wave.position.y = 0.05
	SpellFx.animate_ring(wave, 0.7, -0.6)
	var sparks := SpellFx.particles(root, 70, 0.8, true, true, Vector2(0.06, 0.7), COLOR, ACCENT)
	var pm := sparks.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(SwordModel.HALF_WIDTH, 0.2, 0.6)
	pm.direction = Vector3.UP
	pm.spread = 55.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 15.0
	pm.gravity = Vector3(0, -14, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	var motes := SpellFx.particles(root, 50, 1.6, true, false, Vector2(0.3, 0.3), COLOR, Color(0.8, 0.65, 0.45))
	var mm := motes.process_material as ParticleProcessMaterial
	mm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mm.emission_box_extents = Vector3(SwordModel.HALF_WIDTH + 1.0, 0.3, 1.5)
	mm.direction = Vector3.UP
	mm.spread = 80.0
	mm.initial_velocity_min = 1.0
	mm.initial_velocity_max = 4.0
	mm.damping_min = 2.0
	mm.damping_max = 3.0
	SpellFx.flash(root, _ground + Vector3.UP * 3.0, COLOR, 6.0, 26.0, 0.8)


## Damage and shove for the local player if the sword landed on them (other players handle
## themselves), hit markers for the local caster, and a shake for anyone close.
func _strike() -> void:
	var inv := global_basis.inverse()
	var me := get_tree().current_scene.get_node_or_null("Player") as Node3D
	if me and me.has_method("take_damage") and not me.is_dead():
		var l := inv * (me.global_position - _ground)
		if _inside(l):
			var side := signf(l.z) if absf(l.z) > 0.01 else -1.0
			me.global_position += global_basis.z * side * (HALF_DEPTH + 0.6 - absf(l.z))
			if me.has_method("add_knockback"):
				me.add_knockback(global_basis.z * side * 7.0 + Vector3.UP * 4.0)
			if _caster == null:
				me.take_damage(_spell.damage, _caster_id)
		var dist := me.global_position.distance_to(_ground)
		if dist < SHAKE_RANGE and me.has_method("add_shake"):
			me.add_shake(1.0 - dist / SHAKE_RANGE)
	if _caster and _caster.has_method("confirm_hit"):
		for node in get_tree().get_nodes_in_group("remote_player"):
			var a := node as RemotePlayer
			if a and a.visible and not a.is_dead() and _inside(inv * (a.global_position + Vector3.UP * 0.9 - _ground)):
				_caster.confirm_hit(a.peer_id)


## A sword landing on an Aegis Dome shatters it outright. Every client runs this for every
## sword (same landing point everywhere), so the dome breaks for all without extra messages.
func _shatter_domes() -> void:
	var inv := global_basis.inverse()
	for node in get_tree().get_nodes_in_group("shield"):
		var dome := node as ShieldDome
		if dome == null or dome._ended:
			continue
		# Closest point of the blade's footprint to the dome's centre (both on the ground).
		var l := inv * (dome.global_position - _ground)
		var closest := Vector2(clampf(l.x, -SwordModel.HALF_WIDTH, SwordModel.HALF_WIDTH), clampf(l.z, -HALF_DEPTH, HALF_DEPTH))
		if Vector2(l.x, l.z).distance_to(closest) < dome.spell.radius:
			dome.end(true)


static func _inside(l: Vector3) -> bool:
	return absf(l.x) < SwordModel.HALF_WIDTH + 0.45 and absf(l.z) < HALF_DEPTH + 0.45 \
		and l.y > -2.0 and l.y < VISIBLE_BLADE + 1.5


func _start_dissolve() -> void:
	_phase = Phase.DISSOLVE
	_t = 0.0
	if _body:
		_body.queue_free()
		_body = null
	var motes := SpellFx.particles(self, 90, 1.4, false, false, Vector2(0.2, 0.2), COLOR, ACCENT)
	motes.position.y = VISIBLE_BLADE + 0.5
	var pm := motes.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(SwordModel.HALF_WIDTH + 0.5, 4.0, 0.4)
	pm.direction = Vector3.UP
	pm.spread = 30.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 2.0
	# Bound to the emitter itself, so the connection goes away if it is freed first.
	get_tree().create_timer(DISSOLVE_TIME * 0.8).timeout.connect(motes.set.bind("emitting", false))
