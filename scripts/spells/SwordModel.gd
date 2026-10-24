class_name SwordModel
extends RefCounted
## Procedural giant sword for the Sword Wall spell (after an ornate golden dagger reference):
## a broad pearl blade with a lens-shaped cross-section, a gold-inlaid fuller and filigree near
## the base, a crossguard whose arms curl into scrolls (plus smaller scrolls rising towards the
## grip), a collar with a turquoise gem medallion on both faces, a banded grip and a crowned
## pommel with another gem. Everything is lathed or swept, so there are no boxy shapes.
##
## Model frame: blade base at y = 0 with the blade pointing down (tip at -BLADE_LEN), hilt
## upwards; the blade's width runs along X and its faces look along ±Z.
## Surfaces: 0 = blade, 1 = gold, 2 = gems (all use shaders/vfx/sword.gdshader with `part`).

const BLADE_LEN := 13.0
const HALF_WIDTH := 3.0
const HALF_THICK := 0.3
## Top of the pommel.
const HILT_TOP := 4.7

const SHADER := preload("res://shaders/vfx/sword.gdshader")

static var _mesh: ArrayMesh


static func mesh() -> ArrayMesh:
	if _mesh == null:
		_mesh = _build()
	return _mesh


static func _build() -> ArrayMesh:
	var m := ArrayMesh.new()
	var blade := _st()
	_blade(blade)
	_commit(blade, m, 0)
	var gold := _st()
	_guard(gold)
	_hilt(gold)
	_commit(gold, m, 1)
	var gems := _st()
	for side in [-1.0, 1.0]:
		_gem(gems, Vector3(0, 0.75, 0.5 * side), Vector3(0, 0, side), 0.27, 0.12, 0.2, 8)
	_gem(gems, Vector3(0, HILT_TOP - 0.85, 0.47), Vector3(0, 0, 1), 0.14, 0.06, 0.1, 8)
	_gem(gems, Vector3(0, HILT_TOP - 0.85, -0.47), Vector3(0, 0, -1), 0.14, 0.06, 0.1, 8)
	_commit(gems, m, 2)
	return m


static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _commit(st: SurfaceTool, m: ArrayMesh, part: int) -> void:
	st.index()
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("part", part)
	st.set_material(mat)
	st.commit(m)


# --- Blade ------------------------------------------------------------------------------

## Half width along the blade (v = 0 base .. 1 tip): a slight flare at the base, a gentle
## waist, then an ogive point.
static func _half_width(v: float) -> float:
	var w := HALF_WIDTH * (1.04 - 0.04 * smoothstep(0.0, 0.05, v)) * (1.0 - 0.1 * v)
	var t := clampf((v - 0.68) / 0.32, 0.0, 1.0)
	return w * sqrt(maxf(1.0 - t * t, 0.0)) * (1.0 - 0.15 * t)


static func _half_thick(v: float) -> float:
	return HALF_THICK * (1.0 - 0.55 * v)


## Where the edge bevel starts (|u|), as on a real blade: a gently sloping flat, then a steep
## polished bevel down to the sharp edge.
const BEVEL := 0.8

## Surface height above the mid-plane at u (-1..1 across the width): the sloping flat, the
## edge bevel (rounded into each other) and the fuller groove down the middle.
static func _height(u: float, v: float) -> float:
	var au := absf(u)
	var flat := 1.0 - 0.42 * au / BEVEL
	var bevel := (1.0 - 0.42) * (1.0 - au) / (1.0 - BEVEL)
	var k := 0.04
	var h := 0.5 * (flat + bevel - sqrt((flat - bevel) * (flat - bevel) + k * k))  # smooth min
	var groove := 0.3 * exp(-pow(u / 0.09, 2.0)) * (1.0 - smoothstep(0.72, 0.82, v))
	return _half_thick(v) * maxf(h - groove, 0.0)


static func _blade_point(u: float, v: float, side: float) -> Vector3:
	return Vector3(u * _half_width(v), -v * BLADE_LEN, side * _height(u, v))


static func _blade(st: SurfaceTool) -> void:
	# Denser samples near the centre (fuller) and the edges, and towards the tip.
	var us := PackedFloat32Array()
	const NU := 40
	for i in NU + 1:
		var s := float(i) / NU * 2.0 - 1.0
		us.append(signf(s) * (1.0 - pow(1.0 - absf(s), 1.6)) if absf(s) > 0.0 else 0.0)
	var vs := PackedFloat32Array()
	const NV := 70
	for j in NV + 1:
		var t := float(j) / NV
		vs.append(t * (0.6 + 0.4 * t) / 1.0)
	for side in [1.0, -1.0]:
		var pos: Array = []
		var nrm: Array = []
		for j in vs.size():
			var row_p: Array = []
			var row_n: Array = []
			for i in us.size():
				var u := us[i]
				var v := vs[j]
				var p := _blade_point(u, v, side)
				var du := _blade_point(clampf(u + 0.002, -1, 1), v, side) - _blade_point(clampf(u - 0.002, -1, 1), v, side)
				var dv := _blade_point(u, minf(v + 0.002, 1.0), side) - _blade_point(u, maxf(v - 0.002, 0.0), side)
				var n := du.cross(dv).normalized()
				if n.z * side < 0.0:
					n = -n
				if n.length_squared() < 0.5:
					n = Vector3(0, 0, side)
				row_p.append(p)
				row_n.append(n)
			pos.append(row_p)
			nrm.append(row_n)
		for j in vs.size() - 1:
			for i in us.size() - 1:
				var uv := func(ii: int, jj: int) -> Vector2: return Vector2(us[ii] * 0.5 + 0.5, vs[jj])
				MeshUtil.quad(st, pos[j][i], pos[j][i + 1], pos[j + 1][i + 1], pos[j + 1][i],
					nrm[j][i], nrm[j][i + 1], nrm[j + 1][i + 1], nrm[j + 1][i],
					uv.call(i, j), uv.call(i + 1, j), uv.call(i + 1, j + 1), uv.call(i, j + 1))


# --- Guard and hilt -----------------------------------------------------------------------

static func _guard(st: SurfaceTool) -> void:
	for sx in [-1.0, 1.0]:
		# Main arm: along the blade's base, then rolling down and outwards into a scroll.
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		const STRAIGHT := 14
		for i in STRAIGHT:
			var t := float(i) / (STRAIGHT - 1)
			pts.append(Vector3(sx * lerpf(0.0, 3.55, t), 0.22 + 0.2 * t * t, 0))
			radii.append(lerpf(0.5, 0.36, t))
		var r0 := 0.62
		var c := Vector3(sx * 3.55, 0.42 - r0, 0)
		const CURL := 40
		for i in range(1, CURL + 1):
			var t := float(i) / CURL
			var a := PI * 0.5 - t * TAU * 1.25
			var r := r0 * (1.0 - 0.62 * t)
			pts.append(c + Vector3(sx * cos(a) * r, sin(a) * r, 0))
			radii.append(lerpf(0.36, 0.11, t) if i < CURL else 0.0)
		MeshUtil.tube(st, pts, radii, 14, 1.0, 1.0)
		# Small scroll rising from the collar towards the grip, curling outwards.
		var up := PackedVector3Array()
		var ur := PackedFloat32Array()
		for i in 10:
			var t := float(i) / 9.0
			up.append(Vector3(sx * lerpf(0.55, 1.35, t), lerpf(0.55, 1.25, sin(t * PI * 0.5)), 0))
			ur.append(lerpf(0.2, 0.15, t))
		var c2 := Vector3(sx * 1.35, 1.25 - 0.3, 0)
		for i in range(1, 25):
			var t := float(i) / 24.0
			var a := PI * 0.5 - t * TAU * 1.1
			var r := 0.3 * (1.0 - 0.6 * t)
			up.append(c2 + Vector3(sx * cos(a) * r, sin(a) * r, 0))
			ur.append(lerpf(0.15, 0.06, t) if i < 24 else 0.0)
		MeshUtil.tube(st, up, ur, 10, 1.0, 1.0)
		# Hanging drop at the blade's shoulder.
		_lathe(st, Vector3(sx * 2.3, 0.0, 0), [Vector2(0, 0.12), Vector2(0.2, 0.0), Vector2(0.17, -0.25),
			Vector2(0.08, -0.45), Vector2(0, -0.55)], 12, 1.0, 1.0)
	# Gem medallions on both faces of the collar.
	for sz in [-1.0, 1.0]:
		var ring := PackedVector3Array()
		var rr := PackedFloat32Array()
		for i in 33:
			var a := TAU * i / 32.0
			ring.append(Vector3(cos(a) * 0.36, 0.75 + sin(a) * 0.36, 0.47 * sz))
			rr.append(0.07)
		MeshUtil.tube(st, ring, rr, 8, 1.0, 1.0)
		# Little beads around the setting.
		for i in 8:
			var a := TAU * (i + 0.5) / 8.0
			_lathe(st, Vector3(cos(a) * 0.5, 0.75 + sin(a) * 0.5, 0.4 * sz), [Vector2(0, 0.07), Vector2(0.06, 0.04),
				Vector2(0.07, 0.0), Vector2(0.06, -0.04), Vector2(0, -0.07)], 8, 1.0, 1.0)


static func _hilt(st: SurfaceTool) -> void:
	# Collar (elliptical: wide across the blade, flatter along Z).
	_lathe(st, Vector3.ZERO, [Vector2(0.0, 0.1), Vector2(0.75, 0.1), Vector2(0.95, 0.3), Vector2(1.0, 0.55),
		Vector2(0.9, 0.95), Vector2(0.62, 1.2), Vector2(0.45, 1.32), Vector2(0.0, 1.34)], 32, 0.95, 0.5)
	# Grip with raised bands.
	var grip: Array = [Vector2(0.0, 1.3), Vector2(0.4, 1.3), Vector2(0.44, 1.4)]
	var y := 1.45
	while y < HILT_TOP - 1.25:
		grip.append(Vector2(0.3, y + 0.04))
		grip.append(Vector2(0.31, y + 0.2))
		grip.append(Vector2(0.3, y + 0.33))
		grip.append(Vector2(0.37, y + 0.38))
		grip.append(Vector2(0.37, y + 0.44))
		y += 0.46
	grip.append(Vector2(0.42, HILT_TOP - 1.2))
	grip.append(Vector2(0.0, HILT_TOP - 1.18))
	_lathe(st, Vector3.ZERO, grip, 24, 1.0, 1.0)
	# Pommel: flared neck, bulb holding the gems, crown of points, finial.
	var top := HILT_TOP
	_lathe(st, Vector3.ZERO, [Vector2(0.0, top - 1.22), Vector2(0.45, top - 1.22), Vector2(0.55, top - 1.12),
		Vector2(0.42, top - 1.02), Vector2(0.5, top - 0.9), Vector2(0.56, top - 0.75), Vector2(0.5, top - 0.6),
		Vector2(0.34, top - 0.5), Vector2(0.4, top - 0.42), Vector2(0.0, top - 0.4)], 24, 1.0, 1.0)
	for i in 8:
		var a := TAU * i / 8.0
		var base := Vector3(cos(a) * 0.32, top - 0.45, sin(a) * 0.32)
		var tip := Vector3(cos(a) * 0.42, top - 0.05, sin(a) * 0.42)
		MeshUtil.tube(st, PackedVector3Array([base, base.lerp(tip, 0.5) + Vector3(cos(a), 0, sin(a)) * 0.05, tip]),
			PackedFloat32Array([0.08, 0.06, 0.0]), 6, 1.0, 1.0)
	_lathe(st, Vector3(0, top - 0.42, 0), [Vector2(0.0, 0.0), Vector2(0.18, 0.05), Vector2(0.1, 0.25),
		Vector2(0.16, 0.36), Vector2(0.0, 0.48)], 16, 1.0, 1.0)


## Surface of revolution around the Y axis through `center`. profile = [Vector2(radius, y)],
## from bottom to top; sx/sz stretch it into an ellipse.
static func _lathe(st: SurfaceTool, center: Vector3, profile: Array, segments: int, sx: float, sz: float) -> void:
	var n := profile.size()
	var normals: Array = []
	for i in n:
		var a: Vector2 = profile[maxi(i - 1, 0)]
		var b: Vector2 = profile[mini(i + 1, n - 1)]
		var t := (b - a).normalized()
		normals.append(Vector2(t.y, -t.x))  # outward: (dy, -dr)
	for i in n - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		var n0: Vector2 = normals[i]
		var n1: Vector2 = normals[i + 1]
		for s in segments:
			var a0 := TAU * s / segments
			var a1 := TAU * (s + 1) / segments
			var q := func(p: Vector2, a: float) -> Vector3:
				return center + Vector3(cos(a) * p.x * sx, p.y, sin(a) * p.x * sz)
			var qn := func(nn: Vector2, a: float) -> Vector3:
				return Vector3(cos(a) * nn.x / sx, nn.y, sin(a) * nn.x / sz).normalized()
			var uv := Vector2(float(s) / segments, float(i) / n)
			MeshUtil.quad(st, q.call(p0, a0), q.call(p0, a1), q.call(p1, a1), q.call(p1, a0),
				qn.call(n0, a0), qn.call(n0, a1), qn.call(n1, a1), qn.call(n1, a0), uv, uv, uv, uv)


## Faceted gem: a crown of `sides` facets rising to a table along `axis`, and a pavilion below.
static func _gem(st: SurfaceTool, center: Vector3, axis: Vector3, radius: float, crown: float, pavilion: float,
		sides: int) -> void:
	var x := MeshUtil.perpendicular(axis)
	var y := axis.cross(x)
	var table := center + axis * crown
	var culet := center - axis * pavilion
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		var g0 := center + (x * cos(a0) + y * sin(a0)) * radius
		var g1 := center + (x * cos(a1) + y * sin(a1)) * radius
		var t0 := table + (x * cos(a0) + y * sin(a0)) * radius * 0.55
		var t1 := table + (x * cos(a1) + y * sin(a1)) * radius * 0.55
		var nc := (g1 - g0).cross(t0 - g0).normalized()
		if nc.dot(axis) < 0.0:
			nc = -nc
		MeshUtil.quad(st, g0, g1, t1, t0, nc, nc, nc, nc, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		MeshUtil.tri(st, table, t0, t1, axis, axis, axis, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		var np := (g1 - g0).cross(culet - g0).normalized()
		if np.dot(axis) > 0.0:
			np = -np
		MeshUtil.tri(st, g0, g1, culet, np, np, np, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
