class_name ShieldDome
extends Shield
## Shield bubble: a hex-tile dome around where it was cast. Tiles rise out of the ground ring by
## ring, then it stands until it has absorbed `hp` damage (or its caster casts a new one). Hits
## ripple across it and flash the struck tiles; damage cracks more and more tiles (flickering
## when close to breaking); breaking shatters every tile outwards with a burst of shards and a
## flash; expiring lets the tiles sink away.
##
## Collision: a sphere (the lower half is underground). Rays starting inside it pass out
## (Godot ignores shapes containing the ray origin), so it blocks shots coming in from outside.

enum State { RISE, HOLD, BREAK, FADE }

const RISE_TIME := 0.7
const SHATTER_TIME := 1.1
const FADE_TIME := 0.6

var spell: ShieldBubbleSpell
var hp := 0.0
var _state := State.RISE
var _t := 0.0
var _opacity := 1.0
var _base_ring: MeshInstance3D
var _motes: GPUParticles3D


static func spawn(parent: Node, bubble: ShieldBubbleSpell, center: Vector3, owner: int, local: bool) -> ShieldDome:
	var dome := ShieldDome.new()
	dome.spell = bubble
	dome.owner_id = owner
	dome.kind = "bubble"
	dome.is_local = local
	dome.hp = bubble.hp
	parent.add_child(dome)
	dome.global_position = center
	return dome


## Raises a dome and shatters it in the loading viewport so the shader and particles compile.
static func prewarm(vp: Node) -> void:
	var dome := spawn(vp, load("res://spells/shield_bubble.tres"), Vector3(0, -1, -8), -99, false)
	dome.absorb(10.0, Vector3(0, 1, -5))
	vp.get_tree().create_timer(0.3).timeout.connect(dome.end.bind(true))


func _ready() -> void:
	_init_shield(HexShieldMesh.dome(), spell.color, spell.accent)
	mesh_instance.scale = Vector3.ONE * spell.radius
	material.set_shader_parameter("reveal", -0.1)
	material.set_shader_parameter("shatter_distance", 1.6 / spell.radius)
	material.set_shader_parameter("ripple_speed", 7.0 / spell.radius)
	material.set_shader_parameter("ripple_width", 0.45 / spell.radius)
	material.set_shader_parameter("hit_size", 3.0 * spell.radius * spell.radius)
	material.set_shader_parameter("tint", spell.tint)
	material.set_shader_parameter("dent", 0.25 / spell.radius)
	material.set_shader_parameter("wave_speed", 0.35)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = spell.radius
	shape.shape = sphere
	body.add_child(shape)
	_rise_fx()
	_ambient_fx()


## While it stands: a turning rune circle around its base and motes drifting up its surface.
func _ambient_fx() -> void:
	_base_ring = SpellFx.ring(self, true, spell.radius * 2.15, spell.color, spell.tint)
	_base_ring.position.y = 0.08
	_base_ring.set_instance_shader_parameter("progress", 0.15)
	_motes = SpellFx.particles(self, 90, 3.0, false, false, Vector2(0.14, 0.14), spell.accent, spell.color)
	_motes.visibility_aabb = AABB(Vector3.ONE * -spell.radius * 1.5, Vector3.ONE * spell.radius * 3.0)
	var pm := _motes.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = spell.radius
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9


func _outward(point: Vector3) -> Vector3:
	return (point - global_position).normalized()


func _rise_fx() -> void:
	var root := SpellFx.effect_root(get_parent(), global_position + Vector3.UP * 0.1, 2.0)
	var ring := SpellFx.ring(root, true, spell.radius * 2.4, spell.color, spell.accent)
	SpellFx.animate_ring(ring, 1.2, 0.8)
	var motes := SpellFx.particles(root, 60, 1.2, true, false, Vector2(0.12, 0.12), spell.color, spell.accent)
	var pm := motes.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = spell.radius
	pm.emission_ring_inner_radius = spell.radius * 0.9
	pm.emission_ring_height = 0.1
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	pm.damping_min = 2.0
	pm.damping_max = 3.0


func absorb(damage: float, point: Vector3) -> void:
	if _ended:
		return
	super.absorb(damage, point)
	hp -= damage
	material.set_shader_parameter("damage", clampf(1.0 - hp / spell.hp, 0.0, 1.0))
	if hp <= 0.0:
		end(true)


func end(broke: bool) -> void:
	if _ended:
		return
	super.end(broke)
	_state = State.BREAK if broke else State.FADE
	_t = 0.0
	if broke:
		_shatter_fx()


func _shatter_fx() -> void:
	var root := SpellFx.effect_root(get_parent(), global_position, 2.0)
	var shards := SpellFx.particles(root, 120, 1.0, true, true, Vector2(0.05, 0.5), spell.accent, spell.color)
	var pm := shards.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = spell.radius
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -6, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	shards.position.y = spell.radius * 0.4
	var wave := SpellFx.ring(root, true, spell.radius * 4.0, spell.accent, spell.color)
	wave.position.y = 0.1
	SpellFx.animate_ring(wave, 0.8, -0.5)
	SpellFx.flash(root, global_position + Vector3.UP * spell.radius * 0.6, spell.accent, 5.0, spell.radius * 5.0, 0.6)


## From inside (the caster's own view) the dome fades down so it doesn't wall in the view.
const INSIDE_OPACITY := 0.35


func _process(delta: float) -> void:
	_t += delta
	_update_hits(delta)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var inside := cam.global_position.distance_to(global_position) < spell.radius
		_opacity = move_toward(_opacity, INSIDE_OPACITY if inside else 1.0, delta * 3.0)
		material.set_shader_parameter("opacity", _opacity)
	if _base_ring:
		_base_ring.set_instance_shader_parameter("spin", _t * 0.15)
		var fade := 0.0 if _state == State.BREAK or _state == State.FADE else _opacity
		_base_ring.visible = fade > 0.05
		_motes.emitting = _state == State.RISE or _state == State.HOLD
	match _state:
		State.RISE:
			material.set_shader_parameter("reveal", lerpf(-0.1, 1.4, clampf(_t / RISE_TIME, 0.0, 1.0)))
			if _t >= RISE_TIME:
				_state = State.HOLD
				_t = 0.0
		State.HOLD:
			# Stands until it is broken, replaced by a new cast or its lifetime is up (decided by
			# the owner, who tells the others); a remote copy also goes when its caster leaves.
			if is_local and _t + RISE_TIME >= spell.lifetime:
				end(false)
			if not is_local and Net.is_online() and not Net.players.has(owner_id):
				end(false)
		State.BREAK:
			material.set_shader_parameter("shatter", clampf(_t / SHATTER_TIME, 0.0, 1.0))
			if _t >= SHATTER_TIME:
				queue_free()
		State.FADE:
			material.set_shader_parameter("reveal", lerpf(1.4, -0.1, clampf(_t / FADE_TIME, 0.0, 1.0)))
			if _t >= FADE_TIME:
				queue_free()
