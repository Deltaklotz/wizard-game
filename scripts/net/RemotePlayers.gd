extends Node3D
## Spawns and updates the wizards of other players from Net's signals, relays the local
## player's spell casts, and returns to the title screen when the connection drops.

const TITLE_SCENE := "res://scenes/Title.tscn"

var _avatars := {}  # peer id -> RemotePlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Net.is_online():
		return
	for info in Net.players.values():
		_spawn(info)
	Net.player_joined.connect(_spawn)
	Net.player_left.connect(_despawn)
	Net.player_states.connect(_on_states)
	Net.spell_cast.connect(_on_spell_cast)
	# Decoys (illusions of players) live here too.
	Net.event_received.connect(func(id: int, ev: Dictionary) -> void: Decoy.handle_event(self, id, ev))
	Net.disconnected.connect(_on_disconnected)


func avatar(id: int) -> RemotePlayer:
	return _avatars.get(id)


func _spawn(info: Dictionary) -> void:
	if _avatars.has(info.id):
		return
	var a := RemotePlayer.new()
	add_child(a)
	a.setup(info)
	_avatars[info.id] = a


func _despawn(id: int) -> void:
	var a: RemotePlayer = _avatars.get(id)
	if a:
		a.queue_free()
		_avatars.erase(id)


func _on_states(states: Dictionary) -> void:
	for id in states:
		var a: RemotePlayer = _avatars.get(id)
		if a:
			a.push_state(states[id])


func _on_spell_cast(id: int, spell_path: String, origin: Vector3, direction: Vector3) -> void:
	var a: RemotePlayer = _avatars.get(id)
	if a == null:
		return
	# Spells can show their effect for remote casters (see Spell.cast_remote).
	var spell: Spell = null
	if spell_path.begins_with("res://") and ResourceLoader.exists(spell_path):
		spell = load(spell_path) as Spell
	if spell == null or spell.cast_gesture:
		a.play_cast()
	if spell:
		spell.cast_remote(a, Transform3D(Basis.IDENTITY, origin), direction)


func _on_disconnected(_reason: String) -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(TITLE_SCENE)
