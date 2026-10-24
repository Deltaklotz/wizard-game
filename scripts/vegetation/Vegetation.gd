class_name Vegetation
extends Node3D
## Scatters trees, boulders, rocks, pebbles and sticks over the terrain, driven by a
## forest-mask noise, slope, altitude and the erosion control map.

const TREE_SPACING := 4.2
const ROCK_SPACING := 2.5
const EDGE_MARGIN := 24.0
const TREE_NEAR := 60.0
const TREE_MID := 260.0
const TREE_FAR := 1100.0
const GREEBLE_FAR := 85.0
const BOULDER_FAR := 450.0

## Tree base positions and whether each is a pine, e.g. for gameplay or debugging.
var tree_positions := PackedVector3Array()
var tree_is_pine := PackedByteArray()

var _bodies: Array[RID] = []
var _shapes: Array[RID] = []


func build(data: TerrainData, seed: int) -> void:
	var t0 := Time.get_ticks_msec()
	var assets := VegetationAssets.get_shared()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var forest := FastNoiseLite.new()
	forest.seed = seed
	forest.frequency = 0.0045
	forest.fractal_octaves = 3
	var species := FastNoiseLite.new()
	species.seed = seed + 1
	species.frequency = 0.007

	var trees := ScatterBatch.new(128.0)
	var greebles := ScatterBatch.new(64.0)
	var collision: Array = []  # [position, radius, height]
	var tree_spots: Array = []
	var half := data.world_size() * 0.5 - EDGE_MARGIN

	# --- Trees ---
	var steps := int(half * 2.0 / TREE_SPACING)
	for zi in steps:
		for xi in steps:
			var x := -half + (xi + rng.randf()) * TREE_SPACING
			var z := -half + (zi + rng.randf()) * TREE_SPACING
			# The big forests (ForestLayout): dense, with trails and glades kept clear; they also
			# grow on steeper slopes and across erosion rills (only real streambeds stay open).
			var fd := 0.0
			var fpine := -1.0
			if data.forests:
				if data.forests.blocked_at(x, z):
					continue
				fd = data.forests.density_at(x, z)
				fpine = data.forests.pine_at(x, z)
			var in_forest := fd > 0.3
			var n := data.normal_at(x, z)
			if n.y < (0.8 if in_forest else 0.86):
				continue
			var h := data.height_at(x, z)
			if h > 195.0 or h < data.water_level_at(x, z) + 0.8 or data.in_clearing(x, z):
				continue
			var ctl := data.control_at(x, z)
			if ctl.g > (0.93 if in_forest else 0.74):
				continue
			var f := forest.get_noise_2d(x, z) * 0.5 + 0.5
			# Outside them only small groves and the odd lone tree.
			var density := maxf(smoothstep(0.52, 0.66, f) * 0.7 + 0.008, fd * 0.95)
			if not in_forest:
				density *= 1.0 - smoothstep(0.08, 0.14, 1.0 - n.y) * 0.7
			density *= 1.0 - smoothstep(170.0, 195.0, h)
			if rng.randf() > density:
				continue
			var p_pine := clampf(smoothstep(80.0, 140.0, h) + species.get_noise_2d(x, z) * 0.6 + (1.0 - n.y) * 2.0, 0.0, 1.0)
			if fpine >= 0.0:
				p_pine = lerpf(p_pine, clampf(fpine + species.get_noise_2d(x, z) * 0.3, 0.0, 1.0), smoothstep(0.1, 0.5, fd))
			var pine := rng.randf() < p_pine
			var variants := assets.pines if pine else assets.broadleaf
			var tree: Dictionary = variants[rng.randi() % variants.size()]
			var s := rng.randf_range(0.75, 1.3)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
			basis = Basis(MeshUtil.rand_dir(rng).cross(Vector3.UP).normalized(), rng.randf_range(0.0, 0.04)) * basis
			var pos := Vector3(x, h - 0.25 * s, z)
			var xf := Transform3D(basis, pos)
			trees.add(tree.lod0, xf, 0.0, TREE_NEAR)
			trees.add(tree.lod1, xf, TREE_NEAR, TREE_MID)
			trees.add(tree.lod2, xf, TREE_MID, TREE_FAR, false)
			collision.append([pos, tree.trunk_radius * s * 1.1, 4.0 * s])
			tree_spots.append([pos, pine, s])
			tree_positions.append(pos)
			tree_is_pine.append(1 if pine else 0)

	# --- Sticks and fallen twigs around trees ---
	for spot in tree_spots:
		var count: int = rng.randi_range(1, 3) if spot[1] else rng.randi_range(2, 5)
		for i in count:
			var a := rng.randf() * TAU
			var r: float = rng.randf_range(0.8, 6.0) * spot[2]
			var x: float = spot[0].x + cos(a) * r
			var z: float = spot[0].z + sin(a) * r
			var n := data.normal_at(x, z)
			if data.height_at(x, z) < data.water_level_at(x, z) + 0.1 or data.in_clearing(x, z, 0.8) \
					or (data.forests and data.forests.in_secret(x, z, 2.0)):
				continue
			var xf := Transform3D(ScatterBatch.aligned_basis(n, rng.randf() * TAU, rng.randf_range(0.7, 1.3)), Vector3(x, data.height_at(x, z) - 0.01, z))
			greebles.add(assets.sticks[rng.randi() % assets.sticks.size()], xf, 0.0, GREEBLE_FAR * 0.8, false)

	# --- Rocks, boulders and pebbles ---
	steps = int(half * 2.0 / ROCK_SPACING)
	for zi in steps:
		for xi in steps:
			var x := -half + (xi + rng.randf()) * ROCK_SPACING
			var z := -half + (zi + rng.randf()) * ROCK_SPACING
			var n := data.normal_at(x, z)
			var slope := 1.0 - n.y
			var ctl := data.control_at(x, z)
			var p := 0.025 + smoothstep(0.1, 0.3, slope) * 0.3 + ctl.b * 0.12 + ctl.r * 0.08
			if rng.randf() > p:
				continue
			var h := data.height_at(x, z)
			if h < data.water_level_at(x, z) + 0.05 or data.in_clearing(x, z, 0.75) \
					or (data.forests and data.forests.in_secret(x, z, 2.0)):
				continue
			var up := Vector3.UP.lerp(n, 0.7).normalized()
			if rng.randf() < 0.05:
				var s := rng.randf_range(0.9, 2.4)
				var xf := Transform3D(ScatterBatch.aligned_basis(up, rng.randf() * TAU, s), Vector3(x, h - 0.2 * s, z))
				greebles.add(assets.big_rocks[rng.randi() % assets.big_rocks.size()], xf, 0.0, BOULDER_FAR)
				collision.append([Vector3(x, h, z), 0.55 * s, 0.9 * s])
			else:
				var s := lerpf(0.12, 0.55, pow(rng.randf(), 2.0))
				var xf := Transform3D(ScatterBatch.aligned_basis(up, rng.randf() * TAU, s), Vector3(x, h - 0.12 * s, z))
				greebles.add(assets.rocks[rng.randi() % assets.rocks.size()], xf, 0.0, GREEBLE_FAR, s > 0.3)
			# Pebble clusters on sediment.
			if ctl.r > 0.45 and rng.randf() < 0.6:
				for k in rng.randi_range(3, 6):
					var px := x + rng.randf_range(-0.8, 0.8)
					var pz := z + rng.randf_range(-0.8, 0.8)
					var ps := rng.randf_range(0.04, 0.12)
					var pxf := Transform3D(ScatterBatch.aligned_basis(data.normal_at(px, pz), rng.randf() * TAU, ps), Vector3(px, data.height_at(px, pz) - 0.02, pz))
					greebles.add(assets.rocks[rng.randi() % assets.rocks.size()], pxf, 0.0, GREEBLE_FAR * 0.5, false)

	var tree_count := tree_spots.size()
	var greeble_count := greebles.count()
	trees.build(self)
	greebles.build(self)
	_build_collision(collision)
	print("Vegetation: %d trees, %d greebles in %d ms" % [tree_count, greeble_count, Time.get_ticks_msec() - t0])


## Trunk and boulder colliders straight on the PhysicsServer (thousands of nodes otherwise).
func _build_collision(items: Array) -> void:
	var space := get_world_3d().space
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body, space)
	_bodies.append(body)
	var shape_cache := {}
	for it in items:
		var radius := maxf(snappedf(it[1], 0.05), 0.1)
		var height := maxf(snappedf(it[2], 0.5), 0.5)
		var key := Vector2(radius, height)
		var shape: RID = shape_cache.get(key, RID())
		if not shape.is_valid():
			shape = PhysicsServer3D.cylinder_shape_create()
			PhysicsServer3D.shape_set_data(shape, {"radius": radius, "height": height})
			shape_cache[key] = shape
			_shapes.append(shape)
		var pos: Vector3 = it[0]
		PhysicsServer3D.body_add_shape(body, shape, Transform3D(Basis.IDENTITY, pos + Vector3.UP * height * 0.5))


func _exit_tree() -> void:
	for b in _bodies:
		PhysicsServer3D.free_rid(b)
	for s in _shapes:
		PhysicsServer3D.free_rid(s)
	_bodies.clear()
	_shapes.clear()
