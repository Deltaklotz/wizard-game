class_name SmokeCloud
extends Node3D
## The cloud of a Smoke Bomb: a burst of big puffs (smoke_cloud.gdshader) that billow out to
## the spell's radius and hang there, plus slowly churning puffs on top, for `duration` seconds,
## then thinning out. Thick enough that nothing behind it can be seen.
##   density_at(point): 0..1 how deep in smoke a point is (HUD fogs the screen by it).
##   blocks(a, b): true if the line a→b passes through thick smoke (name tags are hidden).

const SHADER := preload("res://shaders/vfx/smoke_cloud.gdshader")
const FADE_TIME := 2.5

var spell: SmokeSpell
var _age := 0.0
var _body: GPUParticles3D
var _churn: GPUParticles3D


static func spawn(parent: Node, smoke_spell: SmokeSpell, at: Vector3) -> SmokeCloud:
	var c := SmokeCloud.new()
	c.spell = smoke_spell
	parent.add_child(c)
	c.global_position = at
	return c


static func prewarm(vp: Node) -> void:
	var c := spawn(vp, load("res://spells/smoke.tres"), Vector3(0, 0, -10))
	vp.get_tree().create_timer(0.5).timeout.connect(c.queue_free)


## How thick the smoke is at `p` (0 = none, 1 = deep inside).
static func density_at(tree: SceneTree, p: Vector3) -> float:
	var best := 0.0
	for node in tree.get_nodes_in_group("smoke_cloud"):
		var c := node as SmokeCloud
		if c:
			best = maxf(best, c._density(p))
	return best


## True if the segment a→b runs through thick smoke.
static func blocks(tree: SceneTree, a: Vector3, b: Vector3) -> bool:
	for node in tree.get_nodes_in_group("smoke_cloud"):
		var c := node as SmokeCloud
		if c == null or c._strength() < 0.5:
			continue
		var center := c._center()
		var r := c._radius() * 0.8
		var ab := b - a
		var t := clampf((center - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if (a + ab * t).distance_to(center) < r:
			return true
	return false


func _center() -> Vector3:
	return global_position + Vector3.UP * spell.radius * 0.35


## Current radius (it billows out over the first second).
func _radius() -> float:
	return spell.radius * (1.0 - pow(1.0 - clampf(_age / 1.2, 0.0, 1.0), 3.0))


func _strength() -> float:
	return clampf((spell.duration - _age) / FADE_TIME, 0.0, 1.0)


func _density(p: Vector3) -> float:
	var d := p - _center()
	d.y *= 1.4  # the cloud is flatter than it is wide
	var r := maxf(_radius(), 0.1)
	return clampf((1.0 - d.length() / r) * 1.8, 0.0, 1.0) * _strength()


func _ready() -> void:
	add_to_group("smoke_cloud")
	var r := spell.radius
	# The body: puffs blasted out from the bomb that brake to a stop across the radius and hang
	# there for the whole duration.
	_body = _puffs(90, spell.duration + 0.5, r * 1.05, true)
	var bm := _body.process_material as ParticleProcessMaterial
	bm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	bm.emission_box_extents = Vector3(r * 0.6, r * 0.45, r * 0.6)
	bm.direction = Vector3.UP
	bm.spread = 180.0
	bm.flatness = 0.45
	bm.initial_velocity_min = r * 0.3
	bm.initial_velocity_max = r * 1.4
	bm.damping_min = r * 1.5
	bm.damping_max = r * 2.5
	bm.gravity = Vector3(0, 0.15, 0)
	_body.position.y = r * 0.35
	# Churning puffs on top, so it keeps moving.
	_churn = _puffs(40, 3.0, r * 0.8, false)
	var cm := _churn.process_material as ParticleProcessMaterial
	cm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	cm.emission_sphere_radius = r * 0.7
	cm.direction = Vector3.UP
	cm.spread = 180.0
	cm.initial_velocity_min = 0.2
	cm.initial_velocity_max = 0.6
	cm.gravity = Vector3(0, 0.2, 0)
	_churn.position.y = r * 0.35
	# The pop.
	var flash := SpellFx.particles(self, 24, 0.5, true, true, Vector2(0.04, 0.5), Color(0.9, 0.85, 1.0), SmokeBomb.COLOR)
	var fm := flash.process_material as ParticleProcessMaterial
	fm.direction = Vector3.UP
	fm.spread = 180.0
	fm.initial_velocity_min = 6.0
	fm.initial_velocity_max = 12.0
	fm.damping_min = 8.0
	fm.damping_max = 12.0
	var ring := SpellFx.ring(self, false, r * 2.0, SmokeBomb.COLOR, Color(0.85, 0.8, 1.0))
	ring.rotation.x = -PI * 0.5
	ring.position.y = 0.2
	SpellFx.animate_ring(ring, 0.5, 0.0)


func _puffs(amount: int, lifetime: float, size: float, burst: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = burst
	p.explosiveness = 0.95 if burst else 0.0
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var e := spell.radius * 2.5
	p.visibility_aabb = AABB(Vector3(-e, -e, -e), Vector3(e, e, e) * 2.0)
	var pm := ParticleProcessMaterial.new()
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	if burst:
		# Visible at once, holds, thins out over the last FADE_TIME seconds.
		var k := clampf(1.0 - FADE_TIME / lifetime, 0.5, 0.95)
		pm.color_ramp = MoneyRain._ramp([0.0, 0.02, k, 1.0], [Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		pm.scale_curve = _curve([Vector2(0, 0.5), Vector2(0.06, 1.0), Vector2(1, 1.15)])
	else:
		pm.color_ramp = MoneyRain._ramp([0.0, 0.3, 0.7, 1.0], [Color(1, 1, 1, 0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	quad.material = mat
	p.draw_pass_1 = quad
	add_child(p)
	p.emitting = true
	return p


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for pt in points:
		c.add_point(pt)
	var t := CurveTexture.new()
	t.curve = c
	return t


func _process(delta: float) -> void:
	_age += delta
	if _age > spell.duration - FADE_TIME and _churn.emitting:
		_churn.emitting = false
	if _age > spell.duration + 3.5:
		queue_free()
