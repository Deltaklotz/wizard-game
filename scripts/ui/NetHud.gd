extends CanvasLayer
## Small multiplayer message feed in the top-left corner: who joined or left.
## Messages fade out after a few seconds.

const LIFETIME := 7.0

var _box: VBoxContainer
var _known := {}  # id -> player info (names stay available after they leave)


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_box = VBoxContainer.new()
	_box.position = Vector2(16, 40)
	_box.add_theme_constant_override("separation", 4)
	add_child(_box)
	if not Net.is_online():
		return
	for info in Net.players.values():
		_known[info.id] = info
	Net.player_joined.connect(func(info: Dictionary) -> void:
		_known[info.id] = info
		post("%s joined" % info.name, info.color))
	Net.player_left.connect(func(id: int) -> void:
		var info: Dictionary = _known.get(id, {"name": "A wizard", "color": Color.WHITE})
		_known.erase(id)
		post("%s left" % info.name, info.color))
	Net.event_received.connect(func(id: int, event: Dictionary) -> void:
		if event.get("kind") != "death":
			return
		var victim: Dictionary = _known.get(id, {"name": "A wizard", "color": Color.WHITE})
		var by := int(event.get("by", -1))
		if by == Net.my_id:
			post("You struck down %s" % victim.name, Net.my_color)
		elif _known.has(by):
			post("%s struck down %s" % [_known[by].name, victim.name], _known[by].color)
		else:
			post("%s was struck down" % victim.name, victim.color))
	var others := Net.players.size()
	post("Connected as %s. %s" % [Net.my_name, "You are the first wizard here." if others == 0 else
		"%d other wizard%s here." % [others, "" if others == 1 else "s"]], Net.my_color)


func post(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = "✦ " + text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", color.lightened(0.35))
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.05))
	l.add_theme_constant_override("outline_size", 6)
	_box.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(LIFETIME)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	tw.tween_callback(l.queue_free)
