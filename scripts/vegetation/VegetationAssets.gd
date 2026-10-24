class_name VegetationAssets
extends RefCounted
## Generates and caches every procedural vegetation/greeble asset once, shared by the
## ground scatter and the floating islands.

const BROADLEAF_VARIANTS := 4
const PINE_VARIANTS := 4
const ROCK_VARIANTS := 8
const BIG_ROCK_VARIANTS := 6
const STICK_VARIANTS := 5

static var _shared: VegetationAssets
static var _shared_pack := ""

## Each entry: {"lod0", "lod1", "lod2", "height", "trunk_radius"}
var broadleaf: Array[Dictionary] = []
var pines: Array[Dictionary] = []
var rocks: Array[ArrayMesh] = []
var big_rocks: Array[ArrayMesh] = []
var sticks: Array[ArrayMesh] = []

var mat_rock: ShaderMaterial
var mat_orbit_rock: ShaderMaterial
var mat_stick: StandardMaterial3D


static func get_shared() -> VegetationAssets:
	# Rebuilt when the texture resource pack changed since the last world.
	if _shared == null or _shared_pack != ResourcePacks.active_id():
		_shared_pack = ResourcePacks.active_id()
		_shared = VegetationAssets.new()
		_shared._build()
	return _shared


func _build() -> void:
	var t0 := Time.get_ticks_msec()
	var bark_oak := _bark_material("bark_oak")
	var bark_pine := _bark_material("bark_pine")
	var leaves := _foliage_material("leaves", Color(0.85, 1.0, 0.8), Color(1.12, 1.02, 0.72), 0.14)
	var needles := _foliage_material("needles", Color(0.85, 0.95, 0.9), Color(1.0, 1.05, 0.85), 0.07)
	for i in BROADLEAF_VARIANTS:
		var t := TreeGenerator.generate(TreeGenerator.Species.BROADLEAF, 1000 + i * 17)
		_assign(t, bark_oak, leaves)
		broadleaf.append(t)
	for i in PINE_VARIANTS:
		var t := TreeGenerator.generate(TreeGenerator.Species.PINE, 2000 + i * 31)
		_assign(t, bark_pine, needles)
		pines.append(t)

	mat_rock = _rock_material(preload("res://shaders/rock.gdshader"), preload("res://shaders/rock_lite.gdshader"))
	mat_orbit_rock = _rock_material(preload("res://shaders/orbit_rock.gdshader"), preload("res://shaders/orbit_rock_lite.gdshader"))
	mat_orbit_rock.set_shader_parameter("moss_amount", 0.45)
	for i in ROCK_VARIANTS:
		var m := RockGenerator.rock(300 + i, 2, 0.5 + (i % 4) * 0.1)
		m.surface_set_material(0, mat_rock)
		rocks.append(m)
	for i in BIG_ROCK_VARIANTS:
		var m := RockGenerator.rock(500 + i, 3, 0.75 + i * 0.05)
		m.surface_set_material(0, mat_rock)
		big_rocks.append(m)

	mat_stick = StandardMaterial3D.new()
	mat_stick.albedo_texture = ResourcePacks.texture("bark_oak_albedo.png")
	mat_stick.normal_enabled = true
	mat_stick.normal_texture = ResourcePacks.texture("bark_oak_normal.png")
	mat_stick.albedo_color = Color(0.8, 0.72, 0.62)
	mat_stick.roughness = 0.95
	for i in STICK_VARIANTS:
		var m := RockGenerator.stick(700 + i)
		m.surface_set_material(0, mat_stick)
		sticks.append(m)
	print("Vegetation assets built in %d ms" % (Time.get_ticks_msec() - t0))


func _assign(tree: Dictionary, bark: Material, foliage: Material) -> void:
	for key in ["lod0", "lod1", "lod2"]:
		var mesh: ArrayMesh = tree[key]
		mesh.surface_set_material(0, bark)
		mesh.surface_set_material(1, foliage)


func _bark_material(name: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = ResourcePacks.texture(name + "_albedo.png")
	m.normal_enabled = true
	m.normal_texture = ResourcePacks.texture(name + "_normal.png")
	m.normal_scale = 1.2
	m.roughness = 0.92
	return m


func _foliage_material(name: String, tint_a: Color, tint_b: Color, wind: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	GraphicsQuality.use(m, preload("res://shaders/foliage.gdshader"), preload("res://shaders/foliage_lite.gdshader"))
	m.set_shader_parameter("albedo_tex", ResourcePacks.texture(name + "_albedo.png"))
	m.set_shader_parameter("normal_tex", ResourcePacks.texture(name + "_normal.png"))
	m.set_shader_parameter("tint_a", tint_a)
	m.set_shader_parameter("tint_b", tint_b)
	m.set_shader_parameter("wind_strength", wind)
	return m


func _rock_material(shader: Shader, lite: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	GraphicsQuality.use(m, shader, lite)
	for t in ["rock", "moss"]:
		m.set_shader_parameter(t + "_albedo", ResourcePacks.texture(t + "_albedo.png"))
		m.set_shader_parameter(t + "_normal", ResourcePacks.texture(t + "_normal.png"))
	return m
