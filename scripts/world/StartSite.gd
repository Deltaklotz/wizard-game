class_name StartSite
extends Node3D
## The Waystone Circle: the starting location near the middle of the map where every
## player spawns. A paved round plaza with a kerb, a stepped dais carrying a rune pillar
## (the magic orb floats above it), a glowing rune ring inlaid in the paving and a ring
## of weathered standing stones, one of them fallen. Worn dirt paths lead away in the
## four directions.
## find() + flatten() run on the heightmap before the terrain is built (like LakeShape);
## build() adds the geometry afterwards.

const SITE_NAME := "Waystone Circle"
const PLAZA_RADIUS := 11.0
const KERB_WIDTH := 0.6
const STONE_RING := 14.5
const FLAT_RADIUS := 18.0
const BLEND_RADIUS := 36.0
## No trees within this radius (rocks: 75 %).
const CLEAR_RADIUS := 30.0
const PATH_LENGTH := 48.0
const ORB_HEIGHT := 4.1
## Paving top above the flattened ground (which is raised by PAVE_LIFT inside the plaza).
const PAVE_TOP := 0.15
const PAVE_LIFT := 0.1
const RUNE_COLOR := Color(0.45, 0.72, 1.0)

var center: Vector2
var level: float
var path_angle := 0.0
var seed := 0


## Flattest dry spot close to the middle of the map, away from the lake and bare rock.
static func find(data: TerrainData, world_seed: int) -> StartSite:
	var site := StartSite.new()
	site.name = "StartSite"
	site.seed = world_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 7 + 3
	site.path_angle = rng.randf() * TAU
	var best := INF
	var step := 10.0
	var reach := 32
	for zi in range(-reach, reach + 1):
		for xi in range(-reach, reach + 1):
			var c := Vector2(xi, zi) * step
			var dist := c.length()
			if dist > reach * step:
				continue
			var near_water := false
			for lake in data.lakes:
				if c.distance_to(lake.center) < lake.outer_radius() + BLEND_RADIUS + 10.0:
					near_water = true
			if near_water:
				continue
			var sum := 0.0
			var sum2 := 0.0
			var rock := 0.0
			var n := 0
			for ring: float in [0.0, 8.0, 16.0, 24.0]:
				var count := 1 if ring == 0.0 else 10
				for k in count:
					var p := c + Vector2.from_angle(TAU * k / count) * ring
					var h := data.height_at(p.x, p.y)
					sum += h
					sum2 += h * h
					rock += data.rock_at(p.x, p.y)
					n += 1
			var mean := sum / n
			var std := sqrt(maxf(sum2 / n - mean * mean, 0.0))
			var score := std + rock * 2.0 + dist * 0.012
			if score < best:
				best = score
				site.center = c
	return site


## Levels the plaza, blends it into the surroundings, paints worn ground and paths and
## registers the clearing so no trees, rocks or grass grow on it.
func flatten(data: TerrainData) -> void:
	var sum := 0.0
	var n := 0
	for ring: float in [0.0, 6.0, 12.0, FLAT_RADIUS]:
		for k in 12:
			var p := center + Vector2.from_angle(TAU * k / 12.0) * ring
			sum += data.height_at(p.x, p.y)
			n += 1
	level = sum / n
	var path_noise := FastNoiseLite.new()
	path_noise.seed = seed
	path_noise.frequency = 0.08
	var res := data.resolution
	var o := data.origin()
	var reach := PATH_LENGTH + 4.0
	var x0 := clampi(int((center.x - reach - o.x) / data.cell_size), 0, res - 1)
	var x1 := clampi(int((center.x + reach - o.x) / data.cell_size) + 1, 0, res - 1)
	var z0 := clampi(int((center.y - reach - o.y) / data.cell_size), 0, res - 1)
	var z1 := clampi(int((center.y + reach - o.y) / data.cell_size) + 1, 0, res - 1)
	for gz in range(z0, z1 + 1):
		for gx in range(x0, x1 + 1):
			var p := Vector2(o.x + gx * data.cell_size, o.y + gz * data.cell_size)
			var off := p - center
			var d := off.length()
			var i := gz * res + gx
			if d < BLEND_RADIUS:
				var target := level + PAVE_LIFT * (1.0 - smoothstep(PLAZA_RADIUS, PLAZA_RADIUS + 3.0, d))
				data.heights[i] = lerpf(data.heights[i], target, 1.0 - smoothstep(FLAT_RADIUS, BLEND_RADIUS, d))
				data.rock.set_pixel(gx, gz, Color(0, 0, 0))
			# Worn earth around the kerb and along four paths.
			var wear := 1.0 - smoothstep(PLAZA_RADIUS + 1.0, PLAZA_RADIUS + 5.0 + path_noise.get_noise_2dv(p) * 2.0, d)
			for k in 4:
				var dir := Vector2.from_angle(path_angle + k * PI * 0.5)
				var along := off.dot(dir)
				if along > PLAZA_RADIUS and along < PATH_LENGTH:
					var wander := sin(along * 0.09 + k * 1.7) * 2.5 * smoothstep(PLAZA_RADIUS, PLAZA_RADIUS + 15.0, along)
					var side := absf(off.dot(dir.orthogonal()) - wander)
					var width := 1.3 + path_noise.get_noise_2dv(p * 1.5) * 0.4
					var fade := 1.0 - smoothstep(PATH_LENGTH - 12.0, PATH_LENGTH, along)
					wear = maxf(wear, (1.0 - smoothstep(width * 0.6, width, side)) * fade)
			if d < BLEND_RADIUS or wear > 0.0:
				# Meadow around the circle (flat ground is often sediment = dirt), worn paths.
				var ctl := data.control.get_pixel(gx, gz)
				var meadow := 1.0 - smoothstep(FLAT_RADIUS, BLEND_RADIUS, d)
				ctl.r = lerpf(ctl.r, minf(ctl.r, 0.25), meadow)
				ctl.g = lerpf(ctl.g, minf(ctl.g, 0.4), meadow)
				ctl.r = maxf(ctl.r, 0.9 * wear)
				data.control.set_pixel(gx, gz, ctl)
	data.clearings.append(Vector4(center.x, center.y, CLEAR_RADIUS, PLAZA_RADIUS + KERB_WIDTH))


## Spawn point for the player with the given index: spread on the plaza around the dais.
func spawn_point(index: int) -> Vector3:
	var a := path_angle + PI * 0.25 + index * 2.39996
	var r := 6.0 + (index % 3) * 1.2
	return Vector3(center.x + cos(a) * r, level + PAVE_TOP, center.y + sin(a) * r)


func orb_position() -> Vector3:
	return Vector3(center.x, level + ORB_HEIGHT, center.y)


# --- Geometry --------------------------------------------------------------------------

func build() -> void:
	position = Vector3(center.x, level, center.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 13 + 5
	var assets := VegetationAssets.get_shared()
	var cut_stone := assets.mat_rock.duplicate() as ShaderMaterial
	cut_stone.set_shader_parameter("moss_amount", 0.12)
	cut_stone.set_shader_parameter("tint", Color(1.08, 1.04, 0.98))
	var bedding := assets.mat_rock.duplicate() as ShaderMaterial
	bedding.set_shader_parameter("moss_amount", 0.0)
	bedding.set_shader_parameter("tint", Color(0.3, 0.27, 0.23))
	var glow := StandardMaterial3D.new()
	glow.albedo_color = RUNE_COLOR
	glow.emission_enabled = true
	glow.emission = RUNE_COLOR
	glow.emission_energy_multiplier = 2.5

	# Dark bedding under the stones shows in the joints.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_slab(st, _circle(PLAZA_RADIUS + KERB_WIDTH, 64), PAVE_LIFT + 0.02, -0.6, 0.0)
	_add_mesh(st, bedding, "Bedding")

	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_paving(st, rng)
	_dais_and_pillar(st)
	_add_mesh(st, cut_stone, "Paving")

	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_runes(st, rng)
	var runes := _add_mesh(st, glow, "Runes")
	runes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var light := OmniLight3D.new()
	light.light_color = RUNE_COLOR
	light.light_energy = 1.4
	light.omni_range = 14.0
	light.shadow_enabled = false
	light.position.y = ORB_HEIGHT - 0.3
	add_child(light)

	_standing_stones(rng, assets)
	_collision()


func _add_mesh(st: SurfaceTool, mat: Material, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
	return mi


func _circle(r: float, sides: int, phase := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for s in sides:
		pts.append(Vector2.from_angle(phase + TAU * s / sides) * r)
	return pts


## A stone block: `poly` (roughly convex, any winding) extruded from `bottom` to `top`,
## with a bevel of `bevel` metres around the top face. `tilt` slopes the top slightly.
## `underside` closes the bottom, for blocks that overhang and can be seen from below.
func _slab(st: SurfaceTool, poly: PackedVector2Array, top: float, bottom: float, bevel: float, tilt := Vector2.ZERO,
		underside := false) -> void:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= poly.size()
	var n := poly.size()
	var inner := PackedVector2Array()
	for p in poly:
		var toward := c - p
		inner.append(p + toward.normalized() * minf(bevel, toward.length() * 0.4))
	var top_y := func(p: Vector2) -> float: return top + (p - c).dot(tilt)
	var up := Vector3(-tilt.x, 1.0, -tilt.y).normalized()
	var ct := Vector3(c.x, top_y.call(c), c.y)
	for k in n:
		var k2 := (k + 1) % n
		var a := inner[k]
		var b := inner[k2]
		MeshUtil.tri(st, ct, Vector3(a.x, top_y.call(a), a.y), Vector3(b.x, top_y.call(b), b.y), up, up, up,
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		var pa := poly[k]
		var pb := poly[k2]
		var out := Vector3(pb.y - pa.y, 0.0, pa.x - pb.x).normalized()
		if out.dot(Vector3(pa.x - c.x, 0.0, pa.y - c.y)) < 0.0:
			out = -out
		var bev_n := (out + up).normalized()
		var ya: float = top_y.call(pa) - bevel * 0.8
		var yb: float = top_y.call(pb) - bevel * 0.8
		if bevel > 0.0:
			MeshUtil.quad(st, Vector3(a.x, top_y.call(a), a.y), Vector3(b.x, top_y.call(b), b.y), Vector3(pb.x, yb, pb.y),
				Vector3(pa.x, ya, pa.y), bev_n, bev_n, bev_n, bev_n, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		else:
			ya = top_y.call(pa)
			yb = top_y.call(pb)
		MeshUtil.quad(st, Vector3(pa.x, ya, pa.y), Vector3(pb.x, yb, pb.y), Vector3(pb.x, bottom, pb.y), Vector3(pa.x, bottom, pa.y),
			out, out, out, out, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		if underside:
			MeshUtil.tri(st, Vector3(c.x, bottom, c.y), Vector3(pa.x, bottom, pa.y), Vector3(pb.x, bottom, pb.y),
				Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)


## Concentric courses of flagstones with jittered joints, and a kerb of long stones.
func _paving(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var gap := 0.035
	var r := 3.3
	while r < PLAZA_RADIUS - 0.3:
		var width := minf(rng.randf_range(0.9, 1.4), PLAZA_RADIUS - r)
		_course(st, rng, r, r + width, 1.35, PAVE_LIFT + PAVE_TOP, gap, 0.04)
		r += width
	_course(st, rng, PLAZA_RADIUS, PLAZA_RADIUS + KERB_WIDTH, 1.9, PAVE_LIFT + PAVE_TOP + 0.05, gap, 0.06)


func _course(st: SurfaceTool, rng: RandomNumberGenerator, r0: float, r1: float, length: float, top: float, gap: float, bevel: float) -> void:
	var mid := (r0 + r1) * 0.5
	var count := maxi(6, roundi(TAU * mid / length))
	var phase := rng.randf() * TAU
	var cuts := PackedFloat32Array()
	for k in count:
		cuts.append(phase + (k + rng.randf_range(-0.25, 0.25)) * TAU / count)
	for k in count:
		var a0 := cuts[k] + gap * 0.5 / mid
		var a1 := (cuts[(k + 1) % count] + (TAU if k == count - 1 else 0.0)) - gap * 0.5 / mid
		if rng.randf() < 0.03:
			continue  # a missing stone
		var poly := PackedVector2Array()
		var steps := 3
		for s in steps + 1:
			poly.append(Vector2.from_angle(lerpf(a0, a1, float(s) / steps)) * (r1 - gap * 0.5))
		for s in steps + 1:
			poly.append(Vector2.from_angle(lerpf(a1, a0, float(s) / steps)) * (r0 + gap * 0.5))
		var tilt := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.012
		_slab(st, poly, top + rng.randf_range(-0.02, 0.015), PAVE_LIFT - 0.2, bevel, tilt)


func _dais_and_pillar(st: SurfaceTool) -> void:
	var steps := [[3.4, 0.36], [2.75, 0.56], [2.1, 0.76]]
	for s in steps:
		_slab(st, _circle(s[0], 8, PI / 8.0), PAVE_LIFT + s[1], 0.0, 0.05)
	var y0: float = PAVE_LIFT + steps[2][1]
	_slab(st, _circle(0.62, 8, PI / 8.0), y0 + 0.28, y0 - 0.1, 0.04)
	# Tapered octagonal shaft.
	var sides := 8
	var shaft_top := ORB_HEIGHT - 1.0
	for k in sides:
		var a0 := PI / 8.0 + TAU * k / sides
		var a1 := PI / 8.0 + TAU * (k + 1) / sides
		var b0 := Vector3(cos(a0) * 0.42, y0 + 0.28, sin(a0) * 0.42)
		var b1 := Vector3(cos(a1) * 0.42, y0 + 0.28, sin(a1) * 0.42)
		var t0 := Vector3(cos(a0) * 0.32, shaft_top, sin(a0) * 0.32)
		var t1 := Vector3(cos(a1) * 0.32, shaft_top, sin(a1) * 0.32)
		var nrm := Vector3(cos((a0 + a1) * 0.5), 0.1, sin((a0 + a1) * 0.5)).normalized()
		MeshUtil.quad(st, b0, b1, t1, t0, nrm, nrm, nrm, nrm, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	# Capital: a wider block with a flared bowl for the orb.
	_slab(st, _circle(0.5, 8, PI / 8.0), shaft_top + 0.22, shaft_top - 0.02, 0.04, Vector2.ZERO, true)
	_slab(st, _circle(0.62, 8, 0.0), shaft_top + 0.36, shaft_top + 0.2, 0.05, Vector2.ZERO, true)


## Glowing inlays: a ring of runes in the paving, bands around the pillar.
func _runes(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var y := PAVE_LIFT + PAVE_TOP + 0.03
	var ring_r := 7.3
	_annulus(st, ring_r - 0.05, ring_r + 0.05, y, 96)
	_annulus(st, ring_r + 0.7, ring_r + 0.76, y, 96)
	for k in 16:
		var a := TAU * k / 16.0 + 0.1
		var base := Vector2.from_angle(a) * (ring_r + 0.38)
		var t := Vector2.from_angle(a).orthogonal()
		var rad := Vector2.from_angle(a)
		# Each rune: a few strokes from a small alphabet of shapes.
		var strokes: Array = [[-rad * 0.22, rad * 0.22]]
		match rng.randi() % 4:
			0: strokes.append([rad * 0.22, rad * 0.05 + t * 0.14])
			1: strokes.append([-rad * 0.05 - t * 0.13, rad * 0.12 + t * 0.13])
			2: strokes.append_array([[rad * 0.1, rad * 0.1 + t * 0.13], [-rad * 0.1, -rad * 0.1 - t * 0.13]])
			3: strokes.append([-t * 0.12, t * 0.12])
		for s in strokes:
			_stroke(st, base + s[0], base + s[1], 0.035, y)
	var y0 := PAVE_LIFT + 0.76 + 0.28
	for band_y in [y0 + 0.9, y0 + 1.5]:
		var r := lerpf(0.42, 0.32, (band_y - y0) / (ORB_HEIGHT - 1.0 - y0)) + 0.012
		for k in 8:
			var a0 := PI / 8.0 + TAU * k / 8.0
			var a1 := PI / 8.0 + TAU * (k + 1) / 8.0
			var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
			var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
			var nrm := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
			MeshUtil.quad(st, p0 + Vector3.UP * band_y, p1 + Vector3.UP * band_y, p1 + Vector3.UP * (band_y + 0.06),
				p0 + Vector3.UP * (band_y + 0.06), nrm, nrm, nrm, nrm, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)


func _annulus(st: SurfaceTool, r0: float, r1: float, y: float, sides: int) -> void:
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		MeshUtil.quad(st, Vector3(cos(a0) * r0, y, sin(a0) * r0), Vector3(cos(a1) * r0, y, sin(a1) * r0),
			Vector3(cos(a1) * r1, y, sin(a1) * r1), Vector3(cos(a0) * r1, y, sin(a0) * r1),
			Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)


func _stroke(st: SurfaceTool, a: Vector2, b: Vector2, w: float, y: float) -> void:
	var side := (b - a).normalized().orthogonal() * w * 0.5
	MeshUtil.quad(st, Vector3(a.x + side.x, y, a.y + side.y), Vector3(b.x + side.x, y, b.y + side.y),
		Vector3(b.x - side.x, y, b.y - side.y), Vector3(a.x - side.x, y, a.y - side.y),
		Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)


## Weathered menhirs between the paths; one has toppled over.
func _standing_stones(rng: RandomNumberGenerator, assets: VegetationAssets) -> void:
	var body := StaticBody3D.new()
	body.name = "StoneColliders"
	add_child(body)
	var slots := 12
	var fallen := rng.randi() % slots
	for k in slots:
		var a := path_angle + PI / slots + TAU * k / slots
		if rng.randf() < 0.12 and k != fallen:
			continue
		var mesh := RockGenerator.rock(900 + seed % 1000 + k, 2, 1.0)
		mesh.surface_set_material(0, assets.mat_rock)
		var r := STONE_RING + rng.randf_range(-0.5, 0.5)
		var pos := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var height := rng.randf_range(1.9, 2.6)
		var sc := Vector3(rng.randf_range(0.65, 0.85), height, rng.randf_range(0.42, 0.55))
		var yaw := -a + PI * 0.5 + rng.randf_range(-0.2, 0.2)
		var basis := Basis(Vector3.UP, yaw)
		if k == fallen:
			basis = basis * Basis(Vector3.RIGHT, PI * 0.5 - 0.12) * Basis(Vector3.UP, rng.randf_range(-0.3, 0.3))
			pos.y = 0.25
		else:
			var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
			basis = Basis(lean.cross(Vector3.UP).normalized(), rng.randf_range(0.0, 0.09)) * basis
			pos.y = 0.3 * height - 0.25
		var xf := Transform3D(basis * Basis.from_scale(sc), pos)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.transform = xf
		add_child(mi)
		var aabb := mesh.get_aabb()
		var shape := BoxShape3D.new()
		shape.size = aabb.size * sc * 0.85
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(basis, xf * aabb.get_center())
		body.add_child(cs)


## Simple walkable shapes: a flat disc for the plaza, a gentle cone over the dais steps
## (the steps are too tall to walk up), and the pillar.
func _collision() -> void:
	var body := StaticBody3D.new()
	body.name = "PlazaCollider"
	add_child(body)
	var plaza := CylinderShape3D.new()
	plaza.radius = PLAZA_RADIUS + KERB_WIDTH
	plaza.height = 0.6
	_add_shape(body, plaza, Vector3(0, PAVE_LIFT + PAVE_TOP - 0.3, 0))
	var pts := PackedVector3Array()
	for p in _circle(3.9, 16):
		pts.append(Vector3(p.x, PAVE_LIFT + PAVE_TOP, p.y))
	for p in _circle(2.1, 16):
		pts.append(Vector3(p.x, PAVE_LIFT + 0.76, p.y))
	var cone := ConvexPolygonShape3D.new()
	cone.points = pts
	_add_shape(body, cone, Vector3.ZERO)
	var pillar := CylinderShape3D.new()
	pillar.radius = 0.55
	pillar.height = ORB_HEIGHT
	_add_shape(body, pillar, Vector3(0, ORB_HEIGHT * 0.5, 0))


func _add_shape(body: StaticBody3D, shape: Shape3D, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)
