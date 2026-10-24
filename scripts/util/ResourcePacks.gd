class_name ResourcePacks
extends RefCounted
## Texture resource packs: folders in res://resource_packs/<id>/ with a pack.cfg and a
## textures/ folder whose files replace the defaults in res://textures/ by name. The active
## pack is the "resource_pack" setting ("" = default); files a pack lacks fall back to the
## default. Materials read textures when the world is built, so a change applies on the
## next world load.

const DEFAULT_DIR := "res://textures/"
const PACKS_DIR := "res://resource_packs/"

## Pack in use when the current world was built.
static var loaded_id := ""


## [{"id", "name", "description", "author"}] for every installed pack.
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dir in DirAccess.get_directories_at(PACKS_DIR):
		var cfg := ConfigFile.new()
		if cfg.load(PACKS_DIR + dir + "/pack.cfg") != OK:
			continue
		out.append({"id": dir, "name": cfg.get_value("pack", "name", dir),
			"description": cfg.get_value("pack", "description", ""), "author": cfg.get_value("pack", "author", "")})
	return out


static func active_id() -> String:
	var settings := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Settings")
	if settings == null:
		return ""
	var id: String = settings.get_value("resource_pack")
	if id.is_empty() or not FileAccess.file_exists(PACKS_DIR + id + "/pack.cfg"):
		return ""
	return id


## Loads `file` (e.g. "rock_albedo.png") from the active pack, else from the defaults.
static func texture(file: String) -> Texture2D:
	var id := active_id()
	loaded_id = id
	if not id.is_empty():
		var path := PACKS_DIR + id + "/textures/" + file
		if ResourceLoader.exists(path):
			return load(path)
	return load(DEFAULT_DIR + file)
