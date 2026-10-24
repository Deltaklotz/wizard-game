class_name SmokeSpell
extends Spell
## Smoke Bomb: a small hissing orb thrown in an arc towards the crosshair. It bounces, rolls to a
## stop (or hits its fuse) and bursts into a thick cloud of smoke for `duration` seconds that
## nobody can see through; inside it the view drowns in grey (HUD) and name tags are hidden.
##
## Purely visual and fully deterministic: the cast message carries origin + throw velocity and
## every client flies the same bomb against the same world (SmokeBomb, world collision only).

@export var speed := 21.0
@export var gravity := 14.0
## Seconds after the first bounce before it bursts (sooner if it comes to rest).
@export var fuse := 1.2
@export var radius := 7.0
@export var duration := 14.0


func can_cast(caster: Node, _grimoire: Node3D) -> bool:
	return caster.has_method("get_aim_origin")


func cast(caster: Node, origin: Transform3D, _direction: Vector3) -> void:
	var cam: Camera3D = caster.camera
	var view := -cam.global_basis.z
	# Lobbed a little above the crosshair.
	var velocity := (view + Vector3.UP * 0.18).normalized() * speed
	caster.cast_direction = velocity
	SmokeBomb.launch(caster.get_tree().current_scene, self, origin.origin, velocity)


func cast_remote(caster: Node3D, origin: Transform3D, direction: Vector3) -> void:
	SmokeBomb.launch(caster.get_tree().current_scene, self, origin.origin, direction)


func _stats() -> Array:
	return [["Radius", "%s m" % _num(radius)], ["Lasts", "%s s" % _num(duration)]]
