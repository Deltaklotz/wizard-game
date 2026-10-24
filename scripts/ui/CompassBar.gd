class_name CompassBar
extends Control
## Compass strip at the top of the screen (Hud): the headings around the view direction scroll
## past a fixed centre notch – cardinal letters, intercardinals, degree ticks – plus markers for
## places (the Waystone Circle). North is world −Z, matching the map. Inked gold on a soft dark
## band that fades out at both ends.

const SPAN := 150.0          # degrees shown across the strip
const SIZE := Vector2(620, 46)
const GOLD := Color(0.96, 0.84, 0.56)
const NORTH := Color(1.0, 0.42, 0.32)
const LABELS := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}

## Heading the view faces (degrees clockwise from north).
var heading := 0.0
## Markers: [{bearing: float (degrees), color: Color}]
var markers: Array = []

var _font: SystemFont


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Palatino Linotype", "Book Antiqua", "Georgia", "serif"])


## Heading from a view yaw (Player._yaw convention: yaw 0 faces −Z, positive turns left).
static func heading_from_yaw(yaw: float) -> float:
	return fposmod(-rad_to_deg(yaw), 360.0)


## Bearing (degrees clockwise from north) from `from` to `to` on the ground plane.
static func bearing(from: Vector3, to: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(to.x - from.x, -(to.z - from.z))), 360.0)


func set_heading(h: float) -> void:
	if not is_equal_approx(h, heading):
		heading = h
		queue_redraw()


func _x_for(deg: float) -> float:
	var d := wrapf(deg - heading, -180.0, 180.0)
	return size.x * 0.5 + d / SPAN * size.x


func _alpha_at(x: float) -> float:
	var t := absf(x - size.x * 0.5) / (size.x * 0.5)
	return clampf(1.0 - pow(t, 3.0), 0.0, 1.0)


func _draw() -> void:
	var w := size.x
	var mid := 22.0
	# Band, fading at the ends (drawn as slices).
	var slices := 24
	for i in slices:
		var x0 := w * i / slices
		var a := _alpha_at(x0 + w / slices * 0.5)
		draw_rect(Rect2(x0, 8, w / slices + 0.5, 28), Color(0.04, 0.03, 0.05, 0.45 * a))
		draw_line(Vector2(x0, 8), Vector2(x0 + w / slices, 8), Color(GOLD, 0.55 * a), 1.0)
		draw_line(Vector2(x0, 36), Vector2(x0 + w / slices, 36), Color(GOLD, 0.55 * a), 1.0)
	# Ticks every 5 degrees, labels every 45.
	var first := int(floor((heading - SPAN * 0.5) / 5.0)) * 5
	var deg := first
	while deg <= heading + SPAN * 0.5 + 5:
		var x := _x_for(float(deg))
		var a := _alpha_at(x)
		var key := posmod(deg, 360)
		if a > 0.01 and x > 0.0 and x < w:
			if LABELS.has(key):
				var text: String = LABELS[key]
				var big := key % 90 == 0
				var fs := 22 if big else 15
				var col := NORTH if key == 0 else GOLD
				var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string_outline(_font, Vector2(x - tw * 0.5, mid + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.6 * a))
				draw_string(_font, Vector2(x - tw * 0.5, mid + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, a))
			else:
				var long := key % 15 == 0
				draw_line(Vector2(x, 36 - (9 if long else 5)), Vector2(x, 36), Color(GOLD, (0.8 if long else 0.45) * a), 1.5 if long else 1.0)
		deg += 5
	# Place markers (diamonds on the lower edge).
	for m in markers:
		var x := _x_for(m.bearing)
		var a := _alpha_at(x)
		if a <= 0.01 or x < 0.0 or x > w:
			continue
		var c: Color = m.color
		var pts := PackedVector2Array([Vector2(x, 31), Vector2(x + 5, 37), Vector2(x, 43), Vector2(x - 5, 37)])
		draw_colored_polygon(pts, Color(c, a))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.7 * a), 1.0)
	# Centre notch.
	var notch := PackedVector2Array([Vector2(w * 0.5 - 7, 0), Vector2(w * 0.5 + 7, 0), Vector2(w * 0.5, 9)])
	draw_colored_polygon(notch, GOLD)
	draw_line(Vector2(w * 0.5, 9), Vector2(w * 0.5, 36), Color(GOLD, 0.35), 1.0)
