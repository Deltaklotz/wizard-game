class_name PlayerModel
extends Node3D
## The players' character, from assets/player/player.glb (Mixamo rig; meshes face, hat,
## jacket, body; clips "idle" and "run", both in place) plus Mixamo clips in
## assets/player/animations/<name>.fbx retargeted onto it at startup (AnimRetarget).
## Used for other players' avatars and the connect-screen preview. Feet at the origin,
## facing -Z, about HEIGHT metres tall; the body is tinted in the player's colour.
##
## Animation: idle / walk / run blended by ground speed; jump -> fall -> land from the
## on-floor flag and vertical speed; swim in the lake; dash while dashing; death (played once,
## holding the last pose) while dead; cast as an upper-body one-shot.
## Drive it with update_motion() every frame and play_cast() on a cast.

const SCENE := preload("res://assets/player/player.glb")
const ANIM_DIR := "res://assets/player/animations/"
## Extra clips: file name -> loops.
const EXTRA_CLIPS := {"walk": true, "jump": false, "fall": true, "land": false, "cast": false, "swim": true,
	"dash": true, "death": false}
## Playback rate of the dash clip (a little slow as downloaded), and the shortest time it shows.
const DASH_RATE := 1.5
const DASH_MIN_TIME := 0.3
## Clips whose average sideways body turn is removed (Mixamo's air clips face ~43° off).
const FACE_FORWARD := ["jump", "fall", "land"]
const HEIGHT := 2.0
## Soles to hat tip in the file's units, and the soles' height while animated (the clips
## lift the rig ~5 units above its T-pose, which is centred on the origin).
const SOURCE_HEIGHT := 10.26
const SOURCE_SOLES := -0.17
## Ground speeds (m/s) at which each clip is at full weight; run plays faster beyond RUN_SPEED.
const WALK_SPEED := 1.6
const RUN_SPEED := 5.0
## Airborne for longer than this before touching down -> landing clip (if not running on).
const LAND_MIN_AIR := 0.45
const CAST_RATE := 1.5
const UPPER_BODY := ["Spine", "Spine1", "Spine2", "Neck", "Head", "HeadTop_End",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand"]

## Retargeted clips, shared by all instances: name -> Animation. Timeline windows (start, end)
## for the jump (skipping the crouch before take-off) and the landing (from touchdown).
static var _clips := {}
static var _windows := {}

var _scene: Node3D
var _anim: AnimationPlayer
var _tree: AnimationTree
var _speed := 0.0
var _state := "ground"
var _state_time := 0.0
var _air_time := 0.0


func _init(color: Color = Color.WHITE) -> void:
	name = "PlayerModel"
	_scene = SCENE.instantiate()
	var s := HEIGHT / SOURCE_HEIGHT
	_scene.scale = Vector3.ONE * s
	_scene.position.y = -SOURCE_SOLES * s
	_scene.rotation.y = PI  # the file faces +Z
	add_child(_scene)
	_setup_materials(color)
	_setup_animation()


## speed: horizontal speed (m/s), vertical_speed: m/s, on_floor / swimming / dashing: movement state.
func update_motion(delta: float, speed: float, vertical_speed: float, on_floor: bool, swimming: bool,
		dashing: bool = false, dead: bool = false) -> void:
	_speed = lerpf(_speed, speed, 1.0 - exp(-10.0 * delta))
	_state_time += delta
	var want := _state
	if dead and _has("death"):
		want = "death"
		if _state != "death" and _tree and _has("cast"):
			_tree.set("parameters/cast/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	elif (dashing or (_state == "dash" and _state_time < DASH_MIN_TIME)) and _has("dash"):
		want = "dash"
		if _state != "dash" and _tree and _has("cast"):
			# The dash itself is the cast: no arm gesture on top.
			_tree.set("parameters/cast/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	elif swimming:
		want = "swim"
	elif not on_floor:
		_air_time += delta
		match _state:
			"ground", "land", "swim":
				want = "jump" if vertical_speed > 1.0 and _has("jump") else "fall"
				_air_time = 0.0
			"jump":
				if _state_time > _window_length("jump") * 0.9 or vertical_speed < -1.0:
					want = "fall"
	else:
		match _state:
			"jump", "fall":
				want = "land" if _air_time > LAND_MIN_AIR and _speed < 3.0 and _has("land") else "ground"
			"land":
				if _state_time > _window_length("land") * 0.85 or _speed > 3.0:
					want = "ground"
			"swim", "dash", "death":
				want = "ground"
	if _state == "dash" and want == "dash" and not dashing and _state_time >= DASH_MIN_TIME:
		want = "ground"
	if want == "ground" and _state == "dash" and not on_floor:
		want = "fall"
		_air_time = 0.0
	if not _has(want) and want != "ground":
		want = "ground"
	if want != _state:
		_state = want
		_state_time = 0.0
		if _tree:
			_tree.set("parameters/state/transition_request", want)
	if _tree:
		_tree.set("parameters/ground/blend_position", minf(_speed, RUN_SPEED))
		_tree.set("parameters/ground_rate/scale", clampf(_speed / RUN_SPEED, 1.0, 1.7))
		_tree.set("parameters/swim_rate/scale", clampf(0.45 + _speed / 3.0, 0.45, 1.3))


## Upper-body spell gesture (the legs keep doing what they do).
func play_cast() -> void:
	if _tree and _has("cast"):
		_tree.set("parameters/cast/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## A frozen copy of the current pose with `material` on every mesh (e.g. dash afterimages).
func make_ghost(material: Material) -> Node3D:
	var copy := _scene.duplicate() as Node3D
	for mixer in copy.find_children("*", "AnimationMixer", true, false):
		mixer.get_parent().remove_child(mixer)
		mixer.free()
	for mi in copy.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = material
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var holder := Node3D.new()
	holder.add_child(copy)
	holder.transform = global_transform
	return holder


func _setup_materials(color: Color) -> void:
	for mi: MeshInstance3D in _scene.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if src == null:
				continue
			var mat := src.duplicate() as BaseMaterial3D
			match src.resource_name:
				"body":
					mat.albedo_color = color
				"jacket":
					# Exported as alpha-blended but fully opaque: blending breaks depth sorting.
					mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				"face":
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			mi.set_surface_override_material(i, mat)


func _has(clip: String) -> bool:
	return clip == "ground" or _anim.has_animation(clip)


func _window_length(clip: String) -> float:
	var w: Vector2 = _windows.get(clip, Vector2(0.0, _anim.get_animation(clip).length))
	return w.y - w.x


func _setup_animation() -> void:
	var players := _scene.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	_anim = players[0]
	for clip in ["idle", "run"]:
		if _anim.has_animation(clip):
			_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_add_extra_clips()

	var bt := AnimationNodeBlendTree.new()
	# Ground locomotion.
	var ground := AnimationNodeBlendSpace1D.new()
	ground.min_space = 0.0
	ground.max_space = RUN_SPEED
	ground.add_blend_point(_clip_node("idle"), 0.0, -1, "idle")
	if _has("walk"):
		ground.add_blend_point(_clip_node("walk"), WALK_SPEED, -1, "walk")
	ground.add_blend_point(_clip_node("run"), RUN_SPEED, -1, "run")
	bt.add_node("ground", ground)
	bt.add_node("ground_rate", AnimationNodeTimeScale.new())
	bt.connect_node("ground_rate", 0, "ground")
	# Movement states.
	var state := AnimationNodeTransition.new()
	state.xfade_time = 0.18
	var inputs := ["ground"]
	for clip in ["jump", "fall", "land", "swim", "dash", "death"]:
		if _has(clip):
			inputs.append(clip)
	for i in inputs.size():
		state.add_input(inputs[i])
	bt.add_node("state", state)
	bt.connect_node("state", 0, "ground_rate")
	for i in range(1, inputs.size()):
		var clip: String = inputs[i]
		var node := _clip_node(clip)
		if clip == "swim" or clip == "dash":
			bt.add_node(clip + "_clip", node)
			bt.add_node(clip + "_rate", AnimationNodeTimeScale.new())
			bt.connect_node(clip + "_rate", 0, clip + "_clip")
			bt.connect_node("state", i, clip + "_rate")
		else:
			bt.add_node(clip + "_clip", node)
			bt.connect_node("state", i, clip + "_clip")
	# Casting on top, upper body only.
	var out_node := "state"
	if _has("cast"):
		var cast := AnimationNodeOneShot.new()
		cast.fadein_time = 0.12
		cast.fadeout_time = 0.3
		cast.filter_enabled = true
		var skel := _scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var prefix := str(_scene.get_path_to(skel)) + ":mixamorig_"
		for bone in UPPER_BODY:
			cast.set_filter_path(NodePath(prefix + bone), true)
		bt.add_node("cast", cast)
		bt.add_node("cast_clip", _clip_node("cast"))
		var rate := AnimationNodeTimeScale.new()
		bt.add_node("cast_rate", rate)
		bt.connect_node("cast_rate", 0, "cast_clip")
		bt.connect_node("cast", 0, "state")
		bt.connect_node("cast", 1, "cast_rate")
		out_node = "cast"
	bt.connect_node("output", 0, out_node)

	_tree = AnimationTree.new()
	_tree.tree_root = bt
	_anim.add_sibling(_tree)
	_tree.anim_player = _tree.get_path_to(_anim)
	_tree.active = true
	# The transition plays nothing until a state is requested.
	_tree.set("parameters/state/transition_request", "ground")
	_tree.set("parameters/ground/blend_position", 0.0)
	_tree.set("parameters/ground_rate/scale", 1.0)
	if _has("swim"):
		_tree.set("parameters/swim_rate/scale", 1.0)
	if _has("cast"):
		_tree.set("parameters/cast_rate/scale", CAST_RATE)
	if _has("dash"):
		_tree.set("parameters/dash_rate/scale", DASH_RATE)


func _clip_node(clip: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	if _windows.has(clip):
		var w: Vector2 = _windows[clip]
		node.use_custom_timeline = true
		node.start_offset = w.x
		node.timeline_length = w.y - w.x
		node.stretch_time_scale = false
		node.loop_mode = Animation.LOOP_NONE
	return node


## Retargets the Mixamo clips once (cached for every instance) and adds them to this model's
## AnimationPlayer. Missing files are skipped.
func _add_extra_clips() -> void:
	var lib := _anim.get_animation_library("")
	if _clips.is_empty():
		var skel := _scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var t0 := Time.get_ticks_msec()
		for clip: String in EXTRA_CLIPS:
			var path := ANIM_DIR + clip + ".fbx"
			if not ResourceLoader.exists(path):
				continue
			var anim := AnimRetarget.bake(load(path), skel, _scene, SOURCE_SOLES, EXTRA_CLIPS[clip], clip in FACE_FORWARD)
			_clips[clip] = anim
			var hips: PackedFloat32Array = anim.get_meta("hips_y")
			match clip:
				"jump":
					# Start at take-off: after the crouch, once the hips rise past their start height.
					var lowest := 0
					for f in hips.size():
						if hips[f] < hips[lowest]:
							lowest = f
					var take_off := lowest
					while take_off < hips.size() - 1 and hips[take_off] < hips[0]:
						take_off += 1
					_windows[clip] = Vector2(take_off / AnimRetarget.FPS, anim.length)
				"land":
					# Start at touchdown: the hips first reach the standing height the clip ends at.
					var end_y := hips[hips.size() - 1]
					var touch := 0
					while touch < hips.size() - 1 and hips[touch] > end_y + 0.05 * (hips[0] - end_y):
						touch += 1
					_windows[clip] = Vector2(maxf(0.0, (touch - 2) / AnimRetarget.FPS), anim.length)
		print("PlayerModel: retargeted %d clips in %d ms" % [_clips.size(), Time.get_ticks_msec() - t0])
	for clip in _clips:
		if not lib.has_animation(clip):
			lib.add_animation(clip, _clips[clip])
