class_name GpuCompute
extends RefCounted
## Thin wrapper around a local RenderingDevice for running compute shaders.

var rd: RenderingDevice
var _pipelines: Dictionary = {}
var _buffers: Array[RID] = []


func _init() -> void:
	rd = RenderingServer.create_local_rendering_device()


func is_valid() -> bool:
	return rd != null


## Storage buffer of `bytes` size, optionally initialised with data.
func buffer(bytes: int, data := PackedByteArray()) -> RID:
	var rid := rd.storage_buffer_create(bytes, data)
	_buffers.append(rid)
	return rid


func read(buf: RID) -> PackedByteArray:
	return rd.buffer_get_data(buf)


## Copies `bytes` (a multiple of 4) from one buffer to another on the GPU. A compute pass:
## RenderingDevice.buffer_copy silently did nothing on this local device.
func copy(src: RID, dst: RID, bytes: int) -> void:
	var count := bytes / 4
	dispatch("res://shaders/compute/buffer_copy.glsl", [src, dst], push_constants([count, 0, 0, 0]),
		Vector3i(ceili(count / 256.0), 1, 1))


func write(buf: RID, data: PackedByteArray) -> void:
	rd.buffer_update(buf, 0, data.size(), data)


## Runs a compute shader. `buffers` are bound to set 0 at bindings 0..n in order.
func dispatch(shader_path: String, buffers: Array, push: PackedByteArray, groups: Vector3i) -> void:
	var p := _pipeline(shader_path)
	var uniforms: Array[RDUniform] = []
	for i in buffers.size():
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding = i
		u.add_id(buffers[i])
		uniforms.append(u)
	var uset := rd.uniform_set_create(uniforms, p[0], 0)
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, p[1])
	rd.compute_list_bind_uniform_set(cl, uset, 0)
	if not push.is_empty():
		rd.compute_list_set_push_constant(cl, push, push.size())
	rd.compute_list_dispatch(cl, groups.x, groups.y, groups.z)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	rd.free_rid(uset)


func free_all() -> void:
	for b in _buffers:
		rd.free_rid(b)
	_buffers.clear()
	for p in _pipelines.values():
		rd.free_rid(p[1])
		rd.free_rid(p[0])
	_pipelines.clear()
	rd.free()
	rd = null


## Packs ints and floats into a push-constant block padded to 16 bytes.
static func push_constants(values: Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	var count := ceili(values.size() / 4.0) * 4
	bytes.resize(count * 4)
	for i in values.size():
		if values[i] is int:
			bytes.encode_s32(i * 4, values[i])
		else:
			bytes.encode_float(i * 4, values[i])
	return bytes


func _pipeline(path: String) -> Array:
	if _pipelines.has(path):
		return _pipelines[path]
	var file: RDShaderFile = load(path)
	var spirv := file.get_spirv()
	if not spirv.compile_error_compute.is_empty():
		push_error("%s: %s" % [path, spirv.compile_error_compute])
	var shader := rd.shader_create_from_spirv(spirv)
	var pipeline := rd.compute_pipeline_create(shader)
	_pipelines[path] = [shader, pipeline]
	return _pipelines[path]
