class_name IslandField
extends Node3D
## Places groups of floating islands. Groups are spread out (Poisson-disk) so they are
## neither rare nor everywhere, and each group picks a different composition:
##   monolith     - one huge island ringed by small satellites
##   twins        - two large islands at different heights, plus satellites
##   archipelago  - an arc of medium islands with small ones between
##   shard_spiral - one medium island with a rising spiral of small shards
##   lone         - a single medium/large island with a couple of stragglers
## Extra groups float outside the playable area to fill the skyline.

const INNER_GROUP_SPACING := 340.0
const INNER_EXTENT := 360.0
const OUTER_GROUPS := 5

var islands: Array[FloatingIsland] = []

var _placed: Array = []  # [Vector3 center, radius] of every island, for overlap checks


func build(data: TerrainData, seed: int) -> void:
	var t0 := Time.get_ticks_msec()
	IslandGrass.reset()
	for mesh in VegetationAssets.get_shared().big_rocks:
		FloatingIsland.prewarm_hull(mesh)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mats := _materials()

	var centers: Array[Vector2] = []
	for attempt in 400:
		var c := Vector2(rng.randf_range(-INNER_EXTENT, INNER_EXTENT), rng.randf_range(-INNER_EXTENT, INNER_EXTENT))
		var ok := true
		for o in centers:
			if o.distance_to(c) < INNER_GROUP_SPACING:
				ok = false
				break
		if ok:
			centers.append(c)
	var kinds := ["monolith", "twins", "archipelago", "shard_spiral", "lone"]
	# Seeded shuffle (Array.shuffle() uses the global RNG, so every client got different islands).
	for i in range(kinds.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: String = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = tmp
	var group_index := 0
	for c in centers:
		# Cycle through the kinds first so every composition shows up, then pick randomly.
		var kind: String = kinds[group_index] if group_index < kinds.size() else kinds[rng.randi() % kinds.size()]
		var ground := _max_ground(data, c, 140.0)
		_build_group(data, rng, mats, kind, Vector3(c.x, ground + rng.randf_range(70.0, 120.0), c.y), true)
		group_index += 1

	# Skyline groups beyond the border mountains.
	var a0 := rng.randf() * TAU
	for i in OUTER_GROUPS:
		var a := a0 + TAU * i / OUTER_GROUPS + rng.randf_range(-0.3, 0.3)
		var dist := rng.randf_range(700.0, 1100.0)
		var kind: String = ["monolith", "twins", "archipelago", "lone"][rng.randi() % 4]
		_build_group(data, rng, mats, kind, Vector3(cos(a) * dist, rng.randf_range(280.0, 380.0), sin(a) * dist), false)
	print("Sky islands: %d islands in %d groups, %d ms" % [islands.size(), centers.size() + OUTER_GROUPS, Time.get_ticks_msec() - t0])


func _build_group(data: TerrainData, rng: RandomNumberGenerator, mats: Dictionary, kind: String, center: Vector3, inside: bool) -> void:
	var specs: Array = []  # [offset Vector3, radius]
	match kind:
		"monolith":
			var big := rng.randf_range(38.0, 58.0)
			specs.append([Vector3.ZERO, big])
			_satellites(rng, specs, Vector3.ZERO, big, rng.randi_range(5, 9), 3.0, 9.0)
		"twins":
			var r1 := rng.randf_range(24.0, 36.0)
			var r2 := rng.randf_range(20.0, 32.0)
			var dir := Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU)
			var gap := r1 + r2 + rng.randf_range(12.0, 35.0)
			var o1 := -dir * gap * 0.5
			var o2 := dir * gap * 0.5 + Vector3.UP * rng.randf_range(15.0, 35.0) * (1.0 if rng.randf() < 0.5 else -1.0)
			specs.append([o1, r1])
			specs.append([o2, r2])
			_satellites(rng, specs, o1, r1, rng.randi_range(2, 4), 3.0, 8.0)
			_satellites(rng, specs, o2, r2, rng.randi_range(2, 4), 3.0, 8.0)
		"archipelago":
			var n := rng.randi_range(3, 4)
			var arc_r := rng.randf_range(50.0, 80.0)
			var a0 := rng.randf() * TAU
			for i in n:
				var a := a0 + i * rng.randf_range(0.6, 0.9)
				var r := rng.randf_range(12.0, 22.0)
				var o := Vector3(cos(a) * arc_r, rng.randf_range(-18.0, 18.0), sin(a) * arc_r)
				specs.append([o, r])
				_satellites(rng, specs, o, r, rng.randi_range(1, 3), 2.5, 6.0)
		"shard_spiral":
			var r := rng.randf_range(15.0, 24.0)
			specs.append([Vector3.ZERO, r])
			var count := rng.randi_range(8, 14)
			var a := rng.randf() * TAU
			var dist := r + 8.0
			var y := -r * 0.8
			for i in count:
				a += rng.randf_range(0.45, 0.75)
				dist += rng.randf_range(2.0, 5.0)
				y += rng.randf_range(2.0, 5.0)
				specs.append([Vector3(cos(a) * dist, y, sin(a) * dist), rng.randf_range(2.0, 5.5)])
		_:
			var r := rng.randf_range(20.0, 32.0)
			specs.append([Vector3.ZERO, r])
			_satellites(rng, specs, Vector3.ZERO, r, rng.randi_range(2, 3), 3.0, 7.0)

	# Random orientation of the whole composition.
	var yaw := rng.randf() * TAU
	for spec in specs:
		var pos: Vector3 = center + (spec[0] as Vector3).rotated(Vector3.UP, yaw)
		var radius: float = spec[1]
		if _overlaps(pos, radius):
			continue
		var shape := IslandShape.random(rng, radius)
		if inside:
			# Keep the bottom well clear of the terrain underneath.
			var ground := _max_ground(data, Vector2(pos.x, pos.z), radius * 1.2)
			pos.y = maxf(pos.y, ground + 18.0 - shape.bottom_y())
		var island := FloatingIsland.new()
		island.name = "Island_%d" % islands.size()
		island.position = pos
		var tilt := deg_to_rad(rng.randf_range(0.0, 2.0) if radius > 15.0 else rng.randf_range(2.0, 10.0))
		island.basis = Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, tilt)
		add_child(island)
		# Every island inside the map can be stood on; the small ones bob (moving collider).
		island.setup(shape, rng, mats, inside, radius < 12.0)
		if radius < 12.0:
			island.start_bobbing(rng)
		islands.append(island)
		_placed.append([pos, radius])


func _satellites(rng: RandomNumberGenerator, specs: Array, around: Vector3, main_r: float, count: int, rmin: float, rmax: float) -> void:
	for i in count:
		var a := rng.randf() * TAU
		var d := main_r + rng.randf_range(6.0, main_r * 1.3 + 12.0)
		var y := rng.randf_range(-main_r * 0.9, main_r * 0.25)
		specs.append([around + Vector3(cos(a) * d, y, sin(a) * d), rng.randf_range(rmin, rmax)])


func _overlaps(pos: Vector3, radius: float) -> bool:
	for p in _placed:
		var o: Vector3 = p[0]
		var d := Vector2(o.x - pos.x, o.z - pos.z).length()
		if d < (radius + p[1]) * 1.05 + 3.0 and absf(o.y - pos.y) < (radius + p[1]) * 1.2:
			return true
	return false


func _max_ground(data: TerrainData, c: Vector2, r: float) -> float:
	var m := -INF
	for i in 9:
		for j in 9:
			var p := c + Vector2(i - 4, j - 4) / 4.0 * r
			if data.is_inside(p.x, p.y):
				m = maxf(m, data.height_at(p.x, p.y))
	return m if m > -INF else 0.0


func _materials() -> Dictionary:
	var island := ShaderMaterial.new()
	GraphicsQuality.use(island, preload("res://shaders/island.gdshader"), preload("res://shaders/island_lite.gdshader"))
	for t in ["grass", "rock", "dirt", "moss"]:
		island.set_shader_parameter(t + "_albedo", ResourcePacks.texture(t + "_albedo.png"))
		island.set_shader_parameter(t + "_normal", ResourcePacks.texture(t + "_normal.png"))
	island.set_shader_parameter("macro_noise", ResourcePacks.texture("macro_albedo.png"))

	var root := StandardMaterial3D.new()
	root.albedo_texture = ResourcePacks.texture("bark_oak_albedo.png")
	root.normal_enabled = true
	root.normal_texture = ResourcePacks.texture("bark_oak_normal.png")
	root.albedo_color = Color(0.7, 0.6, 0.5)
	root.roughness = 0.95

	var crystal := StandardMaterial3D.new()
	crystal.albedo_color = Color(0.45, 0.3, 0.95)
	crystal.metallic = 0.3
	crystal.roughness = 0.1
	crystal.emission_enabled = true
	crystal.emission = Color(0.55, 0.35, 1.0)
	crystal.emission_energy_multiplier = 2.5
	crystal.rim_enabled = true
	crystal.rim = 0.6

	var mote := StandardMaterial3D.new()
	mote.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mote.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote.vertex_color_use_as_albedo = true
	mote.albedo_color = Color(0.75, 0.65, 1.0)
	mote.emission_enabled = true
	mote.emission = Color(0.6, 0.5, 1.0)
	mote.emission_energy_multiplier = 3.0
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = g
	mote.albedo_texture = dot
	return {"island": island, "root": root, "crystal": crystal, "mote": mote}
