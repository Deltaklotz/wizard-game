class_name ShieldWall
extends Shield
## Directional shield: a flat hex-tile shield held in front of the caster, facing where they
## look, a little further out the bigger it is. Raised by casting, held until cast is pressed
## again or the caster dies (Grimoire channel - the book can't flip, and the mouse wheel resizes
## the shield instead: ring 0 = a single hexagon, each ring adds a hexagon of tiles around it).
## Holding is free but blocks mana regeneration (it is a channel); blocked damage drains mana
## (more for a bigger shield), and when the mana can't pay for a blow the shield shatters.
## It comes back at the size it had when it was last lowered (last_rings).
##
## The owner sends {"kind": "shield_wall", "rings"} when it resizes; other players draw it in
## front of the caster's avatar from their view direction.

const FIRST_PERSON_OPACITY := 0.45
const COLLAPSE_TIME := 0.3
const SHATTER_TIME := 0.9

## The local player's last ward size, restored on the next raise (for this session).
static var last_rings := 0

var spell: ShieldWallSpell
var rings := 0
var _shown := -1.0
var _player: Node3D
var _avatar: RemotePlayer
var _collapse := -1.0
var _broke := false
var _motes: GPUParticles3D
var _shape: CylinderShape3D


static func raise_local(wall_spell: ShieldWallSpell, player: Node3D) -> ShieldWall:
	var w := _make(wall_spell, Net.my_id, true)
	w._player = player
	w.rings = clampi(last_rings, 0, wall_spell.max_rings)
	player.get_tree().current_scene.add_child(w)
	player.grimoire.begin_channel(w)
	# Deferred: the cast message (which makes the others raise theirs) is sent after cast()
	# returns, and this has to arrive after it.
	if w.rings > 0:
		w._send_rings.call_deferred()
	return w


func _send_rings() -> void:
	if not _ended:
		Net.send_event({"kind": "shield_wall", "rings": rings})


static func raise_remote(wall_spell: ShieldWallSpell, avatar: RemotePlayer) -> ShieldWall:
	var old := Shield.find(avatar.get_tree(), avatar.peer_id, "wall")
	if old:
		old.end(false)
	var w := _make(wall_spell, avatar.peer_id, false)
	w._avatar = avatar
	avatar.get_tree().current_scene.add_child(w)
	return w


static func _make(wall_spell: ShieldWallSpell, owner: int, local: bool) -> ShieldWall:
	var w := ShieldWall.new()
	w.spell = wall_spell
	w.owner_id = owner
	w.kind = "wall"
	w.is_local = local
	return w


func _ready() -> void:
	top_level = true
	_init_shield(HexShieldMesh.wall(spell.max_rings, spell.tile_radius), spell.color, spell.accent)
	material.set_shader_parameter("reveal", 0.0)
	material.set_shader_parameter("shatter_distance", 1.2)
	material.set_shader_parameter("ripple_speed", 4.0)
	material.set_shader_parameter("ripple_width", 0.3)
	material.set_shader_parameter("hit_size", 8.0)
	material.set_shader_parameter("tint", spell.tint)
	material.set_shader_parameter("dent", 0.12)
	material.set_shader_parameter("wave_speed", 0.6)
	material.set_shader_parameter("opacity", FIRST_PERSON_OPACITY if is_local else 1.0)
	var cs := CollisionShape3D.new()
	_shape = CylinderShape3D.new()
	_shape.height = 0.16
	cs.shape = _shape
	cs.rotation.x = PI * 0.5
	body.add_child(cs)
	_resize_collision()
	_follow()
	# Motes drifting off the front of the ward.
	_motes = SpellFx.particles(self, 40, 1.2, false, false, Vector2(0.06, 0.06), spell.accent, spell.color)
	var pm := _motes.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	_motes.local_coords = true
	var root := SpellFx.effect_root(get_parent(), global_position, 0.8)
	var ring := SpellFx.ring(root, false, spell.tile_radius * 4.0, spell.color, spell.accent)
	ring.global_basis = global_basis
	SpellFx.animate_ring(ring, 0.4, 0.0)


## Mouse wheel while the shield is up.
func scroll(direction: int) -> void:
	if _ended:
		return
	var r := clampi(rings + direction, 0, spell.max_rings)
	if r == rings:
		return
	rings = r
	last_rings = r
	_resize_collision()
	Net.send_event({"kind": "shield_wall", "rings": rings})


## Cast pressed again: lower the shield.
func cancel() -> void:
	end(false)


func absorb(damage: float, point: Vector3) -> void:
	if _ended:
		return
	super.absorb(damage, point)
	if is_local and is_instance_valid(_player):
		var cost := damage * spell.block_mana * (1.0 + spell.block_mana_per_ring * rings)
		if _player.mana < cost:
			_player.spend_mana(_player.mana)
			end(true)
		else:
			_player.spend_mana(cost)


func end(broke: bool) -> void:
	if _ended:
		return
	super.end(broke)
	if is_local and is_instance_valid(_player):
		_player.grimoire.end_channel(self)
	_collapse = 0.0
	_broke = broke
	if _motes:
		_motes.emitting = false
	if broke:
		var root := SpellFx.effect_root(get_parent(), global_position, 1.5)
		var shards := SpellFx.particles(root, 50, 0.8, true, true, Vector2(0.04, 0.4), spell.accent, spell.color)
		var pm := shards.process_material as ParticleProcessMaterial
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = HexShieldMesh.wall_extent(rings, spell.tile_radius) * 0.7
		pm.direction = -global_basis.z
		pm.spread = 70.0
		pm.initial_velocity_min = 2.0
		pm.initial_velocity_max = 6.0
		pm.gravity = Vector3(0, -6, 0)


func _resize_collision() -> void:
	if _shape:
		_shape.radius = HexShieldMesh.wall_extent(rings, spell.tile_radius) * 0.95


func _process(delta: float) -> void:
	_update_hits(delta)
	if _collapse >= 0.0:
		_follow()
		_collapse += delta
		var span := SHATTER_TIME if _broke else COLLAPSE_TIME
		var u := clampf(_collapse / span, 0.0, 1.0)
		if _broke:
			material.set_shader_parameter("shatter", u)
		else:
			material.set_shader_parameter("reveal", lerpf(_shown + 1.0, -0.3, u))
		if _collapse >= span:
			queue_free()
		return
	if is_local:
		if not is_instance_valid(_player) or _player.is_dead():
			end(false)
			return
	elif not is_instance_valid(_avatar) or _avatar.is_dead():
		end(false)
		return
	_shown = move_toward(_shown, float(rings), delta * 8.0)
	material.set_shader_parameter("reveal", _shown + 1.0)
	material.set_shader_parameter("order_max", maxf(_shown, 0.0) + 0.5)
	var extent := HexShieldMesh.wall_extent(maxi(roundi(_shown), 0), spell.tile_radius)
	(_motes.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(extent * 0.75, extent * 0.75, 0.05)
	_motes.amount_ratio = clampf(0.15 + 0.85 * maxf(_shown, 0.0) / spell.max_rings, 0.0, 1.0)
	_follow()


## In front of the caster's eyes, facing along their view.
func _follow() -> void:
	var eye: Vector3
	var dir: Vector3
	if is_local:
		if not is_instance_valid(_player):
			return
		var cam: Camera3D = _player.camera
		eye = cam.global_position
		dir = -cam.global_basis.z
	else:
		if not is_instance_valid(_avatar):
			return
		eye = _avatar.global_position + Vector3.UP * RemotePlayer.EYE_HEIGHT
		dir = _avatar.get_look_direction()
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.BACK
	var dist := spell.distance + spell.distance_per_ring * maxf(_shown, 0.0)
	global_transform = Transform3D(Basis.looking_at(dir, up), eye + dir * dist)


func _outward(_point: Vector3) -> Vector3:
	return -global_basis.z


func _on_net_event(id: int, ev: Dictionary) -> void:
	super._on_net_event(id, ev)
	if str(ev.get("kind", "")) == "shield_wall" and id == owner_id and not is_local:
		rings = clampi(int(ev.get("rings", 0)), 0, spell.max_rings)
		_resize_collision()
