class_name Decoy
extends RemotePlayer
## An illusion of a player (DecoySpell). It *is* a RemotePlayer – same avatar, name tag, map pin,
## animations from movement flags – so other players' spells target and hit it like a person.
## Its peer_id is a fake negative id (make_id), so hit events sent at it reach no one; instead
## any hit pops it (struck(), from Player.confirm_hit, or a {"kind": "hit"} event aimed at it)
## and {"kind": "decoy_pop"} makes it vanish everywhere.
##   Owner (the caster's client, _sim): runs the brain – sprints, wanders, turns away from walls,
##     steep slopes and water, jumps, dashes (the real dash effect, FLAG_DASHING) and fakes a
##     sniper aim (FLAG_AIMING → the red warning crosshair) at the nearest other player; more
##     rarely it stops, scopes in, looks around frantically and fires a harmless sniper beam in
##     a random direction (SniperSpell.cast_remote's visuals everywhere, event "shot") – feeds
##     its own snapshots and sends {"kind": "decoy", "d": id, "s": state} every SEND_INTERVAL.
##   Others: created on the first such event (handle_event), interpolated like a player; gone if
##     the events stop.

const SEND_INTERVAL := 0.1
const GRAVITY := 9.8
const JUMP_SPEED := 4.5
const DASH_DISTANCE := 9.0
const DASH_TIME := 0.24
const AIM_TIME := Vector2(2.2, 3.2)
const SILENCE_LIMIT := 2.0

static var _counter := 0

var owner_id := -1
var spell: DecoySpell
var _sim := false
var _popped := false
var _life := 0.0
var _silence := 0.0
var _send_t := 0.0
var _rng := RandomNumberGenerator.new()
# Brain state (owner only). _pos is the body centre like a player's state.
var _pos := Vector3.ZERO
var _vy := 0.0
var _yaw := 0.0
var _target_yaw := 0.0
var _pitch := 0.0
var _on_floor := true
var _next_act := 1.0
var _dash_t := -1.0
var _dash_dir := Vector3.ZERO
var _aim_t := 0.0
var _aim_at: Node3D
## The fake aim is a panicked shot (looking around wildly, then firing anywhere).
var _panic := false
var _jitter := 0.0
var _exclude: Array[RID] = []


## Unique fake id for an owner's n-th decoy (always ≤ -1000, never a real peer id or -1).
static func make_id(owner: int, n: int) -> int:
	return -(1000 + (owner + 2) * 64 + n % 64)


static func find(tree: SceneTree, id: int) -> Decoy:
	if id > -1000:
		return null
	for node in tree.get_nodes_in_group("decoy"):
		var d := node as Decoy
		if d and d.peer_id == id:
			return d
	return null


## A hit landed on `id`: if that is a decoy, it vanishes (for everyone).
static func struck(tree: SceneTree, id: int) -> void:
	var d := find(tree, id)
	if d:
		d.pop(true)


## The local caster summons one.
static func summon(decoy_spell: DecoySpell, caster: Node3D) -> Decoy:
	var tree := caster.get_tree()
	var mine: Array[Decoy] = []
	for node in tree.get_nodes_in_group("decoy"):
		var old := node as Decoy
		if old and old._sim and not old._popped:
			mine.append(old)
	while mine.size() >= decoy_spell.max_decoys:
		mine.pop_front().pop(true)
	var name_text: String = Net.my_name if not Net.my_name.is_empty() else str(Settings.get_value("player_name"))
	var color: Color = Net.my_color if Net.is_online() else Color.html(str(Settings.get_value("player_color")))
	var d := Decoy.new()
	d.spell = decoy_spell
	d.owner_id = Net.my_id
	d._sim = true
	_counter += 1
	tree.current_scene.add_child(d)
	d.setup({"id": make_id(Net.my_id, _counter), "name": name_text, "color": color})
	d._rng.randomize()
	d._exclude = [(caster as CollisionObject3D).get_rid()]
	var cam: Camera3D = caster.camera
	var view := -cam.global_basis.z
	var flat := Vector3(view.x, 0.0, view.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else -caster.global_basis.z
	d._yaw = atan2(-flat.x, -flat.z)
	d._target_yaw = d._yaw
	d._pos = caster.global_position + flat * 0.6
	d._next_act = d._rng.randf_range(0.6, 1.5)
	d.push_state(d._state())
	split_fx(tree.current_scene, caster.global_position - Vector3.UP * 0.9, color)
	return d


## Shimmer where a decoy splits off its caster.
static func split_fx(parent: Node, feet: Vector3, color: Color) -> void:
	var root := SpellFx.effect_root(parent, feet + Vector3.UP * 1.0, 1.2)
	var motes := SpellFx.particles(root, 30, 0.8, true, false, Vector2(0.1, 0.1), color.lightened(0.5), color)
	var pm := motes.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.3, 0.9, 0.3)
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 2.0
	var ring := SpellFx.ring(root, false, 2.2, color, color.lightened(0.6))
	ring.rotation.x = -PI * 0.5
	ring.position.y = -0.9
	SpellFx.animate_ring(ring, 0.4, 0.0)


## Events about decoys from other players (RemotePlayers forwards them).
static func handle_event(parent: Node, from_id: int, ev: Dictionary) -> void:
	var tree := parent.get_tree()
	match str(ev.get("kind", "")):
		"decoy":
			var id := int(ev.get("d", 0))
			var s: Variant = ev.get("s")
			if not s is Array or (s as Array).size() < 6:
				return
			var d := find(tree, id)
			if d == null:
				var info: Dictionary = Net.players.get(from_id, {})
				if info.is_empty():
					return
				d = Decoy.new()
				d.owner_id = from_id
				parent.add_child(d)
				d.setup({"id": id, "name": info.get("name", ""), "color": info.get("color", Color.WHITE)})
			if d._popped:
				return
			d._silence = 0.0
			d.push_state(s)
			if ev.has("dash"):
				d._dash_fx(Net._to_vec(ev.dash))
			var shot: Variant = ev.get("shot")
			if shot is Array and (shot as Array).size() == 2:
				d._shot_fx(Net._to_vec(shot[0]), Net._to_vec(shot[1]))
		"decoy_pop":
			var d := find(tree, int(ev.get("d", 0)))
			if d:
				d.pop(false)
		"hit":
			var d := find(tree, int(ev.get("target", -1)))
			if d:
				d.pop(false)


func _ready() -> void:
	add_to_group("decoy")


func _state() -> Array:
	var flags := 0
	if _on_floor:
		flags |= Net.FLAG_ON_FLOOR
	if _dash_t >= 0.0:
		flags |= Net.FLAG_DASHING
	if _aim_t > 0.0:
		flags |= Net.FLAG_AIMING
	return [_pos.x, _pos.y, _pos.z, wrapf(_yaw, -PI, PI), _pitch, flags]


## Vanish in a puff (send = tell the others too).
func pop(send: bool) -> void:
	if _popped:
		return
	_popped = true
	if send:
		Net.send_event({"kind": "decoy_pop", "d": peer_id})
	var feet := global_position
	var root := SpellFx.effect_root(get_parent(), feet + Vector3.UP * 1.0, 2.0)
	var puff := FireFx.smoke(root, 24, 1.2, 1.2, 0.8)
	puff.one_shot = true
	puff.explosiveness = 0.9
	var pm := puff.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.35, 0.9, 0.35)
	pm.color_ramp = MoneyRain._ramp([0.0, 0.1, 1.0], [Color(0.8, 0.78, 0.86, 0), Color(0.8, 0.78, 0.86, 0.8), Color(0.6, 0.6, 0.66, 0)])
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.spread = 180.0
	split_fx(get_parent(), feet, player_color)
	queue_free()


func _process(delta: float) -> void:
	if _popped:
		return
	super._process(delta)
	if not _sim:
		_silence += delta
		if _silence > SILENCE_LIMIT:
			pop(false)


func _physics_process(delta: float) -> void:
	if not _sim or _popped:
		return
	_life += delta
	if _life > spell.lifetime or _pos.y < -1000.0:
		pop(true)
		return
	_think(delta)
	_move(delta)
	push_state(_state())
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = SEND_INTERVAL
		Net.send_event({"kind": "decoy", "d": peer_id, "s": _state()})


func _think(delta: float) -> void:
	if _aim_t > 0.0:
		_aim_t -= delta
		if _panic:
			# Glancing around wildly.
			_jitter -= delta
			if _jitter <= 0.0:
				_jitter = _rng.randf_range(0.18, 0.4)
				_target_yaw = _yaw + _rng.randf_range(0.7, 2.2) * (1.0 if _rng.randf() < 0.5 else -1.0)
				_pitch = _rng.randf_range(-0.25, 0.45)
			if _aim_t <= 0.0:
				_fire_panic()
		elif is_instance_valid(_aim_at):
			var to := _aim_at.global_position + Vector3.UP * 1.2 - (_pos + Vector3.UP * 0.6)
			_target_yaw = atan2(-to.x, -to.z)
			_pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -1.2, 1.2)
		if _aim_t <= 0.0:
			_pitch = 0.0
			_panic = false
			_next_act = _rng.randf_range(0.3, 1.0)
	_yaw = lerp_angle(_yaw, _target_yaw, 1.0 - exp(-(10.0 if _aim_t > 0.0 else 4.0) * delta))
	if _dash_t >= 0.0 or _aim_t > 0.0:
		return
	_next_act -= delta
	if _next_act > 0.0:
		return
	_next_act = _rng.randf_range(0.8, 2.4)
	var r := _rng.randf()
	if r < 0.2:
		_start_dash()
	elif r < 0.28 and _on_floor:
		_panic = true
		_jitter = 0.0
		_aim_t = _rng.randf_range(2.0, 2.8)
	elif r < 0.4 and _on_floor:
		_start_aim()
	elif r < 0.56 and _on_floor:
		_vy = JUMP_SPEED
		_on_floor = false
	else:
		_target_yaw = _yaw + _rng.randf_range(-1.5, 1.5)


func _start_dash() -> void:
	var side := _rng.randf_range(-0.9, 0.9)
	var a := _yaw + side
	_dash_dir = Vector3(-sin(a), 0.0, -cos(a))
	_dash_t = 0.0
	_target_yaw = a
	_dash_fx(_dash_dir)
	Net.send_event({"kind": "decoy", "d": peer_id, "s": _state(), "dash": Net._vec(_dash_dir)})


func _dash_fx(dir: Vector3) -> void:
	var dash := load("res://spells/dash.tres") as DashSpell
	if dash:
		dash.cast_remote(self, Transform3D(Basis.IDENTITY, global_position), dir)


## The panicked shot: a sniper beam along wherever it happens to look (no damage).
func _fire_panic() -> void:
	var look := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch) * Vector3.FORWARD
	var feet := _pos - Vector3.UP * FOOT_OFFSET
	var from := feet + Basis(Vector3.UP, _yaw) * Vector3(0.22, 1.3, -0.45)
	var space := get_world_3d().direct_space_state
	var hit := _ray(space, from, from + look * 400.0)
	var to: Vector3 = hit.position if not hit.is_empty() else from + look * 400.0
	_shot_fx(from, to)
	Net.send_event({"kind": "decoy", "d": peer_id, "s": _state(), "shot": [Net._vec(from), Net._vec(to)]})


func _shot_fx(from: Vector3, to: Vector3) -> void:
	play_cast()
	var sniper := load("res://spells/sniper.tres") as SniperSpell
	if sniper:
		sniper.cast_remote(self, Transform3D(Basis.IDENTITY, from), to - from)


## Fake sniper aim at the nearest other player in sight (skipped if there is none).
func _start_aim() -> void:
	var best: Node3D = null
	var best_d := 120.0
	for node in get_tree().get_nodes_in_group("remote_player"):
		var a := node as RemotePlayer
		if a == null or a is Decoy or not a.visible or a.is_dead():
			continue
		var d := a.global_position.distance_to(_pos)
		if d < best_d:
			best_d = d
			best = a
	if best == null:
		_target_yaw = _yaw + _rng.randf_range(-2.0, 2.0)
		return
	_aim_at = best
	_aim_t = _rng.randf_range(AIM_TIME.x, AIM_TIME.y)


func _move(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var feet := _pos - Vector3.UP * FOOT_OFFSET
	var horiz := Vector3.ZERO
	if _dash_t >= 0.0:
		_dash_t += delta
		horiz = _dash_dir * (DASH_DISTANCE / DASH_TIME)
		if _dash_t >= DASH_TIME:
			_dash_t = -1.0
	elif _aim_t <= 0.0:
		horiz = Vector3(-sin(_yaw), 0.0, -cos(_yaw)) * spell.run_speed
	if horiz != Vector3.ZERO:
		var dir := horiz.normalized()
		var ahead := _ray(space, feet + Vector3.UP * 0.6, feet + Vector3.UP * 0.6 + dir * (horiz.length() * delta + 0.8))
		if not ahead.is_empty() and (ahead.normal as Vector3).y < 0.6:
			# Wall or cliff ahead: turn away.
			horiz = Vector3.ZERO
			_dash_t = -1.0
			_target_yaw = _yaw + PI + _rng.randf_range(-0.8, 0.8)
	_vy -= GRAVITY * delta
	var next := feet + horiz * delta + Vector3.UP * _vy * delta
	var g := _ray(space, next + Vector3.UP * 0.9, next + Vector3.DOWN * 1.2)
	var lake := get_tree().get_first_node_in_group("lake") as Lake
	if lake and lake.depth_at(next) > 0.6:
		# Don't run into the lake.
		next = Vector3(feet.x, next.y, feet.z)
		_target_yaw = _yaw + PI + _rng.randf_range(-0.6, 0.6)
	if not g.is_empty() and _vy <= 0.0 and (next.y <= g.position.y + 0.05 or (_on_floor and next.y - g.position.y < 0.7)):
		if (g.normal as Vector3).y < 0.55:
			# Too steep to run up.
			next = Vector3(feet.x, next.y, feet.z)
			_target_yaw = _yaw + PI + _rng.randf_range(-0.8, 0.8)
		next.y = maxf(g.position.y, next.y if (g.normal as Vector3).y < 0.55 else g.position.y)
		_vy = 0.0
		_on_floor = true
	else:
		_on_floor = false
	_pos = next + Vector3.UP * FOOT_OFFSET


func _ray(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collision_mask = 1
	q.exclude = _exclude
	return space.intersect_ray(q)
