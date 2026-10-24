class_name WaterPlants
extends RefCounted
## Procedural meshes for lake vegetation.
## Reeds use the same conventions as GrassMeshes (UV.y root->tip, COLOR.b = seed heads).
## Lily meshes: UV = (angle / TAU, radius) on pads; COLOR.g = 1 on petals, COLOR.b = 1 on stamens.


## Clump of common reed (Phragmites): tall stems, long leaves, feathery plumes;
## `cattails` swaps some plumes for brown cattail heads.
static func reed_clump(seed: int, cattails: bool) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stems := rng.randi_range(9, 15)
	for i in stems:
		var base := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.28
		var h := rng.randf_range(1.3, 2.3)
		var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.12
		var top := base + Vector3(0, h, 0) + lean * h * 0.3
		var shade := rng.randf()
		_stem(st, base, top, 0.012, Color(shade, 0, 0))
		# Long leaves spraying off the stem.
		for k in rng.randi_range(1, 3):
			var at := base.lerp(top, rng.randf_range(0.15, 0.55))
			_leaf(st, rng, at, rng.randf_range(0.5, 0.9), 0.035, Color(shade, 0, 0))
		if rng.randf() < 0.6:
			if cattails and rng.randf() < 0.6:
				_cattail(st, top - Vector3(0, 0.08, 0), 0.028, 0.22)
			else:
				_plume(st, rng, top)
	st.index()
	return st.commit()


static func lily_pad(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 22
	var rings := 3
	var notch := rng.randf_range(0.25, 0.4)  # radians of the cut-out wedge
	var up := Vector3.UP
	for s in segments:
		var a0 := notch * 0.5 + (TAU - notch) * s / segments
		var a1 := notch * 0.5 + (TAU - notch) * (s + 1) / segments
		for r in rings:
			var r0 := float(r) / rings
			var r1 := float(r + 1) / rings
			var p00 := _pad_point(a0, r0)
			var p01 := _pad_point(a1, r0)
			var p10 := _pad_point(a0, r1)
			var p11 := _pad_point(a1, r1)
			var col := Color(1, 0, 0)
			if r == 0:
				MeshUtil.tri(st, p00, p10, p11, up, up, up, Vector2(a0 / TAU, r0), Vector2(a0 / TAU, r1), Vector2(a1 / TAU, r1), col)
			else:
				MeshUtil.quad(st, p00, p10, p11, p01, up, up, up, up, Vector2(a0 / TAU, r0), Vector2(a0 / TAU, r1),
					Vector2(a1 / TAU, r1), Vector2(a1 / TAU, r0), col)
	st.index()
	return st.commit()


static func lily_flower(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for layer in 2:
		var count := 8
		var tilt := 0.35 + layer * 0.45
		var length := 0.11 - layer * 0.025
		for i in count:
			var a := TAU * (i + layer * 0.5) / count + rng.randf_range(-0.1, 0.1)
			var dir := Vector3(cos(a) * cos(tilt), sin(tilt), sin(a) * cos(tilt))
			var side := Vector3(-sin(a), 0, cos(a)) * 0.025
			var base := Vector3(0, 0.02 + layer * 0.01, 0)
			var mid := base + dir * length * 0.5
			var tip := base + dir * length
			var n := (Vector3.UP + dir * 0.3).normalized()
			MeshUtil.quad(st, base - side * 0.4, mid - side, mid + side, base + side * 0.4, n, n, n, n,
				Vector2(0, 0), Vector2(0, 0.5), Vector2(1, 0.5), Vector2(1, 0), Color(1, 1, 0))
			MeshUtil.tri(st, mid - side, tip, mid + side, n, n, n, Vector2(0, 0.5), Vector2(0.5, 1), Vector2(1, 0.5), Color(1, 1, 0))
	for i in 6:
		var a := TAU * i / 6.0
		var c := Vector3(cos(a) * 0.012, 0.05, sin(a) * 0.012)
		_stem(st, Vector3(0, 0.02, 0), c, 0.004, Color(1, 0, 1))
	st.index()
	return st.commit()


static func _pad_point(a: float, r: float) -> Vector3:
	# Slightly cupped with a wavy rim.
	return Vector3(cos(a) * r, 0.02 * r * r + 0.008 * sin(a * 7.0) * r, sin(a) * r)


static func _stem(st: SurfaceTool, a: Vector3, b: Vector3, r: float, color: Color) -> void:
	for k in 2:
		var side := Vector3(1, 0, 0).rotated(Vector3.UP, k * PI * 0.5 + 0.3) * r
		MeshUtil.quad(st, a - side, a + side, b + side * 0.5, b - side * 0.5, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), color)


static func _leaf(st: SurfaceTool, rng: RandomNumberGenerator, at: Vector3, length: float, width: float, color: Color) -> void:
	var dir := Vector3(cos(rng.randf() * TAU), 0, sin(rng.randf() * TAU)).normalized()
	var side := Vector3(-dir.z, 0, dir.x)
	var n := Vector3.UP
	var prev_l := at - side * width * 0.5
	var prev_r := at + side * width * 0.5
	var y0 := at.y / 2.3
	for i in range(1, 5):
		var t := i / 4.0
		var c := at + Vector3.UP * t * length * 0.8 + dir * t * t * length * 0.7 - Vector3.UP * t * t * length * 0.35
		var hw := width * 0.5 * (1.0 - t)
		var l := c - side * hw
		var r := c + side * hw
		var v0 := clampf(y0 + (i - 1) * 0.1, 0.0, 1.0)
		var v1 := clampf(y0 + i * 0.1, 0.0, 1.0)
		MeshUtil.quad(st, prev_l, prev_r, r, l, n, n, n, n, Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1), color)
		prev_l = l
		prev_r = r


## Feathery panicle: many thin strands arching out and drooping from the stem tip.
static func _plume(st: SurfaceTool, rng: RandomNumberGenerator, top: Vector3) -> void:
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	for k in 9:
		var t := float(k) / 8.0
		var start := top - Vector3(0, 0.28 * (1.0 - t), 0)
		var dir := (lean * 0.6 + Vector3(cos(k * 2.4), 0, sin(k * 2.4)) * 0.5 + Vector3.UP * 0.4).normalized()
		var length := rng.randf_range(0.12, 0.22) * (0.6 + 0.4 * t)
		var mid := start + dir * length * 0.5
		var end := start + dir * length + Vector3.DOWN * length * 0.45
		var side := dir.cross(Vector3.UP).normalized() * 0.009
		MeshUtil.quad(st, start - side * 0.5, start + side * 0.5, mid + side, mid - side, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP,
			Vector2(0, 0.9), Vector2(1, 0.9), Vector2(1, 0.95), Vector2(0, 0.95), Color(0.5, 0, 1))
		MeshUtil.quad(st, mid - side, mid + side, end + side * 0.3, end - side * 0.3, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP,
			Vector2(0, 0.95), Vector2(1, 0.95), Vector2(1, 1), Vector2(0, 1), Color(0.5, 0, 1))


static func _cattail(st: SurfaceTool, center: Vector3, r: float, h: float) -> void:
	var pts := PackedVector3Array([center - Vector3(0, h * 0.5, 0), center, center + Vector3(0, h * 0.5, 0)])
	var radii := PackedFloat32Array([r * 0.8, r, r * 0.7])
	MeshUtil.tube(st, pts, radii, 5, 1.0, 1.0, Color(0.3, 0, 1))
