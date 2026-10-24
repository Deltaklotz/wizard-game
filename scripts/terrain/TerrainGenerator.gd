class_name TerrainGenerator
extends RefCounted
## GPU terrain pipeline:
##   1. layered noise heightmap, at coarse and full resolution  (terrain_height.glsl)
##   2. coarse hydraulic erosion -> valleys and drainage         (terrain_erosion.glsl)
##   3. upsample the coarse erosion onto the full-res map        (terrain_apply_coarse.glsl)
##   4. fine hydraulic erosion -> small rills                    (terrain_erosion.glsl)
##   5. thermal erosion -> scree slopes                          (terrain_thermal.glsl)
##   6. rock outcrops: terraced risers, ledges, stone relief     (terrain_outcrop.glsl)
##   7. finalize heights + erosion maps                          (terrain_finalize.glsl)

const SHADER_HEIGHT := "res://shaders/compute/terrain_height.glsl"
const SHADER_EROSION := "res://shaders/compute/terrain_erosion.glsl"
const SHADER_APPLY := "res://shaders/compute/terrain_apply_coarse.glsl"
const SHADER_THERMAL := "res://shaders/compute/terrain_thermal.glsl"
const SHADER_OUTCROP := "res://shaders/compute/terrain_outcrop.glsl"
const SHADER_FINALIZE := "res://shaders/compute/terrain_finalize.glsl"


static func generate(s: TerrainSettings) -> TerrainData:
	var gpu := GpuCompute.new()
	if not gpu.is_valid():
		push_error("Terrain generation needs the Forward+ or Mobile renderer (compute shaders).")
		return null
	var t0 := Time.get_ticks_msec()
	var res := s.resolution
	var res_c := (res - 1) / s.coarse_factor + 1
	var cells := res * res
	var cells_c := res_c * res_c

	# 1. Noise layers at both resolutions (same world coordinates).
	var fine := gpu.buffer(cells * 4)
	_noise(gpu, s, fine, res, s.cell_size)
	var coarse := gpu.buffer(cells_c * 4)
	_noise(gpu, s, coarse, res_c, s.cell_size * s.coarse_factor)
	var coarse_orig := gpu.buffer(cells_c * 4, gpu.read(coarse))

	# 2. Large-scale erosion on the coarse grid.
	var c_ero := gpu.buffer(cells_c * 4, _zeros(cells_c))
	var c_dep := gpu.buffer(cells_c * 4, _zeros(cells_c))
	var c_flow := gpu.buffer(cells_c * 4, _zeros(cells_c))
	_erode(gpu, s, coarse, res_c, [c_ero, c_dep, c_flow], s.coarse_droplets, s.coarse_lifetime, s.coarse_radius, 1.0, 0, s.coarse_batch)

	# 3. Transfer it to full resolution.
	var ero := gpu.buffer(cells * 4, _zeros(cells))
	var dep := gpu.buffer(cells * 4, _zeros(cells))
	var flow := gpu.buffer(cells * 4, _zeros(cells))
	gpu.dispatch(SHADER_APPLY, [fine, coarse_orig, coarse, c_ero, c_dep, c_flow, ero, dep, flow],
		GpuCompute.push_constants([res, res_c, s.coarse_factor, float(s.coarse_factor)]), _groups(res))

	# 4. Fine rills.
	_erode(gpu, s, fine, res, [ero, dep, flow], s.fine_droplets, s.fine_lifetime, s.fine_radius, s.fine_strength, 7919, s.droplet_batch)

	# 5. Thermal erosion, ping-ponging between two height buffers.
	var src := fine
	var dst := gpu.buffer(cells * 4)
	for i in s.thermal_iterations:
		gpu.dispatch(SHADER_THERMAL, [src, dst], GpuCompute.push_constants([res, s.talus * s.cell_size, s.thermal_rate, 0.0]), _groups(res))
		var tmp := src
		src = dst
		dst = tmp

	# 6. Rock outcrops.
	var rock := gpu.buffer(cells * 4, _zeros(cells))
	if s.outcrops_enabled:
		gpu.dispatch(SHADER_OUTCROP, [src, dst, rock], GpuCompute.push_constants([
			res, s.seed, s.cell_size, s.outcrop_slope_start, s.outcrop_slope_end,
			s.terrace_height, s.outcrop_relief, s.outcrop_patchiness,
		]), _groups(res))
		src = dst

	# 7. Finalize.
	var height_out := gpu.buffer(cells * 4)
	var control_out := gpu.buffer(cells * 4)
	gpu.dispatch(SHADER_FINALIZE, [src, ero, dep, flow, height_out, control_out],
		GpuCompute.push_constants([res, s.erosion_norm, s.deposit_norm, s.flow_norm, s.concavity_scale, 0.0, 0.0, 0.0]), _groups(res))

	var data := TerrainData.new()
	data.resolution = res
	data.cell_size = s.cell_size
	data.heights = gpu.read(height_out).to_float32_array()
	data.control = Image.create_from_data(res, res, false, Image.FORMAT_RGBA8, gpu.read(control_out))
	data.rock = Image.create_from_data(res, res, false, Image.FORMAT_RF, gpu.read(rock))
	data.rock.convert(Image.FORMAT_R8)
	gpu.free_all()

	data.min_height = INF
	data.max_height = -INF
	for h in data.heights:
		data.min_height = minf(data.min_height, h)
		data.max_height = maxf(data.max_height, h)
	print("Terrain generated in %d ms (heights %.1f .. %.1f m)" % [Time.get_ticks_msec() - t0, data.min_height, data.max_height])
	return data


static func _noise(gpu: GpuCompute, s: TerrainSettings, buf: RID, res: int, cell: float) -> void:
	gpu.dispatch(SHADER_HEIGHT, [buf], GpuCompute.push_constants([
		res, s.seed, cell, s.base_height,
		s.continent_freq, s.continent_amp, s.hill_freq, s.hill_amp,
		s.mountain_freq, s.mountain_amp, s.mountain_mask_freq, s.mountain_coverage,
		s.warp_freq, s.warp_amp, s.border_width, s.border_amp,
		s.detail_freq, s.detail_amp, s.valley_depth, 0.0,
	]), _groups(res))


## Droplet erosion in batches so later droplets flow over earlier changes. Each batch reads a
## snapshot of the heights and only adds to the live ones (see terrain_erosion.glsl), which
## makes the result independent of GPU scheduling: the same seed gives the same terrain.
## Smaller batches = closer to one-droplet-at-a-time erosion, more dispatches.
static func _erode(gpu: GpuCompute, s: TerrainSettings, heights: RID, res: int, acc: Array, droplets: int,
		lifetime: int, radius: int, strength: float, seed_offset: int, batch_size: int) -> void:
	if droplets <= 0:
		return
	var brush := _make_brush(radius)
	var offsets := gpu.buffer(brush[0].size(), brush[0])
	var weights := gpu.buffer(brush[1].size(), brush[1])
	var brush_count: int = brush[1].size() / 4
	var bytes := res * res * 4
	var snapshot := gpu.buffer(bytes)
	var done := 0
	while done < droplets:
		var batch := mini(batch_size, droplets - done)
		gpu.copy(heights, snapshot, bytes)
		gpu.dispatch(SHADER_EROSION, [heights, snapshot, offsets, weights, acc[0], acc[1], acc[2]],
			GpuCompute.push_constants([
				res, brush_count, done, s.seed + seed_offset, lifetime,
				s.inertia, s.capacity_factor, s.min_capacity, s.erode_speed * strength, s.deposit_speed * strength,
				s.evaporate_speed, s.gravity, 1.0, 1.0, s.height_scale, 0.0,
			]), Vector3i(ceili(batch / 64.0), 1, 1))
		done += batch


static func _groups(res: int) -> Vector3i:
	return Vector3i(ceili(res / 16.0), ceili(res / 16.0), 1)


static func _zeros(count: int) -> PackedByteArray:
	var z := PackedByteArray()
	z.resize(count * 4)
	return z


## Returns [offsets (ivec2 bytes), weights (float bytes)] for a circular erosion brush.
static func _make_brush(radius: int) -> Array:
	var offsets := PackedInt32Array()
	var weights := PackedFloat32Array()
	var total := 0.0
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var d := sqrt(float(x * x + y * y))
			if d <= radius:
				offsets.append(x)
				offsets.append(y)
				var w := 1.0 - d / (radius + 0.5)
				weights.append(w)
				total += w
	for i in weights.size():
		weights[i] /= total
	return [offsets.to_byte_array(), weights.to_byte_array()]
