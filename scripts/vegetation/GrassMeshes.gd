class_name GrassMeshes
extends RefCounted
## Procedural meshes for ground cover: blade clumps, tall grass bundles and flowers.
## UV.y runs 0 (root) -> 1 (tip) and drives wind bending and root darkening.
## COLOR: r = per-blade shade variation, g = 1 on petals, b = 1 on flower centers / seed heads.


## Clump of curved, tapered blades.
static func blade_clump(seed: int, blades: int, h_min: float, h_max: float, width: float, segments: int,
		spread: float, bend: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in blades:
		_blade(st, rng, Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * spread,
			rng.randf_range(h_min, h_max), width * rng.randf_range(0.7, 1.2), segments, bend * rng.randf_range(0.5, 1.4), Color(rng.randf(), 0, 0))
	st.index()
	return st.commit()


## Tall wild grass with a few seed-headed stems.
static func seed_grass(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in 9:
		_blade(st, rng, Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.14, rng.randf_range(0.35, 0.6), 0.03, 3, 0.35, Color(rng.randf(), 0, 0))
	for s in 4:
		var base := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.1
		var h := rng.randf_range(0.7, 1.05)
		var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.05, 0.2)
		var top := base + Vector3(0, h, 0) + lean
		_stem(st, base, top, 0.006, Color(0.5, 0, 0))
		# Seed head: two crossed, tapering quads.
		var head := 0.13
		for k in 2:
			var side := Vector3(1, 0, 0).rotated(Vector3.UP, k * PI * 0.5 + rng.randf()) * 0.018
			var up := (top - base).normalized()
			var a := top - up * head * 0.2
			var c := top + up * head
			MeshUtil.quad(st, a - side, a + side, c + side * 0.3, c - side * 0.3, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP,
				Vector2(0, 0.9), Vector2(1, 0.9), Vector2(1, 1), Vector2(0, 1), Color(0.5, 0, 1))
	return st.commit()


## kind: 0 daisy, 1 bell flower, 2 clustered umbel
static func flower(seed: int, kind: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A few leaves at the base.
	for i in 3:
		_blade(st, rng, Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.04, rng.randf_range(0.1, 0.18), 0.04, 2, 0.5, Color(0.6, 0, 0))
	var h := rng.randf_range(0.28, 0.45)
	var top := Vector3(rng.randf_range(-0.04, 0.04), h, rng.randf_range(-0.04, 0.04))
	_stem(st, Vector3.ZERO, top, 0.005, Color(0.5, 0, 0))
	match kind:
		0:
			var petals := 11
			for i in petals:
				var a := TAU * i / petals + rng.randf_range(-0.1, 0.1)
				var dir := Vector3(cos(a), 0.25, sin(a)).normalized()
				var side := Vector3(-sin(a), 0, cos(a)) * 0.011
				var p0 := top + dir * 0.012
				var p1 := top + dir * 0.055
				MeshUtil.quad(st, p0 - side, p0 + side, p1 + side * 0.8, p1 - side * 0.8, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP,
					Vector2(0, 0.95), Vector2(1, 0.95), Vector2(1, 1), Vector2(0, 1), Color(0.5, 1, 0))
			_disc(st, top + Vector3.UP * 0.004, 0.016, Color(0.5, 0, 1))
		1:
			for i in 3:
				var a := rng.randf() * TAU
				var at := top - Vector3(0, i * 0.05, 0) + Vector3(cos(a), 0, sin(a)) * 0.035
				_stem(st, top - Vector3(0, i * 0.05, 0), at, 0.003, Color(0.5, 0, 0))
				_bell(st, at, 0.022, 0.035)
		_:
			for i in 8:
				var a := rng.randf() * TAU
				var r := rng.randf_range(0.0, 0.045)
				var at := top + Vector3(cos(a) * r, rng.randf_range(0.0, 0.015), sin(a) * r)
				_disc(st, at, 0.009, Color(0.5, 1, 0))
	return st.commit()


static func _blade(st: SurfaceTool, rng: RandomNumberGenerator, base: Vector3, height: float, width: float,
		segments: int, bend: float, color: Color) -> void:
	var yaw := rng.randf() * TAU
	var lean := Vector3(cos(yaw), 0, sin(yaw))
	var side := Vector3(-lean.z, 0, lean.x).rotated(Vector3.UP, rng.randf_range(-0.6, 0.6))
	var face := side.cross(Vector3.UP).normalized()
	var n := (face * 0.35 + Vector3.UP * 0.65).normalized()
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in segments + 1:
		var t := float(i) / segments
		var center := base + Vector3.UP * t * height + lean * t * t * bend * height
		var hw := width * 0.5 * pow(1.0 - t, 0.8)
		var l := center - side * hw
		var r := center + side * hw
		if i > 0:
			var t0 := float(i - 1) / segments
			if i == segments:
				MeshUtil.tri(st, prev_l, prev_r, center, n, n, n, Vector2(0, t0), Vector2(1, t0), Vector2(0.5, t), color)
			else:
				MeshUtil.quad(st, prev_l, prev_r, r, l, n, n, n, n, Vector2(0, t0), Vector2(1, t0), Vector2(1, t), Vector2(0, t), color)
		prev_l = l
		prev_r = r


static func _stem(st: SurfaceTool, a: Vector3, b: Vector3, r: float, color: Color) -> void:
	for k in 2:
		var side := Vector3(1, 0, 0).rotated(Vector3.UP, k * PI * 0.5) * r
		MeshUtil.quad(st, a - side, a + side, b + side, b - side, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.9), Vector2(0, 0.9), color)


static func _disc(st: SurfaceTool, c: Vector3, r: float, color: Color) -> void:
	for i in 6:
		var a0 := TAU * i / 6.0
		var a1 := TAU * (i + 1) / 6.0
		MeshUtil.tri(st, c, c + Vector3(cos(a0), 0, sin(a0)) * r, c + Vector3(cos(a1), 0, sin(a1)) * r,
			Vector3.UP, Vector3.UP, Vector3.UP, Vector2(0.5, 1), Vector2(0, 1), Vector2(1, 1), color)


static func _bell(st: SurfaceTool, top: Vector3, r: float, h: float) -> void:
	var col := Color(0.5, 1, 0)
	for i in 5:
		var a0 := TAU * i / 5.0
		var a1 := TAU * (i + 1) / 5.0
		var b0 := top + Vector3(cos(a0) * r, -h, sin(a0) * r)
		var b1 := top + Vector3(cos(a1) * r, -h, sin(a1) * r)
		var n := Vector3(cos((a0 + a1) * 0.5), 0.3, sin((a0 + a1) * 0.5)).normalized()
		MeshUtil.tri(st, top, b0, b1, n, n, n, Vector2(0.5, 1), Vector2(0, 1), Vector2(1, 1), col)
