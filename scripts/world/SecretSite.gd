class_name SecretSite
extends RefCounted
## The secret spot deep in the biggest forest (ForestLayout.secret): a sunken, grassy hollow that
## can't be seen from outside the forest – reserved for the secret village. carve() runs on the
## heightmap before the terrain is built: a flat floor (FLOOR_R) with soft undulation, slopes up to
## the rim, rock mask cleared so the slopes stay soil. Nothing is built on it yet.

const FLOOR_R := 30.0
const DEPTH := 8.0


static func carve(d: TerrainData) -> void:
	if d.forests == null or not d.forests.has_secret():
		return
	var sc := d.forests.secret
	var c := Vector2(sc.x, sc.y)
	var floor_level := sc.w - DEPTH
	var res := d.resolution
	var o := d.origin()
	var cs := d.cell_size
	var reach := sc.z + 6.0
	var noise := FastNoiseLite.new()
	noise.seed = int(sc.x * 13.0 + sc.y * 7.0)
	noise.frequency = 0.06
	for gz in range(clampi(int((c.y - reach - o.y) / cs), 0, res - 1), clampi(int((c.y + reach - o.y) / cs) + 1, 0, res - 1) + 1):
		for gx in range(clampi(int((c.x - reach - o.x) / cs), 0, res - 1), clampi(int((c.x + reach - o.x) / cs) + 1, 0, res - 1) + 1):
			var p := Vector2(o.x + gx * cs, o.y + gz * cs)
			var dist := p.distance_to(c) + noise.get_noise_2dv(p) * 3.0
			if dist > reach:
				continue
			var i := gz * res + gx
			var k := smoothstep(FLOOR_R, sc.z, dist)
			var target := floor_level + noise.get_noise_2dv(p * 2.0) * 0.35
			# Outside the rim the ground eases into the old height.
			d.heights[i] = lerpf(target, d.heights[i], k)
			d.rock.set_pixel(gx, gz, Color(0, 0, 0))
			# Meadow floor: no sediment/dirt or flow channels in the hollow.
			var ctl := d.control.get_pixel(gx, gz)
			var floor_k := 1.0 - smoothstep(FLOOR_R - 6.0, FLOOR_R + 4.0, dist)
			ctl.r = lerpf(ctl.r, minf(ctl.r, 0.25), floor_k)
			ctl.g = lerpf(ctl.g, minf(ctl.g, 0.3), floor_k)
			ctl.b = minf(ctl.b, 0.3)
			d.control.set_pixel(gx, gz, ctl)
