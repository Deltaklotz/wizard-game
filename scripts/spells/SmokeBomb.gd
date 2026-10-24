class_name SmokeBomb
extends Node3D
## The thrown orb of the Smoke Bomb (SmokeSpell): falls under the spell's gravity, bounces off
## the world (collision layer 1 only, so every client flies it the same way), and bursts into a
## SmokeCloud when its fuse runs out after the first bounce, when it comes to rest, or after
## MAX_FLIGHT seconds. A dark orb with a violet glow trailing hissing sparks and wisps.

const MAX_FLIGHT := 4.0
const RADIUS := 0.12
const BOUNCE := 0.38
const FRICTION := 0.6
const COLOR := Color(0.62, 0.5, 1.0)

var spell: SmokeSpell
var velocity := Vector3.ZERO
var _age := 0.0
var _fuse := -1.0
var _orb: MeshInstance3D
var _sparks: GPUParticles3D
var _done := false


static func launch(parent: Node, smoke_spell: SmokeSpell, from: Vector3, vel: Vector3) -> SmokeBomb:
	var b := SmokeBomb.new()
	b.spell = smoke_spell
	b.velocity = vel
	parent.add_child(b)
	b.global_position = from
	return b


func _ready() -> void:
	_orb = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.07, 0.1)
	mat.roughness = 0.35
	mat.metallic = 0.4
	mat.emission_enabled = true
	mat.emission = COLOR
	mat.emission_energy_multiplier = 0.6
	mat.rim_enabled = true
	mat.rim = 0.6
	sphere.material = mat
	_orb.mesh = sphere
	add_child(_orb)
	_sparks = SpellFx.particles(self, 30, 0.35, false, true, Vector2(0.02, 0.16), Color(1.0, 0.8, 0.5), COLOR)
	var pm := _sparks.process_material as ParticleProcessMaterial
	pm.direction = Vector3.UP
	pm.spread = 60.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.5
	pm.gravity = Vector3(0, -4, 0)
	var wisps := FireFx.smoke(self, 16, 0.8, 0.35, 0.6)
	(wisps.process_material as ParticleProcessMaterial).color_ramp = MoneyRain._ramp([0.0, 0.2, 1.0],
		[Color(0.5, 0.48, 0.56, 0), Color(0.5, 0.48, 0.56, 0.6), Color(0.4, 0.4, 0.45, 0)])


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _fuse >= 0.0:
		_fuse += delta
	velocity.y -= spell.gravity * delta
	var a := global_position
	var b := a + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(a, b + (b - a).normalized() * RADIUS)
	q.collision_mask = 1
	var me := get_tree().current_scene.get_node_or_null("Player") as CollisionObject3D
	if me:
		q.exclude = [me.get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		var n: Vector3 = r.normal
		global_position = r.position + n * RADIUS
		var vn := n * velocity.dot(n)
		velocity = (velocity - vn) * FRICTION - vn * BOUNCE
		if _fuse < 0.0:
			_fuse = 0.0
	else:
		global_position = b
	_orb.rotation += Vector3(velocity.z, 0.0, -velocity.x) * delta * 3.0
	var resting := _fuse >= 0.0 and velocity.length() < 1.2
	if (_fuse >= 0.0 and _fuse > spell.fuse) or resting or _age > MAX_FLIGHT:
		_burst()


func _burst() -> void:
	_done = true
	SmokeCloud.spawn(get_parent(), spell, global_position)
	_orb.visible = false
	_sparks.emitting = false
	get_tree().create_timer(1.0).timeout.connect(queue_free)
