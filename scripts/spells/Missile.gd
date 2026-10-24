class_name Missile
extends Node3D
## One homing missile (MissileSpell): a star-flared glowing head (missile_core.gdshader) with a
## trail of motes and sparks (explosive ones: flames and smoke), a small light. volley() launches
## them one after another (spawn_interval): out of the book, or (launch_behind) from behind the
## caster's head, arcing up over it. After the spell's launch_time it homes: locks onto the player
## nearest the line to the aim point (lock_angle, homing_range, in sight – re-checked every
## SEEK_INTERVAL while it has none or lost it) and turns towards their chest at turn_rate.
## Without a target it heads for the aim point: the caster's live crosshair (follow_crosshair)
## or the point they aimed at when casting, where it lands. Traced every physics step.
##   Local (shooter set): hits world / shields / domes / avatars (decoys too, not the caster's
##     own). A player hit → {"kind": "hit"} (+ hit marker); explosive → explode() here and
##     {"kind": "missile_boom"} so every client applies the blast.
##   Replay (shooter null): candidates are every player but the caster (the local player
##     included) so it steers the same way; it stops at the world and at players, visual only.

## Metres over which the head grows to full size and seconds before the trail starts (keeps
## the caster's view clear at launch).
const GROW := 3.0
const TRAIL_DELAY := 0.1
const SEEK_INTERVAL := 0.25
const CAPSULE_LOW := 0.3
const CAPSULE_HIGH := 1.8
const SHADER := preload("res://shaders/vfx/missile_core.gdshader")

static var _materials := {}

var spell: MissileSpell
var owner_id := -1
var velocity := Vector3.ZERO
## Where it goes without a target: fixed (aim point at cast) or the caster's live crosshair.
var aim_point := Vector3.ZERO
var _caster: Node3D
var _travel := 0.0
var _shooter: Node3D
var _skip: Node3D
var _age := 0.0
var _target: Node3D
var _seek := 0.0
var _head: MeshInstance3D
var _trails: Array[GPUParticles3D] = []
var _light: OmniLight3D
var _done := false
var _wobble := 0.0


## Launches the spell's volley: `count` missiles, one every spawn_interval, from the caster's
## position at that moment (caster: the local Player or a RemotePlayer; shooter: the local player
## when it is their own cast, else null; aim: the aimed point).
static func volley(parent: Node, ms: MissileSpell, owner: int, caster: Node3D, shooter: Node3D, aim: Vector3) -> void:
	for i in ms.count:
		if i > 0:
			await parent.get_tree().create_timer(ms.spawn_interval, false).timeout
		if not is_instance_valid(caster) or not is_instance_valid(parent) or caster.is_dead():
			return
		var start := launch(ms, caster, i)
		spawn(parent, ms, start[0], start[1], owner, caster, shooter, aim)


static func spawn(parent: Node, ms: MissileSpell, from: Vector3, dir: Vector3, owner: int, caster: Node3D,
		shooter: Node3D, aim: Vector3) -> Missile:
	var m := Missile.new()
	m.spell = ms
	m.owner_id = owner
	m.velocity = dir * ms.speed
	m.aim_point = aim
	m._caster = caster
	m._shooter = shooter
	m._skip = caster if shooter == null else null
	m._wobble = randf() * TAU
	parent.add_child(m)
	m.global_position = from
	return m


## [position, direction] of the i-th missile for the caster as they stand now.
static func launch(ms: MissileSpell, caster: Node3D, i: int) -> Array:
	var eye := eye_of(caster)
	var look := look_of(caster)
	var flat := Vector3(look.x, 0.0, look.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	var right := flat.cross(Vector3.UP).normalized()
	var side: float = [0.0, -1.0, 1.0, -2.0, 2.0, -0.5, 0.5][i % 7]
	if ms.launch_behind:
		var pos := eye - flat * 1.2 + Vector3.UP * 0.45 + right * side * 0.7
		return [pos, (flat * 0.9 + Vector3.UP + right * side * 0.25).normalized()]
	var hand: Vector3
	if caster is RemotePlayer:
		hand = (caster as RemotePlayer).get_hand_position()
	else:
		hand = caster.grimoire.get_cast_origin().origin
	var up2 := right.cross(look).normalized()
	return [hand + right * side * 0.2, (look + right * side * 0.45 + up2 * 0.3).normalized()]


static func eye_of(caster: Node3D) -> Vector3:
	if caster is RemotePlayer:
		return caster.global_position + Vector3.UP * RemotePlayer.EYE_HEIGHT
	return (caster.camera as Camera3D).global_position


static func look_of(caster: Node3D) -> Vector3:
	if caster is RemotePlayer:
		return (caster as RemotePlayer).get_look_direction()
	return -(caster.camera as Camera3D).global_basis.z


## The point under the caster's crosshair (or `reach` m along it).
static func crosshair_point(caster: Node3D, reach: float) -> Vector3:
	var eye := eye_of(caster)
	var look := look_of(caster)
	var q := PhysicsRayQueryParameters3D.create(eye, eye + look * reach)
	var ex: Array[RID] = []
	if caster is RemotePlayer:
		q.collision_mask = 1
		var me := caster.get_tree().current_scene.get_node_or_null("Player") as CollisionObject3D
		if me:
			ex.append(me.get_rid())
	else:
		ex = Shield.excludes_for(caster.get_tree(), Net.my_id, true)
		ex.append((caster as CollisionObject3D).get_rid())
	q.exclude = ex
	var r := caster.get_world_3d().direct_space_state.intersect_ray(q)
	return r.position if not r.is_empty() else eye + look * reach


static func prewarm(vp: Node) -> void:
	for path in ["res://spells/magic_missile.tres", "res://spells/homing_missile.tres"]:
		var ms := load(path) as MissileSpell
		spawn(vp, ms, Vector3(0, 1, -3), Vector3(0, 0, -1), -999, null, null, Vector3(0, 1, -40))
		_impact_fx(vp, ms, Vector3(0, 1, -6), Vector3.BACK)
	FireFx.explosion(vp, Vector3(0, 1, -8), Vector3.UP, 3.5)


## A blast everywhere (explosive missiles): visuals, damage / knock-back / shake for the local
## player (falling off over the blast radius; the caster takes self_damage of it), hit markers
## for the local caster, and the visual replay of the missile ends.
static func explode(parent: Node, ms: MissileSpell, at: Vector3, normal: Vector3, owner: int, local_caster: Node3D) -> void:
	var tree := parent.get_tree()
	var nearest: Missile = null
	for node in tree.get_nodes_in_group("missile"):
		var m := node as Missile
		if m and m.owner_id == owner and m._shooter == null and not m._done and m.spell == ms:
			if nearest == null or m.global_position.distance_to(at) < nearest.global_position.distance_to(at):
				nearest = m
	if nearest:
		nearest._fizzle()
	_impact_fx(parent, ms, at, normal)
	var me := parent.get_node_or_null("Player") as Node3D
	if me and me.has_method("take_damage") and not me.is_dead():
		var d := me.global_position.distance_to(at)
		if d < ms.blast_radius + 0.5 and not Fireball._dome_between(tree, at, me.global_position):
			var k := clampf(d / ms.blast_radius, 0.0, 1.0)
			var dmg := lerpf(ms.damage, ms.min_damage, k) * (ms.self_damage if owner == Net.my_id else 1.0)
			var away := me.global_position - at
			away = away.normalized() if away.length_squared() > 0.01 else Vector3.UP
			me.add_knockback((Vector3(away.x, 0.0, away.z).normalized() * 6.0 + Vector3.UP * 3.5) * (1.0 - k * 0.6))
			if dmg > 0.0:
				me.take_damage(dmg, owner)
		if me.has_method("add_shake") and d < ms.blast_radius * 6.0:
			me.add_shake(clampf(1.0 - d / (ms.blast_radius * 6.0), 0.0, 1.0) * 0.7)
	if local_caster and local_caster.has_method("confirm_hit"):
		for node in tree.get_nodes_in_group("remote_player"):
			var a := node as RemotePlayer
			if a and a.visible and not a.is_dead() and a.global_position.distance_to(at) < ms.blast_radius + 0.5:
				local_caster.confirm_hit(a.peer_id)


static func _impact_fx(parent: Node, ms: MissileSpell, at: Vector3, normal: Vector3) -> void:
	if normal.length_squared() < 0.01:
		normal = Vector3.UP
	if ms.explosive:
		FireFx.explosion(parent, at, normal, ms.blast_radius)
	var root := SpellFx.effect_root(parent, at + normal * 0.1, 1.2)
	var sparks := SpellFx.particles(root, 26 if ms.explosive else 14, 0.45, true, true, Vector2(0.04, 0.4), ms.accent, ms.color)
	var pm := sparks.process_material as ParticleProcessMaterial
	pm.direction = normal
	pm.spread = 80.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 10.0 if ms.explosive else 7.0
	pm.gravity = Vector3(0, -6, 0)
	pm.damping_min = 3.0
	pm.damping_max = 5.0
	var ring := SpellFx.ring(root, false, ms.blast_radius * 2.4 if ms.explosive else 1.4, ms.color, ms.accent)
	ring.global_basis = Basis.looking_at(-normal, Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT)
	SpellFx.animate_ring(ring, 0.35 if ms.explosive else 0.25, 0.0)
	SpellFx.flash(root, root.global_position, ms.color, 4.0 if ms.explosive else 1.5, 8.0 if ms.explosive else 3.0, 0.3)


func _ready() -> void:
	add_to_group("missile")
	top_level = true
	_head = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * spell.size * 3.2
	_head.mesh = quad
	_head.material_override = _material(spell)
	_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_head)
	var motes := SpellFx.particles(self, 40, 0.6, false, false, Vector2.ONE * spell.size * 1.4, spell.color, spell.accent)
	_trails.append(motes)
	var sparks := SpellFx.particles(self, 16, 0.3, false, true, Vector2(0.03, spell.size * 2.0), spell.accent, spell.color)
	var sm := sparks.process_material as ParticleProcessMaterial
	sm.spread = 180.0
	sm.initial_velocity_min = 0.5
	sm.initial_velocity_max = 2.0
	_trails.append(sparks)
	if spell.explosive:
		_trails.append(FireFx.flames(self, 90, 0.35, spell.size * 2.2, 0.5))
		_trails.append(FireFx.smoke(self, 30, 1.2, spell.size * 3.0, 0.4))
	for p in _trails:
		p.emitting = false
	_head.scale = Vector3.ONE * 0.25
	_light = OmniLight3D.new()
	_light.light_color = spell.color
	_light.omni_range = 4.0 if spell.explosive else 2.5
	_light.light_energy = 1.5
	_light.light_volumetric_fog_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	_travel += spell.speed * delta
	var arrived := _target == null and not spell.follow_crosshair and _age > spell.launch_time 		and global_position.distance_to(aim_point) < maxf(spell.speed * delta * 1.5, 0.5)
	if _age > spell.lifetime or (spell.max_distance > 0.0 and _travel > spell.max_distance) or arrived:
		if _shooter and spell.explosive:
			Net.send_event({"kind": "missile_boom", "s": spell.resource_path, "p": Net._vec(global_position), "n": Net._vec(Vector3.UP)})
			explode(get_parent(), spell, global_position, Vector3.UP, owner_id, _shooter)
		elif not spell.explosive:
			_impact_fx(get_parent(), spell, global_position, -velocity.normalized())
		_fizzle()
		return
	_steer(delta)
	var a := global_position
	var b := a + velocity * delta
	var hit := _trace(a, b)
	if not hit.is_empty():
		global_position = hit.point
		if _shooter:
			if spell.explosive:
				if hit.shield:
					(hit.shield as Shield).report_hit(spell.damage, hit.point)
				Net.send_event({"kind": "missile_boom", "s": spell.resource_path, "p": Net._vec(hit.point), "n": Net._vec(hit.normal)})
				explode(get_parent(), spell, hit.point, hit.normal, owner_id, _shooter)
			else:
				if hit.shield:
					(hit.shield as Shield).report_hit(spell.damage, hit.point)
				elif hit.target != -1:
					Net.send_event({"kind": "hit", "target": hit.target, "damage": spell.damage, "spell": spell.resource_path})
					if _shooter.has_method("confirm_hit"):
						_shooter.confirm_hit(hit.target)
				_impact_fx(get_parent(), spell, hit.point, hit.normal)
		elif not spell.explosive:
			_impact_fx(get_parent(), spell, hit.point, hit.normal)
		_fizzle()
		return
	global_position = b
	# A little corkscrew wobble of the head (visual only).
	var t := _age * 9.0 + _wobble
	var side := velocity.normalized().cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(velocity.normalized())
	_head.position = (side * sin(t) + up * cos(t)) * spell.size * 0.4
	_light.light_energy = 1.3 + 0.4 * sin(_age * 30.0)
	var grow := clampf(_age * spell.speed / GROW, 0.0, 1.0)
	_head.scale = Vector3.ONE * lerpf(0.25, 1.0, grow)
	if _age > TRAIL_DELAY and not _trails[0].emitting:
		for p in _trails:
			p.emitting = true


func _steer(delta: float) -> void:
	if _age < spell.launch_time:
		return
	if _target and not _valid(_target):
		_target = null
	_seek -= delta
	if _target == null and _seek <= 0.0:
		_seek = SEEK_INTERVAL
		_target = _find_target()
	var want := (_goal() - global_position).normalized()
	# Turns harder once it has left the launch.
	var rate := spell.turn_rate * clampf((_age - spell.launch_time) / 0.4, 0.3, 1.0)
	var cur := velocity.normalized()
	var ang := cur.angle_to(want)
	if ang < 0.0001:
		return
	var dir := cur.slerp(want, minf(1.0, rate * delta / ang))
	velocity = dir.normalized() * spell.speed


## Where it is heading: the locked target's chest, else the aim point.
func _goal() -> Vector3:
	if _target:
		return _aim_point(_target)
	return _aim_now()


## The aim point now: the caster's live crosshair for follow_crosshair spells (while they live).
func _aim_now() -> Vector3:
	if spell.follow_crosshair and is_instance_valid(_caster) and not _caster.is_dead():
		aim_point = crosshair_point(_caster, spell.aim_range)
	return aim_point


## Players this missile may hunt: everyone but its caster (and the caster's decoys).
func _candidates() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("remote_player"):
		var a := node as RemotePlayer
		if a == null or a == _skip or (a is Decoy and (a as Decoy).owner_id == owner_id):
			continue
		if _valid(a):
			out.append(a)
	if _shooter == null:
		var me := get_tree().current_scene.get_node_or_null("Player") as Node3D
		if me and _valid(me):
			out.append(me)
	return out


func _valid(t: Node3D) -> bool:
	if not is_instance_valid(t) or not t.is_inside_tree() or not t.visible:
		return false
	return not t.is_dead() if t.has_method("is_dead") else true


func _aim_point(t: Node3D) -> Vector3:
	# Avatars stand on their origin; the local player's origin is the body centre.
	return t.global_position + (Vector3.UP * 1.1 if t is RemotePlayer else Vector3.UP * 0.2)


func _find_target() -> Node3D:
	var best: Node3D = null
	var best_ang := deg_to_rad(spell.lock_angle)
	# Measured from the line to the aim point, not the missile's own heading (it may still be
	# arcing over the caster's head).
	var cur := (_aim_now() - global_position).normalized()
	var space := get_world_3d().direct_space_state
	for t in _candidates():
		var p := _aim_point(t)
		var to := p - global_position
		var dist := to.length()
		if dist > spell.homing_range or dist < 0.1:
			continue
		var ang := cur.angle_to(to / dist)
		if ang >= best_ang:
			continue
		var q := PhysicsRayQueryParameters3D.create(global_position, p)
		q.collision_mask = 1
		var ex: Array[RID] = []
		if t is CollisionObject3D:
			ex.append((t as CollisionObject3D).get_rid())
		if _shooter is CollisionObject3D:
			ex.append((_shooter as CollisionObject3D).get_rid())
		q.exclude = ex
		if not space.intersect_ray(q).is_empty():
			continue
		best_ang = ang
		best = t
	return best


## {"point", "normal", "target" (peer id, -1 = none), "shield"} of the first thing hit, or {}.
func _trace(a: Vector3, b: Vector3) -> Dictionary:
	var result := {}
	var seg := b - a
	var best := seg.length()
	var dir := seg / maxf(best, 0.0001)
	var radius := spell.size + 0.3
	var q := PhysicsRayQueryParameters3D.create(a, b)
	if _shooter:
		var ex := Shield.excludes_for(get_tree(), Net.my_id)
		ex.append((_shooter as CollisionObject3D).get_rid())
		q.exclude = ex
	else:
		q.collision_mask = 1
		var me := get_tree().current_scene.get_node_or_null("Player") as CollisionObject3D
		if me:
			q.exclude = [me.get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		best = a.distance_to(r.position)
		result = {"point": r.position, "normal": r.normal, "target": -1, "shield": Shield.from_collider(r.collider)}
	if _shooter:
		var dome := Shield.dome_exit(get_tree(), a, a + dir * best)
		if not dome.is_empty():
			best = dome.dist
			result = {"point": dome.point, "normal": dome.normal, "target": -1, "shield": dome.shield}
	for t in _candidates():
		var low: Vector3
		var high: Vector3
		if t is RemotePlayer:
			low = t.global_position + Vector3.UP * CAPSULE_LOW
			high = t.global_position + Vector3.UP * CAPSULE_HIGH
		else:
			low = t.global_position - Vector3.UP * 0.6
			high = t.global_position + Vector3.UP * 0.6
		var pts := Geometry3D.get_closest_points_between_segments(a, a + dir * best, low, high)
		if pts[0].distance_to(pts[1]) <= radius:
			var d := a.distance_to(pts[0])
			if d < best:
				best = d
				var id: int = (t as RemotePlayer).peer_id if t is RemotePlayer else -1
				result = {"point": pts[0], "normal": (pts[0] - pts[1]).normalized(), "target": id, "shield": null}
	return result


func _fizzle() -> void:
	if _done:
		return
	_done = true
	_head.visible = false
	_light.visible = false
	for p in _trails:
		p.emitting = false
	get_tree().create_timer(1.3).timeout.connect(queue_free)


static func _material(ms: MissileSpell) -> ShaderMaterial:
	var key := ms.get_instance_id()
	if not _materials.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("color", ms.color)
		mat.set_shader_parameter("accent", ms.accent)
		_materials[key] = mat
	return _materials[key]
