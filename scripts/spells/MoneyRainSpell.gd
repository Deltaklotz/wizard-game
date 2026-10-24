class_name MoneyRainSpell
extends Spell
## Money Rain: a golden cloud gathers above the caster, a divine shaft of light shines down from
## it and banknotes rain out of it. Everyone standing in the light (the caster, allies
## and enemies alike) heals `heal_rate` per second for `duration` seconds.
##
## The cast message carries the ground point below the caster as origin + direction; every
## client builds the same MoneyRain there and heals its own player.

@export var heal_rate := 5.0
@export var duration := 10.0
## Radius of the healing light on the ground and the cloud's height above it (m).
@export var radius := 4.5
@export var height := 9.0


func cast(caster: Node, origin: Transform3D, _direction: Vector3) -> void:
	var at := ground_below(caster as Node3D)
	caster.cast_direction = at - origin.origin
	MoneyRain.spawn(caster.get_tree().current_scene, self, at)


func cast_remote(caster: Node3D, origin: Transform3D, direction: Vector3) -> void:
	MoneyRain.spawn(caster.get_tree().current_scene, self, origin.origin + direction)


## The ground under the caster's feet (or the feet themselves when there is none close).
func ground_below(caster: Node3D) -> Vector3:
	var feet := caster.global_position - Vector3.UP * float(caster.get("FOOT_OFFSET"))
	var q := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.5, feet + Vector3.DOWN * 30.0)
	q.collision_mask = 1
	q.exclude = [(caster as CollisionObject3D).get_rid()]
	var r := caster.get_world_3d().direct_space_state.intersect_ray(q)
	return r.position if not r.is_empty() else feet


func _stats() -> Array:
	return [["Heals", "%s /s for %s s" % [_num(heal_rate), _num(duration)]], ["Radius", "%s m" % _num(radius)]]
