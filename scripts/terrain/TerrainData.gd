class_name TerrainData
extends RefCounted
## Result of the terrain pipeline plus world-space sampling helpers.
## The terrain is centered on the world origin.

var resolution: int
var cell_size: float
var heights: PackedFloat32Array
## RGBA8: R deposit, G flow, B erosion, A concavity (see terrain_finalize.glsl).
var control: Image
## R8: 1 where bedrock outcrops (terraced cliffs, ledges), 0 on soil.
var rock: Image
var min_height: float
var max_height: float
## Lakes carved into the terrain (see LakeShape).
var lakes: Array[LakeShape] = []
## Open areas kept free of scatter: x, z, clear radius (no trees/rocks), paved radius
## (no grass, no close-range ground displacement). See StartSite.
var clearings: Array[Vector4] = []
## The big forests, their glades and trails (ForestLayout); null until generated.
var forests: ForestLayout


func world_size() -> float:
	return (resolution - 1) * cell_size


## World XZ of heightmap texel (0, 0).
func origin() -> Vector2:
	var half := world_size() * 0.5
	return Vector2(-half, -half)


func is_inside(x: float, z: float, margin := 0.0) -> bool:
	var half := world_size() * 0.5 - margin
	return absf(x) <= half and absf(z) <= half


func height_at(x: float, z: float) -> float:
	var o := origin()
	var gx := clampf((x - o.x) / cell_size, 0.0, resolution - 1.001)
	var gz := clampf((z - o.y) / cell_size, 0.0, resolution - 1.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var i := iz * resolution + ix
	var h00 := heights[i]
	var h10 := heights[i + 1]
	var h01 := heights[i + resolution]
	var h11 := heights[i + resolution + 1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


func normal_at(x: float, z: float) -> Vector3:
	var e := cell_size
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func control_at(x: float, z: float) -> Color:
	var o := origin()
	var gx := clampi(roundi((x - o.x) / cell_size), 0, resolution - 1)
	var gz := clampi(roundi((z - o.y) / cell_size), 0, resolution - 1)
	return control.get_pixel(gx, gz)


func rock_at(x: float, z: float) -> float:
	var o := origin()
	var gx := clampi(roundi((x - o.x) / cell_size), 0, resolution - 1)
	var gz := clampi(roundi((z - o.y) / cell_size), 0, resolution - 1)
	return rock.get_pixel(gx, gz).r


## True inside a clearing, with its clear radius scaled by `scale`.
func in_clearing(x: float, z: float, scale := 1.0) -> bool:
	for c in clearings:
		if Vector2(x - c.x, z - c.y).length() < c.z * scale:
			return true
	return false


## Water surface height at (x, z), or -INF when not inside a lake.
func water_level_at(x: float, z: float) -> float:
	for lake in lakes:
		if lake.shore_fraction(Vector2(x, z)) < 1.3:
			return lake.level
	return -INF
