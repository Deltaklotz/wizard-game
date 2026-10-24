class_name SniperSpell
extends Spell
## Arcane sniper beam. Hold cast to scope in (aim_zoom), release to fire an instant beam
## along the view; the caster has to stay scoped for min_aim_time first (an earlier release
## fires at that mark) so there are no instant quick-scopes. While scoping, other players see
## a spinning red crosshair in front of the caster (RemotePlayer, flag Net.FLAG_AIMING).
##
## Hits are decided by the shooter: the first of world geometry (physics ray) and other
## players (capsule test against RemotePlayer avatars) along the ray. A hit player gets a
## {"kind": "hit"} event and applies the damage itself. The cast message carries the beam
## as direction * length, so remote replays end where the shot ended.

@export var damage := 70.0
@export var max_range := 2000.0
## Radius of a player's hit capsule, and its span above the feet.
@export var hit_radius := 0.5
@export var color := Color(1.0, 0.13, 0.2)
@export var accent := Color(1.0, 0.6, 0.35)

const CAPSULE_LOW := 0.3
const CAPSULE_HIGH := 1.8


func can_cast(caster: Node, _grimoire: Node3D) -> bool:
	return caster.has_method("get_aim_origin")


func cast(caster: Node, origin: Transform3D, direction: Vector3) -> void:
	var eye: Vector3 = caster.get_aim_origin()
	var hit := trace(caster as Node3D, eye, direction.normalized())
	var to: Vector3 = hit.point
	var target: int = hit.target
	if hit.shield:
		(hit.shield as Shield).report_hit(damage, to)
	elif target >= 0:
		Net.send_event({"kind": "hit", "target": target, "damage": damage, "spell": resource_path})
		if caster.has_method("confirm_hit"):
			caster.confirm_hit(target)
	caster.cast_direction = to - origin.origin
	if caster.has_method("add_recoil"):
		caster.add_recoil(0.035)
	SniperFx.fire(caster.get_tree().current_scene, origin.origin, to, hit.normal, color, accent,
		target >= 0, true, eye)


func cast_remote(caster: Node3D, origin: Transform3D, direction: Vector3) -> void:
	var to := origin.origin + direction
	var dir := direction.normalized()
	# The end point is the shooter's; only the surface normal there (for the impact ring) is
	# looked up locally.
	var normal := -dir
	var q := PhysicsRayQueryParameters3D.create(to - dir * 0.5, to + dir * 0.5)
	var r := caster.get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		normal = r.normal
	var viewer := caster.get_viewport().get_camera_3d()
	SniperFx.fire(caster.get_tree().current_scene, origin.origin, to, normal, color, accent, false, false,
		viewer.global_position if viewer else to)


## First hit along the ray: {"point", "normal", "target"} (target = peer id of a hit player, or -1).
func trace(caster: Node3D, from: Vector3, dir: Vector3) -> Dictionary:
	var end := from + dir * max_range
	var result := {"point": end, "normal": -dir, "target": -1, "shield": null}
	var space := caster.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, end)
	var exclude := Shield.excludes_for(caster.get_tree(), Net.my_id)
	if caster is CollisionObject3D:
		exclude.append((caster as CollisionObject3D).get_rid())
	q.exclude = exclude
	var r := space.intersect_ray(q)
	var best := max_range
	if not r.is_empty():
		best = from.distance_to(r.position)
		result.point = r.position
		result.normal = r.normal
		result.shield = Shield.from_collider(r.collider)
	var dome := Shield.dome_exit(caster.get_tree(), from, from + dir * best)
	if not dome.is_empty():
		best = dome.dist
		result.point = dome.point
		result.normal = dome.normal
		result.shield = dome.shield
	for node in caster.get_tree().get_nodes_in_group("remote_player"):
		var avatar := node as RemotePlayer
		if avatar == null or not avatar.visible or avatar.is_dead():
			continue
		var a := avatar.global_position + Vector3.UP * CAPSULE_LOW
		var b := avatar.global_position + Vector3.UP * CAPSULE_HIGH
		var pts := Geometry3D.get_closest_points_between_segments(from, from + dir * best, a, b)
		if pts[0].distance_to(pts[1]) <= hit_radius:
			var d := from.distance_to(pts[0])
			if d < best:
				best = d
				result.point = pts[0]
				result.normal = (pts[0] - pts[1]).normalized() if pts[0].distance_to(pts[1]) > 0.01 else -dir
				result.target = avatar.peer_id
				result.shield = null
	return result


func _stats() -> Array:
	return [["Damage", _num(damage)], ["Aim", "%s s" % _num(min_aim_time)]]
