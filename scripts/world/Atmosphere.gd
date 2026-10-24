extends Node
## Stylized sky and lighting glue: builds the cloud noise textures for the sky shader,
## drifts the cloud layer with the wind and publishes the global shader uniforms that the
## world's materials use for cloud shadows (cloud_weather, cloud_params, sun_direction).
## Look parameters live on the sky material (shaders/sky/stylized_sky.gdshader) and the
## Environment in Main.tscn.

@export var environment_path: NodePath
@export var sun_path: NodePath
## Cloud drift in metres per second (x, z).
@export var wind := Vector2(11.0, 4.0)
@export_range(0.0, 1.0) var coverage := 0.52
## Size of one repeat of the weather (cloud coverage) map in metres.
@export var weather_size := 16000.0

var _offset := Vector2.ZERO
var _sun: DirectionalLight3D


func _ready() -> void:
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	var we := get_node_or_null(environment_path) as WorldEnvironment
	if we == null or we.environment.sky == null:
		return
	var mat := we.environment.sky.sky_material as ShaderMaterial
	mat.set_shader_parameter("cloud_shape", _noise3d(64, FastNoiseLite.TYPE_PERLIN, 4, 4.0 / 64.0, false, 11))
	mat.set_shader_parameter("cloud_detail", _noise3d(32, FastNoiseLite.TYPE_CELLULAR, 3, 4.0 / 32.0, true, 12))
	var weather := NoiseTexture2D.new()
	weather.width = 256
	weather.height = 256
	weather.seamless = true
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.seed = 13
	n.frequency = 0.014
	n.fractal_octaves = 3
	weather.noise = n
	RenderingServer.global_shader_parameter_set("cloud_weather", weather)
	_publish()


func _noise3d(size: int, type: FastNoiseLite.NoiseType, octaves: int, freq: float, invert: bool, seed: int) -> NoiseTexture3D:
	var tex := NoiseTexture3D.new()
	tex.width = size
	tex.height = size
	tex.depth = size
	tex.seamless = true
	tex.invert = invert
	var n := FastNoiseLite.new()
	n.noise_type = type
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = octaves
	if type == FastNoiseLite.TYPE_CELLULAR:
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	tex.noise = n
	return tex


func _process(delta: float) -> void:
	_offset = (_offset + wind * delta).posmod(weather_size * 64.0)
	_publish()


func _publish() -> void:
	RenderingServer.global_shader_parameter_set("cloud_params", Vector4(_offset.x, _offset.y, 1.0 / weather_size, coverage))
	if _sun:
		RenderingServer.global_shader_parameter_set("sun_direction", _sun.global_basis.z.normalized())
