class_name DashSpell
extends Spell
## Blink-dash: a short burst of speed straight along the view direction (upwards too),
## carrying a little momentum out of it. The motion itself is done by the
## caster (Player.start_dash); this spell supplies the tuning and the visuals.

@export var distance := 9.0
@export var duration := 0.24
@export var color := Color(0.42, 0.62, 1.0)
@export var accent := Color(0.82, 0.5, 1.0)


func can_cast(caster: Node, _grimoire: Node3D) -> bool:
	return caster.has_method("start_dash") and not caster.is_dashing()


func cast(caster: Node, _origin: Transform3D, direction: Vector3) -> void:
	var dir: Vector3 = caster.get_dash_direction(direction)
	caster.start_dash(dir, distance, duration)
	# Sent to other players instead of the view direction (see Player._on_spell_cast).
	caster.cast_direction = dir
	DashFx.play(caster, dir, duration, color, accent, caster.FOOT_OFFSET, true)


func cast_remote(caster: Node3D, _origin: Transform3D, direction: Vector3) -> void:
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else -caster.global_basis.z
	var ghost: Node3D = null
	if caster is RemotePlayer:
		ghost = (caster as RemotePlayer).get_body()
	DashFx.play(caster, dir, duration, color, accent, 0.0, false, ghost)


func _stats() -> Array:
	return [["Distance", "%s m" % _num(distance)]]
