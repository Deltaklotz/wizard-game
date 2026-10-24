extends SceneTree
## Bakes all procedural material textures to res://textures/ (seamlessly tiling PNGs).
## Run from the project folder (needs a GPU, so no --headless):
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/bake_textures.gd
## PACK=<id> bakes a resource pack instead: shader, jobs and strip height come from
## res://resource_packs/<id>/pack.cfg [bake], output goes to its textures/ folder.

const OUT_DIR := "res://textures/"
const SHADER := "res://shaders/compute/texture_bake.glsl"

# name, mode (see texture_bake.glsl), size, normal strength (0 = no normal map)
const JOBS := [
	["grass", 0, 1024, 6.0],
	["rock", 1, 1024, 9.0],
	["dirt", 2, 1024, 8.0],
	["snow", 3, 512, 4.0],
	["bark_oak", 4, 1024, 10.0],
	["bark_pine", 5, 1024, 10.0],
	["leaves", 6, 1024, 3.0],
	["needles", 7, 1024, 3.0],
	["macro", 8, 512, 0.0],
	["moss", 9, 1024, 6.0],
	["detail", 10, 512, 0.0],
	["water", 11, 1024, 5.0],
]


func _initialize() -> void:
	var gpu := GpuCompute.new()
	if not gpu.is_valid():
		push_error("No RenderingDevice available; run without --headless.")
		quit(1)
		return
	var out_dir := OUT_DIR
	var shader := SHADER
	var jobs: Array = JOBS
	var strip := 0
	var pack := OS.get_environment("PACK")
	if not pack.is_empty():
		var cfg := ConfigFile.new()
		if cfg.load(ResourcePacks.PACKS_DIR + pack + "/pack.cfg") != OK:
			push_error("No pack.cfg for pack '%s'." % pack)
			quit(1)
			return
		out_dir = ResourcePacks.PACKS_DIR + pack + "/textures/"
		shader = cfg.get_value("bake", "shader")
		jobs = cfg.get_value("bake", "jobs")
		strip = cfg.get_value("bake", "strip", 0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var only := OS.get_environment("BAKE_ONLY")
	for job in jobs:
		var tex_name: String = job[0]
		if not only.is_empty() and not tex_name in only.split(","):
			continue
		var size: int = job[2]
		var strength: float = job[3]
		var bytes := size * size * 4
		var albedo_buf := gpu.buffer(bytes)
		var normal_buf := gpu.buffer(bytes)
		var t0 := Time.get_ticks_msec()
		if strip > 0:
			# Pack shaders take the first row in the last push constant.
			for row in range(0, size, strip):
				var push := GpuCompute.push_constants([size, job[1], strength, row])
				gpu.dispatch(shader, [albedo_buf, normal_buf], push, Vector3i(ceili(size / 8.0), ceili(mini(strip, size - row) / 8.0), 1))
		else:
			var push := GpuCompute.push_constants([size, job[1], strength, 0.0])
			gpu.dispatch(shader, [albedo_buf, normal_buf], push, Vector3i(ceili(size / 8.0), ceili(size / 8.0), 1))

		var albedo := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, gpu.read(albedo_buf))
		_save(albedo, out_dir, tex_name + "_albedo", false, not pack.is_empty())
		if strength > 0.0:
			var normal := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, gpu.read(normal_buf))
			normal.convert(Image.FORMAT_RGB8)
			_save(normal, out_dir, tex_name + "_normal", true, not pack.is_empty())
		print("baked %s (%d px, %d ms)" % [tex_name, size, Time.get_ticks_msec() - t0])
	gpu.free_all()
	quit()


func _save(img: Image, dir: String, file: String, is_normal: bool, high_quality: bool) -> void:
	var path := dir + file + ".png"
	img.save_png(path)
	var import_path := ProjectSettings.globalize_path(path + ".import")
	if FileAccess.file_exists(import_path):
		return
	# VRAM-compressed with mipmaps; normal maps use RG compression.
	var cfg := ConfigFile.new()
	cfg.set_value("remap", "importer", "texture")
	cfg.set_value("remap", "type", "CompressedTexture2D")
	cfg.set_value("deps", "source_file", path)
	# Height data (detail) must stay lossless; everything else is VRAM compressed.
	cfg.set_value("params", "compress/mode", 0 if file.begins_with("detail") else 2)
	# Packs use BC7 for colour (better gradients than BC1/3 at the cost of size).
	cfg.set_value("params", "compress/high_quality", high_quality)
	cfg.set_value("params", "compress/normal_map", 1 if is_normal else 2)
	cfg.set_value("params", "mipmaps/generate", true)
	cfg.set_value("params", "mipmaps/limit", -1)
	cfg.set_value("params", "process/fix_alpha_border", true)
	cfg.set_value("params", "detect_3d/compress_to", 0)
	cfg.save(import_path)
