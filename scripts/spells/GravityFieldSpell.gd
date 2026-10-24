class_name GravityFieldSpell
extends Spell
## Gravity Field: hold cast to aim a column of crushing gravity (preview: its rune circle and a
## faint column at the crosshair, out to `max_range`), release to call it down. The column
## reaches endlessly upwards; for `duration` seconds everyone inside it – anyone in the air above
## it too – is dragged straight down to the ground at `slam_speed` (dashes and grapples cut
## short). Made to pluck players out of the sky on their way to the high islands. Aiming at a
## player in the air puts the column under them.
##
## The cast message carries the ground point as origin + direction; every client builds the same
## field (GravityField) and drags its own player.

@export var radius := 7.0
@export var duration := 6.0
@export var max_range := 120.0
## Downward speed forced on those inside (m/s) and seconds it takes to form.
@export var slam_speed := 40.0
@export var form_time := 0.5
@export var color := Color(0.45, 0.28, 1.0)
@export var accent := Color(0.85, 0.75, 1.0)


func can_cast(caster: Node, _grimoire: Node3D) -> bool:
	return caster.has_method("get_aim_origin")


func make_preview(caster: Node) -> Node:
	return GravityField.make_preview(self, caster as Node3D)


func cast(caster: Node, origin: Transform3D, _direction: Vector3) -> void:
	var spot := find_spot(caster as Node3D)
	caster.cast_direction = spot - origin.origin
	GravityField.spawn(caster.get_tree().current_scene, self, spot, false)


func cast_remote(caster: Node3D, origin: Transform3D, direction: Vector3) -> void:
	GravityField.spawn(caster.get_tree().current_scene, self, origin.origin + direction, false)


## Ground point for the caster's current view: under a player near the crosshair line (so it
## can be aimed at someone flying), else under whatever the crosshair hits, else under the point
## at max range.
func find_spot(caster: Node3D) -> Vector3:
	var cam: Camera3D = caster.camera
	var from := cam.global_position
	var view := -cam.global_basis.z
	var space := caster.get_world_3d().direct_space_state
	var exclude: Array[RID] = [(caster as CollisionObject3D).get_rid()]
	var q := PhysicsRayQueryParameters3D.create(from, from + view * max_range)
	q.collision_mask = 1
	q.exclude = exclude
	var r := space.intersect_ray(q)
	var reach: float = from.distance_to(r.position) if not r.is_empty() else max_range
	var probe: Vector3 = r.position if not r.is_empty() else from + view * max_range
	var best := radius * 0.7
	for node in caster.get_tree().get_nodes_in_group("remote_player"):
		var a := node as RemotePlayer
		if a == null or not a.visible or a.is_dead():
			continue
		var p := a.global_position + Vector3.UP
		var t := (p - from).dot(view)
		if t < 0.0 or t > reach:
			continue
		var d := (from + view * t).distance_to(p)
		if d < best:
			best = d
			probe = p
	var down := PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 0.5, probe + Vector3.DOWN * 2000.0)
	down.collision_mask = 1
	down.exclude = exclude
	var g := space.intersect_ray(down)
	return g.position if not g.is_empty() else probe


func _stats() -> Array:
	return [["Radius", "%s m" % _num(radius)], ["Lasts", "%s s" % _num(duration)], ["Range", "%s m" % _num(max_range)]]
