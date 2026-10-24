class_name Bounceshroom
extends Node3D
## A Bounceshroom (placed around the world by ShroomField): a big, low procedural mushroom
## (lathed stem, gills and domed cap, shaders/vfx/mushroom.gdshader – red cap with cream spots,
## glowing gills) standing along the ground's normal. A cylinder collider makes it solid; its cap
## top is low enough to jump onto (TOP). Whoever's feet touch the cap is launched along the
## mushroom's up axis (so a shroom on a slope throws sideways; each client bounces its own player,
## Player.bounce), and the cap squashes and flashes – also when another player's avatar lands on
## it (visual only).

## Cap radius and the height of its top (m). The mesh profile is lathed at full height
## (MESH_TOP) and squashed to TOP.
const CAP_RADIUS := 1.6
const MESH_TOP := 1.35
const TOP := 0.62
const BOUNCE_SPEED := 22.0
## Big shrooms are drawn out to this distance, small decorative ones to SMALL_RANGE.
const DRAW_RANGE := 260.0
const SMALL_RANGE := 90.0
const SHADER := preload("res://shaders/vfx/mushroom.gdshader")
const GLOW := Color(0.45, 0.9, 1.0)
const RED := Color(0.95, 0.25, 0.32)
## Cap colours of the small decorative ones: [cap, rim].
const SMALL_CAPS := [[Color(0.85, 0.12, 0.2), Color(0.45, 0.04, 0.12)], [Color(0.78, 0.42, 0.16), Color(0.4, 0.18, 0.06)],
	[Color(0.55, 0.22, 0.75), Color(0.25, 0.08, 0.38)]]

static var _meshes := {}
static var _material: ShaderMaterial
static var _small_materials: Array[ShaderMaterial] = []

var _mi: MeshInstance3D
var _squash := 0.0
var _squash_v := 0.0
var _glow := 0.0
var _cool := 0.0
var _seen := {}


## A bouncing mushroom standing on `at` along `up`, turned by `yaw` about it.
static func spawn(parent: Node, at: Vector3, up: Vector3, yaw: float) -> Bounceshroom:
	var s := Bounceshroom.new()
	parent.add_child(s)
	s.global_transform = Transform3D(_basis(up, yaw), at)
	return s


## A small decorative mushroom (no collision, no bounce). variant picks the cap colour.
static func small(parent: Node, at: Vector3, up: Vector3, yaw: float, size: float, variant: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(14)
	mi.material_override = _small_material(variant)
	mi.visibility_range_end = SMALL_RANGE
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if size < 0.35 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	mi.global_transform = Transform3D(_basis(up, yaw).scaled(Vector3(size, size * lerpf(0.7, 1.2, fmod(yaw, 1.0)), size)), at)
	return mi


static func _basis(up: Vector3, yaw: float) -> Basis:
	return SpellFx.basis_with_up(up.normalized(), Vector3(sin(yaw), 0.0, cos(yaw)))


static func prewarm(vp: Node) -> void:
	var s := spawn(vp, Vector3(0, 0, -6), Vector3.UP, 0.0)
	small(s, Vector3(1.5, 0, -6), Vector3.UP, 0.0, 0.4, 1)
	vp.get_tree().create_timer(0.5).timeout.connect(s.queue_free)


func _ready() -> void:
	add_to_group("bounceshroom")
	_mi = MeshInstance3D.new()
	_mi.mesh = mesh(32)
	_mi.material_override = _big_material()
	_mi.scale = Vector3(1.0, TOP / MESH_TOP, 1.0)
	_mi.visibility_range_end = DRAW_RANGE
	add_child(_mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = CAP_RADIUS * 0.92
	cyl.height = TOP
	cs.shape = cyl
	cs.position.y = TOP * 0.5
	body.add_child(cs)
	add_child(body)


static func _big_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("top", MESH_TOP)
	return _material


static func _small_material(variant: int) -> ShaderMaterial:
	if _small_materials.is_empty():
		for caps in SMALL_CAPS:
			var m := ShaderMaterial.new()
			m.shader = SHADER
			m.set_shader_parameter("top", MESH_TOP)
			m.set_shader_parameter("cap_color", caps[0])
			m.set_shader_parameter("cap_dark", caps[1])
			_small_materials.append(m)
	return _small_materials[variant % _small_materials.size()]


func _process(delta: float) -> void:
	if _squash == 0.0 and _squash_v == 0.0 and _glow == 0.0:
		return
	# Springy squash (damped spring towards 0).
	_squash_v += (-_squash * 160.0 - _squash_v * 9.0) * delta
	_squash += _squash_v * delta
	if absf(_squash) < 0.001 and absf(_squash_v) < 0.01:
		_squash = 0.0
		_squash_v = 0.0
	_glow = move_toward(_glow, 0.0, delta * 2.5)
	_mi.set_instance_shader_parameter("squash", _squash)
	_mi.set_instance_shader_parameter("glow", _glow)


func _physics_process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	var scene := get_tree().current_scene
	if scene == null:
		return
	var me := scene.get_node_or_null("Player") as Node3D
	if me and me.has_method("bounce") and not me.is_dead() and _cool <= 0.0:
		var feet: Vector3 = me.global_position - Vector3.UP * float(me.get("FOOT_OFFSET"))
		var up := global_basis.y
		if global_position.distance_squared_to(feet) < 16.0 and _on_cap(feet) and (me.get("velocity") as Vector3).dot(up) <= 1.0:
			me.bounce(up * BOUNCE_SPEED)
			_boing()
			_cool = 0.35
	# Other players landing on it: just the squash.
	for node in get_tree().get_nodes_in_group("remote_player"):
		var a := node as RemotePlayer
		if a == null or not a.visible or global_position.distance_squared_to(a.global_position) > 16.0:
			_seen.erase(a.peer_id if a else 0)
			continue
		var on := _on_cap(a.global_position)
		if on and not _seen.get(a.peer_id, false):
			_boing()
		_seen[a.peer_id] = on


## True if `feet` (world) rest on the cap: in the mushroom's own frame, within the cap and just
## at its top.
func _on_cap(feet: Vector3) -> bool:
	var l := global_transform.affine_inverse() * feet
	return Vector2(l.x, l.z).length() < CAP_RADIUS + 0.25 and l.y > TOP - 0.4 and l.y < TOP + 0.5


func _boing() -> void:
	_squash_v = 9.0
	_glow = 1.0
	var root := SpellFx.effect_root(get_parent(), global_transform * Vector3(0, TOP + 0.1, 0), 1.0)
	var ring := SpellFx.ring(root, false, CAP_RADIUS * 3.0, GLOW, Color(1, 1, 1))
	ring.global_basis = global_basis * Basis(Vector3.RIGHT, -PI * 0.5)
	SpellFx.animate_ring(ring, 0.35, 0.0)
	var spores := SpellFx.particles(root, 18, 0.7, true, true, Vector2(0.04, 0.35), GLOW, RED)
	var pm := spores.process_material as ParticleProcessMaterial
	pm.direction = global_basis.y
	pm.spread = 35.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 10.0
	pm.gravity = Vector3(0, -9, 0)


## The mushroom with `segments` around: lathed profiles (COLOR.r = part: 0 stem, 1 cap, 2 gills).
static func mesh(segments: int) -> ArrayMesh:
	if _meshes.has(segments):
		return _meshes[segments]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Stem bottom → top (slight bulge, flared foot, sunk a little into the ground).
	_lathe(st, segments, [Vector2(0.62, -0.25), Vector2(0.5, 0.06), Vector2(0.42, 0.25), Vector2(0.38, 0.5),
		Vector2(0.36, 0.72), Vector2(0.4, 0.86)], 0.0)
	# Gills: from the stem out to the rim, facing down.
	_lathe(st, segments, [Vector2(0.38, 0.84), Vector2(0.9, 0.86), Vector2(1.35, 0.84), Vector2(1.58, 0.8)], 2.0)
	# Cap: rim → top.
	_lathe(st, segments, [Vector2(1.58, 0.8), Vector2(1.66, 0.88), Vector2(1.62, 0.98), Vector2(1.48, 1.1),
		Vector2(1.2, 1.22), Vector2(0.8, 1.3), Vector2(0.4, 1.34), Vector2(0.001, 1.35)], 1.0)
	var m := st.commit()
	_meshes[segments] = m
	return m


## Revolves a profile (x = radius, y = height); normals from the profile (outward/upward when the
## profile runs upwards or outwards, downward for the gills).
static func _lathe(st: SurfaceTool, segments: int, profile: Array, part: float) -> void:
	var n := profile.size()
	var normals: Array[Vector2] = []
	for i in n:
		var a: Vector2 = profile[maxi(i - 1, 0)]
		var b: Vector2 = profile[mini(i + 1, n - 1)]
		var t := (b - a).normalized()
		normals.append(Vector2(t.y, -t.x))
	for i in n - 1:
		for k in segments:
			var a0 := TAU * k / segments
			var a1 := TAU * (k + 1) / segments
			var quad := [[i, a0], [i + 1, a0], [i + 1, a1], [i, a1]]
			var verts: Array[Vector3] = []
			var norms: Array[Vector3] = []
			for q in quad:
				var p: Vector2 = profile[q[0]]
				var nn: Vector2 = normals[q[0]]
				var ang: float = q[1]
				verts.append(Vector3(sin(ang) * p.x, p.y, cos(ang) * p.x))
				norms.append(Vector3(sin(ang) * nn.x, nn.y, cos(ang) * nn.x).normalized())
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(Color(part, 0, 0))
				st.set_normal(norms[idx])
				st.add_vertex(verts[idx])
