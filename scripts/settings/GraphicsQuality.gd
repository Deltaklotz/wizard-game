class_name GraphicsQuality
extends RefCounted
## World-side graphics options that live on nodes and materials built at load time (Settings
## only knows the viewport and environment). Everything here can change while playing.
##   - Performance shaders: world materials registered with use() swap between their full and
##     lite shader (same uniforms, so values survive the swap).
##   - Vegetation distance: tree / rock MultiMeshes (ScatterBatch, meta "vis") get their
##     visibility ranges scaled by the view distance; mid-range trees only cast shadows from
##     "Medium" shadows up (they were the bulk of the shadow pass).
##   - Shadows: "Low" renders 2 cascades instead of 4, "Off" none.
##   - The sky's radiance map updates incrementally (not every frame) with performance shaders.

## Visibility ranges of trees and rocks, per view distance (Near, Medium, Far).
const VEGETATION_RANGE := [0.6, 0.8, 1.0]
## Shadow levels (Settings.SHADOWS): directional cascade distance.
const SHADOW_DISTANCE := [0.0, 90.0, 160.0, 250.0, 350.0]

static var _materials: Array = []  # [WeakRef ShaderMaterial, full Shader, lite Shader]


static func _settings() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Settings")


static func lite() -> bool:
	var s := _settings()
	return s != null and bool(s.get_value("performance_shaders"))


## Gives `mat` the full or lite shader as the setting says, and keeps it updated.
static func use(mat: ShaderMaterial, full: Shader, lite_shader: Shader) -> void:
	mat.shader = lite_shader if lite() else full
	for entry in _materials:
		if (entry[0] as WeakRef).get_ref() == mat:
			return
	_materials.append([weakref(mat), full, lite_shader])


static func refresh_shaders() -> void:
	var on := lite()
	var alive: Array = []
	for entry in _materials:
		var mat := (entry[0] as WeakRef).get_ref() as ShaderMaterial
		if mat == null:
			continue
		mat.shader = entry[2] if on else entry[1]
		alive.append(entry)
	_materials = alive


## Applies vegetation distance and tree shadows to every ScatterBatch MultiMesh under `root`.
static func apply_vegetation(root: Node) -> void:
	var s := _settings()
	if s == null or root == null:
		return
	var f: float = VEGETATION_RANGE[clampi(s.get_value("view_distance"), 0, 2)]
	var shadows: int = s.get_value("shadows")
	for node in root.find_children("*", "MultiMeshInstance3D", true, false):
		if not node.has_meta("vis"):
			continue
		var mmi := node as MultiMeshInstance3D
		var vis: Vector2 = mmi.get_meta("vis")
		mmi.visibility_range_begin = vis.x * f
		mmi.visibility_range_end = vis.y * f
		var cast: bool = mmi.get_meta("shadows", true) and (vis.x <= 0.0 or shadows >= 2)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func apply_light(light: DirectionalLight3D, level: int) -> void:
	light.shadow_enabled = level > 0
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if level <= 1 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_max_distance = maxf(SHADOW_DISTANCE[clampi(level, 0, 4)], 1.0)


static func apply_sky(env: Environment) -> void:
	if env and env.sky:
		env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL if lite() else Sky.PROCESS_MODE_REALTIME
