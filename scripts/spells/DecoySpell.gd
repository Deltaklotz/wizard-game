class_name DecoySpell
extends Spell
## Decoy: an illusion of the caster splits off and runs away along their view – same model,
## colour and name tag, so to everyone else it looks like the real player. It sprints around,
## turns, jumps, now and then dashes (with the real dash effect) or stops and raises a fake
## sniper scope (the red warning crosshair) at someone. Any hit makes it vanish in a puff; it
## also fades after `lifetime` seconds. The caster can keep up to `max_decoys` at once.
##
## The caster's client runs it (Decoy) and sends its state as {"kind": "decoy"} events ~10x/s;
## the others show it like any other player (it is a RemotePlayer, so spells can hit it).

@export var lifetime := 20.0
@export var max_decoys := 2
## m/s it runs (sprint is 8.5).
@export var run_speed := 8.5


func can_cast(caster: Node, _grimoire: Node3D) -> bool:
	return caster.has_method("get_aim_origin")


func cast(caster: Node, _origin: Transform3D, _direction: Vector3) -> void:
	Decoy.summon(self, caster as Node3D)


func cast_remote(caster: Node3D, _origin: Transform3D, _direction: Vector3) -> void:
	# The decoy itself arrives with its first state; here just the split-off shimmer.
	Decoy.split_fx(caster.get_tree().current_scene, caster.global_position,
		(caster as RemotePlayer).player_color if caster is RemotePlayer else theme_color)


func _stats() -> Array:
	return [["Lasts", "%s s" % _num(lifetime)], ["At once", str(max_decoys)]]
