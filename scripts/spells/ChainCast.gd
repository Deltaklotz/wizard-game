class_name ChainCast
extends Node
## A chain thrown by the local player (see ChainSpell). Lives in the scene while the chain is
## out and is the Grimoire's channel meanwhile (no page flips; cast again = cancel()).
##
##   GROW:     the head flies at grow_speed, turning at most turn_rate towards the crosshair
##             point (so it can be steered while flying) plus a noise wander; homes onto
##             players/chainables near the head. Mana per metre; empty -> snap.
##   ANCHORED: hit a surface – the chain straightens and hauls the caster in (Player.set_pull).
##   TOWING:   hit a player (their client pulls itself in, see Player._on_net_event) or a
##             "chainable" node (chain_pull() is called on it here).
## Ends with snap() (burst: cancelled, out of mana, too long, out-pulled) or a quiet release
## (arrived, target gone, stuck).

enum Phase { GROW, ANCHORED, TOWING, DONE }

const SEND_RATE := 15.0
const STRAIGHTEN_TIME := 0.18
## The grapple lets go this close to its anchor; a towed target this close to the caster.
const ARRIVE_DISTANCE := 1.8
const TOW_RELEASE := 2.2
## Radius around a player's body (capsule) / a chainable's point that catches the head.
const CATCH_RADIUS := 0.7
const CAPSULE_LOW := 0.3
const CAPSULE_HIGH := 1.8
## Feet -> chest of a remote player (where the chain attaches).
const CHEST := 1.15
## No progress towards the anchor for this long (while not out-pulled) -> let go.
const STUCK_TIME := 1.5
## Spacing of the path points sent to other players.
const NET_SPACING := 1.5
const PULL_KEY := "grapple"

var spell: ChainSpell
var caster: Node3D
var phase := Phase.GROW
## Peer id of the towed player (-1 = none / a chainable).
var target_id := -1

var _path := PackedVector3Array()
var _dir := Vector3.FORWARD
var _length := 0.0
var _anchor := Vector3.ZERO
var _target: Node3D
var _lock: Node3D
var _straight := 0.0
var _send := 0.0
var _best := INF
var _stuck := 0.0
var _fx: ChainFx
var _noise := FastNoiseLite.new()


func start(chain_spell: ChainSpell, by: Node3D, origin: Vector3, direction: Vector3) -> void:
	spell = chain_spell
	caster = by
	_dir = direction.normalized() if direction.length_squared() > 0.0001 else -by.global_basis.z
	_path = PackedVector3Array([origin, origin + _dir * 0.05])
	_noise.seed = randi()
	_noise.frequency = 0.11
	_fx = ChainFx.create(get_parent(), spell.color, spell.accent, true)
	_fx.set_head_visible(true)
	caster.grimoire.begin_channel(self)
	_send_state()


## Cast pressed again while the chain is out: it snaps.
func cancel() -> void:
	snap()


## The chain breaks: the links burst apart.
func snap() -> void:
	_finish(true)


func _physics_process(delta: float) -> void:
	if phase == Phase.DONE:
		return
	if not is_instance_valid(caster) or caster.is_dead():
		snap()
		return
	if phase == Phase.GROW:
		_grow(delta)
	else:
		_hold(delta)
	if phase == Phase.DONE:
		return
	_send -= delta
	if _send <= 0.0:
		_send = 1.0 / SEND_RATE
		_send_state()


func _hand() -> Vector3:
	return caster.grimoire.get_cast_origin().origin


func _grow(delta: float) -> void:
	_path[0] = _hand()
	var head := _path[_path.size() - 1]
	if _lock and not _is_valid(_lock):
		_lock = null
	if _lock == null:
		_lock = _find_target(head)
	var goal: Vector3
	var rate := spell.turn_rate
	if _lock:
		goal = (_chest(_lock) - head).normalized()
		rate = spell.homing_turn_rate
	else:
		goal = _wander(_aim_goal(head))
	_dir = _turn(_dir, goal, rate * delta)

	var step := spell.grow_speed * delta
	var cost := step * spell.mana_per_meter
	if caster.mana < cost:
		snap()
		return
	caster.spend_mana(cost)
	var to := head + _dir * step
	var hit := _trace(head, to)
	if not hit.is_empty():
		_path.append(hit.point)
		_attach(hit)
		return
	_path.append(to)
	_length += step
	if _length > spell.max_length:
		snap()
		return
	_fx.set_points(_path)


## Where the head wants to go: the point under the crosshair, or straight along the view once
## the head is level with it.
func _aim_goal(head: Vector3) -> Vector3:
	var cam: Camera3D = caster.camera
	var view := -cam.global_basis.z
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + view * 400.0)
	q.exclude = _exclude()
	var r := caster.get_world_3d().direct_space_state.intersect_ray(q)
	var aim: Vector3 = r.position if not r.is_empty() else from + view * 400.0
	var to_aim := aim - head
	if to_aim.dot(view) < 1.5:
		return view
	return to_aim.normalized()


## Slow random sway around the goal direction, so the chain flies in stiff waves.
func _wander(goal: Vector3) -> Vector3:
	var side := goal.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = goal.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(goal).normalized()
	var n1 := _noise.get_noise_1d(_length)
	var n2 := _noise.get_noise_1d(_length + 437.0)
	return (goal + side * n1 * spell.wander * 2.2 + up * n2 * spell.wander * 1.5).normalized()


## Turns `from` towards `to` by at most `max_angle` radians.
static func _turn(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var angle := from.angle_to(to)
	if angle <= max_angle:
		return to
	var axis := from.cross(to)
	if axis.length_squared() < 0.000001:
		axis = from.cross(Vector3.UP if absf(from.y) < 0.9 else Vector3.RIGHT)
	return from.rotated(axis.normalized(), max_angle).normalized()


## First thing the head runs into between a and b: {"point", "node" (null = world), "id"}.
func _trace(a: Vector3, b: Vector3) -> Dictionary:
	var result := {}
	var best := a.distance_to(b)
	var dir := (b - a) / maxf(best, 0.0001)
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = _exclude()
	var r := caster.get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		best = a.distance_to(r.position)
		result = {"point": r.position, "node": null, "id": -1}
	# A dome stops the chain from inside too (it anchors on it).
	var dome := Shield.dome_exit(get_tree(), a, a + dir * best)
	if not dome.is_empty():
		best = dome.dist
		result = {"point": dome.point, "node": null, "id": -1}
	for t in _targets():
		var p: Vector3
		var d: float
		if t is RemotePlayer:
			var pts := Geometry3D.get_closest_points_between_segments(a, a + dir * best,
				t.global_position + Vector3.UP * CAPSULE_LOW, t.global_position + Vector3.UP * CAPSULE_HIGH)
			p = pts[0]
			d = pts[0].distance_to(pts[1])
		else:
			p = Geometry3D.get_closest_point_to_segment(t.get_chain_point(), a, a + dir * best)
			d = p.distance_to(t.get_chain_point())
		if d <= CATCH_RADIUS:
			var along := a.distance_to(p)
			if along <= best:
				best = along
				result = {"point": _chest(t), "node": t, "id": (t as RemotePlayer).peer_id if t is RemotePlayer else -1}
	return result


## The caster and their own shields.
func _exclude() -> Array[RID]:
	var out := Shield.excludes_for(get_tree(), Net.my_id)
	out.append((caster as CollisionObject3D).get_rid())
	return out


func _attach(hit: Dictionary) -> void:
	_straight = 0.0
	_fx.set_head_visible(false)
	if hit.node == null:
		phase = Phase.ANCHORED
		_anchor = hit.point
		_best = caster.global_position.distance_to(_anchor)
		caster.set_pull(PULL_KEY, _anchor, spell.pull_speed)
	else:
		phase = Phase.TOWING
		_target = hit.node
		target_id = hit.id
		caster.chain_caught.emit(target_id)
	_fx.set_points(_path)
	_send_state()


func _hold(delta: float) -> void:
	var start := _hand()
	var end := _anchor
	if phase == Phase.TOWING:
		if not _is_valid(_target):
			_finish(false)
			return
		end = _chest(_target)
	_straight = move_toward(_straight, 1.0, delta / STRAIGHTEN_TIME)
	_fx.set_points(_straightened(start, end))

	if phase == Phase.ANCHORED:
		caster.set_pull(PULL_KEY, _anchor, spell.pull_speed)
		var over: float = caster.get_pull_overpower(PULL_KEY)
		if over >= ChainSpell.BREAK_TIME:
			snap()
			return
		var d := caster.global_position.distance_to(_anchor)
		if d < ARRIVE_DISTANCE:
			_finish(false)
			return
		if d < _best - 0.15:
			_best = d
			_stuck = 0.0
		elif over <= 0.0:
			_stuck += delta
			if _stuck > STUCK_TIME:
				_finish(false)
	else:
		var feet: Vector3 = caster.global_position
		if _target.global_position.distance_to(feet) < TOW_RELEASE:
			_finish(false)
			return
		if not _target is RemotePlayer:
			var pull_dir: Vector3 = (feet - _target.get_chain_point()).normalized()
			_target.chain_pull(pull_dir, spell.pull_speed, delta)
			if _target.has_method("get_chain_overpower") and _target.get_chain_overpower() >= ChainSpell.BREAK_TIME:
				snap()


## The flight path pulled taut: ends follow the hand and the anchor, the curve eases into
## the straight line between them.
func _straightened(start: Vector3, end: Vector3) -> PackedVector3Array:
	_path = PackedVector3Array([start, end]) if _straight >= 1.0 else straighten(_path, start, end, _straight)
	return _path


## `path` with its ends moved to start/end (the rest shifted along by arc length) and eased
## towards the straight line by t (0..1). Also used for remote chains.
static func straighten(path: PackedVector3Array, start: Vector3, end: Vector3, t: float) -> PackedVector3Array:
	var n := path.size()
	if n < 2:
		return PackedVector3Array([start, end])
	var cum := PackedFloat32Array()
	cum.resize(n)
	cum[0] = 0.0
	for i in range(1, n):
		cum[i] = cum[i - 1] + path[i - 1].distance_to(path[i])
	var total := maxf(cum[n - 1], 0.001)
	var d0 := start - path[0]
	var d1 := end - path[n - 1]
	var e := t * t * (3.0 - 2.0 * t)
	var out := PackedVector3Array()
	out.resize(n)
	for i in n:
		var f := cum[i] / total
		var p := path[i] + d0 * (1.0 - f) + d1 * f
		out[i] = p.lerp(start.lerp(end, f), e)
	return out


func _targets() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("remote_player"):
		if _is_valid(node):
			out.append(node)
	for node in get_tree().get_nodes_in_group("chainable"):
		if _is_valid(node):
			out.append(node)
	return out


func _is_valid(t: Node) -> bool:
	if not is_instance_valid(t) or not t.is_inside_tree():
		return false
	if t is RemotePlayer:
		return t.visible and not t.is_dead()
	return t.has_method("get_chain_point") and t.has_method("chain_pull")


func _chest(t: Node3D) -> Vector3:
	return t.global_position + Vector3.UP * CHEST if t is RemotePlayer else t.get_chain_point()


## Nearest player/chainable within homing range of the head, ahead of it and in sight.
func _find_target(head: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := spell.homing_radius
	var space := caster.get_world_3d().direct_space_state
	for t in _targets():
		var p := _chest(t)
		var d := head.distance_to(p)
		if d > best_d or (p - head).dot(_dir) < -0.3 * d:
			continue
		var q := PhysicsRayQueryParameters3D.create(head, p)
		q.exclude = _exclude()
		if t is CollisionObject3D:
			q.exclude.append((t as CollisionObject3D).get_rid())
		if not space.intersect_ray(q).is_empty():
			continue
		best = t
		best_d = d
	return best


func _send_state() -> void:
	var ev := {"kind": "chain", "st": phase, "tg": target_id}
	if phase == Phase.GROW:
		ev["pts"] = _sparse()
	else:
		ev["pts"] = Net._vec(_anchor if phase == Phase.ANCHORED else _chest(_target))
		ev["sp"] = spell.pull_speed
	Net.send_event(ev)


## Path points (without the start) at least NET_SPACING apart, flattened, head always included.
func _sparse() -> Array:
	var out := []
	var last := _path[0]
	var n := _path.size()
	for i in range(1, n):
		if i == n - 1 or _path[i].distance_to(last) >= NET_SPACING:
			last = _path[i]
			out.append_array(Net._vec(last))
	return out


func _finish(burst: bool) -> void:
	if phase == Phase.DONE:
		return
	var was := phase
	phase = Phase.DONE
	if is_instance_valid(caster):
		caster.clear_pull(PULL_KEY)
		caster.grimoire.end_channel(self)
	Net.send_event({"kind": "chain_end", "burst": burst, "pts": _sparse() if was == Phase.GROW else []})
	if is_instance_valid(_fx):
		if burst:
			_fx.burst()
		else:
			_fx.dissolve()
	queue_free()


func _exit_tree() -> void:
	if phase != Phase.DONE and is_instance_valid(caster):
		caster.clear_pull(PULL_KEY)
		caster.grimoire.end_channel(self)
