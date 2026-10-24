class_name WizardModel
extends RefCounted
## Procedural wizard figure for other players (and the colour preview on the connect
## screen): flowing robe, sleeves, belt, bearded head, a floppy pointed hat in the
## player's colour and a small book in hand. Feet at the origin, facing -Z, ~2.1 m tall.

const SKIN := Color(0.86, 0.68, 0.55)
const BEARD := Color(0.86, 0.85, 0.82)
const GOLD := Color(0.83, 0.64, 0.26)
const LEATHER := Color(0.33, 0.2, 0.12)


static func build(color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Wizard"
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.85
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var robe := color.darkened(0.15)
	var hat := color
	_robe(st, robe, color.lightened(0.35).lerp(GOLD, 0.6))
	_ring(st, 0.93, 0.255, 0.035, LEATHER)
	_ring(st, 1.66, 0.155, 0.03, GOLD.lerp(color, 0.3))
	# Sleeves reaching forward, hands just out of them.
	for side in [-1.0, 1.0]:
		var pts := PackedVector3Array([Vector3(side * 0.2, 1.33, 0.0), Vector3(side * 0.3, 1.12, -0.06),
			Vector3(side * 0.27, 1.0, -0.2), Vector3(side * 0.19, 0.98, -0.3)])
		MeshUtil.tube(st, pts, PackedFloat32Array([0.075, 0.085, 0.1, 0.12]), 10, 1.0, 1.0, robe.darkened(0.05))
		_sphere(st, Vector3(side * 0.17, 0.96, -0.35), Vector3.ONE * 0.05, SKIN)
	_sphere(st, Vector3(0, 1.53, 0), Vector3(0.12, 0.135, 0.12), SKIN)
	_sphere(st, Vector3(0, 1.525, -0.115), Vector3(0.025, 0.03, 0.03), SKIN.darkened(0.08))
	for side in [-1.0, 1.0]:
		_sphere(st, Vector3(side * 0.045, 1.56, -0.105), Vector3.ONE * 0.016, Color(0.08, 0.06, 0.05))
	# Beard: a drooping cone from the chin.
	MeshUtil.tube(st, PackedVector3Array([Vector3(0, 1.49, -0.07), Vector3(0, 1.4, -0.12), Vector3(0, 1.28, -0.13), Vector3(0, 1.18, -0.1)]),
		PackedFloat32Array([0.1, 0.085, 0.05, 0.005]), 10, 1.0, 1.0, BEARD)
	# Hat: wide brim and a bent, tapering cone.
	_disc(st, Vector3(0, 1.64, 0), 0.3, 0.02, hat.darkened(0.1))
	var cone := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 9:
		var t := i / 8.0
		cone.append(Vector3(0.0, 1.64 + t * 0.5, t * t * 0.18))
		radii.append(lerpf(0.16, 0.012, pow(t, 0.8)))
	MeshUtil.tube(st, cone, radii, 12, 1.0, 1.0, hat)
	# Book held in front.
	_box(st, Vector3(0.0, 0.97, -0.36), Vector3(0.24, 0.035, 0.17), LEATHER.lerp(color, 0.25))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	root.add_child(mi)
	return root


static func _robe(st: SurfaceTool, color: Color, trim: Color) -> void:
	# Lathe profile [height, radius]; folds wobble the hem.
	var profile := [[0.0, 0.34], [0.06, 0.33], [0.4, 0.28], [0.8, 0.235], [0.95, 0.24], [1.2, 0.235], [1.35, 0.2], [1.44, 0.09]]
	var sides := 24
	var rows: Array = []
	for p in profile:
		var ring: Array = []
		var fold: float = (1.0 - smoothstep(0.0, 0.9, p[0])) * 0.035
		for s in sides + 1:
			var a := TAU * s / sides
			var r: float = p[1] + sin(a * 7.0) * fold
			ring.append(Vector3(cos(a) * r, p[0], sin(a) * r))
		rows.append(ring)
	for i in rows.size() - 1:
		var c := trim if i == 0 else color
		for s in sides:
			var a: Vector3 = rows[i][s]
			var b: Vector3 = rows[i][s + 1]
			var cc: Vector3 = rows[i + 1][s + 1]
			var d: Vector3 = rows[i + 1][s]
			var na := Vector3(a.x, 0.15, a.z).normalized()
			var nb := Vector3(b.x, 0.15, b.z).normalized()
			MeshUtil.quad(st, a, b, cc, d, na, nb, nb, na, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, c)


static func _ring(st: SurfaceTool, y: float, radius: float, half_h: float, color: Color) -> void:
	var sides := 24
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		var p0 := Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		MeshUtil.quad(st, p0 + Vector3.UP * (y - half_h), p1 + Vector3.UP * (y - half_h), p1 + Vector3.UP * (y + half_h),
			p0 + Vector3.UP * (y + half_h), p0.normalized(), p1.normalized(), p1.normalized(), p0.normalized(),
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, color)


static func _disc(st: SurfaceTool, c: Vector3, radius: float, h: float, color: Color) -> void:
	var sides := 24
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		# Brim droops slightly at the edge.
		var p0 := c + Vector3(cos(a0) * radius, -0.03, sin(a0) * radius)
		var p1 := c + Vector3(cos(a1) * radius, -0.03, sin(a1) * radius)
		MeshUtil.tri(st, c + Vector3.UP * h, p0, p1, Vector3.UP, Vector3.UP, Vector3.UP, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, color)
		MeshUtil.tri(st, c, p1, p0, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, color.darkened(0.2))


static func _sphere(st: SurfaceTool, c: Vector3, r: Vector3, color: Color) -> void:
	var rings := 8
	var sides := 12
	for i in rings:
		var t0 := PI * i / rings
		var t1 := PI * (i + 1) / rings
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var n := [Vector3(sin(t0) * cos(a0), cos(t0), sin(t0) * sin(a0)), Vector3(sin(t0) * cos(a1), cos(t0), sin(t0) * sin(a1)),
				Vector3(sin(t1) * cos(a1), cos(t1), sin(t1) * sin(a1)), Vector3(sin(t1) * cos(a0), cos(t1), sin(t1) * sin(a0))]
			MeshUtil.quad(st, c + n[0] * r, c + n[1] * r, c + n[2] * r, c + n[3] * r, n[0], n[1], n[2], n[3],
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, color)


static func _box(st: SurfaceTool, c: Vector3, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	for axis in 3:
		for sgn in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sgn
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = h[(axis + 1) % 3]
			var v := Vector3.ZERO
			v[(axis + 2) % 3] = h[(axis + 2) % 3]
			var f := c + n * h[axis]
			MeshUtil.quad(st, f - u - v, f + u - v, f + u + v, f - u + v, n, n, n, n,
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, color)
