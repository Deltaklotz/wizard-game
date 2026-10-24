class_name MapBuilder
extends RefCounted
## Builds the hand-drawn relief map from the live world: terrain relief, inked paper,
## billboard trees, the lake, floating islands, the start site, labels and player pins.

const PAPER_W := 11.0
const PAPER_D := 10.0
## Map frame inside the paper (uv): x0, y0, x1, y1.
const MAP_RECT := Vector4(0.1, 0.06, 0.9, 0.94)
const TEX_SIZE := Vector2i(2816, 2560)
const RELIEF_N := 256
const RELIEF_SCALE := 0.85
const LAKE_DEPTH := 0.09
## Deepest a valley may be pressed into the paper (relief units, before RELIEF_SCALE).
const MAX_DEPTH := 0.3
const INK := Color(0.18, 0.125, 0.08)
const PAPER := Color(0.91, 0.84, 0.68)
const PIN_PATH := "res://assets/map/player_pin.obj"

var data: TerrainData
var lake: LakeShape
var site: StartSite
var islands: Array = []
var tree_positions := PackedVector3Array()
var tree_is_pine := PackedByteArray()
var relief := PackedFloat32Array()
## Relief of the lake surface (the water sheet sits there).
var water_relief := 0.0
var world_size: float
var rng := RandomNumberGenerator.new()

# Built scene pieces, animated by MapOverlay.
var sheet_material: ShaderMaterial
var tree_material: ShaderMaterial
var water: MeshInstance3D
var pin: Node3D
## Flat arrow around the player pin pointing where the player faces (the pin itself spins).
var pin_arrow: Node3D
## [Node3D, base position, base scale, label category ("" = not a label, "location", "landmark")]
var pops: Array = []
var floaters: Array = []   # {node, base, phase, pebbles: [{node, a, rr, y, sp}]}

var _font: SystemFont
var _label_spots: Array[Vector2] = []
var _font_italic: SystemFont


func _init(world: Node) -> void:
	data = world.terrain_data
	world_size = data.world_size()
	rng.seed = 90210
	if not data.lakes.is_empty():
		lake = data.lakes[0]
	site = world.get("start_site")
	var veg := world.get_node_or_null("Vegetation")
	if veg:
		tree_positions = veg.tree_positions
		tree_is_pine = veg.tree_is_pine
	var field := world.get_node_or_null("SkyIslands")
	if field:
		islands = field.islands
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Palatino Linotype", "Book Antiqua", "Georgia", "Times New Roman", "serif"])
	_font_italic = _font.duplicate()
	_font_italic.font_italic = true


# --- Coordinates -----------------------------------------------------------------

func world_to_map(p: Vector2) -> Vector2:
	return (p - data.origin()) / world_size


func map_to_world(m: Vector2) -> Vector2:
	return data.origin() + m * world_size


func map_to_tex(m: Vector2) -> Vector2:
	return Vector2((MAP_RECT.x + m.x * (MAP_RECT.z - MAP_RECT.x)) * TEX_SIZE.x, (MAP_RECT.y + m.y * (MAP_RECT.w - MAP_RECT.y)) * TEX_SIZE.y)


func map_to_3d(m: Vector2) -> Vector3:
	return Vector3((MAP_RECT.x + m.x * (MAP_RECT.z - MAP_RECT.x) - 0.5) * PAPER_W, relief_at(m) * RELIEF_SCALE,
		(MAP_RECT.y + m.y * (MAP_RECT.w - MAP_RECT.y) - 0.5) * PAPER_D)


## Map units (3D) per world metre.
func units_per_metre() -> float:
	return (MAP_RECT.z - MAP_RECT.x) * PAPER_W / world_size


func relief_at(m: Vector2) -> float:
	var gx := clampf(m.x, 0.0, 1.0) * (RELIEF_N - 1)
	var gy := clampf(m.y, 0.0, 1.0) * (RELIEF_N - 1)
	var ix := mini(int(gx), RELIEF_N - 2)
	var iy := mini(int(gy), RELIEF_N - 2)
	var fx := gx - ix
	var fy := gy - iy
	var i := iy * RELIEF_N + ix
	return lerpf(lerpf(relief[i], relief[i + 1], fx), lerpf(relief[i + RELIEF_N], relief[i + RELIEF_N + 1], fx), fy)


# --- Relief ------------------------------------------------------------------------

func compute_relief() -> ImageTexture:
	var n := RELIEF_N
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		for i in n:
			var w := map_to_world(Vector2(i, j) / (n - 1))
			hs[j * n + i] = data.height_at(w.x, w.y)
			if data.forests and data.forests.has_secret():
				# The secret spot's hollow isn't pressed into the paper (it would give it away).
				var sc := data.forests.secret
				var dd := w.distance_to(Vector2(sc.x, sc.y))
				if dd < sc.z + 8.0:
					hs[j * n + i] = lerpf(sc.w, hs[j * n + i], smoothstep(sc.z, sc.z + 8.0, dd))
	var sorted := hs.duplicate()
	sorted.sort()
	# Ground zero is the waystone circle: higher ground rises out of the paper, lower ground
	# (valleys, slopes falling away, the lake basin) is pressed into it at the same scale.
	var h0: float = data.height_at(site.center.x, site.center.y) if site else sorted[int(n * n * 0.5)]
	var span := maxf(sorted[n * n - 1] - h0, 1.0)
	if lake:
		water_relief = _relief_of(lake.level, h0, span)
	relief.resize(n * n)
	for j in n:
		for i in n:
			var m := Vector2(i, j) / (n - 1)
			var h := hs[j * n + i]
			var r := _relief_of(h, h0, span)
			if lake:
				var w := map_to_world(m)
				var f := lake.shore_fraction(w)
				if f < 1.3:
					if h < lake.level:
						r = water_relief - LAKE_DEPTH * clampf((lake.level - h) / 2.0, 0.3, 1.0)
					elif f < 1.0:
						r = water_relief + 0.07 * clampf((h - lake.level) / 2.5, 0.0, 1.0)
			# The border of the sheet stays flat.
			r *= smoothstep(0.0, 0.035, minf(minf(m.x, 1.0 - m.x), minf(m.y, 1.0 - m.y)))
			relief[j * n + i] = r
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RF, relief.to_byte_array())
	return ImageTexture.create_from_image(img)


## Relief for height h: 0 at the waystone circle (h0), 1 at the highest peak (h0 + span, eased
## so lowlands stay gentle); below h0 mirrored at the same scale, down to -MAX_DEPTH.
static func _relief_of(h: float, h0: float, span: float) -> float:
	var r := pow(clampf(absf(h - h0) / span, 0.0, 1.0), 1.25)
	return r if h >= h0 else -minf(r, MAX_DEPTH)


# --- Paper ---------------------------------------------------------------------------

func draw_paper(c: CanvasItem) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 4711
	_draw_frame(c)
	_draw_hachures(c, r)
	_draw_stipple(c, r)
	_draw_lake(c, r)
	_draw_forest_and_meadows(c, r)
	_draw_trails(c)
	_draw_island_shadows(c)
	_draw_start_site(c)
	_draw_compass(c)
	_draw_scale(c)


## Forest trails as dashed ink lines.
func _draw_trails(c: CanvasItem) -> void:
	if data.forests == null:
		return
	for t in data.forests.trails:
		var pts: PackedVector2Array = t.points
		var line := PackedVector2Array()
		for p in pts:
			line.append(map_to_tex(world_to_map(p)))
		for i in line.size() - 1:
			c.draw_dashed_line(line[i], line[i + 1], _ink(0.75), 2.2, 7.0)


func _ink(a: float) -> Color:
	return Color(INK, a)


func _draw_frame(c: CanvasItem) -> void:
	var p0 := map_to_tex(Vector2.ZERO)
	var p1 := map_to_tex(Vector2.ONE)
	c.draw_rect(Rect2(p0 - Vector2(18, 18), p1 - p0 + Vector2(36, 36)), _ink(0.9), false, 5.0)
	c.draw_rect(Rect2(p0 - Vector2(6, 6), p1 - p0 + Vector2(12, 12)), _ink(0.9), false, 1.6)
	var ticks := PackedVector2Array()
	for k in 21:
		var t := k / 20.0
		var x := lerpf(p0.x, p1.x, t)
		var y := lerpf(p0.y, p1.y, t)
		ticks.append_array([Vector2(x, p0.y - 18), Vector2(x, p0.y - 6), Vector2(x, p1.y + 6), Vector2(x, p1.y + 18),
			Vector2(p0.x - 18, y), Vector2(p0.x - 6, y), Vector2(p1.x + 6, y), Vector2(p1.x + 18, y)])
	c.draw_multiline(ticks, _ink(0.9), 1.4)


## Short strokes running downhill, heavier on the shadowed side; hills get only a light touch.
func _draw_hachures(c: CanvasItem, r: RandomNumberGenerator) -> void:
	var buckets := [PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
	var step := 1.0 / 300.0
	var e := 1.0 / RELIEF_N
	var my := 0.0
	while my < 1.0:
		var mx := 0.0
		while mx < 1.0:
			var m := Vector2(mx + (r.randf() - 0.5) * step, my + (r.randf() - 0.5) * step)
			var h := relief_at(m)
			if absf(h) > 0.015:
				var g := Vector2(relief_at(m + Vector2(e, 0)) - relief_at(m - Vector2(e, 0)),
					relief_at(m + Vector2(0, e)) - relief_at(m - Vector2(0, e))) / (2.0 * e)
				var slope := g.length()
				var ah := absf(h)
				var density := slope * 0.16 * (0.25 + 0.75 * smoothstep(0.12, 0.3, ah) if ah < 0.3 else 1.0)
				if slope > 0.001 and r.randf() < minf(1.0, density):
					var d := -g / slope
					var length := minf(18.0, 5.0 + slope * 0.9)
					var shadow := maxf(0.0, d.x * 0.6 + d.y * 0.8)
					var t := map_to_tex(m)
					buckets[mini(int(shadow * 3.0), 2)].append_array([t, t + d * length])
			mx += step
		my += step
	for k in 3:
		if not buckets[k].is_empty():
			c.draw_multiline(buckets[k], _ink(0.55 + k * 0.15), 1.2 + k * 0.6)


func _draw_stipple(c: CanvasItem, r: RandomNumberGenerator) -> void:
	for i in 60000:
		var m := Vector2(r.randf(), r.randf())
		var h := relief_at(m)
		var foot := h > 0.004 and h < 0.05 and r.randf() < 0.35
		var shore := false
		if lake:
			var f := lake.shore_fraction(map_to_world(m))
			shore = f > 1.0 and f < 1.18 and r.randf() < (1.18 - f) * 5.0
		if foot or shore:
			c.draw_circle(map_to_tex(m), 1.3, _ink(0.7))


func _lake_outline(fraction: float, island: bool, steps := 220) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var a := TAU * i / steps
		var w: Vector2
		if island:
			w = lake.island_center + Vector2.from_angle(a) * lake.island_edge(a) * fraction
		else:
			w = lake.center + Vector2.from_angle(a) * lake.shore_radius(a) * fraction
		pts.append(map_to_tex(world_to_map(w)))
	return pts


func _draw_lake(c: CanvasItem, r: RandomNumberGenerator) -> void:
	if lake == null:
		return
	var shore := _lake_outline(1.0, false)
	c.draw_colored_polygon(shore, Color(0.35, 0.41, 0.39, 0.3))
	c.draw_polyline(_wobble(shore, r, 1.5), _ink(0.9), 3.0)
	var isle := _lake_outline(1.0, true, 90)
	c.draw_colored_polygon(isle, PAPER)
	c.draw_polyline(_wobble(isle, r, 1.0), _ink(0.9), 2.4)
	_dashed(c, _lake_outline(1.35, true, 90), _ink(0.5), 1.2, 10.0, 8.0)
	# Reeds on a stretch of shore.
	var strokes := PackedVector2Array()
	for i in 60:
		var a := 3.6 + r.randf() * 1.1
		var w := lake.center + Vector2.from_angle(a) * lake.shore_radius(a) * (0.93 + r.randf() * 0.12)
		var t := map_to_tex(world_to_map(w))
		strokes.append_array([t, t + Vector2((r.randf() - 0.5) * 6.0, -14.0 - r.randf() * 8.0)])
	c.draw_multiline(strokes, _ink(0.8), 1.2)


func _draw_forest_and_meadows(c: CanvasItem, r: RandomNumberGenerator) -> void:
	# Forest floor: a speck of ink under (most) trees.
	for i in tree_positions.size():
		if r.randf() < 0.4:
			continue
		var p := tree_positions[i]
		var t := map_to_tex(world_to_map(Vector2(p.x, p.z))) + Vector2(r.randf() - 0.5, r.randf() - 0.5) * 6.0
		c.draw_circle(t, 1.0, _ink(0.35))
	# Coarse tree-density grid so meadow tufts avoid forests.
	var grid := PackedInt32Array()
	grid.resize(64 * 64)
	for p in tree_positions:
		var m := world_to_map(Vector2(p.x, p.z))
		grid[clampi(int(m.y * 64), 0, 63) * 64 + clampi(int(m.x * 64), 0, 63)] += 1
	var tufts := PackedVector2Array()
	for i in 1800:
		var m := Vector2(r.randf(), r.randf())
		if absf(relief_at(m)) > 0.02 or grid[clampi(int(m.y * 64), 0, 63) * 64 + clampi(int(m.x * 64), 0, 63)] > 0:
			continue
		var w := map_to_world(m)
		if data.rock_at(w.x, w.y) > 0.2 or (lake and lake.shore_fraction(w) < 1.1):
			continue
		var t := map_to_tex(m)
		tufts.append_array([t + Vector2(-5, 0), t + Vector2(-2, -7), t, t + Vector2(1, -9), t + Vector2(5, 0), t + Vector2(3, -6)])
	c.draw_multiline(tufts, _ink(0.6), 1.2)


func _draw_island_shadows(c: CanvasItem) -> void:
	for isl in islands:
		var m := world_to_map(Vector2(isl.global_position.x, isl.global_position.z))
		if m.x < 0.0 or m.y < 0.0 or m.x > 1.0 or m.y > 1.0:
			continue
		var t := map_to_tex(m)
		var rad: float = isl.shape.radius / world_size * (MAP_RECT.z - MAP_RECT.x) * TEX_SIZE.x * 1.1
		var dots := PackedVector2Array()
		var count := maxi(10, int(TAU * rad / 12.0))
		for k in count:
			var a := TAU * k / count
			var p := t + Vector2(cos(a) * rad, sin(a) * rad * 0.8).rotated(0.3)
			var tangent := Vector2(-sin(a), cos(a) * 0.8).rotated(0.3).normalized()
			dots.append_array([p - tangent * 1.5, p + tangent * 1.5])
		c.draw_multiline(dots, _ink(0.7), 2.2)


## The Waystone Circle: paths, a ring of stone marks and a star in the middle.
func _draw_start_site(c: CanvasItem) -> void:
	if site == null:
		return
	var t := map_to_tex(world_to_map(site.center))
	var px := (MAP_RECT.z - MAP_RECT.x) * TEX_SIZE.x / world_size
	var paper_clear := PackedVector2Array()
	for k in 48:
		paper_clear.append(t + Vector2.from_angle(TAU * k / 48.0) * (StartSite.STONE_RING + 4.0) * px)
	c.draw_colored_polygon(paper_clear, Color(PAPER, 0.85))
	for k in 4:
		var dir := Vector2.from_angle(site.path_angle + k * PI * 0.5)
		var pts := PackedVector2Array()
		for s in 12:
			var along := lerpf(StartSite.PLAZA_RADIUS + 1.0, StartSite.PATH_LENGTH, s / 11.0)
			var wander := sin(along * 0.09 + k * 1.7) * 2.5 * smoothstep(StartSite.PLAZA_RADIUS, StartSite.PLAZA_RADIUS + 15.0, along)
			pts.append(t + (dir * along + dir.orthogonal() * wander) * px)
		for side in [-1.0, 1.0]:
			var edge := PackedVector2Array()
			for i in pts.size():
				edge.append(pts[i] + dir.orthogonal() * side * 3.0)
			_dashed(c, edge, _ink(0.75), 1.4, 7.0, 5.0)
	c.draw_arc(t, StartSite.PLAZA_RADIUS * px, 0.0, TAU, 48, _ink(0.9), 2.2)
	c.draw_arc(t, 7.3 * px, 0.0, TAU, 40, _ink(0.6), 1.2)
	for k in 12:
		var a := site.path_angle + PI / 12.0 + TAU * k / 12.0
		var p := t + Vector2.from_angle(a) * StartSite.STONE_RING * px
		var side := Vector2.from_angle(a).orthogonal() * 4.0
		var out := Vector2.from_angle(a) * 2.5
		c.draw_colored_polygon(PackedVector2Array([p - side - out, p + side - out, p + side + out, p - side + out]), _ink(0.9))
	var star := PackedVector2Array()
	for k in 10:
		star.append(t + Vector2.from_angle(-PI * 0.5 + TAU * k / 10.0) * (13.0 if k % 2 == 0 else 5.0))
	c.draw_colored_polygon(star, _ink(0.95))


func _draw_compass(c: CanvasItem) -> void:
	var center := Vector2((MAP_RECT.z + (1.0 - MAP_RECT.z) * 0.5) * TEX_SIZE.x, 0.8 * TEX_SIZE.y)
	c.draw_arc(center, 76.0, 0.0, TAU, 64, _ink(0.9), 2.0)
	c.draw_arc(center, 66.0, 0.0, TAU, 64, _ink(0.9), 2.0)
	for k in 8:
		var a := k * PI / 4.0
		var length := 57.0 if k % 2 else 105.0
		var w := 9.0 if k % 2 else 15.0
		var tip := center + Vector2(0, -length).rotated(a)
		var side := Vector2(w, 0).rotated(a)
		c.draw_colored_polygon(PackedVector2Array([tip, center + side, center]), _ink(0.9))
		var light := PackedVector2Array([tip, center - side, center])
		c.draw_colored_polygon(light, PAPER)
		c.draw_polyline(PackedVector2Array([tip, center - side, center, tip]), _ink(0.9), 1.6)
	c.draw_string(_font, center + Vector2(-40, -122), "N", HORIZONTAL_ALIGNMENT_CENTER, 80, 40, _ink(0.95))


func _draw_scale(c: CanvasItem) -> void:
	var origin := map_to_tex(Vector2(0.62, 1.0)) + Vector2(0, 45)
	var unit := (MAP_RECT.z - MAP_RECT.x) * TEX_SIZE.x * (250.0 / world_size)
	for k in 4:
		c.draw_rect(Rect2(origin + Vector2(k * unit * 0.5, 0), Vector2(unit * 0.5, 12)), PAPER if k % 2 else _ink(0.9))
	c.draw_rect(Rect2(origin, Vector2(unit * 2.0, 12)), _ink(0.9), false, 2.0)
	var labels := ["0", "250", "500 m"]
	for k in 3:
		c.draw_string(_font_italic, origin + Vector2(k * unit - 60, 42), labels[k], HORIZONTAL_ALIGNMENT_CENTER, 120, 22, _ink(0.9))


func _wobble(pts: PackedVector2Array, r: RandomNumberGenerator, amount: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + Vector2(r.randf() - 0.5, r.randf() - 0.5) * amount)
	return out


func _dashed(c: CanvasItem, pts: PackedVector2Array, color: Color, width: float, dash: float, gap: float) -> void:
	var segs := PackedVector2Array()
	var dist := 0.0
	for i in pts.size() - 1:
		var length := pts[i].distance_to(pts[i + 1])
		if fmod(dist + length * 0.5, dash + gap) < dash:
			segs.append_array([pts[i], pts[i + 1]])
		dist += length
	c.draw_multiline(segs, color, width)


# --- Icons ---------------------------------------------------------------------------

## Three ink tree icons side by side (128 x 160 each): pine, leafy tree, poplar.
func draw_tree_icons(c: CanvasItem) -> void:
	var ink := _ink(1.0)
	# Pine.
	for k in 3:
		var top := 10.0 + k * 38.0
		var bot := top + 62.0
		var half := 26.0 + k * 12.0
		var tri := PackedVector2Array([Vector2(64, top), Vector2(64 + half, bot), Vector2(64 - half, bot)])
		c.draw_colored_polygon(tri, PAPER)
		c.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), ink, 4.0)
		for i in 5:
			c.draw_line(Vector2(68 + i * 6, bot - 6), Vector2(76 + i * 5, bot - 22 + i * 3), ink, 2.0)
	c.draw_line(Vector2(64, 134), Vector2(64, 158), ink, 4.0)
	# Leafy tree.
	var ox := 128.0
	c.draw_line(Vector2(ox + 61, 158), Vector2(ox + 62, 96), ink, 4.0)
	c.draw_line(Vector2(ox + 67, 158), Vector2(ox + 66, 96), ink, 4.0)
	var blobs := [[64.0, 60.0, 38.0], [40.0, 80.0, 26.0], [88.0, 80.0, 26.0], [64.0, 34.0, 26.0]]
	for b in blobs:
		c.draw_circle(Vector2(ox + b[0], b[1]), b[2] + 2.0, ink)
	for b in blobs:
		c.draw_circle(Vector2(ox + b[0], b[1]), b[2] - 2.0, PAPER)
	for i in 7:
		c.draw_line(Vector2(ox + 70 + i * 4, 64 + i * 5), Vector2(ox + 84 + i * 3, 56 + i * 5), ink, 2.0)
	# Poplar.
	ox = 256.0
	var ell := PackedVector2Array()
	for i in 41:
		var a := TAU * i / 40.0
		ell.append(Vector2(ox + 64 + cos(a) * 24.0, 70 + sin(a) * 62.0))
	c.draw_colored_polygon(ell, PAPER)
	c.draw_polyline(ell, ink, 4.0)
	c.draw_line(Vector2(ox + 64, 132), Vector2(ox + 64, 158), ink, 4.0)
	for i in 8:
		c.draw_line(Vector2(ox + 68, 30 + i * 11), Vector2(ox + 82, 36 + i * 11), ink, 2.0)


func draw_cartouche(c: CanvasItem) -> void:
	var size := Vector2(640, 240)
	c.draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), PAPER)
	c.draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), _ink(1.0), false, 5.0)
	c.draw_rect(Rect2(Vector2(16, 16), size - Vector2(32, 32)), _ink(1.0), false, 1.6)
	c.draw_string(_font, Vector2(0, 128), "The Vale", HORIZONTAL_ALIGNMENT_CENTER, size.x, 84, _ink(1.0))
	c.draw_string(_font_italic, Vector2(0, 186), "as surveyed by an apprentice wizard", HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, _ink(1.0))


# --- Scene -------------------------------------------------------------------------

func build_scene(root: Node3D, host: Node) -> void:
	var relief_tex := compute_relief()
	var paper_bg := ShaderMaterial.new()
	paper_bg.shader = preload("res://shaders/map/map_paper.gdshader")
	var paper_tex := await InkCanvas.render(host, TEX_SIZE, draw_paper, paper_bg)
	var icons_tex := await InkCanvas.render(host, Vector2i(384, 160), draw_tree_icons)
	var cartouche_tex := await InkCanvas.render(host, Vector2i(640, 240), draw_cartouche)

	_build_sheet(root, paper_tex, relief_tex)
	_build_trees(root, icons_tex)
	_build_water(root)
	_build_islands(root, icons_tex)
	_build_start_site(root)
	_build_labels(root, cartouche_tex)
	_build_pin(root)


func _build_sheet(root: Node3D, paper_tex: Texture2D, relief_tex: Texture2D) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(PAPER_W, PAPER_D)
	plane.subdivide_width = 440
	plane.subdivide_depth = 400
	sheet_material = ShaderMaterial.new()
	sheet_material.shader = preload("res://shaders/map/map_sheet.gdshader")
	sheet_material.set_shader_parameter("paper_tex", paper_tex)
	sheet_material.set_shader_parameter("relief_tex", relief_tex)
	sheet_material.set_shader_parameter("map_rect", MAP_RECT)
	sheet_material.set_shader_parameter("relief_scale", RELIEF_SCALE)
	sheet_material.set_shader_parameter("paper_w", PAPER_W)
	sheet_material.set_shader_parameter("paper_d", PAPER_D)
	var sheet := MeshInstance3D.new()
	sheet.name = "Sheet"
	sheet.mesh = plane
	sheet.material_override = sheet_material
	sheet.custom_aabb = AABB(Vector3(-PAPER_W, -1, -PAPER_D), Vector3(PAPER_W * 2, 4, PAPER_D * 2))
	root.add_child(sheet)


func _billboard_quad() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uvs[i])
		st.set_normal(Vector3.BACK)
		st.add_vertex(pts[i])
	return st.commit()


func _build_trees(root: Node3D, icons: Texture2D) -> void:
	tree_material = ShaderMaterial.new()
	tree_material.shader = preload("res://shaders/map/map_billboard.gdshader")
	tree_material.set_shader_parameter("atlas", icons)
	# One billboard per few real trees keeps forests readable without clutter.
	var picks: Array = []
	var r := RandomNumberGenerator.new()
	r.seed = 1
	for i in tree_positions.size():
		# Denser inside the big forests, so they read as solid woods on the map.
		var p := tree_positions[i]
		var share := 0.3 if data.forests and data.forests.density_at(p.x, p.z) > 0.5 else 0.14
		if r.randf() < share:
			picks.append(i)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _billboard_quad()
	mm.instance_count = picks.size()
	for k in picks.size():
		var p := tree_positions[picks[k]]
		var m := world_to_map(Vector2(p.x, p.z))
		var s := 0.17 + r.randf() * 0.06
		var icon := 0 if tree_is_pine[picks[k]] else (1 if r.randf() < 0.7 else 2)
		mm.set_instance_transform(k, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), map_to_3d(m)))
		mm.set_instance_custom_data(k, Color(icon, 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Trees"
	mmi.multimesh = mm
	mmi.material_override = tree_material
	mmi.custom_aabb = AABB(Vector3(-PAPER_W, -1, -PAPER_D), Vector3(PAPER_W * 2, 4, PAPER_D * 2))
	root.add_child(mmi)


func _build_water(root: Node3D) -> void:
	if lake == null:
		return
	var seg := 96
	var rings := 10
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var c3 := map_to_3d(world_to_map(lake.center))
	verts.append(Vector3(c3.x, 0, c3.z))
	cols.append(Color(1, 0, 0))
	for ring in range(1, rings + 1):
		var t := float(ring) / rings
		for s in seg:
			var a := TAU * s / seg
			var w := lake.center + Vector2.from_angle(a) * lake.shore_radius(a) * t
			var p := map_to_3d(world_to_map(w))
			verts.append(Vector3(p.x, 0, p.z))
			cols.append(Color(1.0 - t, 0, 0))
	for s in seg:
		idx.append_array([0, 1 + (s + 1) % seg, 1 + s])
	for ring in range(1, rings):
		var a0 := 1 + (ring - 1) * seg
		var b0 := 1 + ring * seg
		for s in seg:
			var s2 := (s + 1) % seg
			idx.append_array([a0 + s, a0 + s2, b0 + s, a0 + s2, b0 + s2, b0 + s])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/map/map_water.gdshader")
	water = MeshInstance3D.new()
	water.name = "Lake"
	water.mesh = mesh
	water.material_override = mat
	root.add_child(water)


func _model_material(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/map/map_model.gdshader")
	m.set_shader_parameter("base_color", color)
	return m


func _outline_material(width: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/map/map_outline.gdshader")
	m.set_shader_parameter("width", width)
	return m


func _add_with_outline(parent: Node3D, mesh: Mesh, mat: Material, outline: Material) -> void:
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = mat
	parent.add_child(body)
	var o := MeshInstance3D.new()
	o.mesh = mesh
	o.material_override = outline
	parent.add_child(o)


func _island_mesh(radius: float, seed: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 9
	var levels := [[1.0, 0.0], [0.8, -0.6], [0.45, -1.2], [0.0, -1.8]]
	var rows: Array = [[]]
	for s in seg:
		rows[0].append(Vector3(0, radius * 0.1, 0))
	var top_ring: Array = []
	for s in seg:
		var a := TAU * s / seg
		top_ring.append(Vector3(cos(a) * radius, radius * 0.1, sin(a) * radius))
	rows.append(top_ring)
	for l in levels:
		var ring: Array = []
		for s in seg:
			var a := TAU * s / seg
			var rr: float = radius * l[0] * (0.8 + r.randf() * 0.45)
			ring.append(Vector3(cos(a) * rr, radius * l[1] * (0.85 + r.randf() * 0.3), sin(a) * rr))
		rows.append(ring)
	for i in rows.size() - 1:
		for s in seg:
			var s2 := (s + 1) % seg
			var a: Vector3 = rows[i][s]
			var b: Vector3 = rows[i][s2]
			var c: Vector3 = rows[i + 1][s]
			var d: Vector3 = rows[i + 1][s2]
			for v in [a, c, b, b, c, d]:
				st.add_vertex(v)
	st.index()
	st.generate_normals()
	return st.commit()


func _build_islands(root: Node3D, icons: Texture2D) -> void:
	var paper_mat := _model_material(Color(0.89, 0.81, 0.62))
	var outline := _outline_material(0.012)
	var pebble_mesh := SphereMesh.new()
	pebble_mesh.radius = 0.025
	pebble_mesh.height = 0.05
	pebble_mesh.radial_segments = 6
	pebble_mesh.rings = 3
	var scale := units_per_metre()
	var tree_mat := ShaderMaterial.new()
	tree_mat.shader = preload("res://shaders/map/map_billboard.gdshader")
	tree_mat.set_shader_parameter("atlas", icons)
	var seed := 11
	for isl in islands:
		var wp: Vector3 = isl.global_position
		var m := world_to_map(Vector2(wp.x, wp.z))
		if m.x < 0.02 or m.y < 0.02 or m.x > 0.98 or m.y > 0.98:
			continue
		var radius := maxf(isl.shape.radius * scale, 0.035)
		var node := Node3D.new()
		_add_with_outline(node, _island_mesh(radius, seed), paper_mat, outline)
		seed += 1
		var base := map_to_3d(m)
		# Exaggerated altitude so they clearly float above the relief.
		base.y = maxf(base.y, 0.3) + maxf(wp.y - data.height_at(wp.x, wp.z), 30.0) * scale * 1.4
		node.position = base
		root.add_child(node)
		# A few trees on the bigger islands.
		if isl.shape.radius > 14.0:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = _billboard_quad()
			mm.instance_count = clampi(int(isl.shape.radius / 5.0), 2, 9)
			for k in mm.instance_count:
				var a := rng.randf() * TAU
				var rr := sqrt(rng.randf()) * radius * 0.75
				mm.set_instance_transform(k, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.18), Vector3(cos(a) * rr, radius * 0.1, sin(a) * rr)))
				mm.set_instance_custom_data(k, Color(rng.randi() % 2, 0, 0, 0))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = tree_mat
			node.add_child(mmi)
		var pebbles: Array = []
		for k in clampi(int(isl.shape.radius * 0.25), 2, 8):
			var pn := Node3D.new()
			_add_with_outline(pn, pebble_mesh, paper_mat, _outline_material(0.008))
			root.add_child(pn)
			pebbles.append({"node": pn, "a": rng.randf() * TAU, "rr": radius * rng.randf_range(0.6, 1.5),
				"y": -radius * rng.randf_range(0.6, 1.8), "sp": rng.randf_range(0.2, 0.6)})
		floaters.append({"node": node, "base": base, "phase": rng.randf() * TAU, "pebbles": pebbles,
			"island": isl, "radius": radius})


## category: "location" (forests, lake, mountains) or "landmark" (built places); the map legend
## toggles each kind.
func _label(root: Node3D, text: String, m: Vector2, size: float, lift: float, italic := true, category := "location") -> void:
	var l := Label3D.new()
	l.text = text
	l.font = _font_italic if italic else _font
	l.font_size = 64
	l.pixel_size = size / 64.0
	l.outline_size = 18
	l.modulate = INK
	l.outline_modulate = Color(PAPER, 0.95)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.double_sided = true
	l.render_priority = 2
	l.outline_render_priority = 1
	# Nudge down until it no longer overlaps an earlier label.
	var moved := true
	while moved:
		moved = false
		for spot in _label_spots:
			if absf(spot.x - m.x) < 0.17 and absf(spot.y - m.y) < 0.048:
				m.y = spot.y + 0.05
				moved = true
	_label_spots.append(m)
	var top := 0.0
	for k in 16:
		var a := TAU * k / 16.0
		top = maxf(top, relief_at(m + Vector2(cos(a), sin(a)) * 0.03))
	var base := map_to_3d(m)
	base.y = top * RELIEF_SCALE + lift
	l.position = base
	root.add_child(l)
	pops.append([l, base, l.scale, category])


func _build_labels(root: Node3D, cartouche: Texture2D) -> void:
	if lake:
		var lm := world_to_map(lake.center)
		_label(root, "The Sunken Mere", lm + Vector2(0, lake.radius / world_size * 0.5), 0.3, 0.3)
	_label(root, "The Greywall", Vector2(0.5, 0.05), 0.4, 0.3, false)
	# Densest broadleaf and pine areas get names.
	var cells := 16
	var broad := PackedInt32Array()
	var pine := PackedInt32Array()
	broad.resize(cells * cells)
	pine.resize(cells * cells)
	for i in tree_positions.size():
		var m := world_to_map(Vector2(tree_positions[i].x, tree_positions[i].z))
		var k := clampi(int(m.y * cells), 0, cells - 1) * cells + clampi(int(m.x * cells), 0, cells - 1)
		if tree_is_pine[i]:
			pine[k] += 1
		else:
			broad[k] += 1
	if data.forests and not data.forests.forests.is_empty():
		# Named forests (ForestLayout).
		for f in data.forests.forests:
			_label(root, f.name, world_to_map(f.center), 0.32, 0.5)
		broad.fill(0)
		pine.fill(0)
	for pair in [[broad, "Whisperwood"], [pine, "The Pinewold"]]:
		var best := -1
		var best_n := 0
		for k in cells * cells:
			if pair[0][k] > best_n:
				best_n = pair[0][k]
				best = k
		if best >= 0 and best_n > 20:
			_label(root, pair[1], Vector2((best % cells + 0.5) / cells, (best / cells + 0.5) / cells), 0.3, 0.45)
	# Title cartouche, floating over the south-west corner.
	var s := Sprite3D.new()
	s.texture = cartouche
	s.pixel_size = 0.7 / 240.0
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = false
	s.double_sided = true
	var base := map_to_3d(Vector2(0.14, 0.9))
	base.y = 0.9
	s.position = base
	root.add_child(s)
	pops.append([s, base, s.scale])


## Miniature standing stones and pillar, plus a floating gem marking where everyone starts.
func _build_start_site(root: Node3D) -> void:
	if site == null:
		return
	var m := world_to_map(site.center)
	var scale := units_per_metre()
	var stone_mat := _model_material(Color(0.8, 0.74, 0.62))
	var outline := _outline_material(0.006)
	var model := Node3D.new()
	model.name = "StartSite"
	var stone := BoxMesh.new()
	stone.size = Vector3(0.022, 0.055, 0.014)
	for k in 12:
		var a := site.path_angle + PI / 12.0 + TAU * k / 12.0
		var holder := Node3D.new()
		holder.position = Vector3(cos(a), 0.0, sin(a)) * StartSite.STONE_RING * scale + Vector3.UP * 0.027
		holder.rotation.y = -a + PI * 0.5
		_add_with_outline(holder, stone, stone_mat, outline)
		model.add_child(holder)
	var pillar := CylinderMesh.new()
	pillar.top_radius = 0.008
	pillar.bottom_radius = 0.012
	pillar.height = 0.07
	pillar.radial_segments = 8
	var ph := Node3D.new()
	ph.position.y = 0.035
	_add_with_outline(ph, pillar, stone_mat, outline)
	model.add_child(ph)
	var base := map_to_3d(m)
	model.position = base
	root.add_child(model)
	pops.append([model, base, model.scale])

	var gem := SphereMesh.new()
	gem.radius = 0.04
	gem.height = 0.11
	gem.radial_segments = 4
	gem.rings = 2
	var gem_mat := _model_material(Color(0.5, 0.72, 0.95))
	gem_mat.set_shader_parameter("ambient", 0.6)
	var marker := Node3D.new()
	marker.name = "StartMarker"
	_add_with_outline(marker, gem, gem_mat, _outline_material(0.008))
	root.add_child(marker)
	var gem_base := base + Vector3.UP * 0.32
	floaters.append({"node": marker, "base": gem_base, "phase": 0.0, "pebbles": []})
	_label(root, StartSite.SITE_NAME, m + Vector2(0, 0.03), 0.26, 0.28, false, "landmark")


## Flat double-sided triangle pointing along −Z: base `width` wide at `near`, tip at `far`.
static func _triangle(width: float, near: float, far: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(-width * 0.5, 0, -near), Vector3(0, 0, -far), Vector3(width * 0.5, 0, -near)]
	for order in [[0, 1, 2], [0, 2, 1]]:
		for i in order:
			st.set_normal(Vector3.UP)
			st.add_vertex(pts[i])
	return st.commit()


## A map pin (the editable OBJ) in `color`, e.g. for other players.
func make_pin(color: Color, label := "") -> Node3D:
	var mesh: Mesh = load(PIN_PATH)
	var node := Node3D.new()
	var mat := _model_material(color)
	mat.set_shader_parameter("ambient", 0.55)
	mat.set_shader_parameter("diffuse", 0.6)
	_add_with_outline(node, mesh, mat, _outline_material(0.006))
	if not label.is_empty():
		var l := Label3D.new()
		l.text = label
		l.font = _font_italic
		l.font_size = 64
		l.pixel_size = 0.22 / 64.0
		l.outline_size = 16
		l.modulate = color.darkened(0.35)
		l.outline_modulate = Color(PAPER, 0.95)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.render_priority = 3
		l.outline_render_priority = 2
		l.position.y = 0.45
		node.add_child(l)
	return node


func _build_pin(root: Node3D) -> void:
	pin = make_pin(Net.my_color if Net.is_online() else Color(0.78, 0.16, 0.11))
	pin.name = "PlayerPin"
	root.add_child(pin)
	# Facing arrow: a coloured triangle a little out from the pin's foot, ink outline below it.
	pin_arrow = Node3D.new()
	pin_arrow.name = "PinArrow"
	var color := Net.my_color if Net.is_online() else Color(0.78, 0.16, 0.11)
	var fill := MeshInstance3D.new()
	fill.mesh = _triangle(0.09, 0.11, 0.2)
	var mat := _model_material(color.lightened(0.15))
	mat.set_shader_parameter("ambient", 0.85)
	mat.set_shader_parameter("diffuse", 0.2)
	fill.material_override = mat
	fill.position.y = 0.004
	var edge := MeshInstance3D.new()
	edge.mesh = _triangle(0.12, 0.1, 0.225)
	edge.material_override = _model_material(INK)
	pin_arrow.add_child(edge)
	pin_arrow.add_child(fill)
	root.add_child(pin_arrow)
