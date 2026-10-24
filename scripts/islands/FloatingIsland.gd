class_name FloatingIsland
extends Node3D
## One floating island: rock body, top vegetation, hanging roots, underside crystals,
## a swarm of rocks orbiting its lower half and rising magic motes. Small islands bob.
##
## Everything that moves is a pure function of the shared world clock (Net.world_time), so it
## is in the same place on every client without being sent: the bob here, the orbits in
## shaders/orbit_rock.gdshader (global uniform world_time). Bobbing islands collide through an
## AnimatableBody3D (players standing on them ride along); the orbiting rocks get
## AnimatableBody3D colliders that follow the same orbit math (orbiter_transform), created once
## the local camera comes within ORBITER_RANGE and switched off again beyond it.

const TREE_NEAR := 60.0
const TREE_MID := 260.0
const TREE_FAR := 1600.0
## Orbiting rocks collide while the camera is within this distance of the orbit swarm's edge.
const ORBITER_RANGE := 90.0

var shape: IslandShape
var bob_amplitude := 0.0
var bob_speed := 0.5

var _base_y := 0.0
var _phase := 0.0
var _base_basis := Basis.IDENTITY
var _strata_seed := 0.0
var _island_body: CollisionObject3D
## Orbiting rocks: {mesh, basis (scale + rotation), c (orbit r, phase, speed, height), bob, up}
var _rocks: Array = []
var _rock_bodies: Array[AnimatableBody3D] = []
var _rocks_active := false
var _orbit_extent := 0.0
static var _hull_cache := {}  # Mesh -> shared simplified ConvexPolygonShape3D


## collision: the body gets a collider (and grass); moving: it will bob (start_bobbing), so the
## collider is an AnimatableBody3D that carries whoever stands on it.
func setup(s: IslandShape, rng: RandomNumberGenerator, mats: Dictionary, collision: bool, moving := false) -> void:
	shape = s
	var assets := VegetationAssets.get_shared()
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = s.build_mesh(mats.island)
	body.set_instance_shader_parameter("rock_tint", Color(rng.randf_range(0.9, 1.1), rng.randf_range(0.9, 1.05), rng.randf_range(0.88, 1.05)))
	_strata_seed = rng.randf() * 10.0
	body.set_instance_shader_parameter("strata_seed", _strata_seed)
	add_child(body)
	if collision:
		var sb: CollisionObject3D = AnimatableBody3D.new() if moving else StaticBody3D.new()
		sb.name = "Collider"
		var cs := CollisionShape3D.new()
		cs.shape = body.mesh.create_trimesh_shape()
		sb.add_child(cs)
		if moving:
			# Moved explicitly in _physics_process: an AnimatableBody3D only syncs (and carries
			# riders) when its own transform changes, not when its parent moves.
			sb.top_level = true
		add_child(sb)
		_island_body = sb
		# Walkable (collision) islands get grass and flowers on top.
		IslandGrass.build(self)

	_decorate_top(rng, assets)
	_add_roots(rng, mats.root)
	if s.radius >= 9.0 and rng.randf() < 0.75:
		_add_crystals(rng, mats.crystal)
	_add_orbiters(rng, assets)
	if s.radius >= 14.0:
		_add_motes(rng, mats.mote)


## Seed of the body's texture variation (the grass matches its colour).
func get_strata_seed() -> float:
	return _strata_seed


func start_bobbing(rng: RandomNumberGenerator) -> void:
	bob_amplitude = rng.randf_range(0.6, 1.8)
	bob_speed = rng.randf_range(0.25, 0.5)
	_phase = rng.randf() * TAU
	_base_y = position.y
	_base_basis = basis


func _physics_process(_delta: float) -> void:
	var now := Net.world_time()
	if bob_amplitude > 0.0:
		var t := now * bob_speed + _phase
		position.y = _base_y + sin(t) * bob_amplitude
		basis = _base_basis * Basis(Vector3(1, 0, 0.3).normalized(), sin(t * 0.7) * 0.02)
		if _island_body:
			_island_body.global_transform = global_transform
	_update_rock_bodies(now)


# --- Orbiting rock colliders --------------------------------------------------------

## World transform of orbiting rock `rock` at world time `t` – the same maths as the ORBIT
## vertex shader in shaders/include/rock_common.gdshaderinc (keep them in step).
func orbiter_transform(rock: Dictionary, t: float) -> Transform3D:
	var r: float = rock.r
	var phase: float = rock.phase
	var v_rand := fposmod(phase * 0.1591 + r * 0.37, 1.0)
	var spin_axis := Vector3(sin(phase * 3.1), 1.0, cos(phase * 1.7)).normalized()
	var spin := t * (0.15 + v_rand * 0.4) + phase
	var ang := phase + t * float(rock.speed)
	var orbit := Vector3(cos(ang) * r, float(rock.height) + sin(t * 0.6 + phase * 2.3) * float(rock.bob), sin(ang) * r)
	var up: Vector3 = rock.up
	var axis := Vector3.UP.cross(up)
	var s := axis.length()
	if s > 1e-4:
		orbit = orbit.rotated(axis / s, asin(clampf(s, 0.0, 1.0)))
	var rot := Basis(spin_axis, spin) * global_basis.orthonormalized() * (rock.basis as Basis).orthonormalized()
	return Transform3D(rot, global_position + orbit)


func _update_rock_bodies(t: float) -> void:
	if _rocks.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	var near := cam != null and cam.global_position.distance_to(global_position) < _orbit_extent + ORBITER_RANGE
	if near and _rock_bodies.is_empty():
		_build_rock_bodies()
	if near != _rocks_active:
		_rocks_active = near
		for b in _rock_bodies:
			b.collision_layer = 1 if near else 0
			(b.get_child(0) as CollisionShape3D).disabled = not near
	if not near:
		return
	for i in _rocks.size():
		_rock_bodies[i].global_transform = orbiter_transform(_rocks[i], t)


## Convex hull of an orbiting-rock mesh, computed once (IslandField does it while loading, so
## the first approach to an island doesn't stall).
static func prewarm_hull(mesh: Mesh) -> void:
	if not _hull_cache.has(mesh):
		_hull_cache[mesh] = mesh.create_convex_shape(true, false)


func _build_rock_bodies() -> void:
	for rock in _rocks:
		var mesh: Mesh = rock.mesh
		if not _hull_cache.has(mesh):
			prewarm_hull(mesh)
		# One shared hull per rock mesh, scaled (uniformly) on the shape node: giving every rock
		# its own scaled point set made the physics server rebuild a hull each time (~0.7 ms).
		var cs := CollisionShape3D.new()
		cs.shape = _hull_cache[mesh]
		cs.scale = Vector3.ONE * (rock.basis as Basis).get_scale().x
		var b := AnimatableBody3D.new()
		b.name = "OrbitRock"
		b.top_level = true
		b.add_child(cs)
		add_child(b)
		_rock_bodies.append(b)
	_rocks_active = true


# --- Top ----------------------------------------------------------------------

func _decorate_top(rng: RandomNumberGenerator, assets: VegetationAssets) -> void:
	var r := shape.radius
	var groups := {}
	var area := PI * r * r
	var tree_density := 0.0 if r < 6.0 else rng.randf_range(0.002, 0.012)
	var tree_count := int(area * tree_density)
	var pine_bias := rng.randf()
	var placed: Array[Vector2] = []
	for i in tree_count * 3:
		if placed.size() >= tree_count:
			break
		var p := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * r * 0.8
		if p.length() > shape.rim_radius(p.angle()) * 0.82:
			continue
		if _top_normal(p).y < 0.88:
			continue
		var too_close := false
		for q in placed:
			if q.distance_to(p) < 3.2:
				too_close = true
				break
		if too_close:
			continue
		placed.append(p)
		var pine := rng.randf() < pine_bias
		var variants := assets.pines if pine else assets.broadleaf
		var tree: Dictionary = variants[rng.randi() % variants.size()]
		var sc := rng.randf_range(0.7, 1.15)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(p.x, shape.top_y(p.x, p.y) - 0.3, p.y))
		_group_add(groups, tree.lod0, xf, 0.0, TREE_NEAR)
		_group_add(groups, tree.lod1, xf, TREE_NEAR, TREE_MID)
		_group_add(groups, tree.lod2, xf, TREE_MID, TREE_FAR)

	# Boulders and stones on top.
	for i in int(area * rng.randf_range(0.004, 0.02)) + 2:
		var p := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * r * 0.9
		if p.length() > shape.rim_radius(p.angle()) * 0.92:
			continue
		var big := rng.randf() < 0.2
		var sc := rng.randf_range(0.6, 1.8) if big else rng.randf_range(0.15, 0.5)
		var up := Vector3.UP.lerp(_top_normal(p), 0.7).normalized()
		var xf := Transform3D(ScatterBatch.aligned_basis(up, rng.randf() * TAU, sc), Vector3(p.x, shape.top_y(p.x, p.y) - 0.15 * sc, p.y))
		var meshes := assets.big_rocks if big else assets.rocks
		_group_add(groups, meshes[rng.randi() % meshes.size()], xf, 0.0, 600.0 if big else 120.0)

	for key in groups:
		var g: Dictionary = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = g.mesh
		mm.instance_count = g.xforms.size()
		for i in g.xforms.size():
			mm.set_instance_transform(i, g.xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_begin = g.begin
		mmi.visibility_range_end = g.end
		add_child(mmi)


func _group_add(groups: Dictionary, mesh: Mesh, xf: Transform3D, begin: float, end: float) -> void:
	var key := "%d|%d" % [mesh.get_instance_id(), int(begin)]
	if not groups.has(key):
		groups[key] = {"mesh": mesh, "xforms": [], "begin": begin, "end": end}
	groups[key].xforms.append(xf)


func _top_normal(p: Vector2) -> Vector3:
	var e := 0.8
	var hl := shape.top_y(p.x - e, p.y)
	var hr := shape.top_y(p.x + e, p.y)
	var hd := shape.top_y(p.x, p.y - e)
	var hu := shape.top_y(p.x, p.y + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


# --- Underside ----------------------------------------------------------------

## Roots dangling over the cliff edge and out of the underside.
func _add_roots(rng: RandomNumberGenerator, mat: Material) -> void:
	var r := shape.radius
	var count := int(r * rng.randf_range(0.3, 0.8))
	if count == 0:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in count:
		var th := rng.randf() * TAU
		var rim := shape.rim_radius(th)
		var inset := rng.randf_range(0.9, 1.0) if rng.randf() < 0.7 else rng.randf_range(0.5, 0.85)
		var start_y := shape.cliff_bottom(th) + rng.randf_range(0.0, shape.cliff * 0.6)
		if inset < 0.9:
			start_y = shape.cliff_bottom(th) - shape.depth * (1.0 - inset) * 0.8
		var p := Vector3(cos(th) * rim * inset, start_y, sin(th) * rim * inset)
		var out := Vector3(cos(th), 0, sin(th))
		var length := rng.randf_range(2.0, 4.0 + r * 0.3)
		var thick := rng.randf_range(0.04, 0.09) + r * 0.002
		_root_strand(st, rng, p, out, length, thick, 2)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "Roots"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.visibility_range_end = 700.0
	add_child(mi)


func _root_strand(st: SurfaceTool, rng: RandomNumberGenerator, p: Vector3, out: Vector3, length: float, thick: float, depth_left: int) -> void:
	var pts := PackedVector3Array([p])
	var radii := PackedFloat32Array([thick])
	var dir := (Vector3.DOWN * 0.8 + out * rng.randf_range(0.1, 0.5)).normalized()
	var segs := 7
	for s in segs:
		dir = (dir + Vector3.DOWN * 0.25 + MeshUtil.rand_dir(rng) * 0.25).normalized()
		p += dir * length / segs
		pts.append(p)
		radii.append(lerpf(thick, thick * 0.15, float(s + 1) / segs))
	MeshUtil.tube(st, pts, radii, 4, 1.0, 1.5)
	if depth_left > 0:
		for k in rng.randi_range(0, 2):
			var t := rng.randi_range(2, segs - 2)
			_root_strand(st, rng, pts[t], MeshUtil.rand_dir(rng), length * 0.4, radii[t] * 0.6, depth_left - 1)


## Clusters of glowing crystals growing from the underside tips.
func _add_crystals(rng: RandomNumberGenerator, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tip in shape.tip_points():
		if rng.randf() < 0.35:
			continue
		for k in rng.randi_range(3, 7):
			var dir := (Vector3.DOWN + MeshUtil.rand_dir(rng) * 0.55).normalized()
			var len := rng.randf_range(0.8, 2.5) * clampf(shape.radius / 20.0, 0.6, 2.0)
			_crystal(st, tip + dir * 0.3 + Vector3.UP * 0.6, dir, len, len * rng.randf_range(0.12, 0.2))
	var mi := MeshInstance3D.new()
	mi.name = "Crystals"
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


func _crystal(st: SurfaceTool, base: Vector3, dir: Vector3, length: float, width: float) -> void:
	var side := MeshUtil.perpendicular(dir)
	var side2 := dir.cross(side)
	var ring_a: Array[Vector3] = []
	var ring_b: Array[Vector3] = []
	for i in 6:
		var a := TAU * i / 6.0
		var off := (side * cos(a) + side2 * sin(a)) * width
		ring_a.append(base + off)
		ring_b.append(base + off + dir * length * 0.75)
	var tip := base + dir * length
	for i in 6:
		var j := (i + 1) % 6
		var n := ((ring_a[i] + ring_a[j]) * 0.5 - base).normalized()
		MeshUtil.quad(st, ring_a[i], ring_a[j], ring_b[j], ring_b[i], n, n, n, n, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
		var n2 := (n + dir * 0.6).normalized()
		MeshUtil.tri(st, ring_b[i], ring_b[j], tip, n2, n2, n2, Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1))


## Rocks slowly orbiting the lower part of the island (animated in orbit_rock.gdshader).
func _add_orbiters(rng: RandomNumberGenerator, assets: VegetationAssets) -> void:
	var r := shape.radius
	var count := clampi(int(r * rng.randf_range(0.7, 1.2)), 5, 60)
	var bottom := shape.bottom_y()
	var variants := 3
	var lists: Array = [[], [], []]
	var direction := 1.0 if rng.randf() < 0.5 else -1.0
	for i in count:
		var orbit_r := r * rng.randf_range(0.3, 1.45)
		var height: float
		var sc := lerpf(0.25, clampf(r * 0.07, 0.6, 3.5), pow(rng.randf(), 2.2))
		# Stay below the underside wherever the orbit passes beneath the island.
		var clear := shape.lowest_underside_at(orbit_r) - sc * 1.5 - 1.0
		if orbit_r < r * 1.3:
			height = rng.randf_range(minf(clear, bottom) - r * 0.25, clear)
		else:
			height = rng.randf_range(bottom * 0.75, -shape.cliff * 0.5)
		var speed := rng.randf_range(0.03, 0.12) / sqrt(maxf(orbit_r, 3.0) / 10.0) * (direction if rng.randf() < 0.85 else -direction)
		var basis := Basis(MeshUtil.rand_dir(rng), rng.randf() * TAU).scaled(Vector3.ONE * sc)
		lists[i % variants].append([basis, Color(orbit_r, rng.randf() * TAU, speed, height)])
		_orbit_extent = maxf(_orbit_extent, Vector2(orbit_r, height).length() + sc * 3.0)
	var tilt := (Vector3.UP + MeshUtil.rand_dir(rng) * rng.randf_range(0.0, 0.15)).normalized()
	var extent := r * 1.7
	for v in variants:
		var items: Array = lists[v]
		if items.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = assets.big_rocks[rng.randi() % assets.big_rocks.size()]
		mm.instance_count = items.size()
		for i in items.size():
			mm.set_instance_transform(i, Transform3D(items[i][0], Vector3.ZERO))
			mm.set_instance_custom_data(i, items[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Orbiters"
		mmi.multimesh = mm
		mmi.material_override = assets.mat_orbit_rock
		mmi.custom_aabb = AABB(Vector3(-extent, bottom * 1.3, -extent), Vector3(extent * 2.0, -bottom * 1.3 + 5.0, extent * 2.0))
		var bob := rng.randf_range(0.3, 1.0)
		mmi.set_instance_shader_parameter("orbit_up", tilt)
		mmi.set_instance_shader_parameter("bob_amount", bob)
		add_child(mmi)
		for item in items:
			var c: Color = item[1]
			_rocks.append({"mesh": mm.mesh, "basis": item[0], "r": c.r, "phase": c.g, "speed": c.b,
				"height": c.a, "bob": bob, "up": tilt})


func _add_motes(rng: RandomNumberGenerator, mat: Material) -> void:
	var r := shape.radius
	var p := GPUParticles3D.new()
	p.name = "Motes"
	p.amount = clampi(int(r * 3.0), 30, 160)
	p.lifetime = 9.0
	p.preprocess = 9.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = r * 0.9
	pm.emission_ring_inner_radius = r * 0.2
	pm.emission_ring_height = shape.depth * 0.5
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, 0.08, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.25, 0.25)
	quad.material = mat
	p.draw_pass_1 = quad
	p.position = Vector3(0, shape.cliff_bottom(0.0) - shape.depth * 0.45, 0)
	p.visibility_aabb = AABB(Vector3(-r * 1.5, -shape.depth, -r * 1.5), Vector3(r * 3.0, shape.depth * 2.5, r * 3.0))
	p.visibility_range_end = 500.0
	add_child(p)
