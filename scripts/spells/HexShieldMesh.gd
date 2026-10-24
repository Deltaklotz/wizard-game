class_name HexShieldMesh
extends RefCounted
## Hex-tile meshes for the shields (hex_shield.gdshader). Every tile is a separate fan with a
## small gap to its neighbours, and its vertices carry the data the shader needs to crack,
## reveal and shatter tiles one by one:
##   CUSTOM0 = (tile centre xyz, tile random 0..1)   NORMAL = tile normal
##   UV      = tile-local planar coordinates (tile radius ~0.5)
##   UV2     = (0 at the tile centre .. 1 at its rim, reveal order)
##
## dome(): Goldberg-style dome on the unit sphere – the dual of a subdivided icosahedron (hexagons
## plus a few pentagons), upper part only; reveal order = height (it rises from the ground).
## wall(): flat pointy-top hex grid in the XY plane facing -Z (rings around one centre tile);
## reveal order = ring index.

const GAP := 0.9

static var _dome: ArrayMesh
static var _walls := {}


static func dome() -> ArrayMesh:
	if _dome == null:
		_dome = _build_dome(4)
	return _dome


## Circumradius of one tile in metres.
static func wall(rings: int, tile_radius: float) -> ArrayMesh:
	var key := "%d|%.3f" % [rings, tile_radius]
	if not _walls.has(key):
		_walls[key] = _build_wall(rings, tile_radius)
	return _walls[key]


static func tile_count(rings: int) -> int:
	return 1 + 3 * rings * (rings + 1)


## Distance from the centre to the outermost tile corners of a wall with `rings` rings.
static func wall_extent(rings: int, tile_radius: float) -> float:
	return tile_radius * (sqrt(3.0) * rings + 1.0)


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	return st


## One tile: a fan from `center` through `corners` (ordered around it).
static func _tile(st: SurfaceTool, center: Vector3, normal: Vector3, corners: Array, rand: float, order: float,
		scale: float) -> void:
	var t1 := MeshUtil.perpendicular(normal)
	var t2 := normal.cross(t1)
	var custom := Color(center.x, center.y, center.z, rand)
	var pts: Array[Vector3] = []
	for c in corners:
		pts.append(center + ((c as Vector3) - center) * GAP)
	var uv := func(p: Vector3) -> Vector2:
		var d := p - center
		return Vector2(d.dot(t1), d.dot(t2)) / (scale * 2.0) + Vector2(0.5, 0.5)
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var tri := [[center, 0.0], [a, 1.0], [b, 1.0]]
		# Consistent winding (the shader draws both sides anyway).
		if (a - center).cross(b - center).dot(normal) > 0.0:
			tri = [[center, 0.0], [b, 1.0], [a, 1.0]]
		for v in tri:
			st.set_normal(normal)
			st.set_custom(0, custom)
			st.set_uv(uv.call(v[0]))
			st.set_uv2(Vector2(v[1], order))
			st.add_vertex(v[0])


static func _build_wall(rings: int, s: float) -> ArrayMesh:
	var st := _begin()
	var normal := Vector3(0, 0, -1)
	for q in range(-rings, rings + 1):
		for r in range(-rings, rings + 1):
			var ring := (absi(q) + absi(r) + absi(q + r)) / 2
			if ring > rings:
				continue
			var center := Vector3(s * sqrt(3.0) * (q + r * 0.5), s * 1.5 * r, 0.0)
			var corners: Array = []
			for k in 6:
				var a := deg_to_rad(30.0 + 60.0 * k)
				corners.append(center + Vector3(cos(a), sin(a), 0.0) * s)
			var rand := fmod(absf(sin(q * 12.9898 + r * 78.233) * 43758.5453), 1.0)
			_tile(st, center, normal, corners, rand, float(ring), s)
	return st.commit()


static func _build_dome(subdivisions: int) -> ArrayMesh:
	# Icosahedron.
	var t := (1.0 + sqrt(5.0)) * 0.5
	var verts: Array[Vector3] = []
	for v in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
			Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		verts.append((v as Vector3).normalized())
	var faces: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4],
		[11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for _s in subdivisions:
		var cache := {}
		var mid := func(a: int, b: int) -> int:
			var key := mini(a, b) * 100000 + maxi(a, b)
			if cache.has(key):
				return cache[key]
			verts.append((verts[a] + verts[b]).normalized())
			cache[key] = verts.size() - 1
			return verts.size() - 1
		var next: Array = []
		for f in faces:
			var ab: int = mid.call(f[0], f[1])
			var bc: int = mid.call(f[1], f[2])
			var ca: int = mid.call(f[2], f[0])
			next.append([f[0], ab, ca])
			next.append([f[1], bc, ab])
			next.append([f[2], ca, bc])
			next.append([ab, bc, ca])
		faces = next
	# Dual: one tile per vertex, its corners = the centroids of the faces around it.
	var around: Array = []
	around.resize(verts.size())
	for i in verts.size():
		around[i] = []
	for f in faces:
		var c := ((verts[f[0]] + verts[f[1]] + verts[f[2]]) / 3.0).normalized()
		for vi in f:
			around[vi].append(c)
	var st := _begin()
	var spacing := verts[faces[0][0]].distance_to(verts[faces[0][1]])
	for i in verts.size():
		var v := verts[i]
		if v.y < -0.12:
			continue
		var t1 := MeshUtil.perpendicular(v)
		var t2 := v.cross(t1)
		var corners: Array = around[i]
		corners.sort_custom(func(a: Vector3, b: Vector3) -> bool:
			return atan2((a - v).dot(t2), (a - v).dot(t1)) < atan2((b - v).dot(t2), (b - v).dot(t1)))
		var rand := fmod(absf(sin(v.x * 12.9898 + v.y * 78.233 + v.z * 37.719) * 43758.5453), 1.0)
		_tile(st, v, v, corners, rand, clampf(v.y, 0.0, 1.0), spacing * 0.6)
	return st.commit()
