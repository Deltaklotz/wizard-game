class_name MinigunSpell
extends Spell
## Arcane minigun. Hold cast: a gatling of crystal barrels (MinigunRig) floating in front of the
## book spins up and hoses purple-blue magic orbs (MagicBolt) at the crosshair, faster as it
## spins, spreading more as it heats. Every orb costs mana_cost (1) and does `damage` (1).
## Each shot adds 1 heat; heat winds down when the trigger is released, and reaching max_heat
## overheats the rig: no firing for overheat_time while it vents.
##
## Each orb is a cast message (origin + direction); other players replay it as a visual-only
## orb. Hits are decided by the shooter like the sniper beam ({"kind": "hit"} events).

@export var damage := 1.0
## Shots per second at the start of the spin-up and at full spin.
@export var min_rate := 7.0
@export var max_rate := 14.0
@export var bolt_speed := 50.0
@export var max_range := 250.0
## Spread (degrees) when cold and at max heat.
@export var spread_cold := 0.5
@export var spread_hot := 2.4
@export var max_heat := 100.0
@export var overheat_time := 5.0
## Heat lost per second once the trigger has been released for a moment.
@export var cool_rate := 22.0
@export var color := Color(0.62, 0.3, 1.0)
@export var accent := Color(0.32, 0.6, 1.0)
## Colour of an overheated rig.
@export var hot_color := Color(1.0, 0.42, 0.78)


func can_cast(caster: Node, _grimoire: Node3D) -> bool:
	var rig := get_rig(caster)
	return rig != null and rig.can_fire()


## The caster's rig, created on first use (a child of the player, so the HUD finds it).
func get_rig(caster: Node) -> MinigunRig:
	var rig := caster.get_node_or_null("MinigunRig") as MinigunRig
	if rig == null and caster.has_method("get_aim_origin"):
		rig = MinigunRig.new()
		rig.name = "MinigunRig"
		rig.setup(self, caster as Node3D)
		caster.add_child(rig)
	return rig


func hold(caster: Node, _grimoire: Node3D, _delta: float) -> void:
	var rig := get_rig(caster)
	if rig:
		rig.trigger = true


func cast(caster: Node, origin: Transform3D, _direction: Vector3) -> void:
	var rig := get_rig(caster)
	var from := rig.muzzle_position() if rig else origin.origin
	var dir := (_aim_point(caster as Node3D) - from).normalized()
	var heat := rig.heat / max_heat if rig else 0.0
	dir = _spread(dir, deg_to_rad(lerpf(spread_cold, spread_hot, heat)))
	caster.cast_direction = dir
	MagicBolt.fire(caster.get_tree().current_scene, self, from, dir, caster as Node3D, null)
	if rig:
		rig.on_shot()


func cast_remote(caster: Node3D, origin: Transform3D, direction: Vector3) -> void:
	if direction.length_squared() < 0.0001:
		return
	MagicBolt.fire(caster.get_tree().current_scene, self, origin.origin, direction.normalized(), null, caster)
	MagicBolt.muzzle_flash(caster.get_tree().current_scene, self, origin.origin, direction.normalized())


## Where the crosshair points (first hit along the view, or far away), so the orbs from the
## muzzle beside the view converge on it.
func _aim_point(caster: Node3D) -> Vector3:
	var cam: Camera3D = caster.camera
	var from := cam.global_position
	var view := -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + view * max_range)
	var exclude := Shield.excludes_for(caster.get_tree(), Net.my_id, true)
	exclude.append((caster as CollisionObject3D).get_rid())
	q.exclude = exclude
	var r := caster.get_world_3d().direct_space_state.intersect_ray(q)
	return r.position if not r.is_empty() and from.distance_to(r.position) > 3.0 else from + view * max_range


static func _spread(dir: Vector3, angle: float) -> Vector3:
	var side := MeshUtil.perpendicular(dir)
	var up := dir.cross(side)
	var a := randf() * TAU
	var r := sqrt(randf()) * angle
	return (dir + (side * cos(a) + up * sin(a)) * tan(r)).normalized()


func _stats() -> Array:
	return [["Damage", "%s / orb" % _num(damage)], ["Fire rate", "%s /s" % _num(max_rate)], ["Overheats", "%s shots" % _num(max_heat)]]
