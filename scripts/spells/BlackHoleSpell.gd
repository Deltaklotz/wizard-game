class_name BlackHoleSpell
extends Spell
## Black hole. Costs all the caster's mana (at least mana_cost to start), 2 min cooldown.
## A glowing spark leaves the caster's hand and drifts up like a fairy to `height` metres above
## the cast point (a little ahead), swells, spins up and vanishes as the black hole manifests
## there (BlackHole).
## For `duration` seconds it pulls every other player in – harder the closer they are and the
## longer it lives – and anyone reaching the horizon dies. The caster is not pulled.
##
## The cast message carries the hand as origin and the hole's position as origin + direction,
## so every client builds the same hole; each client pulls and kills its own player.

@export var height := 45.0
## How far in front of the caster (along their facing) the hole forms.
@export var forward := 6.0
@export var duration := 30.0
## Radius of the event horizon at full size (m); it swells by `growth` over its life.
@export var horizon := 2.0
@export var growth := 0.35
## Pull: reach (m), and the pull speed (m/s) right at the horizon at the start and at the end
## of its life (sprint is 8.5, a dash ~45). It falls off with (1 - d / reach)^2.
@export var reach := 110.0
@export var pull_start := 9.0
@export var pull_end := 32.0
## Anyone within this many horizon radii of the centre is consumed.
@export var kill_factor := 1.35


func cast(caster: Node, origin: Transform3D, _direction: Vector3) -> void:
	if caster.has_method("spend_mana"):
		caster.spend_mana(caster.mana)
	var feet: Vector3 = (caster as Node3D).global_position - Vector3.UP * caster.FOOT_OFFSET
	var facing := -(caster as Node3D).global_basis.z
	facing.y = 0.0
	var target := feet + Vector3.UP * height + facing.normalized() * forward
	caster.cast_direction = target - origin.origin
	BlackHole.spawn(caster.get_tree().current_scene, self, origin.origin, target, Net.my_id)


func cast_remote(caster: Node3D, origin: Transform3D, direction: Vector3) -> void:
	var id: int = (caster as RemotePlayer).peer_id if caster is RemotePlayer else -1
	BlackHole.spawn(caster.get_tree().current_scene, self, origin.origin, origin.origin + direction, id)


func _stats() -> Array:
	return [["Duration", "%s s" % _num(duration)], ["Reach", "%s m" % _num(reach)], ["Touch", "death"]]


func _mana_text() -> String:
	return "all (at least %s)" % _num(mana_cost)
