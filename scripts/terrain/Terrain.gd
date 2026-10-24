class_name Terrain
extends Node3D
## Renders a TerrainData as GPU-displaced chunks with distance LODs, plus collision.
## Every chunk of a LOD level shares one flat grid mesh; the vertex shader reads the
## heightmap, so building the terrain costs almost nothing on the CPU.

const CHUNK := 64
## [vertex step (m), visible from, visible to] (0 = unlimited). The 0.5 m ring carries the
## close-range detail displacement, which has faded out before the next ring starts.
const LODS := [[0.5, 0.0, 85.0], [1.0, 85.0, 170.0], [2.0, 170.0, 330.0], [4.0, 330.0, 650.0], [8.0, 650.0, 0.0]]
const SKIRT_DEPTH := 4.0

var data: TerrainData
var material: ShaderMaterial


func build(d: TerrainData) -> void:
	data = d
	_create_material()
	_build_chunks()
	_build_collision()
	_build_backdrop()


func _process(_delta: float) -> void:
	# Centre of the close-range detail (and grass) for every terrain-aware shader.
	var cam := get_viewport().get_camera_3d()
	if cam:
		RenderingServer.global_shader_parameter_set("player_position", cam.global_position)


func _create_material() -> void:
	material = ShaderMaterial.new()
	GraphicsQuality.use(material, preload("res://shaders/terrain.gdshader"), preload("res://shaders/terrain_lite.gdshader"))
	var hm := Image.create_from_data(data.resolution, data.resolution, false, Image.FORMAT_RF, data.heights.to_byte_array())
	material.set_shader_parameter("heightmap", ImageTexture.create_from_image(hm))
	var ctl := data.control.duplicate() as Image
	ctl.generate_mipmaps()
	material.set_shader_parameter("control_map", ImageTexture.create_from_image(ctl))
	material.set_shader_parameter("terrain_origin", data.origin())
	material.set_shader_parameter("terrain_res", float(data.resolution))
	material.set_shader_parameter("cell_size", data.cell_size)
	for c in data.clearings:
		material.set_shader_parameter("flat_zone", Vector4(c.x, c.y, c.w, 3.0))
	material.set_shader_parameter("skirt_depth", SKIRT_DEPTH)
	for tex in ["grass", "rock", "dirt", "snow", "moss"]:
		material.set_shader_parameter(tex + "_albedo", ResourcePacks.texture(tex + "_albedo.png"))
		material.set_shader_parameter(tex + "_normal", ResourcePacks.texture(tex + "_normal.png"))
	material.set_shader_parameter("macro_noise", ResourcePacks.texture("macro_albedo.png"))
	material.set_shader_parameter("detail_noise", ResourcePacks.texture("detail_albedo.png"))
	material.set_shader_parameter("rock_map", ImageTexture.create_from_image(data.rock))


func _build_chunks() -> void:
	var cells := data.resolution - 1
	var count := cells / CHUNK
	var meshes: Array[ArrayMesh] = []
	for lod in LODS:
		meshes.append(_grid_mesh(int(CHUNK / float(lod[0]))))
	var origin := data.origin()
	for cz in count:
		for cx in count:
			var range_y := _chunk_height_range(cx * CHUNK, cz * CHUNK)
			# Padded for the close-range detail displacement.
			var aabb := AABB(Vector3(0, range_y.x - SKIRT_DEPTH - 1.5, 0), Vector3(CHUNK * data.cell_size, range_y.y - range_y.x + SKIRT_DEPTH + 3.0, CHUNK * data.cell_size))
			var pos := Vector3(origin.x + cx * CHUNK * data.cell_size, 0.0, origin.y + cz * CHUNK * data.cell_size)
			for i in LODS.size():
				var mi := MeshInstance3D.new()
				mi.mesh = meshes[i]
				mi.material_override = material
				mi.position = pos
				mi.custom_aabb = aabb
				mi.visibility_range_begin = LODS[i][1]
				mi.visibility_range_end = LODS[i][2]
				mi.visibility_range_begin_margin = 0.0
				mi.visibility_range_end_margin = 0.0
				add_child(mi)


func _chunk_height_range(x0: int, z0: int) -> Vector2:
	var lo := INF
	var hi := -INF
	var res := data.resolution
	for z in range(z0, z0 + CHUNK + 1):
		var row := z * res
		for x in range(x0, x0 + CHUNK + 1, 2):
			var h := data.heights[row + x]
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return Vector2(lo - 1.0, hi + 1.0)


## Flat n x n grid with a skirt ring (UV.x = 1) that the shader pushes down.
func _grid_mesh(n: int) -> ArrayMesh:
	var step := float(CHUNK) / n * data.cell_size
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for z in n + 1:
		for x in n + 1:
			verts.append(Vector3(x * step, 0.0, z * step))
			uvs.append(Vector2.ZERO)
	for z in n:
		for x in n:
			var a := z * (n + 1) + x
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	# Skirt: duplicate the border vertices and connect them with two-sided strips.
	var border: Array[int] = []
	for x in n + 1:
		border.append(x)
	for z in range(1, n + 1):
		border.append(z * (n + 1) + n)
	for x in range(n - 1, -1, -1):
		border.append(n * (n + 1) + x)
	for z in range(n - 1, 0, -1):
		border.append(z * (n + 1))
	var base := verts.size()
	for i in border:
		verts.append(verts[i])
		uvs.append(Vector2(1.0, 0.0))
	for k in border.size():
		var k2 := (k + 1) % border.size()
		var top_a := border[k]
		var top_b := border[k2]
		var bot_a := base + k
		var bot_b := base + k2
		idx.append_array([top_a, top_b, bot_a, top_b, bot_b, bot_a])
		idx.append_array([top_a, bot_a, top_b, top_b, bot_a, bot_b])
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	var shape := HeightMapShape3D.new()
	shape.map_width = data.resolution
	shape.map_depth = data.resolution
	# HeightMapShape3D is centered with 1 unit spacing; for other cell sizes the shape is
	# scaled uniformly, so heights are pre-divided to compensate.
	var heights := data.heights
	if not is_equal_approx(data.cell_size, 1.0):
		heights = heights.duplicate()
		for i in heights.size():
			heights[i] /= data.cell_size
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * data.cell_size
	body.add_child(cs)
	add_child(body)


## Ring of distant, non-playable mountains so the horizon never shows the map edge.
func _build_backdrop() -> void:
	const EXTENT := 2600.0
	const STEP := 40.0
	var n := int(EXTENT * 2.0 / STEP)
	var half := data.world_size() * 0.5
	var noise := FastNoiseLite.new()
	noise.seed = 4242
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.fractal_octaves = 5
	noise.frequency = 0.0014
	var hidden := data.min_height - 60.0
	var heights := PackedFloat32Array()
	heights.resize((n + 1) * (n + 1))
	for zi in n + 1:
		for xi in n + 1:
			var x := -EXTENT + xi * STEP
			var z := -EXTENT + zi * STEP
			var outside := maxf(absf(x), absf(z)) - half
			var h := hidden
			if outside > -STEP * 0.5:
				var edge_h := data.height_at(clampf(x, -half, half), clampf(z, -half, half)) - 6.0
				var ridge := noise.get_noise_2d(x, z) * 0.5 + 0.5
				var mountain := 150.0 + ridge * 280.0 * (0.6 + 0.4 * smoothstep(0.0, 1200.0, outside))
				h = lerpf(edge_h, mountain, smoothstep(0.0, 260.0, outside))
			heights[zi * (n + 1) + xi] = h
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for zi in n + 1:
		for xi in n + 1:
			var i := zi * (n + 1) + xi
			verts.append(Vector3(-EXTENT + xi * STEP, heights[i], -EXTENT + zi * STEP))
			var hl := heights[i - 1] if xi > 0 else heights[i]
			var hr := heights[i + 1] if xi < n else heights[i]
			var hd := heights[i - n - 1] if zi > 0 else heights[i]
			var hu := heights[i + n + 1] if zi < n else heights[i]
			normals.append(Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized())
	for zi in n:
		for xi in n:
			var a := zi * (n + 1) + xi
			idx.append_array([a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/backdrop.gdshader")
	for tex in ["rock", "grass", "snow"]:
		mat.set_shader_parameter(tex + "_albedo", ResourcePacks.texture(tex + "_albedo.png"))
	mat.set_shader_parameter("macro_noise", ResourcePacks.texture("macro_albedo.png"))
	var mi := MeshInstance3D.new()
	mi.name = "Backdrop"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
