class_name FireballSpell
extends Spell
## Fireball: a ball of fire thrown towards the crosshair that drops in an arc (gravity), trailing
## flames and smoke. On impact (ground, wall, shield or player) it explodes – damage falling off
## from `damage` at the centre to `min_damage` at `blast_radius`, a knock-back, and (if there is
## ground below) a pool of fire (FirePatch) that sets anyone standing in it ablaze
## (Player.ignite: burn_dps for burn_time, refreshed while inside; water puts it out).
##
## The shooter decides the impact and sends {"kind": "fireball", "p", "n"}; every client then
## explodes it there and applies damage / fire to its own player (the caster takes
## `self_damage` of the blast). Other players see a visual-only fireball from the cast message
## (origin + velocity) until the explosion arrives.

@export var damage := 45.0
@export var min_damage := 10.0
@export var blast_radius := 4.0
## Launch speed (m/s) and gravity (m/s²) – the arc / drop-off.
@export var speed := 38.0
@export var gravity := 7.0
## Share of the blast damage the caster takes from their own fireball.
@export var self_damage := 0.5
@export var patch_radius := 4.0
@export var patch_time := 7.0
@export var burn_time := 3.5
@export var burn_dps := 8.0
@export var max_flight := 5.0


func can_cast(caster: Node, _grimoire: Node3D) -> bool:
	return caster.has_method("get_aim_origin")


func cast(caster: Node, origin: Transform3D, _direction: Vector3) -> void:
	var from := origin.origin
	var dir := (_aim_point(caster as Node3D) - from).normalized()
	var velocity := dir * speed
	caster.cast_direction = velocity
	Fireball.launch(caster.get_tree().current_scene, self, from, velocity, Net.my_id, caster as Node3D, null)


func cast_remote(caster: Node3D, origin: Transform3D, direction: Vector3) -> void:
	var id: int = (caster as RemotePlayer).peer_id if caster is RemotePlayer else -1
	Fireball.launch(caster.get_tree().current_scene, self, origin.origin, direction, id, null, caster)


## Where the crosshair points, so the ball from beside the view flies at it.
func _aim_point(caster: Node3D) -> Vector3:
	var cam: Camera3D = caster.camera
	var from := cam.global_position
	var view := -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + view * 300.0)
	var exclude := Shield.excludes_for(caster.get_tree(), Net.my_id, true)
	exclude.append((caster as CollisionObject3D).get_rid())
	q.exclude = exclude
	var r := caster.get_world_3d().direct_space_state.intersect_ray(q)
	return r.position if not r.is_empty() and from.distance_to(r.position) > 3.0 else from + view * 300.0


func _stats() -> Array:
	return [["Damage", "%s – %s" % [_num(damage), _num(min_damage)]], ["Blast", "%s m" % _num(blast_radius)],
		["Burns", "%s /s for %s s" % [_num(burn_dps), _num(burn_time)]]]
