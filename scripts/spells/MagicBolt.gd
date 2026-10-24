class_name MagicBolt
extends Node3D
## One orb of the arcane minigun: a camera-facing orb with a swirling two-tone core and a
## streak tail along its flight (one mesh, shaders/vfx/magic_bolt.gdshader). Flies straight,
## traced every physics step against the world and player capsules; on impact it bursts into
## sparks, a small ring and motes.
##   Local shots (shooter set): a hit on another player sends the damage event + hit marker.
##   Remote replays (shooter null): visual only; stop at the world, the local player's body
##   (physics ray) and other avatars except the shooter's own.

const SHADER := preload("res://shaders/vfx/magic_bolt.gdshader")
## Orb size and tail length at full size (metres).
const SIZE := 0.34
const TAIL := 3.0
## Distance over which the orb grows to full size after leaving the muzzle (keeps it from
## filling the shooter's view).
const GROW := 2.5
const HIT_RADIUS := 0.45
const CAPSULE_LOW := 0.3
const CAPSULE_HIGH := 1.8

static var _mesh: ArrayMesh
static var _materials := {}

var _spell: MinigunSpell
var _dir := Vector3.FORWARD
var _travel := 0.0
var _shooter: CollisionObject3D
var _skip: Node3D
var _mi: MeshInstance3D


## shooter: the local caster (deals damage), or null for a replay; skip: avatar to ignore.
static func fire(parent: Node, spell: MinigunSpell, from: Vector3, dir: Vector3, shooter: Node3D,
		skip: Node3D) -> void:
	var bolt := MagicBolt.new()
	bolt._spell = spell
	bolt._dir = dir
	bolt._shooter = shooter as CollisionObject3D
	bolt._skip = skip
	parent.add_child(bolt)
	bolt.global_position = from


## Burst at a remote caster's hand for each replayed shot.
static func muzzle_flash(parent: Node, spell: MinigunSpell, at: Vector3, dir: Vector3) -> void:
	var root := SpellFx.effect_root(parent, at, 0.4)
	var p := SpellFx.particles(root, 6, 0.2, true, true, Vector2(0.03, 0.3), spell.accent, spell.color)
	var pm := p.process_material as ParticleProcessMaterial
	pm.direction = dir
	pm.spread = 18.0
	pm.initial_velocity_min = 8.0
	pm.initial_velocity_max = 14.0
	var ring := SpellFx.ring(root, false, 0.6, spell.color, spell.accent)
	ring.global_basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
	SpellFx.animate_ring(ring, 0.18, 0.0)


static func prewarm(vp: Node) -> void:
	var spell := load("res://spells/minigun.tres") as MinigunSpell
	fire(vp, spell, Vector3(0, 1, -2), Vector3(0, 0, -1), null, null)
	impact(vp, spell, Vector3(0, 1, -6), Vector3.BACK, true)
	muzzle_flash(vp, spell, Vector3(0, 1, -3), Vector3(0, 0, -1))


func _ready() -> void:
	top_level = true
	_mi = MeshInstance3D.new()
	_mi.mesh = _bolt_mesh()
	_mi.material_override = _material(_spell)
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.custom_aabb = AABB(Vector3(-TAIL, -TAIL, -TAIL), Vector3(TAIL, TAIL, TAIL) * 2.0)
	add_child(_mi)
	_mi.set_instance_shader_parameter("dir", _dir)
	_mi.set_instance_shader_parameter("tail", 0.0)
	_mi.set_instance_shader_parameter("size", SIZE * 0.15)
	_mi.set_instance_shader_parameter("seed", randf())


func _physics_process(delta: float) -> void:
	var step := _spell.bolt_speed * delta
	var a := global_position
	var b := a + _dir * step
	var hit := _trace(a, b)
	if not hit.is_empty():
		global_position = hit.point
		if _shooter and hit.shield:
			(hit.shield as Shield).report_hit(_spell.damage, hit.point)
		elif _shooter and hit.target >= 0:
			Net.send_event({"kind": "hit", "target": hit.target, "damage": _spell.damage, "spell": _spell.resource_path})
			if _shooter.has_method("confirm_hit"):
				_shooter.confirm_hit(hit.target)
		impact(get_parent(), _spell, hit.point, hit.normal, hit.target >= 0)
		queue_free()
		return
	global_position = b
	_travel += step
	if _travel > _spell.max_range:
		queue_free()
		return
	var g := clampf(_travel / GROW, 0.0, 1.0)
	_mi.set_instance_shader_parameter("size", SIZE * lerpf(0.3, 1.0, g))
	_mi.set_instance_shader_parameter("tail", minf(_travel * 0.8, TAIL))


## {"point", "normal", "target" (peer id or -1)} of the first thing between a and b, or {}.
func _trace(a: Vector3, b: Vector3) -> Dictionary:
	var result := {}
	var best := a.distance_to(b)
	var q := PhysicsRayQueryParameters3D.create(a, b)
	# The shooter's own Hex Ward lets their orbs through (domes don't).
	var exclude := Shield.excludes_for(get_tree(), Net.my_id if _shooter else (_skip as RemotePlayer).peer_id if _skip is RemotePlayer else -99)
	if _shooter:
		exclude.append(_shooter.get_rid())
	q.exclude = exclude
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		best = a.distance_to(r.position)
		result = {"point": r.position, "normal": r.normal, "target": -1, "shield": Shield.from_collider(r.collider)}
	var dome := Shield.dome_exit(get_tree(), a, a + _dir * best)
	if not dome.is_empty():
		best = dome.dist
		result = {"point": dome.point, "normal": dome.normal, "target": -1, "shield": dome.shield}
	var end := a + _dir * best
	for node in get_tree().get_nodes_in_group("remote_player"):
		var av := node as RemotePlayer
		if av == null or av == _skip or not av.visible or av.is_dead():
			continue
		var pts := Geometry3D.get_closest_points_between_segments(a, end,
			av.global_position + Vector3.UP * CAPSULE_LOW, av.global_position + Vector3.UP * CAPSULE_HIGH)
		if pts[0].distance_to(pts[1]) <= HIT_RADIUS:
			var d := a.distance_to(pts[0])
			if d < best:
				best = d
				end = pts[0]
				result = {"point": pts[0], "normal": (pts[0] - pts[1]).normalized(), "target": av.peer_id, "shield": null}
	return result


static func impact(parent: Node, spell: MinigunSpell, at: Vector3, normal: Vector3, on_player: bool) -> void:
	if normal.length_squared() < 0.01:
		normal = Vector3.UP
	var root := SpellFx.effect_root(parent, at + normal * 0.05, 0.9)
	var sparks := SpellFx.particles(root, 12 if on_player else 9, 0.35, true, true, Vector2(0.03, 0.28),
		spell.accent, spell.color)
	var pm := sparks.process_material as ParticleProcessMaterial
	pm.direction = normal
	pm.spread = 70.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3(0, -6, 0)
	pm.damping_min = 3.0
	pm.damping_max = 5.0
	var motes := SpellFx.particles(root, 5, 0.6, true, false, Vector2(0.12, 0.12), spell.color, spell.accent)
	var mm := motes.process_material as ParticleProcessMaterial
	mm.direction = normal
	mm.spread = 90.0
	mm.initial_velocity_min = 0.3
	mm.initial_velocity_max = 1.2
	var ring := SpellFx.ring(root, false, 1.1 if on_player else 0.8, spell.color, spell.accent)
	ring.global_basis = Basis.looking_at(-normal, Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT)
	SpellFx.animate_ring(ring, 0.25, 0.0)


static func _material(spell: MinigunSpell) -> ShaderMaterial:
	var key := spell.get_instance_id()
	if not _materials.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("color", spell.color)
		mat.set_shader_parameter("accent", spell.accent)
		_materials[key] = mat
	return _materials[key]


## Two quads: COLOR.r = 0 the camera-facing orb, 1 the streak (the shader places both).
static func _bolt_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for kind in [0.0, 1.0]:
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(kind, 0, 0))
			st.set_uv(uvs[i])
			st.add_vertex(Vector3(uvs[i].x - 0.5, 0.5 - uvs[i].y, 0.0))
	_mesh = st.commit()
	return _mesh
