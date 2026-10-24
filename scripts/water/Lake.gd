class_name Lake
extends Node3D
## Visuals for a carved LakeShape: water surface, lily pad clusters, reed beds on a few
## stretches of shore (not all the way around), and the small island's trees and rocks.
## Swimming: an invisible floor sits SWIM_FLOOR below the surface, so players wade out
## until their head stays just above the water instead of sinking to the bed.

## Depth of the swimming floor below the water surface (player feet; eyes end up ~0.25 m above).
const SWIM_FLOOR := 1.25

var shape: LakeShape


func build(data: TerrainData, lake: LakeShape, seed: int) -> void:
	shape = lake
	add_to_group("lake")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_build_water()
	_build_swim_floor()
	_build_lilies(data, rng)
	_build_reeds(data, rng)
	_build_island(data, rng)


## How far below the water surface `feet` are, or -INF outside the lake.
func depth_at(feet: Vector3) -> float:
	if shape.shore_fraction(Vector2(feet.x, feet.z)) > 1.05:
		return -INF
	return shape.level - feet.y


## The floor follows the (wobbly) shoreline, reaching SWIM_FLOOR_REACH × its radius: up to
## 1.2× the carved bank is guaranteed to stand above the water, so the floor stays buried. A plain
## disc out to outer_radius() poked out where the bank blends back into lower terrain.
const SWIM_FLOOR_REACH := 1.1
const SWIM_FLOOR_SEGMENTS := 96


func _build_swim_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "SwimFloor"
	var y := shape.level - SWIM_FLOOR
	var faces := PackedVector3Array()
	var c := Vector3(shape.center.x, y, shape.center.y)
	for i in SWIM_FLOOR_SEGMENTS:
		var a0 := TAU * i / SWIM_FLOOR_SEGMENTS
		var a1 := TAU * (i + 1) / SWIM_FLOOR_SEGMENTS
		var p0 := c + Vector3(cos(a0), 0.0, sin(a0)) * shape.shore_radius(a0) * SWIM_FLOOR_REACH
		var p1 := c + Vector3(cos(a1), 0.0, sin(a1)) * shape.shore_radius(a1) * SWIM_FLOOR_REACH
		faces.append_array([c, p1, p0])
	var poly := ConcavePolygonShape3D.new()
	poly.set_faces(faces)
	poly.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = poly
	body.add_child(cs)
	add_child(body)


func _build_water() -> void:
	var segments := 128
	var rings := 12
	var verts := PackedVector3Array([Vector3.ZERO])
	var normals := PackedVector3Array([Vector3.UP])
	var idx := PackedInt32Array()
	for r in range(1, rings + 1):
		var t := float(r) / rings
		for s in segments:
			var th := TAU * s / segments
			var rr := shape.shore_radius(th) * 1.18 * t
			verts.append(Vector3(cos(th) * rr, 0.0, sin(th) * rr))
			normals.append(Vector3.UP)
	for s in segments:
		var s2 := (s + 1) % segments
		idx.append_array([0, 1 + s, 1 + s2])
	for r in range(1, rings):
		var a0 := 1 + (r - 1) * segments
		var b0 := 1 + r * segments
		for s in segments:
			var s2 := (s + 1) % segments
			idx.append_array([a0 + s, b0 + s, b0 + s2, a0 + s, b0 + s2, a0 + s2])
	# Make the surface face up (Godot front faces are clockwise).
	var probe := (verts[idx[1]] - verts[idx[0]]).cross(verts[idx[2]] - verts[idx[0]])
	if probe.y > 0.0:
		for i in range(0, idx.size(), 3):
			var tmp := idx[i + 1]
			idx[i + 1] = idx[i + 2]
			idx[i + 2] = tmp
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/water.gdshader")
	mat.set_shader_parameter("wave_normal", ResourcePacks.texture("water_normal.png"))
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(shape.center.x, shape.level, shape.center.y)
	add_child(mi)


func _build_lilies(data: TerrainData, rng: RandomNumberGenerator) -> void:
	var pads: Array[Mesh] = [WaterPlants.lily_pad(1), WaterPlants.lily_pad(2), WaterPlants.lily_pad(3)]
	var flower := WaterPlants.lily_flower(4)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/lily.gdshader")
	var groups: Array = [[], [], [], []]
	var clusters := rng.randi_range(4, 7)
	for c in clusters:
		var center := Vector2.ZERO
		for attempt in 30:
			var th := rng.randf() * TAU
			center = shape.center + Vector2.from_angle(th) * shape.shore_radius(th) * rng.randf_range(0.5, 0.88)
			var d := shape.level - data.height_at(center.x, center.y)
			if d > 0.3 and d < 2.8 and shape.island_fraction(center) > 1.8:
				break
		for i in rng.randi_range(8, 22):
			var p := center + Vector2(rng.randfn(0.0, 1.4), rng.randfn(0.0, 1.4))
			var depth := shape.level - data.height_at(p.x, p.y)
			if depth < 0.15 or shape.island_fraction(p) < 1.3:
				continue
			var s := rng.randf_range(0.22, 0.5)
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, shape.level + 0.012, p.y))
			groups[rng.randi() % 3].append(xf)
			if rng.randf() < 0.18:
				var fp := p + Vector2(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1))
				groups[3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.2)), Vector3(fp.x, shape.level + 0.02, fp.y)))
	for g in 4:
		_multimesh("Lilies", pads[g] if g < 3 else flower, groups[g], mat, 220.0, false)


func _build_reeds(data: TerrainData, rng: RandomNumberGenerator) -> void:
	var meshes: Array[Mesh] = [WaterPlants.reed_clump(21, false), WaterPlants.reed_clump(22, true), WaterPlants.reed_clump(23, false)]
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/reed.gdshader")
	var groups: Array = [[], [], []]
	# A few stretches of the lake shore.
	var arcs := rng.randi_range(3, 4)
	var start := rng.randf() * TAU
	for a in arcs:
		var mid := start + TAU * a / arcs + rng.randf_range(-0.3, 0.3)
		var span := deg_to_rad(rng.randf_range(22.0, 48.0))
		_reed_arc(data, rng, groups, func(th: float, f: float) -> Vector2:
			return shape.center + Vector2.from_angle(th) * shape.shore_radius(th) * f, mid, span, shape.radius)
	# And part of the island shore.
	_reed_arc(data, rng, groups, func(th: float, f: float) -> Vector2:
		return shape.island_center + Vector2.from_angle(th) * shape.island_edge(th) * f,
		rng.randf() * TAU, deg_to_rad(rng.randf_range(50.0, 90.0)), shape.island_radius)
	for g in 3:
		_multimesh("Reeds", meshes[g], groups[g], mat, 300.0, true)


## Plants reed clumps along an arc, in the band where the ground is just below to just
## above the waterline. `at(theta, fraction)` maps to world XZ.
func _reed_arc(data: TerrainData, rng: RandomNumberGenerator, groups: Array, at: Callable, mid: float, span: float, radius: float) -> void:
	var step := 0.75 / radius
	var th := mid - span * 0.5
	while th < mid + span * 0.5:
		# Thin out towards the ends of the arc.
		var edge := absf(th - mid) / (span * 0.5)
		if rng.randf() > 1.0 - edge * edge * 0.8:
			th += step
			continue
		var f := 0.7
		while f < 1.35:
			var p: Vector2 = at.call(th + rng.randf_range(-step, step), f)
			var h := data.height_at(p.x, p.y)
			var rel := h - shape.level
			if rel > -0.55 and rel < 0.3 and rng.randf() < 0.55:
				var s := rng.randf_range(0.75, 1.3)
				var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, h - 0.05, p.y))
				groups[rng.randi() % groups.size()].append(xf)
			f += 0.035
		th += step


func _build_island(data: TerrainData, rng: RandomNumberGenerator) -> void:
	var assets := VegetationAssets.get_shared()
	var body := StaticBody3D.new()
	add_child(body)
	var trees := rng.randi_range(2, 3)
	var a0 := rng.randf() * TAU
	for i in trees:
		var p := shape.island_center + Vector2.from_angle(a0 + TAU * i / trees) * shape.island_radius * rng.randf_range(0.15, 0.4)
		var tree: Dictionary = assets.broadleaf[rng.randi() % assets.broadleaf.size()]
		var s := rng.randf_range(0.8, 1.1)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, data.height_at(p.x, p.y) - 0.25, p.y))
		for lod in [["lod0", 0.0, 60.0], ["lod1", 60.0, 260.0], ["lod2", 260.0, 1100.0]]:
			var mi := MeshInstance3D.new()
			mi.mesh = tree[lod[0]]
			mi.transform = xf
			mi.visibility_range_begin = lod[1]
			mi.visibility_range_end = lod[2]
			add_child(mi)
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = tree.trunk_radius * s
		cyl.height = 4.0
		cs.shape = cyl
		cs.position = xf.origin + Vector3.UP * 2.0
		body.add_child(cs)
	for i in rng.randi_range(3, 6):
		var th := rng.randf() * TAU
		var p := shape.island_center + Vector2.from_angle(th) * shape.island_edge(th) * rng.randf_range(0.6, 1.05)
		var big := rng.randf() < 0.4
		var meshes := assets.big_rocks if big else assets.rocks
		var s := rng.randf_range(0.6, 1.3) if big else rng.randf_range(0.2, 0.5)
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[rng.randi() % meshes.size()]
		mi.transform = Transform3D(ScatterBatch.aligned_basis(data.normal_at(p.x, p.y), rng.randf() * TAU, s), Vector3(p.x, data.height_at(p.x, p.y) - 0.15 * s, p.y))
		mi.visibility_range_end = 400.0
		add_child(mi)


func _multimesh(node_name: String, mesh: Mesh, xforms: Array, mat: Material, vis_end: float, shadows: bool) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	# Anchor at the lake so visibility ranges are measured from here.
	var anchor := Vector3(shape.center.x, shape.level, shape.center.y)
	for i in xforms.size():
		var t: Transform3D = xforms[i]
		t.origin -= anchor
		mm.set_instance_transform(i, t)
	var mmi := MultiMeshInstance3D.new()
	mmi.position = anchor
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.visibility_range_end = vis_end
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
