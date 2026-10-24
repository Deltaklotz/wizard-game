class_name SwordSpell
extends Spell
## Sword Wall: hold cast to see where a giant sword will land (golden ghost + footprint on the
## ground, SwordPreview), release to call it down from the sky. It buries itself point first
## across the view direction – a ~6 m wide wall about two players high, with the hilt towering
## above – damages and shoves aside anyone it lands on, and dissolves after `lifetime` seconds.
##
## The cast message carries the landing point as origin + direction (the remote facing is that
## vector, flattened), so every client builds the same wall with collision (SwordWall). A player
## it lands on takes the damage on their own client.

@export var damage := 40.0
@export var lifetime := 38.0
## Landing distance from the caster (horizontal), along the view.
@export var min_range := 5.0
@export var max_range := 45.0


func can_cast(caster: Node, _grimoire: Node3D) -> bool:
	return caster.has_method("get_aim_origin")


func make_preview(caster: Node) -> Node:
	var preview := SwordPreview.new()
	caster.get_tree().current_scene.add_child(preview)
	preview.setup(self, caster as Node3D)
	return preview


func cast(caster: Node, origin: Transform3D, _direction: Vector3) -> void:
	var land := find_landing(caster as Node3D)
	caster.cast_direction = land.point - origin.origin
	SwordWall.spawn(caster.get_tree().current_scene, self, land.point, land.facing, Net.my_id, caster)


func cast_remote(caster: Node3D, origin: Transform3D, direction: Vector3) -> void:
	var facing := Vector3(direction.x, 0.0, direction.z)
	if facing.length_squared() < 0.0001:
		facing = Vector3(-caster.global_basis.z.x, 0.0, -caster.global_basis.z.z)
	var id: int = (caster as RemotePlayer).peer_id if caster is RemotePlayer else -1
	SwordWall.spawn(caster.get_tree().current_scene, self, origin.origin + direction, facing.normalized(), id, null)


## Where the sword lands for the caster's current view: the point under the crosshair (or at
## max range), clamped to [min_range, max_range] horizontally, dropped onto the ground.
## {"point": Vector3 on the ground, "facing": horizontal unit vector away from the caster}.
func find_landing(caster: Node3D) -> Dictionary:
	var cam: Camera3D = caster.camera
	var from := cam.global_position
	var view := -cam.global_basis.z
	var flat := Vector3(view.x, 0.0, view.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3(-caster.global_basis.z.x, 0.0, -caster.global_basis.z.z)
	flat = flat.normalized()
	var space := caster.get_world_3d().direct_space_state
	var exclude := Shield.excludes_for(caster.get_tree(), Net.my_id, true)
	exclude.append((caster as CollisionObject3D).get_rid())
	for wall in caster.get_tree().get_nodes_in_group("sword_wall"):
		exclude.append((wall as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, from + view * max_range * 1.5)
	q.exclude = exclude
	var r := space.intersect_ray(q)
	var target: Vector3 = r.position if not r.is_empty() else from + view * max_range
	var off := Vector3(target.x - from.x, 0.0, target.z - from.z)
	if off.dot(flat) < 0.1:
		off = flat
	off = off.normalized() * clampf(off.length(), min_range, max_range)
	var x := from.x + off.x
	var z := from.z + off.z
	var down := PhysicsRayQueryParameters3D.create(Vector3(x, from.y + 60.0, z), Vector3(x, from.y - 400.0, z))
	down.exclude = exclude
	down.collision_mask = 1  # ground and world objects, not shields
	var g := space.intersect_ray(down)
	var y: float = g.position.y if not g.is_empty() else from.y - 1.5
	return {"point": Vector3(x, y, z), "facing": flat}


func _stats() -> Array:
	return [["Damage", _num(damage)], ["Stands", "%s s" % _num(lifetime)]]
