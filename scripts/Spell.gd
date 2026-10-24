class_name Spell
extends Resource
## Base class for every spell that can be written into the Grimoire.
## Create concrete spells by extending this script and overriding cast().
## Spells are also inventory items (spell pages): rarity decides their glow, and their numbers
## come from config/balance.cfg (Balance autoload).

enum Rarity { RARE, EPIC, LEGENDARY, PRIMORDIAL }
## In-game names of the rarities, their config names and colours.
const RARITY_NAMES := ["Arcane", "Eldritch", "Celestial", "Primordial"]
const RARITY_KEYS := ["rare", "epic", "legendary", "primordial"]
const RARITY_COLORS := [Color(0.35, 0.62, 1.0), Color(0.72, 0.38, 1.0), Color(1.0, 0.78, 0.3), Color(0.55, 0.3, 0.85)]

@export var spell_name: String = "Unnamed Spell"
@export_multiline var description: String = ""
@export var mana_cost: float = 10.0
## Health spent per cast (spells so powerful they cost the caster's life). Refused if it would kill.
@export var hp_cost: float = 0.0
@export var rarity: Rarity = Rarity.RARE
## Seconds before this spell can be cast again.
@export var cooldown: float = 0.5
## Optional artwork drawn onto the spell's (right-hand) page.
@export var page_texture: Texture2D
## The spell's own colour (independent of rarity): its arcane circle on the grimoire page, the
## crosshair tint and other accents.
@export var theme_color := Color(0.55, 0.7, 1.0)
## How hard the book jolts back when this spell is cast (rapid-fire spells keep it small).
@export var cast_kick := 1.0
## Other players see the caster's cast gesture and flash (off for rapid fire).
@export var cast_gesture := true
## Holding cast keeps calling hold() every frame instead of casting once (rapid fire); the
## spell decides when to cast (Grimoire.try_cast).
@export var hold_fire := false

@export_group("Aiming")
## Hold-to-aim: pressing cast starts aiming, releasing fires (see Grimoire.start_aim).
@export var aimed := false
## Seconds the caster must stay aimed before it fires; an earlier release fires at this mark.
@export var min_aim_time := 0.0
## View zoom while aiming (1 = none).
@export var aim_zoom := 1.0
## Movement speed factor while aiming.
@export var aim_move_factor := 1.0
## Aiming raises a scope: zoom (aim_zoom), HUD lens, lowered book, no sprinting, and other
## players see a warning crosshair. Off = plain hold-to-place aiming (e.g. with a preview).
@export var aim_scope := false


static func rarity_from_name(key: String) -> Rarity:
	var i := RARITY_KEYS.find(key.to_lower())
	return (i if i >= 0 else 0) as Rarity


func get_rarity_name() -> String:
	return RARITY_NAMES[rarity]


func get_rarity_color() -> Color:
	return RARITY_COLORS[rarity]


## Lines for the inventory tooltip: [label, value] pairs. Spells add their own via _stats().
func get_stats() -> Array:
	var out: Array = []
	var mana := _mana_text()
	if not mana.is_empty():
		out.append(["Mana", mana])
	if hp_cost > 0.0:
		out.append(["Life", _num(hp_cost)])
	if cooldown > 0.0:
		out.append(["Cooldown", "%s s" % _num(cooldown)])
	out.append_array(_stats())
	return out


## How the mana cost reads in the tooltip ("" = none).
func _mana_text() -> String:
	return _num(mana_cost) if mana_cost > 0.0 else ""


## Spell-specific tooltip lines.
func _stats() -> Array:
	return []


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


## Extra, spell-specific conditions (line of sight, target present, ...).
## Mana, cooldown and page checks are already handled by the Grimoire.
func can_cast(_caster: Node, _grimoire: Node3D) -> bool:
	return true


## Called every frame while cast is held on a hold_fire spell.
func hold(_caster: Node, _grimoire: Node3D, _delta: float) -> void:
	pass


## Optional node shown while an aimed spell is held (e.g. a landing preview). The Grimoire frees
## it when the aim ends.
func make_preview(_caster: Node) -> Node:
	return null


## Perform the spell. origin is the point just above the open book, direction is where the caster looks.
func cast(_caster: Node, _origin: Transform3D, _direction: Vector3) -> void:
	push_warning("Spell '%s' has no cast() implementation." % spell_name)


## Visual-only replay when another player casts this spell (multiplayer). The spell must
## be a saved resource so its path can be sent over the network. Gameplay effects that
## need one authoritative result (damage, enemies) should go through the server instead.
func cast_remote(_caster: Node3D, _origin: Transform3D, _direction: Vector3) -> void:
	pass
