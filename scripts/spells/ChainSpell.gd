class_name ChainSpell
extends Spell
## Spectral chain. Cast throws a ghostly yellow-green chain from the book that grows towards
## the crosshair in stiff, wandering curves (it follows the view while flying, so it can be
## steered around corners) and homes in on players/creatures that come near its head.
##   Hits a surface  -> the caster is hauled towards it (grappling hook).
##   Hits a player   -> that player is hauled towards the caster. Hits a "chainable" node
##                      (future monsters / items) -> chain_pull() is called on it.
## The chain pulls with a force (Player.set_pull): stronger than sprinting, weaker than a dash.
## Being out-pulled for BREAK_TIME seconds (dash away, own chain the other way) snaps it.
## Mana is spent per metre while it grows (mana_cost is the minimum to start); holding is free.
## Running dry while growing, or pressing cast again, snaps it too. While it is out the book
## can't be flipped (Grimoire channel).
##
## The logic lives in ChainCast (local caster) and ChainRemote (other players' chains); both
## draw through ChainFx. Network: the caster sends {"kind": "chain"} events ~15×/s and
## {"kind": "chain_end"} at the end; a held player answers {"kind": "chain_break"} when it
## out-pulled the chain.

## Seconds a chain may be overpowered before it snaps (long enough that one dash doesn't).
const BREAK_TIME := 3.0
## The held one's own movement must leave the chain at least this fraction of its pull speed
## along the chain, otherwise the chain counts as overpowered (sprinting away does not).
const OVERPOWER_FRACTION := 0.25

## 1 mana per 3 m.
@export var mana_per_meter := 0.3333
## Growth speed of the chain head (m/s) and the longest it can get.
@export var grow_speed := 32.0
@export var max_length := 70.0
## How fast the head turns towards the crosshair (rad/s) – low = stiff, sweeping curves –
## and the size of its random wandering (rad).
@export var turn_rate := 3.6
@export var wander := 0.5
## Players/creatures within this distance of the head attract it.
@export var homing_radius := 5.0
@export var homing_turn_rate := 11.0
## Pull speed: sprint is 8.5 m/s, a dash ~45 m/s.
@export var pull_speed := 13.0
@export var color := Color(0.72, 1.0, 0.32)
@export var accent := Color(1.0, 0.93, 0.42)


func can_cast(caster: Node, _grimoire: Node3D) -> bool:
	return caster.has_method("set_pull")


func cast(caster: Node, origin: Transform3D, direction: Vector3) -> void:
	var chain := ChainCast.new()
	caster.get_tree().current_scene.add_child(chain)
	chain.start(self, caster, origin.origin, direction)


func cast_remote(caster: Node3D, _origin: Transform3D, _direction: Vector3) -> void:
	if caster is RemotePlayer:
		var chain := ChainRemote.new()
		caster.get_tree().current_scene.add_child(chain)
		chain.start(self, caster as RemotePlayer)


func _stats() -> Array:
	return [["Mana", "1 per %s m" % _num(snappedf(1.0 / maxf(mana_per_meter, 0.001), 0.1))], ["Reach", "%s m" % _num(max_length)], ["Pull", "%s m/s" % _num(pull_speed)]]
