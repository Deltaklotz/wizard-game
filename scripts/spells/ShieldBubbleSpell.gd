class_name ShieldBubbleSpell
extends Spell
## Shield bubble: a hex-tile dome (ShieldDome) rises around the caster's feet and blocks shots
## (from outside and, for its caster, from inside) until it has absorbed `hp` damage – it cracks
## along the way and shatters, or `lifetime` runs out (then it sinks away), or a Sword Wall
## lands on it (shatters at once). One per caster: casting again replaces the old dome.
## The cast message carries the dome centre as origin + direction.

@export var hp := 150.0
@export var radius := 7.2
## Seconds it stands before it fades by itself.
@export var lifetime := 120.0
@export var color := Color(0.3, 0.75, 1.0)
@export var accent := Color(0.85, 0.97, 1.0)
## Colour towards the top of the dome.
@export var tint := Color(0.62, 0.55, 1.0)


func cast(caster: Node, origin: Transform3D, _direction: Vector3) -> void:
	var center: Vector3 = (caster as Node3D).global_position - Vector3.UP * caster.FOOT_OFFSET
	caster.cast_direction = center - origin.origin
	var old := Shield.find(caster.get_tree(), Net.my_id, "bubble")
	if old:
		old.end(false)
	ShieldDome.spawn(caster.get_tree().current_scene, self, center, Net.my_id, true)


func cast_remote(caster: Node3D, origin: Transform3D, direction: Vector3) -> void:
	if not caster is RemotePlayer:
		return
	var id := (caster as RemotePlayer).peer_id
	var old := Shield.find(caster.get_tree(), id, "bubble")
	if old:
		old.end(false)
	ShieldDome.spawn(caster.get_tree().current_scene, self, origin.origin + direction, id, false)


func _stats() -> Array:
	return [["Absorbs", _num(hp)], ["Radius", "%s m" % _num(radius)], ["Lasts", "%s s" % _num(lifetime)]]
