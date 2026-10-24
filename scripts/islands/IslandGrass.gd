class_name IslandGrass
extends RefCounted
## Grass and flowers on the top of a walkable floating island. The terrain's GrassField places
## its blades from the terrain heightmap, so islands get their own: clumps scattered on the CPU
## over the island top (sampled on a 1 m grid from IslandShape.top_y, only inside the rim and on
## gentle slopes), binned into CHUNK-sized MultiMeshes with visibility ranges so only the patches
## near the camera are drawn. shaders/island_grass.gdshader colours them like the island's
## ground and adds wind, the player push and the distance fade. Follows the "grass_density"
## setting like the terrain grass.

const SHADER := preload("res://shaders/island_grass.gdshader")
const CHUNK := 16.0
## Ground steeper than this (normal.y in island space) stays bare, like the island shader's rock.
const MIN_UP := 0.78
# name, clumps per m², fade start/end, scale min/max, kind (0 grass, 1 flowers), wind,
# patch threshold (-1 = everywhere), optional (hidden on "low")
const LAYERS := [
	["short", 10.0, 22.0, 30.0, 0.7, 1.3, 0, 0.18, -1.0, false],
	["tall", 0.35, 32.0, 40.0, 0.75, 1.3, 0, 0.22, 0.1, false],
	["tuft", 0.3, 32.0, 40.0, 0.7, 1.2, 0, 0.14, -0.1, true],
	["daisy", 0.2, 24.0, 31.0, 1.1, 1.7, 1, 0.1, 0.2, false],
	["bell", 0.12, 24.0, 31.0, 1.1, 1.6, 1, 0.1, 0.25, true],
]

static var _materials: Array[ShaderMaterial] = []
static var _meshes: Array[Mesh] = []
static var _nodes: Array = []  # [MultiMeshInstance3D, layer index] of every island, for the setting
static var _connected := false


static func build(island: FloatingIsland) -> void:
	_init_shared()
	var shape := island.shape
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(island.position.round()))
	var patches := FastNoiseLite.new()
	patches.seed = rng.randi()
	patches.frequency = 0.06
	# Height and walkable mask of the top on a 1 m grid.
	var ext := ceili(shape.radius * (1.0 + shape.outline_amp) + 2.0)
	var n := ext * 2 + 1
	var heights := PackedFloat32Array()
	var inside := PackedByteArray()
	heights.resize(n * n)
	inside.resize(n * n)
	for gz in n:
		for gx in n:
			var x := float(gx - ext)
			var z := float(gz - ext)
			var i := gz * n + gx
			var rim := shape.rim_radius(atan2(z, x))
			var ok := Vector2(x, z).length() < rim * 0.95
			inside[i] = 1 if ok else 0
			heights[i] = shape.top_y(x, z) if ok else 0.0
	# Per layer, per chunk: instance data (12 floats transform + 4 custom). Plain Arrays: a packed
	# array fetched from a Dictionary is a copy, appending to it would be lost.
	var chunks := {}
	for li in LAYERS.size():
		var layer: Array = LAYERS[li]
		var per_cell: float = layer[1]
		for gz in n - 1:
			for gx in n - 1:
				var i := gz * n + gx
				if inside[i] == 0 or inside[i + 1] == 0 or inside[i + n] == 0 or inside[i + n + 1] == 0:
					continue
				var h00 := heights[i]
				var h10 := heights[i + 1]
				var h01 := heights[i + n]
				var h11 := heights[i + n + 1]
				var up := Vector3(h00 - h10 + h01 - h11, 2.0, h00 - h01 + h10 - h11).normalized()
				if up.y < MIN_UP:
					continue
				var count := int(per_cell) + (1 if rng.randf() < per_cell - floorf(per_cell) else 0)
				for k in count:
					var fx := rng.randf()
					var fz := rng.randf()
					var x := gx - ext + fx
					var z := gz - ext + fz
					if layer[8] > -1.0 and patches.get_noise_2d(x + li * 97.0, z) < layer[8]:
						continue
					var h := lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz) - 0.03
					var yaw := rng.randf() * TAU
					var sc := rng.randf_range(layer[4], layer[5])
					var key := Vector3i(li, floori(x / CHUNK), floori(z / CHUNK))
					if not chunks.has(key):
						chunks[key] = []
					var c := cos(yaw) * sc
					var s := sin(yaw) * sc
					(chunks[key] as Array).append_array([c, 0.0, s, x, 0.0, sc, 0.0, h, -s, 0.0, c, z,
						x, z, rng.randf(), rng.randf()])
	var seed: float = island.get_strata_seed()
	var up_axis := island.global_basis.y.normalized() if island.is_inside_tree() else island.basis.y.normalized()
	for key in chunks:
		var data := PackedFloat32Array(chunks[key])
		var li: int = key.x
		var layer: Array = LAYERS[li]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _meshes[li]
		mm.instance_count = data.size() / 16
		mm.buffer = data
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Grass_%s" % layer[0]
		mmi.multimesh = mm
		mmi.material_override = _materials[li]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = layer[3] + CHUNK * 0.75
		mmi.set_instance_shader_parameter("strata_seed", seed)
		mmi.set_instance_shader_parameter("island_up", up_axis)
		island.add_child(mmi)
		_nodes.append([mmi, li])
	_apply_density(Settings.get_value("grass_density"))


static func _init_shared() -> void:
	if not _materials.is_empty():
		return
	var albedo := ResourcePacks.texture("grass_albedo.png")
	var macro := ResourcePacks.texture("macro_albedo.png")
	for layer in LAYERS:
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("grass_albedo", albedo)
		mat.set_shader_parameter("macro_noise", macro)
		mat.set_shader_parameter("fade_start", layer[2])
		mat.set_shader_parameter("fade_end", layer[3])
		mat.set_shader_parameter("kind", layer[6])
		mat.set_shader_parameter("wind_strength", layer[7])
		_materials.append(mat)
		_meshes.append(_mesh(layer[0]))
	if not _connected:
		_connected = true
		Settings.setting_changed.connect(func(key: String, value: Variant) -> void:
			if key == "grass_density":
				_apply_density(value))


## Islands of a previous world (scene reload) are gone: drop them, and rebuild the materials
## when the resource pack changes.
static func reset() -> void:
	_nodes.clear()
	_materials.clear()
	_meshes.clear()


## 0 off, 1 low, 2 medium, 3 high (like GrassField).
static func _apply_density(level: int) -> void:
	var scale: float = [0.0, 0.45, 0.75, 1.0][clampi(level, 0, 3)]
	for mat in _materials:
		mat.set_shader_parameter("density", scale)
	for entry in _nodes:
		var mmi: MultiMeshInstance3D = entry[0]
		if is_instance_valid(mmi):
			mmi.visible = level > 0 and not (level == 1 and LAYERS[entry[1]][9])


static func _mesh(kind: String) -> Mesh:
	match kind:
		"short":
			return GrassMeshes.blade_clump(11, 9, 0.14, 0.45, 0.04, 3, 0.13, 0.35)
		"tall":
			return GrassMeshes.blade_clump(13, 16, 0.45, 0.95, 0.03, 4, 0.2, 0.45)
		"tuft":
			return GrassMeshes.blade_clump(14, 8, 0.25, 0.5, 0.075, 3, 0.1, 0.8)
		"daisy":
			return GrassMeshes.flower(16, 0)
		_:
			return GrassMeshes.flower(17, 1)
