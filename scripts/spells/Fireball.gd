class_name Fireball
extends Node3D
## A flying fireball (FireballSpell). Falls under the spell's gravity, traced every physics step.
##   Local shot (shooter set): hits world / shields / players → explode() here + the network
##     event {"kind": "fireball", "p", "n"} so every other client explodes it too.
##   Remote replay (shooter null): visual only; it ignores players and fizzles at the world –
##     the explosion comes with the event (which also removes it).

const CAPSULE_LOW := 0.3
const CAPSULE_HIGH := 1.8
## Player capsule radius + the ball's radius.
const HIT_RADIUS := 0.75
const CORE_SHADER := preload("res://shaders/vfx/fireball_core.gdshader")

var spell: FireballSpell
var owner_id := -1
var velocity := Vector3.ZERO

var _shooter: Node3D
var _skip: Node3D
var _age := 0.0
var _trail: GPUParticles3D
var _smoke: GPUParticles3D
var _core: MeshInstance3D
var _light: OmniLight3D
var _done := false


static func launch(parent: Node, fb: FireballSpell, from: Vector3, vel: Vector3, owner: int, shooter: Node3D,
		skip: Node3D) -> Fireball:
	var f := Fireball.new()
	f.spell = fb
	f.owner_id = owner
	f.velocity = vel
	f._shooter = shooter
	f._skip = skip
	parent.add_child(f)
	f.global_position = from
	return f


## The impact everywhere: blast visuals, damage / knock-back / fire for the local player, hit
## markers for the local caster, and the fire pool on the ground below.
static func explode(parent: Node, fb: FireballSpell, at: Vector3, normal: Vector3, owner: int, local_caster: Node3D) -> void:
	var tree := parent.get_tree()
	# A visual replay of this ball still in the air ends here.
	var nearest: Fireball = null
	for node in tree.get_nodes_in_group("fireball"):
		var f := node as Fireball
		if f and f.owner_id == owner and f._shooter == null and not f._done:
			if nearest == null or f.global_position.distance_to(at) < nearest.global_position.distance_to(at):
				nearest = f
	if nearest:
		nearest._fizzle()
	FireFx.explosion(parent, at, normal, fb.blast_radius)
	var me := parent.get_node_or_null("Player") as Node3D
	if me and me.has_method("take_damage") and not me.is_dead():
		var d := me.global_position.distance_to(at)
		if d < fb.blast_radius + 0.5 and not _dome_between(tree, at, me.global_position):
			var k := clampf(d / fb.blast_radius, 0.0, 1.0)
			var dmg := lerpf(fb.damage, fb.min_damage, k) * (fb.self_damage if owner == Net.my_id else 1.0)
			var away := (me.global_position - at)
			away = away.normalized() if away.length_squared() > 0.01 else Vector3.UP
			me.add_knockback((Vector3(away.x, 0.0, away.z).normalized() * 7.0 + Vector3.UP * 4.0) * (1.0 - k * 0.6))
			me.take_damage(dmg, owner)
		if me.has_method("add_shake") and d < fb.blast_radius * 6.0:
			me.add_shake(clampf(1.0 - d / (fb.blast_radius * 6.0), 0.0, 1.0) * 0.8)
	if local_caster and local_caster.has_method("confirm_hit"):
		for node in tree.get_nodes_in_group("remote_player"):
			var a := node as RemotePlayer
			if a and a.visible and not a.is_dead() and a.global_position.distance_to(at) < fb.blast_radius + 0.5:
				local_caster.confirm_hit(a.peer_id)
	# The fire pool: on the ground below the impact (an air burst high up leaves none).
	var space := (parent as Node3D).get_world_3d().direct_space_state if parent is Node3D else null
	if space == null and me:
		space = me.get_world_3d().direct_space_state
	if space:
		var q := PhysicsRayQueryParameters3D.create(at + normal * 0.3 + Vector3.UP * 0.2, at + Vector3.DOWN * 6.0)
		q.collision_mask = 1
		var g := space.intersect_ray(q)
		if not g.is_empty():
			FirePatch.spawn(parent, fb, g.position, owner)
			FireFx.scorch(parent, g.position, fb.blast_radius * 0.8, fb.patch_time)


## True if a dome stands between the blast and `pos` (one inside it, the other not).
static func _dome_between(tree: SceneTree, a: Vector3, b: Vector3) -> bool:
	for node in tree.get_nodes_in_group("shield"):
		var s := node as Shield
		if s == null or s.kind != "bubble" or s.body == null:
			continue
		var r: float = s.get("spell").radius
		var ia := a.distance_to(s.global_position) < r
		var ib := b.distance_to(s.global_position) < r
		if ia != ib:
			return true
	return false


func _ready() -> void:
	add_to_group("fireball")
	_core = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.4, 1.4)
	var mat := ShaderMaterial.new()
	mat.shader = CORE_SHADER
	quad.material = mat
	_core.mesh = quad
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.scale = Vector3.ONE * 0.25
	add_child(_core)
	_trail = FireFx.flames(self, 70, 0.45, 0.55, 1.5)
	var pm := _trail.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.18
	pm.spread = 180.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.8
	_smoke = FireFx.smoke(self, 30, 1.4, 0.7, 0.8)
	_light = FireFx.fire_light(self, 3.0, 8.0)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	velocity.y -= spell.gravity * delta
	var a := global_position
	var b := a + velocity * delta
	var hit := _trace(a, b)
	if not hit.is_empty():
		global_position = hit.point
		if _shooter:
			if hit.shield:
				(hit.shield as Shield).report_hit(spell.damage, hit.point)
			Net.send_event({"kind": "fireball", "p": Net._vec(hit.point), "n": Net._vec(hit.normal)})
			explode(get_parent(), spell, hit.point, hit.normal, owner_id, _shooter)
		_fizzle()
		return
	global_position = b
	if _age > spell.max_flight:
		if _shooter:
			Net.send_event({"kind": "fireball", "p": Net._vec(b), "n": Net._vec(Vector3.UP)})
			explode(get_parent(), spell, b, Vector3.UP, owner_id, _shooter)
		_fizzle()
		return
	# Grows out of the hand over the first metres.
	_core.scale = Vector3.ONE * lerpf(0.25, 1.0, clampf(_age * 5.0, 0.0, 1.0))
	_light.light_energy = 2.5 + 0.6 * sin(_age * 31.0)


## {"point", "normal", "shield"} of the first thing between a and b, or {}.
func _trace(a: Vector3, b: Vector3) -> Dictionary:
	var result := {}
	var seg := b - a
	var best := seg.length()
	var dir := seg / maxf(best, 0.0001)
	var q := PhysicsRayQueryParameters3D.create(a, b)
	if _shooter:
		var ex := Shield.excludes_for(get_tree(), Net.my_id)
		ex.append((_shooter as CollisionObject3D).get_rid())
		q.exclude = ex
	else:
		q.collision_mask = 1  # replays: the world only
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		best = a.distance_to(r.position)
		result = {"point": r.position, "normal": r.normal, "shield": Shield.from_collider(r.collider)}
	if _shooter == null:
		return result
	var dome := Shield.dome_exit(get_tree(), a, a + dir * best)
	if not dome.is_empty():
		best = dome.dist
		result = {"point": dome.point, "normal": dome.normal, "shield": dome.shield}
	for node in get_tree().get_nodes_in_group("remote_player"):
		var av := node as RemotePlayer
		if av == null or not av.visible or av.is_dead():
			continue
		var pts := Geometry3D.get_closest_points_between_segments(a, a + dir * best,
			av.global_position + Vector3.UP * CAPSULE_LOW, av.global_position + Vector3.UP * CAPSULE_HIGH)
		if pts[0].distance_to(pts[1]) <= HIT_RADIUS:
			var d := a.distance_to(pts[0])
			if d < best:
				best = d
				result = {"point": pts[0], "normal": (pts[0] - pts[1]).normalized(), "shield": null}
	return result


## Stops: the core vanishes, the trail and smoke drift off and the node frees itself.
func _fizzle() -> void:
	if _done:
		return
	_done = true
	_core.visible = false
	_light.visible = false
	_trail.emitting = false
	_smoke.emitting = false
	get_tree().create_timer(1.6).timeout.connect(queue_free)
