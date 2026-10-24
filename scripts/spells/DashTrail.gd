class_name DashTrail
extends Node3D
## Follows a dashing caster for the dash's duration.
##   First person: soft motes spawn in a ring a few metres ahead of the camera and hang in the
##   air, so the player rushes through them (no streak lines – they felt unpleasant in view).
##   Third person (remote casters): a comet tail of streaks and motes around the body plus
##   glowing afterimages of the wizard left along the path.

const AFTERIMAGE_INTERVAL := 0.045

var _target: Node3D
var _dir := Vector3.FORWARD
var _time_left := 0.0
var _lead := 0.0
var _height := 0.0
var _color := Color.WHITE
var _ghost_source: Node3D
var _ghost_timer := 0.0
var _emitters: Array[GPUParticles3D] = []


func setup(target: Node3D, dir: Vector3, duration: float, color: Color, accent: Color,
		feet_offset: float, first_person: bool, ghost_source: Node3D) -> void:
	top_level = true
	_target = target
	_dir = dir.normalized()
	_color = color
	_time_left = duration + 0.08
	_ghost_source = ghost_source
	if first_person:
		_lead = 5.5
		_height = 1.5 - feet_offset
		var motes := SpellFx.particles(self, 60, 0.5, false, false, Vector2(0.05, 0.05), color, accent)
		var mm := motes.process_material as ParticleProcessMaterial
		mm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		mm.emission_ring_axis = Vector3(0, 0, 1)
		mm.emission_ring_radius = 2.2
		mm.emission_ring_inner_radius = 0.7
		mm.emission_ring_height = 5.0
		mm.direction = Vector3(0, 0, 1)
		mm.spread = 30.0
		mm.initial_velocity_min = 0.5
		mm.initial_velocity_max = 2.0
		mm.scale_min = 0.5
		mm.scale_max = 1.3
		_emitters.append(motes)
	else:
		_lead = 0.0
		_height = 1.0 - feet_offset
		var streaks := SpellFx.particles(self, 70, 0.4, false, true, Vector2(0.03, 0.8), color, accent)
		var pm := streaks.process_material as ParticleProcessMaterial
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.35, 0.8, 0.3)
		pm.direction = Vector3(0, 0, 1)
		pm.spread = 6.0
		pm.initial_velocity_min = 3.0
		pm.initial_velocity_max = 7.0
		pm.damping_min = 4.0
		pm.damping_max = 8.0
		_emitters.append(streaks)
		var motes := SpellFx.particles(self, 90, 0.9, false, false, Vector2(0.08, 0.08), color, accent)
		var mm := motes.process_material as ParticleProcessMaterial
		mm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		mm.emission_box_extents = Vector3(0.3, 0.9, 0.3)
		mm.direction = Vector3(0, 1, 1)
		mm.spread = 60.0
		mm.initial_velocity_min = 0.3
		mm.initial_velocity_max = 1.5
		mm.damping_min = 1.0
		mm.damping_max = 2.0
		mm.gravity = Vector3(0, 0.6, 0)
		mm.scale_min = 0.4
		mm.scale_max = 1.2
		_emitters.append(motes)
	_follow()


func _process(delta: float) -> void:
	if _time_left <= 0.0:
		return
	_time_left -= delta
	if not is_instance_valid(_target):
		_time_left = 0.0
	else:
		_follow()
		if _ghost_source and is_instance_valid(_ghost_source):
			_ghost_timer -= delta
			if _ghost_timer <= 0.0:
				_ghost_timer = AFTERIMAGE_INTERVAL
				DashFx.afterimage(get_parent(), _ghost_source, _color, 0.9)
	if _time_left <= 0.0:
		var longest := 0.0
		for e in _emitters:
			e.emitting = false
			longest = maxf(longest, e.lifetime)
		get_tree().create_timer(longest + 0.1).timeout.connect(queue_free)


func _follow() -> void:
	global_position = _target.global_position + _dir * _lead + Vector3.UP * _height
	var up := Vector3.UP if absf(_dir.y) < 0.95 else Vector3.RIGHT
	global_basis = Basis.looking_at(_dir, up)
