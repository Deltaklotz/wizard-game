class_name ShieldWallSpell
extends Spell
## Directional hex shield held in front of the caster (ShieldWall): cast raises it, cast again
## lowers it; the mouse wheel sets its size in rings of hexagons while it is up (remembered for
## the next raise). Holding it costs no mana but stops mana regenerating; blocking costs
## block_mana per damage point, more for a bigger shield; if the mana runs out it shatters.

@export var max_rings := 4
## Circumradius of one hexagon (m), the shield's distance in front of the eyes, and how much
## further out each ring moves it (a little, so even the largest stays mostly in view).
@export var tile_radius := 0.36
@export var distance := 1.7
@export var distance_per_ring := 0.5
## Mana drained per point of damage blocked, and the extra share per ring (ring 4 = x3).
@export var block_mana := 1.0
@export var block_mana_per_ring := 0.5
@export var color := Color(0.38, 0.8, 1.0)
@export var accent := Color(0.9, 0.98, 1.0)
## Colour towards the outer rings.
@export var tint := Color(0.62, 0.55, 1.0)


func can_cast(caster: Node, _grimoire: Node3D) -> bool:
	return caster.has_method("get_aim_origin")


func cast(caster: Node, _origin: Transform3D, _direction: Vector3) -> void:
	ShieldWall.raise_local(self, caster as Node3D)


func cast_remote(caster: Node3D, _origin: Transform3D, _direction: Vector3) -> void:
	if caster is RemotePlayer:
		ShieldWall.raise_remote(self, caster as RemotePlayer)


func _stats() -> Array:
	return [["Size", "up to %d rings" % max_rings], ["Mana / blocked", _num(block_mana)]]
