class_name LakeShape
extends RefCounted
## A lake carved into the terrain: finds a flat, low site, digs an irregular basin with
## a raised bank so the water stays contained, raises a small island inside and paints
## mud / wet shore into the terrain control maps. Must run before the terrain is built.

var center: Vector2
## Nominal shoreline radius; the real outline wobbles around it.
var radius: float
var level: float
var depth: float
var island_center: Vector2
var island_radius: float
var island_height: float

var _outline := FastNoiseLite.new()
var _island_outline := FastNoiseLite.new()
var _bed := FastNoiseLite.new()


## Radius of the influence area (bank included).
func outer_radius() -> float:
	return radius * 1.5


func shore_radius(theta: float) -> float:
	return radius * (1.0 + 0.22 * _outline.get_noise_2d(cos(theta) * 2.5, sin(theta) * 2.5))


func island_edge(theta: float) -> float:
	return island_radius * (1.0 + 0.3 * _island_outline.get_noise_2d(cos(theta) * 2.0, sin(theta) * 2.0))


## Normalised distance from the lake center (1 = shoreline).
func shore_fraction(p: Vector2) -> float:
	var off := p - center
	return off.length() / shore_radius(off.angle())


## Normalised distance from the island center (1 = island shore).
func island_fraction(p: Vector2) -> float:
	var off := p - island_center
	return off.length() / island_edge(off.angle())


static func find(data: TerrainData, rng: RandomNumberGenerator) -> LakeShape:
	var lake := LakeShape.new()
	lake.radius = rng.randf_range(38.0, 48.0)
	lake.depth = rng.randf_range(3.0, 4.5)
	var seed := rng.randi()
	lake._outline.seed = seed
	lake._outline.frequency = 0.5
	lake._outline.fractal_octaves = 3
	lake._island_outline.seed = seed + 1
	lake._island_outline.frequency = 0.6
	lake._bed.seed = seed + 2
	lake._bed.frequency = 0.08

	# Flattest, lowest spot away from the border mountains and rock.
	var best_score := INF
	var extent := data.world_size() * 0.5 - lake.radius * 1.6 - 150.0
	var step := 18.0
	var z := -extent
	while z <= extent:
		var x := -extent
		while x <= extent:
			var c := Vector2(x, z)
			var samples := PackedFloat32Array()
			var rock := 0.0
			for ring in [0.0, 0.5, 1.0, 1.35]:
				for a in 12:
					var p: Vector2 = c + Vector2.from_angle(TAU * a / 12.0) * lake.radius * ring
					samples.append(data.height_at(p.x, p.y))
					rock += data.rock_at(p.x, p.y)
			var mean := 0.0
			for h in samples:
				mean += h
			mean /= samples.size()
			var variance := 0.0
			for h in samples:
				variance += (h - mean) * (h - mean)
			var score := sqrt(variance / samples.size()) + rock * 2.0 + maxf(data.height_at(c.x, c.y) - mean, 0.0)
			if score < best_score:
				best_score = score
				lake.center = c
			x += step
		z += step

	# Water sits just below the average shoreline height.
	var shore := 0.0
	for a in 24:
		var th := TAU * a / 24.0
		var p := lake.center + Vector2.from_angle(th) * lake.shore_radius(th)
		shore += data.height_at(p.x, p.y)
	lake.level = shore / 24.0 - 0.25
	lake.island_center = lake.center + Vector2.from_angle(rng.randf() * TAU) * lake.radius * rng.randf_range(0.0, 0.2)
	lake.island_radius = rng.randf_range(9.0, 12.0)
	lake.island_height = rng.randf_range(2.4, 3.4)
	return lake


func carve(data: TerrainData) -> void:
	var res := data.resolution
	var o := data.origin()
	var reach := outer_radius() * 1.3
	var x0 := clampi(int((center.x - reach - o.x) / data.cell_size), 0, res - 1)
	var x1 := clampi(int((center.x + reach - o.x) / data.cell_size) + 1, 0, res - 1)
	var z0 := clampi(int((center.y - reach - o.y) / data.cell_size), 0, res - 1)
	var z1 := clampi(int((center.y + reach - o.y) / data.cell_size) + 1, 0, res - 1)
	for gz in range(z0, z1 + 1):
		for gx in range(x0, x1 + 1):
			var p := Vector2(o.x + gx * data.cell_size, o.y + gz * data.cell_size)
			var i := gz * res + gx
			var h := data.heights[i]
			var nh := h
			var dn := shore_fraction(p)
			if dn < 1.0:
				# Basin: shallow shelf near the shore, deeper towards the middle.
				var bed := level + 0.35 - (0.35 + depth) * (1.0 - smoothstep(0.3, 1.0, dn))
				bed += _bed.get_noise_2d(p.x, p.y) * 0.35
				nh = minf(h, bed)
			elif dn < 1.5:
				# Bank: never lower than just above the water, fading back to the terrain.
				var bank := level + 0.3 + (dn - 1.0) * radius * 0.05
				nh = lerpf(maxf(h, bank), h, smoothstep(1.2, 1.5, dn))
			var xi := island_fraction(p)
			if xi < 1.7:
				var ih := level + island_height * (1.0 - xi * xi) + _bed.get_noise_2d(p.x * 2.0, p.y * 2.0) * 0.3
				nh = maxf(nh, ih)
			data.heights[i] = nh

			if dn < 1.25:
				var ctl := data.control.get_pixel(gx, gz)
				var above := nh - level
				if above < 0.0:
					# Muddy, dark lake bed.
					ctl.r = maxf(ctl.r, 0.95)
					ctl.g = maxf(ctl.g, 0.9)
				elif above < 0.6:
					# Wet shore band.
					var wet := 1.0 - above / 0.6
					ctl.g = maxf(ctl.g, 0.62 + 0.25 * wet)
					ctl.r = maxf(ctl.r, 0.5 * wet)
				data.control.set_pixel(gx, gz, ctl)
				data.rock.set_pixel(gx, gz, Color(0, 0, 0))
	data.min_height = minf(data.min_height, level - depth - 1.0)
	data.lakes.append(self)
