class_name WorldBlob
extends RefCounted
## Serialises the generated terrain (before lake carving etc.) so every player builds on
## the exact same heightmap. GPU erosion races make regeneration differ slightly between
## runs and GPUs, so multiplayer worlds are generated once and shared through the server.
##
## Layout: "WZW1" | u32 version | u32 seed | u32 resolution | f32 cell size |
##         u32 raw size | zstd(heights f32 + control RGBA8 + rock R8)

const MAGIC := "WZW1"
const HEADER := 24


static func encode(data: TerrainData, seed: int, version: int) -> PackedByteArray:
	var raw := data.heights.to_byte_array()
	raw.append_array(data.control.get_data())
	raw.append_array(data.rock.get_data())
	var out := PackedByteArray()
	out.resize(HEADER)
	for i in 4:
		out[i] = MAGIC.unicode_at(i)
	out.encode_u32(4, version)
	out.encode_u32(8, seed)
	out.encode_u32(12, data.resolution)
	out.encode_float(16, data.cell_size)
	out.encode_u32(20, raw.size())
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


## Returns null if the blob is damaged or doesn't match the expected seed.
static func decode(blob: PackedByteArray, seed: int) -> TerrainData:
	if blob.size() < HEADER or blob.slice(0, 4).get_string_from_ascii() != MAGIC or blob.decode_u32(8) != seed:
		return null
	var res := blob.decode_u32(12)
	var cells := res * res
	var raw := blob.slice(HEADER).decompress(blob.decode_u32(20), FileAccess.COMPRESSION_ZSTD)
	if raw.size() != cells * 9:
		return null
	var data := TerrainData.new()
	data.resolution = res
	data.cell_size = blob.decode_float(16)
	data.heights = raw.slice(0, cells * 4).to_float32_array()
	data.control = Image.create_from_data(res, res, false, Image.FORMAT_RGBA8, raw.slice(cells * 4, cells * 8))
	data.rock = Image.create_from_data(res, res, false, Image.FORMAT_R8, raw.slice(cells * 8))
	data.min_height = INF
	data.max_height = -INF
	for h in data.heights:
		data.min_height = minf(data.min_height, h)
		data.max_height = maxf(data.max_height, h)
	return data
