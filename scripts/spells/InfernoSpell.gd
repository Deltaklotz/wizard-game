class_name InfernoSpell
extends Spell
## Infernal Torrent: after a short wind-up a torrent of crimson fire and black smoke erupts from
## the book and pours out along the view for `duration` seconds, widening with distance
## (radius `muzzle_radius` + `spread` per metre) up to `max_range`. The caster steers it with
## the view (it follows with a little lag); cast again to cut it short. Anyone inside the cone
## burns: `dps` while inside, set alight for `burn_time` at `burn_dps`, and is shoved along it.
##
## InfernoBeam does the work. The caster decides the hits (as with every spell) and sends hit
## events; the cast message carries the view direction, remotes then follow the caster's
## avatar's look direction, and {"kind": "inferno_end"} ends it early everywhere.

@export var duration := 3.0
## Seconds of wind-up before it erupts.
@export var charge_time := 0.55
@export var max_range := 90.0
## Cone radius at the muzzle (m) and its growth per metre.
@export var muzzle_radius := 0.35
@export var spread := 0.21
## Damage per second inside the torrent, and the burning it leaves.
@export var dps := 32.0
@export var burn_time := 3.0
@export var burn_dps := 6.0
## Speed (m/s) the torrent shoves those it engulfs along its direction.
## Upward acceleration (m/s²) on the caster when aimed straight down (gravity is ~9.8; scales
## with how steeply down it points, none when level), and the fastest it lifts them (m/s).
@export var lift := 24.0
@export var lift_max_speed := 12.0
@export var push := 5.0
## How fast the torrent turns after the view (1/s).
@export var turn_rate := 7.0


func can_cast(caster: Node, _grimoire: Node3D) -> bool:
	return caster.has_method("get_aim_origin")


func cast(caster: Node, _origin: Transform3D, direction: Vector3) -> void:
	caster.cast_direction = direction.normalized()
	InfernoBeam.start_local(self, caster as Node3D)


func cast_remote(caster: Node3D, origin: Transform3D, direction: Vector3) -> void:
	if caster is RemotePlayer:
		InfernoBeam.start_remote(self, caster as RemotePlayer, origin.origin, direction.normalized())


## Cone radius `d` metres out.
func radius_at(d: float) -> float:
	return muzzle_radius + spread * d


func _stats() -> Array:
	return [["Damage", "%s /s for %s s" % [_num(dps), _num(duration)]], ["Range", "%s m" % _num(max_range)],
		["Burns", "%s /s for %s s" % [_num(burn_dps), _num(burn_time)]]]
