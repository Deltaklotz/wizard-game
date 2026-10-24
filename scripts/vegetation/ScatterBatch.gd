class_name ScatterBatch
extends RefCounted
## Collects instance transforms and turns them into MultiMeshInstance3D nodes, one per
## (mesh, spatial cell, visibility range) so distant cells can be culled/LODed.

var cell_size: float
var _groups: Dictionary = {}


func _init(cell := 96.0) -> void:
	cell_size = cell


func add(mesh: Mesh, xform: Transform3D, vis_begin: float, vis_end: float, shadows := true) -> void:
	var cx := floori(xform.origin.x / cell_size)
	var cz := floori(xform.origin.z / cell_size)
	var key := "%d|%d|%d|%d|%d" % [mesh.get_instance_id(), cx, cz, int(vis_begin), int(vis_end)]
	var g: Dictionary = _groups.get(key, {})
	if g.is_empty():
		g = {"mesh": mesh, "xforms": [], "begin": vis_begin, "end": vis_end, "shadows": shadows,
			"center": Vector3((cx + 0.5) * cell_size, 0.0, (cz + 0.5) * cell_size), "ysum": 0.0}
		_groups[key] = g
	g.xforms.append(xform)
	g.ysum += xform.origin.y


func count() -> int:
	var n := 0
	for g in _groups.values():
		n += g.xforms.size()
	return n


func build(parent: Node3D) -> void:
	for g in _groups.values():
		var xforms: Array = g.xforms
		var center: Vector3 = g.center
		center.y = g.ysum / xforms.size()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = g.mesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			var t: Transform3D = xforms[i]
			t.origin -= center
			mm.set_instance_transform(i, t)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = center
		mmi.visibility_range_begin = g.begin
		mmi.visibility_range_end = g.end
		if not g.shadows:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Base ranges for GraphicsQuality (view distance scales them, shadow level gates shadows).
		mmi.set_meta("vis", Vector2(g.begin, g.end))
		mmi.set_meta("shadows", g.shadows)
		parent.add_child(mmi)
	_groups.clear()
	GraphicsQuality.apply_vegetation(parent)


## Basis with Y along `up`, rotated by `yaw` around it, uniformly scaled.
static func aligned_basis(up: Vector3, yaw: float, scale: float) -> Basis:
	var fwd := Vector3(cos(yaw), 0.0, sin(yaw))
	var x := (fwd - up * fwd.dot(up)).normalized()
	var z := x.cross(up)
	return Basis(x, up, z).scaled_local(Vector3.ONE * scale)
