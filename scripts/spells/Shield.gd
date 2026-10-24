class_name Shield
extends Node3D
## Base of the hex shields (ShieldDome, ShieldWall): a hex-tile mesh with
## shaders/vfx/hex_shield.gdshader, a StaticBody3D on its own physics layer, hit ripples, and
## the network plumbing shared by both.
##
## Blocking: the body is on LAYER (players don't collide with it – their mask is layer 1 only –
## but every spell trace does). Shots decide shield hits like player hits: the shooter calls
## report_hit(), which applies it locally and sends {"kind": "shield_hit", "owner", "shield",
## "damage", "p"}; every other client applies it to its copy. The owner ends its shield with
## {"kind": "shield_end", "shield", "broke"}. A player's own Hex Ward lets their own shots
## through (traces exclude excludes_for(owner)); a dome blocks everyone's shots, its owner's
## too – also from inside (dome_exit(), since physics rays ignore a shape they start in).
## Aiming rays pass all own shields (excludes_for(owner, true)).

const LAYER := 1 << 4
const SHADER := preload("res://shaders/vfx/hex_shield.gdshader")
const MAX_HITS := 6
const HIT_LIFE := 3.0

## Peer id of the caster (-1 offline), and which of their shields this is ("bubble" / "wall").
var owner_id := -1
var kind := ""
## Cast by the local player (authoritative for ending it).
var is_local := false

var body: StaticBody3D
var mesh_instance: MeshInstance3D
var material: ShaderMaterial
var _hit_points: Array[Vector3] = []
var _hit_ages: Array[float] = []
var _ended := false
var _color := Color.WHITE
var _accent := Color.WHITE
var _last_fx := 0


## The shield a physics collider belongs to (or null).
static func from_collider(collider: Object) -> Shield:
	if collider and is_instance_valid(collider) and collider.has_meta("shield"):
		var s: Variant = collider.get_meta("shield")
		if is_instance_valid(s):
			return s as Shield
	return null


## Bodies of the shields `peer` owns that their own shots pass through: the Hex Ward always,
## domes only with `with_domes` (for aiming rays – shots are stopped by every dome).
static func excludes_for(tree: SceneTree, peer: int, with_domes := false) -> Array[RID]:
	var out: Array[RID] = []
	for node in tree.get_nodes_in_group("shield"):
		var s := node as Shield
		if s and s.owner_id == peer and s.body and (with_domes or s.kind != "bubble"):
			out.append(s.body.get_rid())
	return out


## Where the segment a -> b leaves a dome that `a` lies inside (shots fired from within a dome),
## nearest first: {"point", "normal" (facing back inwards), "shield", "dist"}, or {}.
static func dome_exit(tree: SceneTree, a: Vector3, b: Vector3) -> Dictionary:
	var best := {}
	var seg := b - a
	var length := seg.length()
	if length < 0.0001:
		return best
	var dir := seg / length
	for node in tree.get_nodes_in_group("shield"):
		var s := node as Shield
		if s == null or s.kind != "bubble" or s.body == null or s._ended:
			continue
		var radius: float = s.get("spell").radius
		var oc := a - s.global_position
		var c := oc.length_squared() - radius * radius
		if c >= 0.0:
			continue
		var bq := oc.dot(dir)
		var t := -bq + sqrt(bq * bq - c)
		if t <= length and (best.is_empty() or t < best.dist):
			var p := a + dir * t
			best = {"point": p, "normal": (s.global_position - p).normalized(), "shield": s, "dist": t}
	return best


## The local player's shield of `shield_kind`, if one is up.
static func find(tree: SceneTree, peer: int, shield_kind: String) -> Shield:
	for node in tree.get_nodes_in_group("shield"):
		var s := node as Shield
		if s and s.owner_id == peer and s.kind == shield_kind and not s._ended:
			return s
	return null


func _init_shield(mesh: Mesh, color: Color, accent: Color) -> void:
	add_to_group("shield")
	_color = color
	_accent = accent
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("color", color)
	material.set_shader_parameter("accent", accent)
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	body = StaticBody3D.new()
	body.collision_layer = LAYER
	body.collision_mask = 0
	body.set_meta("shield", self)
	add_child(body)
	Net.event_received.connect(_on_net_event)
	_update_hits(0.0)


## A shot (decided by the local shooter) hit this shield.
func report_hit(damage: float, point: Vector3) -> void:
	Net.send_event({"kind": "shield_hit", "owner": owner_id, "shield": kind, "damage": damage,
		"p": Net._vec(point)})
	absorb(damage, point)


## Apply a hit: ripple here; subclasses add their consequences.
func absorb(_damage: float, point: Vector3) -> void:
	if _ended:
		return
	# Sparks off the surface (at most every 50 ms under rapid fire).
	var now := Time.get_ticks_msec()
	if now - _last_fx > 50:
		_last_fx = now
		_hit_fx(point)
	_hit_points.push_front(mesh_instance.to_local(point))
	_hit_ages.push_front(0.0)
	if _hit_points.size() > MAX_HITS:
		_hit_points.resize(MAX_HITS)
		_hit_ages.resize(MAX_HITS)


## Direction the surface faces at `point` (towards attackers).
func _outward(_point: Vector3) -> Vector3:
	return Vector3.UP


func _hit_fx(point: Vector3) -> void:
	var n := _outward(point)
	var root := SpellFx.effect_root(get_parent(), point + n * 0.05, 0.9)
	var sparks := SpellFx.particles(root, 14, 0.45, true, true, Vector2(0.035, 0.35), _accent, _color)
	var pm := sparks.process_material as ParticleProcessMaterial
	pm.direction = n
	pm.spread = 65.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0, -5, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	var ring := SpellFx.ring(root, false, 1.4, _color, _accent)
	ring.global_basis = Basis.looking_at(-n, Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT)
	SpellFx.animate_ring(ring, 0.35, 0.0)


## Ends the shield (broke = shattered). Subclasses animate; the owner tells everyone.
func end(broke: bool) -> void:
	if _ended:
		return
	_ended = true
	if body:
		body.queue_free()
		body = null
	if is_local:
		Net.send_event({"kind": "shield_end", "shield": kind, "broke": broke})


func _update_hits(delta: float) -> void:
	var arr := PackedVector4Array()
	for i in MAX_HITS:
		if i < _hit_points.size():
			_hit_ages[i] += delta
			var p := _hit_points[i]
			arr.append(Vector4(p.x, p.y, p.z, _hit_ages[i]))
		else:
			arr.append(Vector4(0, 0, 0, 99.0))
	material.set_shader_parameter("hits", arr)


func _on_net_event(id: int, ev: Dictionary) -> void:
	match str(ev.get("kind", "")):
		"shield_hit":
			if int(ev.get("owner", -2)) == owner_id and str(ev.get("shield", "")) == kind:
				absorb(float(ev.get("damage", 0.0)), Net._to_vec(ev.get("p")))
		"shield_end":
			if id == owner_id and not is_local and str(ev.get("shield", "")) == kind:
				end(bool(ev.get("broke", false)))
