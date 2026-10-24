class_name ShroomField
extends Node3D
## Clusters of mushrooms around the map: one big Bounceshroom each (standing along the ground's
## normal, so on a slope it throws its rider sideways) ringed by a few small decorative ones in
## mixed colours. Sites: dry, not too steep, not rocky, outside clearings and away from tree
## trunks and other clusters; the first cluster is put near the waystone circle. Seeded only
## (world generation must be identical on every client).

const CLUSTERS := 36
const MIN_SPACING := 70.0
const MARGIN := 60.0
const TREE_CLEARANCE := 3.5
const TREE_CELL := 8.0
const MAX_ATTEMPTS := 1500


func build(data: TerrainData, seed: int, trees: PackedVector3Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var grid := {}
	for t in trees:
		var key := Vector2i(floori(t.x / TREE_CELL), floori(t.z / TREE_CELL))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(Vector2(t.x, t.z))
	var half := data.world_size() * 0.5 - MARGIN
	var placed: Array[Vector2] = []
	var attempts := 0
	while placed.size() < CLUSTERS and attempts < MAX_ATTEMPTS:
		attempts += 1
		var p: Vector2
		if placed.is_empty() and not data.clearings.is_empty() and attempts < 200:
			# The first one within a short walk of the waystone circle.
			var c := data.clearings[0]
			var a := rng.randf() * TAU
			p = Vector2(c.x, c.y) + Vector2(cos(a), sin(a)) * (c.z + rng.randf_range(6.0, 25.0))
		else:
			p = Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half))
		if not _site_ok(data, p, grid, placed):
			continue
		placed.append(p)
		_cluster(data, rng, p)


func _site_ok(data: TerrainData, p: Vector2, grid: Dictionary, placed: Array[Vector2]) -> bool:
	if not data.is_inside(p.x, p.y, MARGIN) or data.water_level_at(p.x, p.y) > -INF:
		return false
	if _normal(data, p).y < 0.9 or data.rock_at(p.x, p.y) > 0.4 or data.in_clearing(p.x, p.y, 1.1) \
			or (data.forests and data.forests.in_secret(p.x, p.y, 15.0)):
		return false
	for q in placed:
		if q.distance_to(p) < MIN_SPACING:
			return false
	var cell := Vector2i(floori(p.x / TREE_CELL), floori(p.y / TREE_CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for t in grid.get(cell + Vector2i(dx, dz), []):
				if (t as Vector2).distance_to(p) < TREE_CLEARANCE:
					return false
	return true


## Ground normal averaged over a couple of metres (the mushroom stands on its whole foot).
func _normal(data: TerrainData, p: Vector2) -> Vector3:
	const E := 1.5
	var hl := data.height_at(p.x - E, p.y)
	var hr := data.height_at(p.x + E, p.y)
	var hd := data.height_at(p.x, p.y - E)
	var hu := data.height_at(p.x, p.y + E)
	return Vector3(hl - hr, 2.0 * E, hd - hu).normalized()


func _cluster(data: TerrainData, rng: RandomNumberGenerator, p: Vector2) -> void:
	var up := _normal(data, p)
	Bounceshroom.spawn(self, Vector3(p.x, data.height_at(p.x, p.y) - 0.05, p.y), up, rng.randf() * TAU)
	for i in rng.randi_range(4, 8):
		var a := rng.randf() * TAU
		var q := p + Vector2(cos(a), sin(a)) * rng.randf_range(2.0, 4.8)
		if data.water_level_at(q.x, q.y) > -INF:
			continue
		var n := (_normal(data, q) + Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))).normalized()
		var size := lerpf(0.12, 0.48, pow(rng.randf(), 1.5))
		Bounceshroom.small(self, Vector3(q.x, data.height_at(q.x, q.y) - 0.03, q.y), n, rng.randf() * TAU, size,
			rng.randi() % 3)
