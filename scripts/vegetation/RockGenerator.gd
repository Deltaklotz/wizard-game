class_name RockGenerator
extends RefCounted
## Procedural rocks and sticks.
## Rocks: noise-displaced icosphere, then sliced by random planes to get the flat
## fracture facets real stones have. Flat shaded; COLOR.r holds a baked occlusion term.


static func rock(seed: int, subdivisions := 2, flatness := 0.7) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.9
	noise.fractal_octaves = 4
	var verts := _icosphere(subdivisions)
	var planes: Array = []
	for i in rng.randi_range(4, 8):
		var n := MeshUtil.rand_dir(rng)
		n.y *= 0.6
		planes.append([n.normalized(), rng.randf_range(0.55, 0.85)])
	var stretch := Vector3(rng.randf_range(0.85, 1.25), flatness * rng.randf_range(0.85, 1.15), rng.randf_range(0.8, 1.1))
	for i in verts.size():
		var p: Vector3 = verts[i]
		p *= 1.0 + noise.get_noise_3dv(p * 1.3) * 0.28
		for pl in planes:
			var d: float = p.dot(pl[0]) - pl[1]
			if d > 0.0:
				p -= pl[0] * d
		p *= stretch
		# Flat-ish underside so the stone sits on the ground.
		if p.y < -0.35 * stretch.y:
			p.y = lerpf(p.y, -0.35 * stretch.y, 0.8)
		verts[i] = p
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := _ico_indices
	var low := -0.35 * stretch.y
	for t in range(0, tris.size(), 3):
		var a: Vector3 = verts[tris[t]]
		var b: Vector3 = verts[tris[t + 1]]
		var c: Vector3 = verts[tris[t + 2]]
		var n := (b - a).cross(c - a).normalized()
		if n.dot((a + b + c) / 3.0) < 0.0:
			n = -n
		var cy := (a.y + b.y + c.y) / 3.0
		var ao := Color(clampf(0.55 + (cy - low) / (stretch.y * 0.9), 0.55, 1.0), 0, 0)
		MeshUtil.tri(st, a, b, c, n, n, n, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z), ao)
	st.generate_tangents()
	return st.commit()


static func stick(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := rng.randf_range(0.6, 1.6)
	var r := rng.randf_range(0.018, 0.045)
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var bend := rng.randf_range(-0.25, 0.25)
	for i in 6:
		var t := i / 5.0
		pts.append(Vector3((t - 0.5) * length, r + sin(t * PI) * 0.03, sin(t * PI) * bend * 0.3 + rng.randf_range(-0.01, 0.01)))
		radii.append(lerpf(r, r * 0.45, t))
	MeshUtil.tube(st, pts, radii, 5, 1.0, 2.0)
	for k in rng.randi_range(0, 2):
		var t := rng.randf_range(0.3, 0.8)
		var o := pts[int(t * 5)]
		var dir := Vector3(rng.randf_range(0.3, 1.0), rng.randf_range(0.0, 0.3), rng.randf_range(-1, 1) * 1.0).normalized()
		var tl := length * rng.randf_range(0.15, 0.3)
		MeshUtil.tube(st, PackedVector3Array([o, o + dir * tl * 0.5, o + dir * tl + Vector3(0, -0.02, 0)]),
			PackedFloat32Array([r * 0.5, r * 0.35, r * 0.15]), 4, 1.0, 2.0)
	st.generate_tangents()
	return st.commit()


# --- Icosphere ---------------------------------------------------------------

static var _ico_indices := PackedInt32Array()


static func _icosphere(subdivisions: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts: Array = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	for i in verts.size():
		verts[i] = verts[i].normalized()
	var faces := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]
	for s in subdivisions:
		var cache := {}
		var next := []
		for f in faces:
			var a := _midpoint(verts, cache, f[0], f[1])
			var b := _midpoint(verts, cache, f[1], f[2])
			var c := _midpoint(verts, cache, f[2], f[0])
			next.append_array([[f[0], a, c], [f[1], b, a], [f[2], c, b], [a, b, c]])
		faces = next
	_ico_indices = PackedInt32Array()
	for f in faces:
		_ico_indices.append_array(f)
	return verts


static func _midpoint(verts: Array, cache: Dictionary, a: int, b: int) -> int:
	var key := mini(a, b) * 100000 + maxi(a, b)
	if cache.has(key):
		return cache[key]
	verts.append(((verts[a] + verts[b]) * 0.5).normalized())
	cache[key] = verts.size() - 1
	return verts.size() - 1
