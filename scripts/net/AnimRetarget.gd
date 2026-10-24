class_name AnimRetarget
extends RefCounted
## Bakes Mixamo FBX clips (downloaded "without skin" for the same rig) onto the player model's
## skeleton. The GLB went through Blender, so its bones are oriented differently from the FBX
## ones (and it sits under a rotated, 0.01-scaled armature): local rotations can't be copied.
## Instead each bone's *world-space* rotation relative to its T-pose rest is transferred:
##   target_global = (source_global * source_global_rest^-1) * target_global_rest
## then turned back into a local rotation under the target parent. The target rest rotations
## are first aligned so each bone points like its source counterpart in rest (the GLB's arms
## droop ~9° in rest, Mixamo's are level). The hips' position is scaled by the hip-to-ankle
## ratio of the two rigs; source ground (y = 0) maps to `soles_y`. With `face_forward`, a clip
## whose body is turned on average (Mixamo's jump/fall/land face ~43° sideways) is turned back.

## Average body turn below which a clip is left as it is.
const MIN_YAW_FIX := deg_to_rad(10.0)

const FPS := 30.0


## source: the FBX PackedScene; target_skeleton: the model's Skeleton3D (not necessarily in the
## tree); target_root: the node the model's AnimationPlayer resolves track paths from.
static func bake(source: PackedScene, target_skeleton: Skeleton3D, target_root: Node, soles_y: float,
		loop: bool, face_forward: bool = false) -> Animation:
	var src_root := source.instantiate()
	var src_skel := src_root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var src_player := src_root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var src_anim := src_player.get_animation(src_player.get_animation_list()[0])
	var src_prefix := str(src_root.get_path_to(src_skel)) + ":"

	# Frame of the target skeleton in model space (the armature's rotation and scale).
	var arm := _transform_to(target_skeleton, target_root)
	var arm_q := arm.basis.orthonormalized().get_rotation_quaternion()

	var t_count := target_skeleton.get_bone_count()
	var t_rest_q: Array[Quaternion] = []     # global rest rotations, model space
	var t_rest_pos: Array[Vector3] = []
	var t_rest_local := _global_rests(target_skeleton)
	for b in t_count:
		var g: Transform3D = arm * t_rest_local[b]
		t_rest_q.append(g.basis.orthonormalized().get_rotation_quaternion())
		t_rest_pos.append(g.origin)
	var s_rest := _global_rests(src_skel)

	# Source bone per target bone, and the rotation track of every source bone.
	var map: Array[int] = []
	for b in t_count:
		map.append(src_skel.find_bone(target_skeleton.get_bone_name(b)))
	var s_track: Array[int] = []
	for sb in src_skel.get_bone_count():
		s_track.append(src_anim.find_track(NodePath(src_prefix + src_skel.get_bone_name(sb)), Animation.TYPE_ROTATION_3D))
	# Align target rest directions (bone -> first mapped child) with the source ones.
	for b in t_count:
		var sb := map[b]
		if sb < 0 or target_skeleton.get_bone_name(b) == "mixamorig_Hips":
			continue
		for c in target_skeleton.get_bone_children(b):
			var sc := map[c]
			if sc < 0:
				continue
			var dt := t_rest_pos[c] - t_rest_pos[b]
			var ds := s_rest[sc].origin - s_rest[sb].origin
			if dt.length_squared() > 1e-8 and ds.length_squared() > 1e-8:
				t_rest_q[b] = (Quaternion(dt.normalized(), ds.normalized()) * t_rest_q[b]).normalized()
			break
	var t_hips := target_skeleton.find_bone("mixamorig_Hips")
	var s_hips := src_skel.find_bone("mixamorig_Hips")
	var hips_pos_track := src_anim.find_track(NodePath(src_prefix + "mixamorig_Hips"), Animation.TYPE_POSITION_3D)
	var t_foot := target_skeleton.find_bone("mixamorig_LeftFoot")
	var s_foot := src_skel.find_bone("mixamorig_LeftFoot")
	var k := (t_rest_pos[t_hips].y - t_rest_pos[t_foot].y) / (s_rest[s_hips].origin.y - s_rest[s_foot].origin.y)

	var out := Animation.new()
	out.length = src_anim.length
	out.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var skel_path := str(target_root.get_path_to(target_skeleton)) + ":"
	var out_rot: Array[int] = []
	for b in t_count:
		var tr := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, NodePath(skel_path + target_skeleton.get_bone_name(b)))
		out_rot.append(tr)
	var out_pos := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(out_pos, NodePath(skel_path + "mixamorig_Hips"))
	var inv_arm := arm.affine_inverse()

	var frames := maxi(1, ceili(src_anim.length * FPS))
	var hips_y := PackedFloat32Array()
	var s_global_q: Array[Quaternion] = []
	s_global_q.resize(src_skel.get_bone_count())
	var t_global_q: Array[Quaternion] = []
	t_global_q.resize(t_count)
	var s_order := _order(src_skel)
	var t_order := _order(target_skeleton)
	# Average body turn of the clip (from the hips' side axis, which stays level when leaning).
	var s_hips_rest_q := s_rest[s_hips].basis.orthonormalized().get_rotation_quaternion()
	var turn := Vector2.ZERO
	for f in frames + 1:
		var q := src_anim.rotation_track_interpolate(s_track[s_hips], minf(f / FPS, src_anim.length)) if s_track[s_hips] >= 0 else s_hips_rest_q
		var side := (q * s_hips_rest_q.inverse()) * Vector3.RIGHT
		turn += Vector2(side.x, -side.z).normalized()
	var mean_yaw := turn.angle()
	var fix := Quaternion(Vector3.UP, -mean_yaw) if face_forward and absf(mean_yaw) > MIN_YAW_FIX else Quaternion.IDENTITY
	for f in frames + 1:
		var time := minf(f / FPS, src_anim.length)
		# Source global rotations for this frame.
		for sb in s_order:
			var tr := s_track[sb]
			var local_q := src_anim.rotation_track_interpolate(tr, time) if tr >= 0 else src_skel.get_bone_rest(sb).basis.get_rotation_quaternion()
			var p := src_skel.get_bone_parent(sb)
			s_global_q[sb] = (s_global_q[p] * local_q) if p >= 0 else local_q
		# Target rotations, parents first.
		for b in t_order:
			var sb := map[b]
			var g: Quaternion
			if sb >= 0:
				var s_rest_q := s_rest[sb].basis.orthonormalized().get_rotation_quaternion()
				g = fix * (s_global_q[sb] * s_rest_q.inverse()) * t_rest_q[b]
			else:
				var p0 := target_skeleton.get_bone_parent(b)
				g = (t_global_q[p0] if p0 >= 0 else arm_q) * _rest_rot(target_skeleton, b)
			t_global_q[b] = g.normalized()
			var p := target_skeleton.get_bone_parent(b)
			var parent_q := t_global_q[p] if p >= 0 else arm_q
			out.rotation_track_insert_key(out_rot[b], time, (parent_q.inverse() * t_global_q[b]).normalized())
		# Hips position.
		var hp: Vector3 = src_anim.position_track_interpolate(hips_pos_track, time) if hips_pos_track >= 0 else s_rest[s_hips].origin
		hp = fix * hp
		var model_pos := Vector3(hp.x * k, hp.y * k + soles_y, hp.z * k)
		hips_y.append(hp.y)
		out.position_track_insert_key(out_pos, time, inv_arm * model_pos)
	src_root.free()
	# Source hips height per frame (metres), e.g. to find take-off / touchdown.
	out.set_meta("hips_y", hips_y)
	return out


static func _rest_rot(skel: Skeleton3D, b: int) -> Quaternion:
	return skel.get_bone_rest(b).basis.orthonormalized().get_rotation_quaternion()


## Global (skeleton space) rest transforms.
static func _global_rests(skel: Skeleton3D) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(skel.get_bone_count())
	for b in _order(skel):
		var p := skel.get_bone_parent(b)
		out[b] = (out[p] * skel.get_bone_rest(b)) if p >= 0 else skel.get_bone_rest(b)
	return out


## Bone indices ordered parents before children.
static func _order(skel: Skeleton3D) -> Array[int]:
	var out: Array[int] = []
	var stack: Array[int] = []
	for b in skel.get_bone_count():
		if skel.get_bone_parent(b) < 0:
			stack.append(b)
	while not stack.is_empty():
		var b: int = stack.pop_back()
		out.append(b)
		for c in skel.get_bone_children(b):
			stack.append(c)
	return out


## Transform of `node` relative to `root` (an ancestor), without needing the scene tree.
static func _transform_to(node: Node3D, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != root and n != null:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
