class_name MissileSpell
extends Spell
## Missiles that hunt other players (Missile). One script, two spells:
##   Magic Missiles (spells/magic_missile.tres): three small arcane darts out of the book,
##     `damage` each, short reach (`max_distance`); without a target they follow the crosshair.
##   Homing Missiles (spells/homing_missile.tres): the bigger cousin – five, faster, longer
##     reach, launched from behind the caster's head over it, and `explosive`: they burst with
##     blast damage falling off over `blast_radius`; without a target they land on the point
##     the caster aimed at.
## They come one after another (`spawn_interval`), then each locks onto the player closest to the
## line towards the aim point within `lock_angle` and `homing_range` (in sight) and turns towards
## them at `turn_rate`. They live `lifetime` seconds.
##
## The cast message carries the aim point as origin + direction; every client flies the same
## missiles from the caster (visual replays seek the same way – every player but the caster). The
## caster decides hits ({"kind": "hit"}, or {"kind": "missile_boom"} for explosive ones, which
## every client then applies).

@export var count := 3
## Seconds between missiles of a volley.
@export var spawn_interval := 0.5
## Seconds after launch before it starts steering.
@export var launch_time := 0.25
## Launched from behind the caster's head (arcing over it) instead of out of the book.
@export var launch_behind := false
## Without a target: follow the caster's live crosshair (else fly to the point aimed at when cast).
@export var follow_crosshair := true
## Reach of the crosshair ray (m) and the furthest a missile flies (m, 0 = only its lifetime).
@export var aim_range := 300.0
@export var max_distance := 0.0
## m/s (sprint is 8.5).
@export var speed := 12.75
@export var damage := 20.0
@export var lifetime := 10.0
@export var homing_range := 60.0
## Degrees off the line towards the aim point a target may be to be locked onto.
@export var lock_angle := 50.0
## How fast it turns towards its target (radians per second).
@export var turn_rate := 2.6
## Head size (m) and look.
@export var size := 0.22
@export var color := Color(0.75, 0.4, 1.0)
@export var accent := Color(1.0, 0.85, 1.0)
@export_group("Explosive")
@export var explosive := false
@export var blast_radius := 3.5
## Blast damage at the edge (`damage` at the centre), and the share the caster takes.
@export var min_damage := 12.0
@export var self_damage := 0.3


func can_cast(caster: Node, _grimoire: Node3D) -> bool:
	return caster.has_method("get_aim_origin")


func cast(caster: Node, origin: Transform3D, _direction: Vector3) -> void:
	var aim := Missile.crosshair_point(caster as Node3D, aim_range)
	caster.cast_direction = aim - origin.origin
	Missile.volley(caster.get_tree().current_scene, self, Net.my_id, caster as Node3D, caster as Node3D, aim)


func cast_remote(caster: Node3D, origin: Transform3D, direction: Vector3) -> void:
	var id: int = (caster as RemotePlayer).peer_id if caster is RemotePlayer else -1
	Missile.volley(caster.get_tree().current_scene, self, id, caster, null, origin.origin + direction)


func _stats() -> Array:
	var out := [["Missiles", str(count)], ["Speed", "%s m/s" % _num(speed)], ["Lasts", "%s s" % _num(lifetime)]]
	if explosive:
		out.push_front(["Damage", "%s – %s each" % [_num(damage), _num(min_damage)]])
		out.append(["Blast", "%s m" % _num(blast_radius)])
	else:
		out.push_front(["Damage", "%s each" % _num(damage)])
	return out
