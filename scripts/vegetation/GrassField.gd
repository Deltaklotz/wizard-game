class_name GrassField
extends Node3D
## Ground cover around the player: dense short grass, a sparser mid-range ring,
## clumps of tall grass bundles and scattered flowers. Each layer is one MultiMesh grid
## that snaps to the camera; the grass shader does placement, fading and wind.

# name, mesh builder, spacing, grid extent, hole start/end, fade start/end, density,
# patch threshold, patch frequency, scale min/max, kind (0 grass, 1 flowers), wind
const LAYERS := [
	["short", "short", 0.21, 40.0, -2.0, -1.0, 13.0, 19.0, 1.0, -1.0, 0.05, 0.6, 1.2, 0, 0.18],
	["short_far", "short_far", 0.6, 100.0, 13.0, 19.0, 36.0, 47.0, 1.0, -1.0, 0.05, 1.0, 1.5, 0, 0.12],
	["tall", "tall", 1.25, 80.0, -2.0, -1.0, 30.0, 39.0, 0.55, 0.52, 0.045, 0.75, 1.3, 0, 0.22],
	["tuft", "tuft", 1.7, 80.0, -2.0, -1.0, 30.0, 39.0, 0.4, 0.45, 0.06, 0.7, 1.2, 0, 0.14],
	["seeds", "seeds", 2.2, 80.0, -2.0, -1.0, 30.0, 39.0, 0.5, 0.55, 0.035, 0.8, 1.2, 0, 0.25],
	["daisy", "daisy", 1.3, 64.0, -2.0, -1.0, 24.0, 31.0, 0.35, 0.5, 0.08, 1.1, 1.7, 1, 0.1],
	["bell", "bell", 1.9, 64.0, -2.0, -1.0, 24.0, 31.0, 0.3, 0.52, 0.07, 1.1, 1.6, 1, 0.1],
	["umbel", "umbel", 1.7, 64.0, -2.0, -1.0, 24.0, 31.0, 0.3, 0.48, 0.06, 1.1, 1.7, 1, 0.12],
]

## Per grass density (off, low, medium, high): grid spacing and range multipliers. Lower
## levels use a coarser grid over a shorter range, so the GPU really processes fewer clumps
## (~22 % at Low, ~50 % at Medium) instead of just rejecting them in the shader; clumps grow a
## little to make up for it.
const SPACING_SCALE := [1.0, 1.5, 1.2, 1.0]
const RANGE_SCALE := [1.0, 0.7, 0.85, 1.0]
const SIZE_SCALE := [1.0, 1.2, 1.08, 1.0]

var _layers: Array = []  # [MultiMeshInstance3D, spacing (current), layer config]
var _y_range := Vector2.ZERO


func setup(terrain: Terrain) -> void:
	var shader := preload("res://shaders/grass.gdshader")
	var shared := ["heightmap", "control_map", "rock_map", "detail_noise", "macro_noise", "terrain_origin",
		"terrain_res", "cell_size", "grass_albedo", "grass_tiling", "flat_zone"]
	var data := terrain.data
	var seed_offset := 0.0
	for layer in LAYERS:
		var spacing: float = layer[2]
		var mat := ShaderMaterial.new()
		mat.shader = shader
		for p in shared:
			mat.set_shader_parameter(p, terrain.material.get_shader_parameter(p))
		mat.set_shader_parameter("spacing", spacing)
		mat.set_shader_parameter("seed_offset", seed_offset)
		mat.set_shader_parameter("hole_start", layer[4])
		mat.set_shader_parameter("hole_end", layer[5])
		mat.set_shader_parameter("fade_start", layer[6])
		mat.set_shader_parameter("fade_end", layer[7])
		mat.set_shader_parameter("density", layer[8])
		mat.set_shader_parameter("patch_threshold", layer[9])
		mat.set_shader_parameter("patch_freq", layer[10])
		mat.set_shader_parameter("scale_min", layer[11])
		mat.set_shader_parameter("scale_max", layer[12])
		mat.set_shader_parameter("kind", layer[13])
		mat.set_shader_parameter("wind_strength", layer[14])
		if not data.lakes.is_empty():
			var lake := data.lakes[0]
			mat.set_shader_parameter("lake_params", Vector4(lake.center.x, lake.center.y, lake.outer_radius(), lake.level))
		seed_offset += 17.31

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _mesh(layer[1])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Grass_" + layer[0]
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_layers.append([mmi, spacing, layer])
	_y_range = Vector2(data.min_height - 5.0, data.max_height + 5.0)
	Settings.setting_changed.connect(_on_setting_changed)
	_apply_density(Settings.get_value("grass_density"))


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "grass_density":
		_apply_density(value)


## 0 off, 1 low, 2 medium, 3 high.
func _apply_density(level: int) -> void:
	level = clampi(level, 0, 3)
	for l in _layers:
		var mmi: MultiMeshInstance3D = l[0]
		var layer: Array = l[2]
		var optional: bool = layer[0] in ["tuft", "seeds", "umbel"]
		mmi.visible = level > 0 and not (level == 1 and optional)
		if not mmi.visible:
			continue
		var spacing: float = layer[2] * SPACING_SCALE[level]
		var reach: float = RANGE_SCALE[level]
		_build_grid(mmi.multimesh, spacing, layer[3] * reach)
		l[1] = spacing
		var extent: float = layer[3] * reach
		mmi.custom_aabb = AABB(Vector3(-extent * 0.5, _y_range.x, -extent * 0.5), Vector3(extent, _y_range.y - _y_range.x, extent))
		var mat := mmi.material_override as ShaderMaterial
		mat.set_shader_parameter("spacing", spacing)
		for i in 4:
			var key: String = ["hole_start", "hole_end", "fade_start", "fade_end"][i]
			var v: float = layer[4 + i]
			mat.set_shader_parameter(key, v * reach if v > 0.0 else v)
		mat.set_shader_parameter("scale_min", layer[11] * SIZE_SCALE[level])
		mat.set_shader_parameter("scale_max", layer[12] * SIZE_SCALE[level])
		mat.set_shader_parameter("density", layer[8])


## Whole-cell offsets: with the node snapped to the same spacing, every grid point lands
## exactly on a world cell, so the shader's cell lookup never flips.
func _build_grid(mm: MultiMesh, spacing: float, extent: float) -> void:
	var n := int(extent / spacing)
	if mm.instance_count == n * n and mm.has_meta("spacing") and is_equal_approx(mm.get_meta("spacing"), spacing):
		return
	mm.set_meta("spacing", spacing)
	mm.instance_count = n * n
	var half := n / 2
	for z in n:
		for x in n:
			mm.set_instance_transform(z * n + x, Transform3D(Basis.IDENTITY, Vector3((x - half) * spacing, 0.0, (z - half) * spacing)))


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	for l in _layers:
		var spacing: float = l[1]
		(l[0] as Node3D).global_position = Vector3(snappedf(p.x, spacing), 0.0, snappedf(p.z, spacing))


func _mesh(kind: String) -> Mesh:
	match kind:
		"short":
			return GrassMeshes.blade_clump(11, 9, 0.14, 0.45, 0.04, 3, 0.13, 0.35)
		"short_far":
			return GrassMeshes.blade_clump(12, 6, 0.16, 0.34, 0.05, 1, 0.22, 0.3)
		"tall":
			return GrassMeshes.blade_clump(13, 16, 0.45, 0.95, 0.03, 4, 0.2, 0.45)
		"tuft":
			return GrassMeshes.blade_clump(14, 8, 0.25, 0.5, 0.075, 3, 0.1, 0.8)
		"seeds":
			return GrassMeshes.seed_grass(15)
		"daisy":
			return GrassMeshes.flower(16, 0)
		"bell":
			return GrassMeshes.flower(17, 1)
		_:
			return GrassMeshes.flower(18, 2)
