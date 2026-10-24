class_name ChainRemote
extends Node
## Another player's chain (see ChainSpell), rebuilt from their {"kind": "chain"} events: while
## it flies, their sparse flight path from the avatar's hand, with the head extrapolated
## between updates so the links feed out smoothly; once it holds, a chain from the hand to the
## anchor / the held player that straightens like the caster's. Ends on "chain_end" (burst or
## fade) or when the caster goes quiet.

const TIMEOUT := 1.2
## The local player's chest relative to its body origin (capsule centre).
const LOCAL_CHEST := 0.25

var _spell: ChainSpell
var _avatar: RemotePlayer
var _fx: ChainFx
var _phase: int = ChainCast.Phase.GROW
var _path := PackedVector3Array()
var _head := Vector3.ZERO
var _head_dir := Vector3.FORWARD
var _since := 0.0
var _end := Vector3.ZERO
var _target_id := -1
var _straight := 0.0
var _silence := 0.0


func start(spell: ChainSpell, avatar: RemotePlayer) -> void:
	_spell = spell
	_avatar = avatar
	var hand := avatar.get_hand_position()
	_head_dir = -avatar.global_basis.z
	_head = hand + _head_dir * 0.1
	_path = PackedVector3Array([hand, _head])
	_fx = ChainFx.create(get_parent(), spell.color, spell.accent, false)
	_fx.set_head_visible(true)
	Net.event_received.connect(_on_event)


func _on_event(id: int, ev: Dictionary) -> void:
	if not is_instance_valid(_avatar) or id != _avatar.peer_id:
		return
	match str(ev.get("kind", "")):
		"chain":
			_silence = 0.0
			var st := int(ev.get("st", 0))
			var pts := _points(ev.get("pts", []))
			if st == ChainCast.Phase.GROW:
				_set_flight(pts)
			elif not pts.is_empty():
				if _phase == ChainCast.Phase.GROW:
					_straight = 0.0
					_fx.set_head_visible(false)
				_phase = st
				_end = pts[0]
				_target_id = int(ev.get("tg", -1))
		"chain_end":
			var pts := _points(ev.get("pts", []))
			if _phase == ChainCast.Phase.GROW and not pts.is_empty():
				_set_flight(pts)
				_since = 0.0
				_fx.set_points(_path)
			_finish(bool(ev.get("burst", false)))


func _set_flight(pts: PackedVector3Array) -> void:
	if pts.is_empty():
		return
	var hand := _avatar.get_hand_position()
	_path = PackedVector3Array([hand])
	_path.append_array(pts)
	var n := _path.size()
	_head = _path[n - 1]
	if n >= 2 and _path[n - 2].distance_to(_head) > 0.01:
		_head_dir = (_head - _path[n - 2]).normalized()
	_since = 0.0


static func _points(flat: Variant) -> PackedVector3Array:
	var out := PackedVector3Array()
	if flat is Array:
		for i in range(0, flat.size() - 2, 3):
			out.append(Vector3(float(flat[i]), float(flat[i + 1]), float(flat[i + 2])))
	return out


func _process(delta: float) -> void:
	if not is_instance_valid(_avatar) or _avatar.is_dead():
		_finish(false)
		return
	_silence += delta
	if _silence > TIMEOUT:
		_finish(false)
		return
	var hand := _avatar.get_hand_position()
	if _phase == ChainCast.Phase.GROW:
		# Keep the head flying on between the ~15 updates a second.
		_since += delta
		var pts := _path.duplicate()
		pts[0] = hand
		pts.append(_head + _head_dir * _spell.grow_speed * minf(_since, 0.12))
		_fx.set_points(pts)
		return
	var end := _end
	if _target_id >= 0:
		var t: Variant = _target_point(_target_id)
		if t != null:
			end = t
	_straight = move_toward(_straight, 1.0, delta / ChainCast.STRAIGHTEN_TIME)
	_path = PackedVector3Array([hand, end]) if _straight >= 1.0 else ChainCast.straighten(_path, hand, end, _straight)
	_fx.set_points(_path)


## Where the held player is drawn: the local player's chest, or another avatar's.
func _target_point(id: int) -> Variant:
	if id == Net.my_id:
		var me := get_tree().current_scene.get_node_or_null("Player") as Node3D
		return me.global_position + Vector3.UP * LOCAL_CHEST if me else null
	var remotes := get_tree().current_scene.get_node_or_null("RemotePlayers")
	if remotes and remotes.has_method("avatar"):
		var a: RemotePlayer = remotes.avatar(id)
		if a:
			return a.global_position + Vector3.UP * ChainCast.CHEST
	return null


func _finish(burst: bool) -> void:
	if is_instance_valid(_fx):
		if burst:
			_fx.burst()
		else:
			_fx.dissolve()
	queue_free()
