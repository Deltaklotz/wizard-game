extends Node
## Autoload "Balance": spell and player numbers from config/balance.cfg (see the file for the
## format). Offline the game's own copy is used; online the server sends its copy in "welcome"
## (Net calls apply()) and leaving the server goes back to the local one.
##
## Values are written straight into the spell resources (res://spells/<section>.tres) – they are
## cached by the ResourceLoader, so every holder (grimoire, remote replays) sees the same numbers.

signal changed

const LOCAL_PATH := "res://config/balance.cfg"
const SPELL_DIR := "res://spells/"

## The data in effect: {section: {key: value}}.
var data := {}
## The configured spell resources, kept alive: a resource nobody holds is freed, and the next
## load() would read the unbalanced values from disk again.
var _held := {}


func _ready() -> void:
	reset_to_local()


## Parses a balance file into {section: {key: value}} (also used by the server).
static func read_file(path: String) -> Dictionary:
	var out := {}
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		push_warning("Balance file not found or invalid: %s" % path)
		return out
	for section in cfg.get_sections():
		var values := {}
		for key in cfg.get_section_keys(section):
			values[key] = cfg.get_value(section, key)
		out[section] = values
	return out


func reset_to_local() -> void:
	apply(read_file(LOCAL_PATH))


func apply(new_data: Dictionary) -> void:
	data = new_data
	for section in data:
		var path: String = SPELL_DIR + str(section) + ".tres"
		if not ResourceLoader.exists(path):
			continue
		var spell := load(path) as Spell
		if spell == null:
			continue
		_held[path] = spell
		var values: Dictionary = data[section]
		for key in values:
			var k := str(key)
			if k == "rarity":
				spell.rarity = Spell.rarity_from_name(str(values[key]))
			elif k in spell:
				var current: Variant = spell.get(k)
				var v: Variant = values[key]
				# JSON (network) turns ints into floats; keep the property's type.
				spell.set(k, int(v) if current is int else float(v) if current is float else v)
	changed.emit()


## A [player] value (max_health, max_mana, mana_regen), or `fallback`.
func player_value(key: String, fallback: float) -> float:
	var p: Dictionary = data.get("player", {})
	return float(p.get(key, fallback))
