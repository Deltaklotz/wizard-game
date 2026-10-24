class_name MeshUtil
extends RefCounted
## Small SurfaceTool helpers shared by the procedural asset generators.


## Emits a triangle facing along the supplied normals (Godot front faces are clockwise).
static func tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, n0: Vector3, n1: Vector3, n2: Vector3,
		uv0: Vector2, uv1: Vector2, uv2: Vector2, color := Color.WHITE) -> void:
	if (p1 - p0).cross(p2 - p0).dot(n0 + n1 + n2) > 0.0:
		var tp := p1
		p1 = p2
		p2 = tp
		var tn := n1
		n1 = n2
		n2 = tn
		var tu := uv1
		uv1 = uv2
		uv2 = tu
	st.set_color(color)
	st.set_normal(n0)
	st.set_uv(uv0)
	st.add_vertex(p0)
	st.set_color(color)
	st.set_normal(n1)
	st.set_uv(uv1)
	st.add_vertex(p1)
	st.set_color(color)
	st.set_normal(n2)
	st.set_uv(uv2)
	st.add_vertex(p2)


## Quad p0-p1-p2-p3 in loop order.
static func quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n0: Vector3, n1: Vector3,
		n2: Vector3, n3: Vector3, uv0: Vector2, uv1: Vector2, uv2: Vector2, uv3: Vector2, color := Color.WHITE) -> void:
	tri(st, p0, p1, p2, n0, n1, n2, uv0, uv1, uv2, color)
	tri(st, p0, p2, p3, n0, n2, n3, uv0, uv2, uv3, color)


## Generalized cylinder along a polyline using parallel-transported frames.
## `v_scale` converts length along the tube into texture V.
static func tube(st: SurfaceTool, pts: PackedVector3Array, radii: PackedFloat32Array, sides: int,
		u_repeat: float, v_scale: float, color := Color.WHITE) -> void:
	var n := pts.size()
	if n < 2:
		return
	var t0 := (pts[1] - pts[0]).normalized()
	var ref := Vector3.RIGHT if absf(t0.x) < 0.9 else Vector3.FORWARD
	var normal := t0.cross(ref).normalized()
	var rings: Array = []
	var v := 0.0
	for i in n:
		var t: Vector3
		if i == 0:
			t = (pts[1] - pts[0]).normalized()
		elif i == n - 1:
			t = (pts[n - 1] - pts[n - 2]).normalized()
		else:
			t = (pts[i + 1] - pts[i - 1]).normalized()
			v += pts[i].distance_to(pts[i - 1]) * v_scale
		if i == n - 1 and n > 1:
			v += pts[i].distance_to(pts[i - 1]) * v_scale
		normal = (normal - t * normal.dot(t)).normalized()
		var binormal := t.cross(normal)
		var ring: Array = []
		for s in sides + 1:
			var a := TAU * s / sides
			var dir := normal * cos(a) + binormal * sin(a)
			ring.append([pts[i] + dir * radii[i], dir, Vector2(float(s) / sides * u_repeat, v)])
		rings.append(ring)
	for i in n - 1:
		var ra: Array = rings[i]
		var rb: Array = rings[i + 1]
		for s in sides:
			quad(st, ra[s][0], ra[s + 1][0], rb[s + 1][0], rb[s][0], ra[s][1], ra[s + 1][1], rb[s + 1][1], rb[s][1],
				ra[s][2], ra[s + 1][2], rb[s + 1][2], rb[s][2], color)


## Random unit vector.
static func rand_dir(rng: RandomNumberGenerator) -> Vector3:
	var z := rng.randf_range(-1.0, 1.0)
	var a := rng.randf() * TAU
	var r := sqrt(1.0 - z * z)
	return Vector3(r * cos(a), z, r * sin(a))


## Any unit vector perpendicular to v.
static func perpendicular(v: Vector3) -> Vector3:
	var ref := Vector3.UP if absf(v.y) < 0.9 else Vector3.RIGHT
	return v.cross(ref).normalized()
