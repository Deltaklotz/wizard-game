class_name ForestLayout
extends RefCounted
## The big forests: COUNT large, dense woods with lobed outlines (dense core, thinning edge), each
## with glades joined by winding trails to entrances on its edge. The largest one hides the
## secret spot (secret: centre x/z, rim radius, ground level before carving), which a trail leads to.
## Runs after the start site is flattened and before the terrain is built (the trails are painted
## into the control map as worn earth). Seeded only, so every client gets the same layout.
## Vegetation reads density_at / blocked_at / pine_at; the map draws names and trails.

const COUNT := 4
## Mask resolution (metres per cell) for density / blocked lookups.
const CELL := 2.0
const KINDS := ["broadleaf", "pine", "mixed"]
const NAMES := {
	"broadleaf": ["Whisperwood", "Elderholt", "The Greenreach", "Oakenhall"],
	"pine": ["The Pinewold", "Mirkwold", "Darkfell Pines", "The Needlewood"],
	"mixed": ["Thornwood", "Hollowmere Wood", "The Tanglewood", "Wyrmwood"],
}
## Secret spot: rim radius of its hollow (SecretSite), and the radius kept free of trees
## (it is the biggest glade until the village is built there).
const SECRET_RIM := 46.0
const SECRET_CLEAR := 50.0

## {center: Vector2, radius: float, kind: String, name: String, lobes: Array}
var forests: Array[Dictionary] = []
## Vector3(x, z, radius)
var glades: Array[Vector3] = []
## {points: PackedVector2Array, width: float, secret: bool}
var trails: Array[Dictionary] = []
## x, z, rim radius (0 = none), ground level before carving.
var secret := Vector4.ZERO
## Direction (from the secret centre) the secret trail arrives from, so a gap faces it.
var secret_entry := Vector2.RIGHT

var _res := 0
var _origin := Vector2.ZERO
var _density := PackedFloat32Array()
var _blocked := PackedByteArray()
var _kind := PackedByteArray()


static func generate(data: TerrainData, seed: int, site: StartSite, lake: LakeShape) -> ForestLayout:
	var t0 := Time.get_ticks_msec()
	var f := ForestLayout.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	f._place_forests(data, rng, site, lake)
	f._place_secret(data, rng)
	f._place_trails(data, rng, site)
	f._rasterize(data, rng)
	f._paint(data)
	print("ForestLayout: %d forests, %d glades, %d trails in %d ms" % [f.forests.size(), f.glades.size(), f.trails.size(), Time.get_ticks_msec() - t0])
	return f


# --- Queries -------------------------------------------------------------------------

## 0..1 forest density at (x, z) (0 outside the big forests, on trails and in glades).
func density_at(x: float, z: float) -> float:
	var i := _cell(x, z)
	return _density[i] if i >= 0 else 0.0


## No trees here: trails, glades, the secret.
func blocked_at(x: float, z: float) -> bool:
	var i := _cell(x, z)
	return i >= 0 and _blocked[i] != 0


## Share of pines the forest at (x, z) wants, or -1 outside the forests.
func pine_at(x: float, z: float) -> float:
	var i := _cell(x, z)
	if i < 0 or _kind[i] == 0:
		return -1.0
	match forests[_kind[i] - 1].kind:
		"pine":
			return 0.9
		"broadleaf":
			return 0.06
	return 0.45


## Inside the secret's hollow (plus `margin` metres).
func in_secret(x: float, z: float, margin := 0.0) -> bool:
	return has_secret() and Vector2(x - secret.x, z - secret.y).length() < secret.z + margin


func has_secret() -> bool:
	return secret.z > 0.0


func outline_radius(forest: Dictionary, angle: float) -> float:
	var r := 1.0
	for l in forest.lobes:
		r += l.x * sin(l.y * angle + l.z)
	return forest.radius * r


func _cell(x: float, z: float) -> int:
	var gx := int((x - _origin.x) / CELL)
	var gz := int((z - _origin.y) / CELL)
	if gx < 0 or gz < 0 or gx >= _res or gz >= _res:
		return -1
	return gz * _res + gx


# --- Generation ----------------------------------------------------------------------

func _place_forests(data: TerrainData, rng: RandomNumberGenerator, site: StartSite, lake: LakeShape) -> void:
	var half := data.world_size() * 0.5
	var name_used := {}
	for n in COUNT:
		# The first (secret) forest is the biggest.
		var radius := rng.randf_range(165.0, 185.0) if n == 0 else rng.randf_range(115.0, 150.0)
		for attempt in 500:
			var r := radius * (1.0 - attempt / 900.0)
			var span := half - 40.0 - r * 0.65
			var c := Vector2(rng.randf_range(-span, span), rng.randf_range(-span, span))
			if site and c.distance_to(site.center) < r + 55.0:
				continue
			if lake and c.distance_to(lake.center) < lake.radius * 1.4 + r * 0.75:
				continue
			var ok := true
			for o in forests:
				if c.distance_to(o.center) < (r + o.radius) * 0.82:
					ok = false
					break
			if not ok:
				continue
			# Mostly gentle ground below the tree line.
			var flat := 0.0
			var high := 0.0
			for k in 9:
				var p := c + Vector2.from_angle(TAU * k / 9.0) * r * 0.5 * float(k > 0)
				flat += data.normal_at(p.x, p.y).y
				high += data.height_at(p.x, p.y)
			if flat / 9.0 < 0.9 or high / 9.0 > 165.0:
				continue
			var kind: String = "pine" if high / 9.0 > 110.0 else KINDS[rng.randi() % KINDS.size()]
			if n == 0 and kind == "pine":
				kind = "mixed"  # the secret's forest: old, mixed woodland
			var names: Array = NAMES[kind]
			var name: String = names[rng.randi() % names.size()]
			while name_used.has(name):
				name = names[rng.randi() % names.size()]
			name_used[name] = true
			var lobes := []
			for k in [2, 3, 5]:
				lobes.append(Vector3([0.13, 0.09, 0.05][lobes.size()] * rng.randf_range(0.6, 1.0), k, rng.randf() * TAU))
			forests.append({"center": c, "radius": r, "kind": kind, "name": name, "lobes": lobes})
			break


func _place_secret(data: TerrainData, rng: RandomNumberGenerator) -> void:
	if forests.is_empty():
		return
	var f: Dictionary = forests[0]
	var best := Vector2.ZERO
	var best_score := INF
	for i in 60:
		var p: Vector2 = f.center + Vector2.from_angle(rng.randf() * TAU) * f.radius * 0.3 * sqrt(rng.randf())
		# Flattest spot (height spread over the hollow).
		var lo := INF
		var hi := -INF
		for k in 12:
			var q := p + Vector2.from_angle(TAU * k / 12.0) * 30.0
			var h := data.height_at(q.x, q.y)
			lo = minf(lo, h)
			hi = maxf(hi, h)
		var score := hi - lo + p.distance_to(f.center) * 0.02
		if score < best_score:
			best_score = score
			best = p
	var level := 0.0
	for k in 12:
		var q := best + Vector2.from_angle(TAU * k / 12.0) * SECRET_RIM
		level += data.height_at(q.x, q.y)
	secret = Vector4(best.x, best.y, SECRET_RIM, level / 12.0)


func _place_trails(data: TerrainData, rng: RandomNumberGenerator, site: StartSite) -> void:
	for fi in forests.size():
		var f: Dictionary = forests[fi]
		var c: Vector2 = f.center
		var nodes: Array[Vector2] = []
		var is_secret: Array[bool] = []
		# Entrances: one facing the start site, one or two more around the edge.
		var toward := (site.center - c).angle() if site else rng.randf() * TAU
		var entrance_angles := [toward + rng.randf_range(-0.4, 0.4)]
		for k in rng.randi_range(1, 2):
			entrance_angles.append(toward + PI * (0.6 + 0.8 * rng.randf()) * (1.0 if k == 0 else -1.0))
		for a in entrance_angles:
			nodes.append(c + Vector2.from_angle(a) * outline_radius(f, a) * 1.05)
			is_secret.append(false)
		# Glades inside, spaced out and away from the secret.
		var count := rng.randi_range(3, 5)
		var tries := 0
		var made := 0
		while made < count and tries < 200:
			tries += 1
			var p: Vector2 = c + Vector2.from_angle(rng.randf() * TAU) * f.radius * rng.randf_range(0.2, 0.72)
			var r := rng.randf_range(9.0, 20.0)
			var ok: bool = not (fi == 0 and has_secret() and p.distance_to(Vector2(secret.x, secret.y)) < SECRET_CLEAR + r + 25.0)
			for g in glades:
				if Vector2(g.x, g.y).distance_to(p) < g.z + r + 30.0:
					ok = false
			if not ok or data.normal_at(p.x, p.y).y < 0.88:
				continue
			glades.append(Vector3(p.x, p.y, r))
			nodes.append(p)
			is_secret.append(false)
			made += 1
		if fi == 0 and has_secret():
			nodes.append(Vector2(secret.x, secret.y))
			is_secret.append(true)
		# Minimum spanning tree (Prim) + one extra edge for a loop.
		var in_tree := [0]
		var edges: Array = []
		while in_tree.size() < nodes.size():
			var best := [-1, -1, INF]
			for a in in_tree:
				for b in nodes.size():
					if b in in_tree:
						continue
					# The secret hangs off a single glade, never between entrances.
					var d := nodes[a].distance_to(nodes[b]) * (3.0 if is_secret[b] and a < entrance_angles.size() else 1.0)
					if d < best[2]:
						best = [a, b, d]
			in_tree.append(best[1])
			edges.append([best[0], best[1]])
		var extra := [-1, -1, INF]
		for a in range(entrance_angles.size(), nodes.size()):
			for b in range(a + 1, nodes.size()):
				if is_secret[a] or is_secret[b] or [a, b] in edges or [b, a] in edges:
					continue
				var d := nodes[a].distance_to(nodes[b])
				if d < extra[2]:
					extra = [a, b, d]
		if extra[0] >= 0:
			edges.append([extra[0], extra[1]])
		for e in edges:
			var to_secret: bool = is_secret[e[0]] or is_secret[e[1]]
			var a: Vector2 = nodes[e[0]]
			var b: Vector2 = nodes[e[1]]
			if is_secret[e[0]]:
				var tmp := a
				a = b
				b = tmp
			var pts := _wander(a, b, rng)
			trails.append({"points": pts, "width": rng.randf_range(2.4, 3.4), "secret": to_secret})
			if to_secret:
				var n := pts.size()
				secret_entry = (pts[n - 4] - Vector2(secret.x, secret.y)).normalized() if n >= 4 else (a - b).normalized()


## A winding line from a to b (lateral wander fading out at both ends).
func _wander(a: Vector2, b: Vector2, rng: RandomNumberGenerator) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var len := a.distance_to(b)
	var n := maxi(4, int(len / 4.0))
	var side := (b - a).normalized().orthogonal()
	var f1 := rng.randf_range(1.5, 3.0)
	var f2 := rng.randf_range(4.0, 7.0)
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	var amp := minf(14.0, len * 0.12)
	for i in n + 1:
		var t := float(i) / n
		var w := sin(t * PI) * (sin(t * f1 * PI + p1) * amp + sin(t * f2 * PI + p2) * amp * 0.25)
		pts.append(a.lerp(b, t) + side * w)
	return pts


func _rasterize(data: TerrainData, rng: RandomNumberGenerator) -> void:
	_res = int(data.world_size() / CELL) + 1
	_origin = data.origin()
	_density.resize(_res * _res)
	_density.fill(0.0)
	_blocked.resize(_res * _res)
	_blocked.fill(0)
	_kind.resize(_res * _res)
	_kind.fill(0)
	var patch := FastNoiseLite.new()
	patch.seed = rng.randi()
	patch.frequency = 0.03
	# Forest bodies: dense core, thinning over the outer part of the outline, a few thin patches.
	for fi in forests.size():
		var f: Dictionary = forests[fi]
		var reach: float = f.radius * 1.3
		var c: Vector2 = f.center
		for gz in range(_cell_z(c.y - reach), _cell_z(c.y + reach) + 1):
			for gx in range(_cell_x(c.x - reach), _cell_x(c.x + reach) + 1):
				var p := Vector2(_origin.x + gx * CELL, _origin.y + gz * CELL)
				var off := p - c
				var rr := off.length() / outline_radius(f, off.angle())
				var d := 1.0 - smoothstep(0.72, 1.08, rr)
				if d <= 0.0:
					continue
				d *= lerpf(0.78, 1.0, smoothstep(-0.3, 0.2, patch.get_noise_2dv(p)))
				var i := gz * _res + gx
				if d > _density[i]:
					_density[i] = d
					_kind[i] = fi + 1
	# Glades: clear with a soft, ragged rim.
	for g in glades:
		_disc(Vector2(g.x, g.y), g.z, g.z * 0.6, patch)
	# Trails.
	for t in trails:
		var pts: PackedVector2Array = t.points
		var w: float = t.width * 0.5
		for i in pts.size() - 1:
			_segment(pts[i], pts[i + 1], w, 2.5)
	if has_secret():
		_disc(Vector2(secret.x, secret.y), SECRET_CLEAR, 6.0, null)


func _cell_x(x: float) -> int:
	return clampi(int((x - _origin.x) / CELL), 0, _res - 1)


func _cell_z(z: float) -> int:
	return clampi(int((z - _origin.y) / CELL), 0, _res - 1)


## Blocks a disc of radius r and thins the trees over `soft` metres beyond it.
func _disc(c: Vector2, r: float, soft: float, noise: FastNoiseLite) -> void:
	var reach := r + soft
	for gz in range(_cell_z(c.y - reach), _cell_z(c.y + reach) + 1):
		for gx in range(_cell_x(c.x - reach), _cell_x(c.x + reach) + 1):
			var p := Vector2(_origin.x + gx * CELL, _origin.y + gz * CELL)
			var d := p.distance_to(c) + (noise.get_noise_2dv(p * 3.0) * r * 0.25 if noise else 0.0)
			var i := gz * _res + gx
			if d < r:
				_blocked[i] = 1
			elif d < reach:
				_density[i] *= lerpf(0.35, 1.0, (d - r) / soft)


func _segment(a: Vector2, b: Vector2, w: float, soft: float) -> void:
	var reach := w + soft
	for gz in range(_cell_z(minf(a.y, b.y) - reach), _cell_z(maxf(a.y, b.y) + reach) + 1):
		for gx in range(_cell_x(minf(a.x, b.x) - reach), _cell_x(maxf(a.x, b.x) + reach) + 1):
			var p := Vector2(_origin.x + gx * CELL, _origin.y + gz * CELL)
			var d := _seg_dist(p, a, b)
			var i := gz * _res + gx
			if d < w:
				_blocked[i] = 1
			elif d < reach:
				_density[i] *= lerpf(0.4, 1.0, (d - w) / soft)


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Worn earth along the trails (control R = deposit/dirt), grassier glade floors.
func _paint(data: TerrainData) -> void:
	var res := data.resolution
	var o := data.origin()
	var cs := data.cell_size
	for t in trails:
		var pts: PackedVector2Array = t.points
		var w: float = t.width * 0.5
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var x0 := clampi(int((minf(a.x, b.x) - w - 1.0 - o.x) / cs), 0, res - 1)
			var x1 := clampi(int((maxf(a.x, b.x) + w + 1.0 - o.x) / cs) + 1, 0, res - 1)
			var z0 := clampi(int((minf(a.y, b.y) - w - 1.0 - o.y) / cs), 0, res - 1)
			var z1 := clampi(int((maxf(a.y, b.y) + w + 1.0 - o.y) / cs) + 1, 0, res - 1)
			for gz in range(z0, z1 + 1):
				for gx in range(x0, x1 + 1):
					var p := Vector2(o.x + gx * cs, o.y + gz * cs)
					var wear := 1.0 - smoothstep(w * 0.45, w, _seg_dist(p, a, b))
					if wear <= 0.0:
						continue
					var ctl := data.control.get_pixel(gx, gz)
					ctl.r = maxf(ctl.r, 0.85 * wear)
					data.control.set_pixel(gx, gz, ctl)
