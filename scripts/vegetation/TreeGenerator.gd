class_name TreeGenerator
extends RefCounted
## Procedural trees. A seed produces a branch/leaf structure, which is then emitted
## at two levels of detail so the near and far versions of a tree match.
## Meshes have two surfaces: 0 = bark, 1 = leaf cards.
## Leaf vertex COLOR: r = wind sway weight, g = per-cluster phase.

enum Species { BROADLEAF, PINE }


## Returns {"lod0", "lod1", "lod2": ArrayMesh, "height": float, "trunk_radius": float}.
## lod0 = full detail, lod1 = every third leaf card (bigger), lod2 = trunk + ~14 huge cards.
static func generate(species: Species, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var tree := _broadleaf(rng) if species == Species.BROADLEAF else _pine(rng)
	tree["species"] = species
	return {
		"lod0": _emit(tree, 0),
		"lod1": _emit(tree, 1),
		"lod2": _emit(tree, 2),
		"height": tree.height,
		"trunk_radius": tree.trunk_radius,
	}


# --- Structure ---------------------------------------------------------------

static func _branch(pts: PackedVector3Array, radii: PackedFloat32Array, level: int) -> Dictionary:
	return {"pts": pts, "radii": radii, "level": level}


## Grows a branch from `origin` along `dir`, bending by `bend` per segment.
static func _grow(rng: RandomNumberGenerator, origin: Vector3, dir: Vector3, length: float, radius: float,
		tip_radius: float, segments: int, bend: Vector3, wobble: float) -> Dictionary:
	var pts := PackedVector3Array([origin])
	var radii := PackedFloat32Array([radius])
	var p := origin
	var d := dir.normalized()
	for s in segments:
		d = (d + bend + MeshUtil.rand_dir(rng) * wobble).normalized()
		p += d * length / segments
		pts.append(p)
		radii.append(lerpf(radius, tip_radius, float(s + 1) / segments))
	return {"pts": pts, "radii": radii}


static func _sample(pts: PackedVector3Array, t: float) -> Vector3:
	var f := clampf(t, 0.0, 1.0) * (pts.size() - 1)
	var i := mini(int(f), pts.size() - 2)
	return pts[i].lerp(pts[i + 1], f - i)


static func _sample_dir(pts: PackedVector3Array, t: float) -> Vector3:
	var f := clampf(t, 0.0, 1.0) * (pts.size() - 1)
	var i := mini(int(f), pts.size() - 2)
	return (pts[i + 1] - pts[i]).normalized()


static func _sample_radius(radii: PackedFloat32Array, t: float) -> float:
	var f := clampf(t, 0.0, 1.0) * (radii.size() - 1)
	var i := mini(int(f), radii.size() - 2)
	return lerpf(radii[i], radii[i + 1], f - i)


static func _broadleaf(rng: RandomNumberGenerator) -> Dictionary:
	var height := rng.randf_range(7.0, 11.0)
	var r0 := rng.randf_range(0.22, 0.34)
	var branches: Array = []
	var cards: Array = []

	# Trunk with a root flare and a slight lean.
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.12
	var trunk_pts := PackedVector3Array()
	var trunk_r := PackedFloat32Array()
	var trunk_top := height * rng.randf_range(0.72, 0.82)
	var phase := rng.randf() * TAU
	for i in 11:
		var t := i / 10.0
		var wob := Vector3(sin(t * 5.0 + phase), 0, cos(t * 4.0 + phase)) * 0.12 * t
		trunk_pts.append(Vector3(0, t * trunk_top, 0) + lean * t * t * trunk_top + wob)
		trunk_r.append(r0 * (1.0 - t * 0.7) * (1.0 + 0.7 * exp(-t * 16.0)))
	branches.append(_branch(trunk_pts, trunk_r, 0))

	var count := rng.randi_range(5, 8)
	var az := rng.randf() * TAU
	for k in count:
		var t := lerpf(0.38, 0.97, float(k) / (count - 1)) + rng.randf_range(-0.04, 0.04)
		az += 2.39996 + rng.randf_range(-0.4, 0.4)
		var elev := deg_to_rad(lerpf(28.0, 62.0, t) + rng.randf_range(-10.0, 10.0))
		var dir := Vector3(cos(az) * cos(elev), sin(elev), sin(az) * cos(elev))
		var length := height * rng.randf_range(0.34, 0.5) * (1.0 - 0.35 * t)
		var origin := _sample(trunk_pts, t)
		var b1 := _grow(rng, origin, dir, length, _sample_radius(trunk_r, t) * 0.62, 0.025, 6, Vector3(0, 0.06, 0), 0.12)
		branches.append(_branch(b1.pts, b1.radii, 1))
		for j in rng.randi_range(3, 5):
			var t2 := rng.randf_range(0.3, 0.95)
			var pdir := _sample_dir(b1.pts, t2)
			var side := pdir.cross(MeshUtil.rand_dir(rng)).normalized()
			var d2 := (pdir * 0.6 + side * 0.7 + Vector3.UP * 0.25).normalized()
			var len2 := length * rng.randf_range(0.32, 0.52)
			var b2 := _grow(rng, _sample(b1.pts, t2), d2, len2, _sample_radius(b1.radii, t2) * 0.6, 0.012, 4, Vector3(0, 0.05, 0), 0.15)
			branches.append(_branch(b2.pts, b2.radii, 2))
			for c in 5:
				var tc := 0.25 + c * 0.19
				_leaf_cluster(rng, cards, _sample(b2.pts, tc), _sample_dir(b2.pts, tc), rng.randf_range(0.7, 1.05))
		for c in 3:
			var tc := 0.6 + c * 0.2
			_leaf_cluster(rng, cards, _sample(b1.pts, tc), _sample_dir(b1.pts, tc), rng.randf_range(0.8, 1.15))
	for i in 5:
		_leaf_cluster(rng, cards, trunk_pts[trunk_pts.size() - 1] + MeshUtil.rand_dir(rng) * 0.8, Vector3.UP, 1.1)
	return {"branches": branches, "cards": cards, "height": height, "trunk_radius": r0}


static func _leaf_cluster(rng: RandomNumberGenerator, cards: Array, pos: Vector3, dir: Vector3, size: float) -> void:
	var cluster_phase := rng.randf()
	for m in 3:
		var up := (dir * 0.55 + MeshUtil.rand_dir(rng) * 0.65 + Vector3.UP * 0.35).normalized()
		var side := up.cross(MeshUtil.rand_dir(rng)).normalized()
		var s := size * rng.randf_range(0.8, 1.15)
		cards.append({"base": pos - up * s * 0.3, "axis": up, "side": side, "length": s, "width": s, "phase": cluster_phase, "kind": 0})


static func _pine(rng: RandomNumberGenerator) -> Dictionary:
	var height := rng.randf_range(11.0, 17.0)
	var r0 := rng.randf_range(0.2, 0.3)
	var branches: Array = []
	var cards: Array = []
	var trunk_pts := PackedVector3Array()
	var trunk_r := PackedFloat32Array()
	var phase := rng.randf() * TAU
	for i in 13:
		var t := i / 12.0
		trunk_pts.append(Vector3(sin(t * 3.0 + phase) * 0.08, t * height, cos(t * 2.5 + phase) * 0.08))
		trunk_r.append(lerpf(r0, 0.03, pow(t, 0.9)) * (1.0 + 0.5 * exp(-t * 20.0)))
	branches.append(_branch(trunk_pts, trunk_r, 0))

	var h := height * rng.randf_range(0.18, 0.28)
	var h0 := h
	var az0 := rng.randf() * TAU
	while h < height * 0.94:
		var t_rel := (h - h0) / (height - h0)
		var n := rng.randi_range(4, 6)
		az0 += rng.randf_range(0.5, 1.2)
		var max_len := lerpf(4.0, 0.5, pow(t_rel, 0.85))
		for k in n:
			var az := az0 + TAU * k / n + rng.randf_range(-0.25, 0.25)
			var elev := lerpf(-0.3, 0.3, t_rel) + rng.randf_range(-0.1, 0.1)
			var dir := Vector3(cos(az) * cos(elev), sin(elev), sin(az) * cos(elev))
			var length := max_len * rng.randf_range(0.8, 1.1)
			var origin := Vector3(_sample(trunk_pts, h / height).x, h, _sample(trunk_pts, h / height).z)
			var b := _grow(rng, origin, dir, length, 0.025 + 0.018 * length, 0.01, 3, Vector3(0, -0.08, 0), 0.08)
			branches.append(_branch(b.pts, b.radii, 1))
			# Overlapping needle cards along the whole branch so no bare wood shows.
			var card_len := minf(length * 0.85, 1.15)
			var steps := maxi(1, ceili((length - card_len * 0.6) / 0.42))
			var p := rng.randf()
			for c in steps:
				var tc := float(c) / steps * clampf(1.0 - card_len * 0.7 / length, 0.0, 1.0)
				var a := (_sample_dir(b.pts, tc + 0.05) + Vector3(0, -0.12, 0)).normalized()
				var side := a.cross(Vector3.UP).normalized()
				if side.length_squared() < 0.01:
					side = MeshUtil.perpendicular(a)
				var jitter := rng.randf_range(-0.25, 0.25)
				for tilt in [jitter, jitter + rng.randf_range(0.9, 1.3), jitter - rng.randf_range(0.9, 1.3)]:
					var s2: Vector3 = side.rotated(a, tilt)
					cards.append({"base": _sample(b.pts, tc), "axis": a, "side": s2, "length": card_len, "width": card_len * 0.95, "phase": p, "kind": 1})
		h += rng.randf_range(0.5, 0.75)
	# Leader at the very top.
	var top := trunk_pts[trunk_pts.size() - 1]
	for i in 3:
		var side := Vector3(cos(i * 2.1), 0, sin(i * 2.1))
		cards.append({"base": top - Vector3.UP * 1.0, "axis": Vector3.UP, "side": side, "length": 1.5, "width": 1.2, "phase": 0.0, "kind": 1})
	return {"branches": branches, "cards": cards, "height": height, "trunk_radius": r0}


# --- Mesh emission -------------------------------------------------------------

static func _emit(tree: Dictionary, lod: int) -> ArrayMesh:
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pine: bool = tree.species == Species.PINE
	var height: float = tree.height

	for b in tree.branches:
		var level: int = b.level
		if lod == 1 and level >= (1 if pine else 2):
			continue
		if lod == 2 and level >= 1:
			continue
		var sides: int = [[8, 5, 4], [5, 3, 3], [3, 3, 3]][lod][level]
		var pts: PackedVector3Array = b.pts
		var radii: PackedFloat32Array = b.radii
		if lod >= 1 and pts.size() > 4:
			pts = _decimate(pts)
			radii = _decimate_f(radii)
		var r: float = radii[0]
		var u_repeat := maxf(1.0, roundf(r * TAU / 0.6))
		MeshUtil.tube(bark, pts, radii, sides, u_repeat, u_repeat / maxf(r * TAU, 0.05) * 0.5, Color(0, 0, 0))

	var center := Vector3(0, height * (0.6 if pine else 0.72), 0)
	var i := 0
	var stride: int = [1, 3, maxi(1, tree.cards.size() / 14)][lod]
	var grow: float = [1.0, 1.55, sqrt(float(stride)) * 0.95][lod]
	for c in tree.cards:
		i += 1
		if i % stride != 0:
			continue
		var base: Vector3 = c.base
		var axis: Vector3 = c.axis
		var side: Vector3 = c.side
		var length: float = c.length * grow
		var width: float = c.width * grow
		var card_n := axis.cross(side).normalized()
		var sway := clampf(base.y / height, 0.2, 1.0)
		var col := Color(sway, c.phase, 0.0)
		# Blend the card normal with the direction from the crown center for soft, volumetric shading.
		var corners: Array[Vector3]
		var uvs: Array[Vector2]
		if c.kind == 0:
			corners = [base - side * width * 0.5, base + side * width * 0.5, base + side * width * 0.5 + axis * length, base - side * width * 0.5 + axis * length]
			uvs = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		else:
			corners = [base - side * width * 0.5, base - side * width * 0.5 + axis * length, base + side * width * 0.5 + axis * length, base + side * width * 0.5]
			uvs = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		var ns: Array[Vector3] = []
		for p in corners:
			var radial := p - center
			radial.y *= 0.6
			var sn := card_n if card_n.dot(radial) >= 0.0 else -card_n
			ns.append((radial.normalized() * 0.7 + sn * 0.3).normalized())
		MeshUtil.quad(leaves, corners[0], corners[1], corners[2], corners[3], ns[0], ns[1], ns[2], ns[3],
			uvs[0], uvs[1], uvs[2], uvs[3], col)

	bark.generate_tangents()
	leaves.generate_tangents()
	var mesh := ArrayMesh.new()
	bark.commit(mesh)
	leaves.commit(mesh)
	return mesh


static func _decimate(pts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(0, pts.size(), 2):
		out.append(pts[i])
	if (pts.size() - 1) % 2 != 0:
		out.append(pts[pts.size() - 1])
	return out


static func _decimate_f(v: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in range(0, v.size(), 2):
		out.append(v[i])
	if (v.size() - 1) % 2 != 0:
		out.append(v[v.size() - 1])
	return out
