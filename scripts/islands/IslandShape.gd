class_name IslandShape
extends RefCounted
## Parametric description of one floating island plus its mesh builder.
## Local frame: y = 0 is roughly the rim of the grassy top, the rock body hangs below.
##
## The surface is swept as rows of rings: top pole -> top rings -> cliff band ->
## underside rings -> bottom tip. Every island gets its own outline, cliff height,
## underside taper, hanging spires and gully pattern, so no two look alike.

var radius: float
var stretch := Vector2.ONE
var stretch_angle := 0.0
var outline_amp := 0.2
var dome := 1.0
var hill_amp := 1.0
var rim_round := 1.0
var cliff := 5.0
var depth := 20.0
var under_pow := 1.6
var shrink := 1.0
var gully_amp := 1.0
var ledge_amp := 0.5
var tip_offset := Vector2.ZERO
## Fraction by which underside depth varies around the island (lopsided bodies).
var depth_variation := 0.3
## Amplitude of 3D noise that roughens the underside.
var crag_amp := 1.0
## Each: [center (Vector2), extra depth, sigma]
var spires: Array = []
## Optional rocky peak on top: [center, height, sigma] or empty.
var crown: Array = []

var _outline := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _gullies := FastNoiseLite.new()
var _ledges := FastNoiseLite.new()
var _crags := FastNoiseLite.new()


static func random(rng: RandomNumberGenerator, r: float) -> IslandShape:
	var s := IslandShape.new()
	s.radius = r
	s.stretch = Vector2(1.0, rng.randf_range(0.62, 1.0))
	s.stretch_angle = rng.randf() * TAU
	s.outline_amp = rng.randf_range(0.1, 0.3)
	s.dome = r * rng.randf_range(0.015, 0.07)
	s.hill_amp = r * rng.randf_range(0.02, 0.08)
	s.rim_round = r * rng.randf_range(0.02, 0.05)
	s.cliff = maxf(1.2, r * rng.randf_range(0.1, 0.35))
	s.depth = r * rng.randf_range(0.75, 1.7)
	s.under_pow = rng.randf_range(1.0, 2.4)
	s.shrink = rng.randf_range(0.6, 1.25)
	s.gully_amp = r * rng.randf_range(0.06, 0.13)
	s.depth_variation = rng.randf_range(0.2, 0.5)
	s.crag_amp = r * rng.randf_range(0.03, 0.07)
	if r < 9.0:
		# Small shards: chunkier, rougher and less cone-like.
		s.crag_amp = r * rng.randf_range(0.08, 0.14)
		s.under_pow = rng.randf_range(0.8, 1.6)
		s.depth = r * rng.randf_range(0.6, 1.3)
		s.stretch.y = rng.randf_range(0.5, 0.9)
	s.ledge_amp = r * rng.randf_range(0.01, 0.04)
	s.tip_offset = Vector2.from_angle(rng.randf() * TAU) * r * rng.randf_range(0.0, 0.25)
	var spire_count := rng.randi_range(0, 2) if r < 10.0 else rng.randi_range(2, 7)
	for i in spire_count:
		var c := Vector2.from_angle(rng.randf() * TAU) * r * sqrt(rng.randf()) * 0.72
		s.spires.append([c, s.depth * rng.randf_range(0.25, 0.9), r * rng.randf_range(0.08, 0.26)])
	if rng.randf() < 0.35:
		var c := Vector2.from_angle(rng.randf() * TAU) * r * rng.randf_range(0.0, 0.45)
		s.crown = [c, r * rng.randf_range(0.12, 0.4), r * rng.randf_range(0.12, 0.28)]
	var seed := rng.randi()
	s._outline.seed = seed
	s._outline.frequency = 0.35
	s._outline.fractal_octaves = 3
	s._hills.seed = seed + 1
	s._hills.frequency = 2.2 / r
	s._hills.fractal_octaves = 4
	s._gullies.seed = seed + 2
	s._gullies.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	s._gullies.frequency = 0.09
	s._gullies.fractal_octaves = 3
	s._ledges.seed = seed + 3
	s._ledges.frequency = 0.25
	s._crags.seed = seed + 4
	s._crags.frequency = clampf(1.5 / r, 0.06, 0.45)
	s._crags.fractal_octaves = 3
	return s


func rim_radius(theta: float) -> float:
	var n := _outline.get_noise_2d(cos(theta) * 3.0, sin(theta) * 3.0)
	var phi := theta - stretch_angle
	var e := 1.0 / sqrt(pow(cos(phi) / stretch.x, 2.0) + pow(sin(phi) / stretch.y, 2.0))
	return radius * (1.0 + outline_amp * n) * e


## Height of the grassy top surface at local (x, z).
func top_y(x: float, z: float) -> float:
	var theta := atan2(z, x)
	var rho := clampf(Vector2(x, z).length() / rim_radius(theta), 0.0, 1.0)
	var y := dome * (1.0 - rho * rho)
	y += _hills.get_noise_2d(x, z) * hill_amp * (1.0 - pow(rho, 4.0))
	y -= rim_round * smoothstep(0.8, 1.0, rho)
	if not crown.is_empty():
		var d: float = (Vector2(x, z) - crown[0]).length()
		y += crown[1] * exp(-d * d / (crown[2] * crown[2]))
	return y


## Local cliff bottom height at an angle.
func cliff_bottom(theta: float) -> float:
	return -cliff * (1.0 + 0.3 * _outline.get_noise_2d(cos(theta) * 5.0 + 11.0, sin(theta) * 5.0))


func bottom_y() -> float:
	var deepest := 0.0
	for s in spires:
		deepest = maxf(deepest, s[1])
	return -cliff * 1.3 - depth - deepest


## Conservative (lowest) underside height anywhere on the circle of horizontal radius `rr`,
## including hanging spires that the circle passes near. Used to keep orbiting rocks clear.
func lowest_underside_at(rr: float) -> float:
	var max_rim := radius * (1.0 + outline_amp)
	var t := clampf(rr / max_rim, 0.0, 1.0)
	var y := -cliff * 1.3 - depth * (1.0 + depth_variation) * (1.0 - pow(t, under_pow / shrink))
	for s in spires:
		var c: Vector2 = s[0]
		var d := absf(c.length() - rr)
		y -= s[1] * exp(-d * d / (s[2] * s[2]))
	return y - crag_amp - gully_amp


## Points at the bottom of the tip and of each spire (for crystals, roots, glow).
func tip_points() -> Array[Vector3]:
	var pts: Array[Vector3] = [Vector3(tip_offset.x, _under_y(1.0, tip_offset, 0.0), tip_offset.y)]
	for s in spires:
		var c: Vector2 = s[0]
		var u := 1.0 - pow(clampf(c.length() / radius, 0.0, 1.0), 1.0 / shrink)
		pts.append(Vector3(c.x, _under_y(u, c, 0.0), c.y))
	return pts


func _under_y(u: float, p: Vector2, theta: float) -> float:
	# Depth varies around the island, fading to the average at the tip.
	var lopsided := 1.0 + depth_variation * _outline.get_noise_2d(cos(theta) * 2.0 + 40.0, sin(theta) * 2.0) * (1.0 - u * u)
	var y := cliff_bottom(theta) - depth * lopsided * (1.0 - pow(1.0 - u, under_pow))
	var fade := smoothstep(0.0, 0.35, u)
	for s in spires:
		var d: float = (p - s[0]).length()
		y -= s[1] * exp(-d * d / (s[2] * s[2])) * fade
	return y


func _gully(theta: float, y: float) -> float:
	return _gullies.get_noise_3d(cos(theta) * radius, y * 0.35, sin(theta) * radius)


func build_mesh(material: Material) -> ArrayMesh:
	var segments := clampi(int(radius * 2.6), 24, 150)
	var top_rings := clampi(int(radius / 3.0), 4, 18)
	var cliff_rings := clampi(int(cliff / 1.5), 3, 8)
	var under_rings := clampi(int(radius / 2.2), 6, 26)
	var rows: Array[PackedVector3Array] = []
	var colors: Array[Color] = []
	var total_depth := -bottom_y()

	var rims := PackedFloat32Array()
	var thetas := PackedFloat32Array()
	for s in segments:
		var th := TAU * s / segments
		thetas.append(th)
		rims.append(rim_radius(th))

	# Top: pole + rings.
	for i in top_rings + 1:
		var rho := float(i) / top_rings
		var row := PackedVector3Array()
		for s in segments:
			var x := cos(thetas[s]) * rims[s] * rho
			var z := sin(thetas[s]) * rims[s] * rho
			row.append(Vector3(x, top_y(x, z), z))
		rows.append(row)
		colors.append(Color(1.0, 0.0, 0.0))

	# Cliff band with ledges and vertical gullies.
	var rim_top := rows[rows.size() - 1]
	for k in range(1, cliff_rings + 1):
		var t := float(k) / cliff_rings
		var row := PackedVector3Array()
		for s in segments:
			var th := thetas[s]
			var y := lerpf(rim_top[s].y, cliff_bottom(th), t)
			var r := rims[s] + _ledges.get_noise_2d(th * radius * 0.3, y * 2.0) * ledge_amp * 2.0 + _gully(th, y) * gully_amp * 0.6 * sin(t * PI)
			row.append(Vector3(cos(th) * r, y, sin(th) * r))
		rows.append(row)
		colors.append(Color(0.0, 0.05 * t, 0.0))

	# Underside down to the tip.
	for j in range(1, under_rings + 1):
		var u := float(j) / under_rings
		var rho := pow(1.0 - u, shrink)
		var row := PackedVector3Array()
		for s in segments:
			var th := thetas[s]
			var base := Vector2(cos(th), sin(th)) * rims[s] * rho
			var p := base.lerp(tip_offset, u * u)
			var y := _under_y(u, p, th)
			var g := _gully(th, y) * gully_amp * (1.0 - u * 0.7) * 1.3
			p += Vector2(cos(th), sin(th)) * g
			var crag := Vector3(_crags.get_noise_3d(p.x, y, p.y), _crags.get_noise_3d(p.x + 50.0, y, p.y), _crags.get_noise_3d(p.x, y + 50.0, p.y)) * crag_amp * (1.0 - u)
			row.append(Vector3(p.x, y, p.y) + crag)
		rows.append(row)
		colors.append(Color(0.0, clampf(-row[0].y / total_depth, 0.0, 1.0), 0.0))

	# Index the grid.
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for r in rows.size():
		verts.append_array(rows[r])
		for s in segments:
			cols.append(colors[r])
	var idx := PackedInt32Array()
	for r in rows.size() - 1:
		for s in segments:
			var s2 := (s + 1) % segments
			var a := r * segments + s
			var b := r * segments + s2
			var c := (r + 1) * segments + s
			var d := (r + 1) * segments + s2
			idx.append_array([a, c, b, b, c, d])
	# Pick the winding so the top faces up (Godot front faces are clockwise).
	var probe := (verts[idx[4]] - verts[idx[3]]).cross(verts[idx[5]] - verts[idx[3]])
	if probe.y > 0.0:
		for i in range(0, idx.size(), 3):
			var tmp := idx[i + 1]
			idx[i + 1] = idx[i + 2]
			idx[i + 2] = tmp

	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in range(0, idx.size(), 3):
		var fn := (verts[idx[i + 2]] - verts[idx[i]]).cross(verts[idx[i + 1]] - verts[idx[i]])
		normals[idx[i]] += fn
		normals[idx[i + 1]] += fn
		normals[idx[i + 2]] += fn
	for i in normals.size():
		normals[i] = normals[i].normalized()
	# The poles collapse to a point; give them clean normals.
	for s in segments:
		normals[s] = Vector3.UP
		normals[verts.size() - 1 - s] = Vector3.DOWN

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh
