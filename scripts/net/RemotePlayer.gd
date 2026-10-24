class_name RemotePlayer
extends Node3D
## Another player's wizard. States arrive ~20 times a second; the avatar is drawn
## INTERP_DELAY behind real time, interpolating between the two surrounding snapshots,
## so movement stays smooth despite network jitter.

const INTERP_DELAY := 0.1
## Player origin (capsule centre) to feet.
const FOOT_OFFSET := 0.9
## Eye height above the feet (player origin + camera offset).
const EYE_HEIGHT := 1.5
## Warning crosshair while this player aims the sniper beam: size, distance ahead of the eyes,
## and the time it takes to charge (the spell's minimum aim time).
const CROSSHAIR_SIZE := 2.2
const CROSSHAIR_DISTANCE := 1.8
const AIM_CHARGE_TIME := 2.0

var peer_id := -1
var player_name := ""
var player_color := Color.WHITE

var _snapshots: Array = []  # [time, position, yaw, pitch, flags]
var _model: PlayerModel
var _label: Label3D
var _speed := 0.0
var _vspeed := 0.0
var _flash := 0.0
var _flash_mesh: MeshInstance3D
var _flash_light: OmniLight3D
var _crosshair: MeshInstance3D
var _aim_time := 0.0
var _aim_fade := 0.0
var _crosshair_spin := 0.0
var _dead := false
var _look_yaw := 0.0
var _look_pitch := 0.0


func setup(info: Dictionary) -> void:
	peer_id = info.id
	player_name = info.name
	player_color = info.color
	name = "Remote_%d" % peer_id
	add_to_group("remote_player")
	_model = PlayerModel.new(player_color)
	add_child(_model)
	_label = Label3D.new()
	_label.text = player_name
	_label.font_size = 40
	_label.pixel_size = 0.006
	_label.outline_size = 10
	_label.modulate = player_color.lightened(0.45)
	_label.outline_modulate = Color(0.05, 0.03, 0.06, 0.9)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 2.45
	_label.visibility_range_end = 150.0
	add_child(_label)
	visible = false
	var s: Array = info.get("s", [])
	if s.size() >= 5:
		push_state(s)


var _fire: GPUParticles3D
var _fire_light: OmniLight3D


## Flames licking up the body while this player burns.
func _update_fire(on: bool) -> void:
	if _fire == null:
		if not on:
			return
		_fire = FireFx.flames(self, 40, 0.7, 0.6, 2.0)
		var pm := _fire.process_material as ParticleProcessMaterial
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.28, 0.75, 0.28)
		pm.direction = Vector3.UP
		pm.spread = 15.0
		pm.initial_velocity_min = 0.3
		pm.initial_velocity_max = 0.9
		_fire.position.y = 0.95
		_fire_light = FireFx.fire_light(self, 1.5, 4.0)
		_fire_light.position.y = 1.2
	_fire.emitting = on
	_fire_light.visible = on


## Struck down and waiting to respawn (can not be hit).
func is_dead() -> bool:
	return _dead


## The character model (e.g. for spell afterimages).
func get_body() -> PlayerModel:
	return _model


## Where this player looks (interpolated like the body).
func get_look_direction() -> Vector3:
	return Basis(Vector3.UP, _look_yaw) * Basis(Vector3.RIGHT, _look_pitch) * Vector3.FORWARD


## Roughly where the casting hand is (spells that start from the caster, e.g. the chain).
func get_hand_position() -> Vector3:
	return global_transform * Vector3(0.22, 1.3, -0.45)


func push_state(s: Array) -> void:
	var now := Time.get_ticks_msec() * 0.001
	var flags := int(s[5]) if s.size() > 5 else Net.FLAG_ON_FLOOR
	_snapshots.append([now, Vector3(s[0], s[1], s[2]), float(s[3]), float(s[4]), flags])
	while _snapshots.size() > 30:
		_snapshots.pop_front()
	if not visible:
		visible = true
		global_position = _snapshots[-1][1] - Vector3.UP * FOOT_OFFSET


func play_cast() -> void:
	if _flash_mesh == null:
		var sphere := SphereMesh.new()
		sphere.radius = 0.25
		sphere.height = 0.5
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/magic_glow.gdshader")
		mat.set_shader_parameter("glow_color", player_color.lightened(0.3))
		_flash_mesh = MeshInstance3D.new()
		_flash_mesh.mesh = sphere
		_flash_mesh.material_override = mat
		_flash_mesh.position = Vector3(0, 1.1, -0.45)
		_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_model.add_child(_flash_mesh)
		_flash_light = OmniLight3D.new()
		_flash_light.light_color = player_color.lightened(0.4)
		_flash_light.omni_range = 6.0
		_flash_light.position = _flash_mesh.position
		_model.add_child(_flash_light)
	_flash = 1.0
	_model.play_cast()


func _process(delta: float) -> void:
	if _snapshots.is_empty():
		return
	var t := Time.get_ticks_msec() * 0.001 - INTERP_DELAY
	var pos: Vector3
	var yaw: float
	var pitch: float
	# Find the snapshots around t; hold the latest if we ran out.
	var i := _snapshots.size() - 1
	while i > 0 and _snapshots[i - 1][0] > t:
		i -= 1
	if i == 0 or _snapshots[i][0] <= t:
		var last: Array = _snapshots[i]
		pos = last[1]
		yaw = last[2]
		pitch = last[3]
	else:
		var a: Array = _snapshots[i - 1]
		var b: Array = _snapshots[i]
		var f := clampf((t - a[0]) / maxf(b[0] - a[0], 0.001), 0.0, 1.0)
		pos = (a[1] as Vector3).lerp(b[1], f)
		yaw = lerp_angle(a[2], b[2], f)
		pitch = lerpf(a[3], b[3], f)
	var prev := global_position
	global_position = pos - Vector3.UP * FOOT_OFFSET
	var moved := Vector2(global_position.x - prev.x, global_position.z - prev.z).length()
	_speed = lerpf(_speed, moved / maxf(delta, 0.001), 1.0 - exp(-10.0 * delta))
	rotation.y = yaw

	# Movement state of the snapshot being left; vertical speed from that snapshot to the next
	# (known ahead of the interpolated position, so a jump is recognised at take-off).
	var from := maxi(i - 1, 0)
	var flags: int = _snapshots[from][4]
	if from + 1 < _snapshots.size():
		var s0: Array = _snapshots[from]
		var s1: Array = _snapshots[from + 1]
		_vspeed = ((s1[1] as Vector3).y - (s0[1] as Vector3).y) / maxf(s1[0] - s0[0], 0.001)
	_dead = (flags & Net.FLAG_DEAD) != 0
	_update_fire((flags & Net.FLAG_BURNING) != 0 and not _dead)
	_model.update_motion(delta, _speed, _vspeed, (flags & Net.FLAG_ON_FLOOR) != 0, (flags & Net.FLAG_SWIMMING) != 0,
		(flags & Net.FLAG_DASHING) != 0, _dead)
	_look_yaw = yaw
	_look_pitch = pitch
	# Name tags don't show through smoke clouds.
	var cam := get_viewport().get_camera_3d()
	if cam:
		_label.visible = not SmokeCloud.blocks(get_tree(), cam.global_position, _label.global_position)
	_update_crosshair(delta, (flags & Net.FLAG_AIMING) != 0 and not _dead, yaw, pitch)

	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.2)
		_flash_mesh.visible = _flash > 0.0
		_flash_mesh.scale = Vector3.ONE * (0.4 + (1.0 - _flash) * 1.6)
		_flash_light.light_energy = _flash * 3.0


## Big spinning red reticle in front of the eyes while this player aims, so everyone can see
## the shot coming and where it points; its arc fills as the aim charges.
func _update_crosshair(delta: float, aiming: bool, yaw: float, pitch: float) -> void:
	_aim_time = _aim_time + delta if aiming else 0.0
	_aim_fade = move_toward(_aim_fade, 1.0 if aiming else 0.0, delta * (6.0 if aiming else 3.0))
	if _aim_fade <= 0.0:
		if _crosshair:
			_crosshair.visible = false
		return
	if _crosshair == null:
		_crosshair = SniperFx.make_crosshair(CROSSHAIR_SIZE)
		add_child(_crosshair)
	_crosshair.visible = true
	var charge := clampf(_aim_time / AIM_CHARGE_TIME, 0.0, 1.0)
	# Spins fast while charging, slows to a menacing crawl when ready.
	_crosshair_spin += delta * lerpf(4.0, 0.8, charge)
	var dir := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD
	var eye := global_position + Vector3.UP * EYE_HEIGHT
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.BACK
	var grow := 0.6 + 0.4 * _aim_fade
	_crosshair.global_transform = Transform3D(Basis.looking_at(dir, up).scaled(Vector3.ONE * grow),
		eye + dir * CROSSHAIR_DISTANCE)
	_crosshair.set_instance_shader_parameter("charge", charge)
	_crosshair.set_instance_shader_parameter("spin", _crosshair_spin)
	_crosshair.set_instance_shader_parameter("fade", _aim_fade)
