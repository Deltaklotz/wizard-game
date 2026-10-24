class_name MinigunRig
extends Node3D
## The local player's arcane gatling (MinigunSpell): six crystal barrels on a spinning wheel
## between two energy collars, a glowing core behind and a turning rune circle at the muzzle,
## floating in front of the book while the minigun page is open. Owns the firing state:
## spin-up, fire cadence, heat (wind-down after the trigger is released) and overheating
## (no firing, steam and sparks while it vents).
##
## Frame: follows the camera, -Z = forward; the muzzle is at -Z.

const BARREL_SHADER := preload("res://shaders/vfx/minigun_barrel.gdshader")
## Seconds to spin up fully / to spin down from full.
const SPIN_UP := 0.45
const SPIN_DOWN := 1.4
## Spin needed before the first shot.
const FIRE_SPIN := 0.35
## Heat starts winding down this long after the last shot.
const COOL_DELAY := 0.3
## Wheel speed at full spin (rad/s).
const WHEEL_SPEED := 38.0
const BARRELS := 6
const RADIUS := 0.021
const LENGTH := 0.13
## Rig position relative to the camera (right, up, back): bottom centre of the view, clear of
## the book on the right.
const OFFSET := Vector3(0.0, -0.165, -0.5)
const SCALE := 1.1
## The barrels point at this distance along the view (so they look aimed at the crosshair).
const AIM_DISTANCE := 25.0
## Seconds after a failed shot (no mana) before trying again.
const RETRY := 0.35

var spell: MinigunSpell
var player: Node3D
## Set by MinigunSpell.hold every frame the trigger is held; consumed each frame.
var trigger := false
var heat := 0.0
## Seconds left of an overheat (0 = none).
var overheat := 0.0
var spin := 0.0

var _angle := 0.0
var _shot_timer := 0.0
var _since_shot := 99.0
var _flash := 0.0
var _show := 0.0
var _wheel: Node3D
var _parts: Array[MeshInstance3D] = []
var _ring: MeshInstance3D
var _ring_mat: ShaderMaterial
var _flare: MeshInstance3D
var _steam: GPUParticles3D
var _sparks: GPUParticles3D


func setup(minigun: MinigunSpell, owner_player: Node3D) -> void:
	spell = minigun
	player = owner_player


## 0..1 of the heat bar (while overheated: the remaining vent time).
func get_heat_fraction() -> float:
	return clampf(heat / spell.max_heat, 0.0, 1.0)


func is_overheated() -> bool:
	return overheat > 0.0


## 0..1: how far the rig has materialised (minigun page open).
func get_presence() -> float:
	return _show


func can_fire() -> bool:
	return overheat <= 0.0


func muzzle_position() -> Vector3:
	return global_transform * Vector3(0, 0, -LENGTH * 0.6)


func _ready() -> void:
	top_level = true
	_wheel = Node3D.new()
	add_child(_wheel)
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.0042
	barrel.bottom_radius = 0.0058
	barrel.height = LENGTH
	barrel.radial_segments = 10
	barrel.rings = 1
	for i in BARRELS:
		var a := TAU * i / BARRELS
		var b := _part(barrel, _wheel, 1.0)
		b.position = Vector3(cos(a) * RADIUS, sin(a) * RADIUS, -LENGTH * 0.05)
		b.rotation.x = -PI * 0.5
	var collar := TorusMesh.new()
	collar.inner_radius = RADIUS * 0.75
	collar.outer_radius = RADIUS * 1.45
	collar.rings = 24
	collar.ring_segments = 8
	for z in [-LENGTH * 0.42, LENGTH * 0.25]:
		var c := _part(collar, _wheel, 0.6)
		c.position.z = z
		c.rotation.x = PI * 0.5
	var core := SphereMesh.new()
	core.radius = RADIUS * 0.9
	core.height = RADIUS * 1.8
	var orb := _part(core, self, 2.0)
	orb.position.z = LENGTH * 0.42
	_ring = SpellFx.ring(self, true, 0.13, spell.accent, spell.color)
	_ring.rotation.x = PI * 0.5
	_ring.position.z = -LENGTH * 0.62
	_ring.set_instance_shader_parameter("progress", 0.22)
	_ring_mat = (_ring.mesh as PlaneMesh).material as ShaderMaterial
	# Muzzle flare: a bright mote that pops with every shot.
	_flare = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var fm := ShaderMaterial.new()
	fm.shader = SpellFx.PARTICLE_SHADER
	q.material = fm
	_flare.mesh = q
	_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flare.position.z = -LENGTH * 0.66
	add_child(_flare)
	_steam = SpellFx.particles(self, 40, 0.9, false, false, Vector2(0.03, 0.03), spell.hot_color,
		Color(0.9, 0.85, 1.0))
	_steam.emitting = false
	var sm := _steam.process_material as ParticleProcessMaterial
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(RADIUS, RADIUS, LENGTH * 0.5)
	sm.direction = Vector3.UP
	sm.spread = 25.0
	sm.initial_velocity_min = 0.05
	sm.initial_velocity_max = 0.2
	_sparks = SpellFx.particles(self, 30, 0.35, false, true, Vector2(0.004, 0.03), spell.hot_color, spell.accent)
	_sparks.emitting = false
	var pm := _sparks.process_material as ParticleProcessMaterial
	pm.direction = Vector3(0, 0.4, -1)
	pm.spread = 50.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0, -1.5, 0)
	_sparks.position.z = -LENGTH * 0.6
	visible = false


func _part(mesh: Mesh, parent: Node3D, glow: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = BARREL_SHADER
	mat.set_shader_parameter("color", spell.color)
	mat.set_shader_parameter("accent", spell.accent)
	mat.set_shader_parameter("hot", spell.hot_color)
	mat.set_shader_parameter("glow_base", glow)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	_parts.append(mi)
	return mi


## A shot left the muzzle (called by MinigunSpell.cast).
func on_shot() -> void:
	heat = minf(heat + 1.0, spell.max_heat)
	_since_shot = 0.0
	_flash = 1.0
	if player.has_method("add_shake"):
		player.add_shake(0.25)
	if heat >= spell.max_heat:
		overheat = spell.overheat_time
		_sparks.restart()


func _process(delta: float) -> void:
	var grimoire: Grimoire = player.get("grimoire")
	var selected := grimoire.get_selected_spell() == spell and not grimoire.is_flipping()
	_show = move_toward(_show, 1.0 if selected else 0.0, delta * (4.0 if selected else 6.0))
	var firing := trigger and overheat <= 0.0 and _show > 0.95
	trigger = false
	spin = move_toward(spin, 1.0 if firing else 0.0, delta / (SPIN_UP if firing else SPIN_DOWN))

	if overheat > 0.0:
		overheat = maxf(0.0, overheat - delta)
		heat = spell.max_heat * overheat / spell.overheat_time
	else:
		_since_shot += delta
		if firing and spin >= FIRE_SPIN:
			_shot_timer -= delta
			var guard := 0
			while _shot_timer <= 0.0 and guard < 4 and overheat <= 0.0:
				guard += 1
				var rate := lerpf(spell.min_rate, spell.max_rate, smoothstep(FIRE_SPIN, 1.0, spin))
				_shot_timer += 1.0 / rate
				if not grimoire.try_cast(player, player.get_aim_direction()):
					_shot_timer = RETRY
					break
		elif not firing:
			_shot_timer = 0.0
		if _since_shot > COOL_DELAY:
			heat = maxf(0.0, heat - spell.cool_rate * delta)
	_steam.emitting = overheat > 0.0 and visible
	_sparks.emitting = overheat > spell.overheat_time - 0.6 and visible
	_update_visuals(delta)


func _update_visuals(delta: float) -> void:
	visible = _show > 0.01
	if not visible:
		return
	var cam: Camera3D = player.get("camera")
	var b := cam.global_basis
	var e := _show * _show * (3.0 - 2.0 * _show)
	var at := cam.global_position + b * OFFSET
	var aim := Basis.looking_at(cam.global_position - b.z * AIM_DISTANCE - at, b.y)
	global_transform = Transform3D(aim.scaled(Vector3.ONE * SCALE * lerpf(0.3, 1.0, e)), at)
	# Recoil: a small kick back with every shot, plus jitter at full spin.
	_flash = move_toward(_flash, 0.0, delta * 14.0)
	position += b.z * 0.006 * _flash + b * Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.0007 * spin
	_angle += spin * WHEEL_SPEED * delta
	_wheel.rotation.z = _angle
	var h := get_heat_fraction()
	var vent := 1.0 if overheat > 0.0 else 0.0
	for p in _parts:
		p.set_instance_shader_parameter("heat", h)
		p.set_instance_shader_parameter("spin", spin)
		p.set_instance_shader_parameter("vent", vent)
		p.set_instance_shader_parameter("fade", e)
	_ring.set_instance_shader_parameter("spin", -_angle * 0.15)
	_ring_mat.set_shader_parameter("energy", (0.8 + 2.5 * spin + 3.0 * _flash) * e * (0.4 if vent > 0.0 else 1.0))
	_flare.visible = _flash > 0.01
	_flare.scale = Vector3.ONE * (0.4 + _flash * randf_range(0.8, 1.3))
