class_name SpinjitzuSpell
extends Spell
## Spinjitzu: the caster spins up into a whirling tornado of light (in their own player colour,
## like the Ninjago ninjas) – cast to start, cast again to stop (Grimoire channel). While it
## spins they run `speed_factor` times faster, it drains `drain` mana per second (ends when the
## mana runs out) and anyone it touches takes `dps` and is flung away. The player inside sees
## out through it; from outside a "window" in the swirl shows which way they face.
##
## Spinjitzu does the work; remotes follow the caster's avatar and end on {"kind": "spin_end"}.

## Mana per second while spinning (mana_cost is paid to start).
@export var drain := 12.0
@export var speed_factor := 1.6
@export var dps := 20.0
## Speed (m/s) those it touches are flung away with.
@export var fling := 7.0
## Tornado size: radius at the bottom and at the top, height (m).
@export var bottom_radius := 0.45
@export var top_radius := 1.9
@export var height := 3.0


func can_cast(caster: Node, _grimoire: Node3D) -> bool:
	return caster.has_method("get_aim_origin") and not caster.is_dead()


func cast(caster: Node, _origin: Transform3D, _direction: Vector3) -> void:
	Spinjitzu.start_local(self, caster as Node3D)


func cast_remote(caster: Node3D, _origin: Transform3D, _direction: Vector3) -> void:
	if caster is RemotePlayer:
		Spinjitzu.start_remote(self, caster as RemotePlayer)


## Funnel radius `h` metres above its base.
func radius_at(h: float) -> float:
	var v := clampf(h / height, 0.0, 1.0)
	return bottom_radius + (top_radius - bottom_radius) * pow(v, 1.4)


func _mana_text() -> String:
	return "%s + %s /s" % [_num(mana_cost), _num(drain)]


func _stats() -> Array:
	return [["Speed", "x%s" % _num(speed_factor)], ["Damage", "%s /s on contact" % _num(dps)]]
