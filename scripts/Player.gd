extends CharacterBody3D

const SPEED = 5.0
const SPRINT_MULTIPLIER = 1.7
const SWIM_SPEED = 0.55
## Feet this deep in the lake count as swimming (the swim floor is at Lake.SWIM_FLOOR).
const SWIM_DEPTH = 0.9
const FOOT_OFFSET = 0.9
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.003
const VIEW_DISTANCES := [900.0, 1800.0, 3000.0]
## Extra field of view (degrees) at full sprint and at the peak of a dash.
const SPRINT_FOV := 7.0
const DASH_FOV := 16.0
## Dash speed profile: full speed, easing to END_SPEED of it over the last part.
const DASH_EASE_START := 0.55
const DASH_END_SPEED := 0.3
## Fraction of the dash speed carried out of the dash as decaying (horizontal) momentum,
## and as upward velocity after dashing upwards.
const DASH_CARRY := 0.35
const DASH_CARRY_UP := 0.12
const STARTING_SPELLS := [preload("res://spells/dash.tres"), preload("res://spells/sniper.tres"),
	preload("res://spells/chain.tres"), preload("res://spells/sword.tres"),
	preload("res://spells/minigun.tres"), preload("res://spells/shield_bubble.tres"),
	preload("res://spells/shield_wall.tres"), preload("res://spells/black_hole.tres"),
	preload("res://spells/fireball.tres"), preload("res://spells/inferno.tres")]
## Spells that start in the satchel (drag them onto a page to use them).
const STARTING_BAG := [preload("res://spells/money_rain.tres"), preload("res://spells/smoke.tres"),
	preload("res://spells/spinjitzu.tres"), preload("res://spells/gravity_field.tres"), preload("res://spells/decoy.tres"),
	preload("res://spells/magic_missile.tres"), preload("res://spells/homing_missile.tres")]
## Seconds the scope stays up after an aimed spell fired, and to raise/lower it.
const SCOPE_HOLD := 0.35
const SCOPE_TIME := 0.18
## Seconds between being struck down and respawning, and the knock-back when struck.
const DEATH_TIME := 3.0
const DEATH_KNOCKBACK := 5.0
## Chain pulls: how fast the body's velocity turns towards the pull, how long a pull lasts
## without being refreshed (remote chains update ~15x/s), the share of the speed kept as
## momentum when a pull lets go, and how long to ignore a chain after breaking free of it.
const PULL_ACCEL := 45.0
const PULL_TIMEOUT := 0.35
const PULL_CARRY := 0.4
const CHAIN_IGNORE_TIME := 1.5

signal damaged(amount: float, from_id: int)
signal died(from_id: int)
## One of this player's spells hit another player.
signal hit_landed(target_id: int)
## This player's chain caught a player (peer id) or a chainable object (-1).
signal chain_caught(target_id: int)
## Another player's chain caught this player.
signal chained(by_id: int)

@export var max_mana: float = 100.0
@export var mana_regen: float = 8.0
@export var max_health: float = 100.0

@onready var camera: Camera3D = $Camera3D
@onready var grimoire: Grimoire = $Camera3D/Grimoire
## Items: the grimoire's pages are the hotbar, plus the satchel (Inventory).
var inventory: Inventory

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var mana: float = max_mana
## Seconds without casting before mana regenerates again.
const REGEN_DELAY := 1.0
var _regen_wait := 0.0
var health: float = max_health
## 0..1: strength of the dash effects (screen blur, FOV), rises during a dash and eases out.
var dash_fx := 0.0
var dash_direction := Vector3.FORWARD
## Direction sent to other players with a cast; spells may replace it (the dash sends its
## direction, the sniper beam direction * length).
var cast_direction := Vector3.FORWARD
## 0..1: how far an aimed spell's scope is raised (zoom, HUD overlay).
var scope := 0.0
var _scope_hold := 0.0
var _aim_zoom := 1.0
var _aim_move := 1.0
## The aimed spell raises a scope (see Spell.aim_scope).
var _aim_scope := false
## Cast is held down on a hold_fire spell (rapid fire).
var _fire_held := false
var _shake := 0.0
## Seconds left until respawn while dead, and the eased 0..1 fall of the view.
var _dead := 0.0
var _death_fall := 0.0
var _death_pitch := 0.0
var _dash_t := -1.0
var _dash_duration := 0.0
var _dash_speed := 0.0
var _dash_carry := Vector3.ZERO
var _base_fov := 75.0
## Seconds since the player last stood on the floor (short gaps don't count as airborne).
var _off_floor := 0.0
var _sprint_fov := 0.0
var _net_timer := 0.0
var _lake: Lake
## 0 on land, 1 while swimming (eased), drives the bobbing.
var _swim := 0.0
var _swim_time := 0.0
var _bob := 0.0
@onready var _camera_y := camera.position.y
@onready var _camera_z := camera.position.z
## Eye height the physics step wants (bobbing, death fall); _process places the camera there.
@onready var _cam_y := _camera_y
## Body position before the latest physics step. The body only moves 60 times a second, but
## the view turns every frame: at high frame rates the camera would hop forward in steps while
## turning smoothly, which looked choppy / doubled. _process puts the camera between the last
## two physics positions instead (adds at most one tick of positional latency, none to looking).
var _phys_prev := Vector3.ZERO
var _phys_prev_valid := false
## Teleports (spawn, respawn) aren't smoothed over.
const INTERP_MAX_STEP := 4.0
## View angles, the only source of the body's and camera's rotation: every frame the body gets
## exactly (0, yaw, 0) and the camera (pitch, 0, roll) (see _apply_look). Incremental rotate_*
## calls could leave the body tilted or the camera turned against it, which showed up as
## inverted movement and a skewed view.
var _yaw := 0.0
var _pitch := 0.0
## Chain pulls on this body: key -> {"point", "node", "speed", "age", "over"}. "grapple" =
## our own chain hauling us to a surface, "tow_<id>" = another player's chain holding us.
## "over" = seconds the pull has been overpowered (see _update_pulls).
var _pulls := {}
var _pulled := false
## Burning (FirePatch): seconds left, damage per second, who lit it, and the damage tick timer.
var _burn_time := 0.0
var _burn_dps := 0.0
var _burn_by := -1
var _burn_tick := 0.0
const BURN_TICK := 0.25
## Caster id -> seconds their chain events are ignored (after breaking free of it).
var _chain_ignore := {}
## Movement speed factor from spells (Spinjitzu).
var move_boost := 1.0
## Gravity Field: seconds the downward slam still holds (refreshed while inside) and its speed.
var _slam_t := 0.0
var _slam_speed := 0.0
## Cosmetic roll (swimming, dash lean, death) and the pitch shown while dead.
var _roll := 0.0
const MAX_PITCH := PI / 2.5

func _ready() -> void:
	_yaw = rotation.y
	_pitch = camera.rotation.x
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Settings.setting_changed.connect(_on_setting_changed)
	for key in ["fov", "view_distance"]:
		_on_setting_changed(key, Settings.get_value(key))
	inventory = Inventory.new()
	inventory.name = "Inventory"
	inventory.setup(self)
	add_child(inventory)
	grimoire.spell_cast.connect(_on_spell_cast)
	grimoire.aim_started.connect(func(spell: Spell) -> void:
		_aim_zoom = spell.aim_zoom
		_aim_move = spell.aim_move_factor
		_aim_scope = spell.aim_scope)
	grimoire.aim_ended.connect(func(_spell: Spell, fired: bool) -> void:
		_scope_hold = SCOPE_HOLD if fired and _aim_scope else 0.0)
	Net.event_received.connect(_on_net_event)
	_apply_balance()
	Balance.changed.connect(_apply_balance)
	SpellFx.prewarm(self)
	for i in STARTING_SPELLS.size():
		if grimoire.get_spell_on_page(i) == null:
			grimoire.set_spell(i, STARTING_SPELLS[i])
	for i in mini(STARTING_BAG.size(), Inventory.BAG_SIZE):
		if inventory.get_item(Inventory.BAG, i) == null:
			inventory.bag[i] = STARTING_BAG[i]
	inventory.changed.emit()

## [player] values from the balance config.
func _apply_balance() -> void:
	var was_full := mana >= max_mana and health >= max_health
	max_health = Balance.player_value("max_health", max_health)
	max_mana = Balance.player_value("max_mana", max_mana)
	mana_regen = Balance.player_value("mana_regen", mana_regen)
	if was_full:
		mana = max_mana
		health = max_health
	mana = minf(mana, max_mana)
	health = minf(health, max_health)

func _on_spell_cast(spell: Spell) -> void:
	Net.send_cast(spell.resource_path, grimoire.get_cast_origin().origin, cast_direction)

func _on_setting_changed(key: String, value: Variant) -> void:
	match key:
		"fov":
			_base_fov = value
			camera.fov = value
		"view_distance":
			camera.far = VIEW_DISTANCES[clampi(value, 0, VIEW_DISTANCES.size() - 1)]

## True while the pause menu, the map or the inventory is open. Offline the menu and map pause
## the whole game; online the world keeps running (gravity, damage, other players) and only the
## controls are ignored. The inventory never pauses.
func is_input_blocked() -> bool:
	if is_menu_open():
		return true
	var inv := get_tree().get_first_node_in_group("inventory_ui")
	return inv != null and inv.is_open()

## The pause menu or the map covers the screen (HUD hidden).
func is_menu_open() -> bool:
	for group in ["pause_menu", "map_overlay"]:
		var ui := get_tree().get_first_node_in_group(group)
		if ui and ui.is_open():
			return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if is_input_blocked() or is_dead():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = MOUSE_SENSITIVITY * Settings.get_value("mouse_sensitivity")
		# Slower turning while zoomed, so the aim moves the same on screen.
		sens *= tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(_base_fov) * 0.5)
		var invert := -1.0 if Settings.get_value("invert_y") else 1.0
		_yaw = wrapf(_yaw - event.relative.x * sens, -PI, PI)
		_pitch = clampf(_pitch - event.relative.y * sens * invert, -MAX_PITCH, MAX_PITCH)
		_apply_look()
		grimoire.add_look_sway(event.relative * float(Settings.get_value("view_bob")))
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Clicking back into the window (e.g. after alt-tab) recaptures the mouse.
		if event is InputEventMouseButton and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		return
	for i in 10:
		if event.is_action_pressed("page_%d" % (i + 1)):
			grimoire.go_to_page(i)
			return
	if event.is_action_pressed("next_page") or event.is_action_pressed("prev_page"):
		# A running spell may use the wheel itself (the directional shield's size).
		var channel := grimoire.get_channel()
		var dir := 1 if event.is_action_pressed("next_page") else -1
		if channel and channel.has_method("scroll"):
			channel.scroll(-dir)
		elif dir > 0:
			grimoire.flip_next()
		else:
			grimoire.flip_previous()
	elif event.is_action_pressed("cast"):
		if grimoire.is_channeling():
			grimoire.cancel_channel()
			return
		cast_direction = -camera.global_basis.z
		var spell := grimoire.get_selected_spell()
		if spell and spell.aimed:
			grimoire.start_aim(self)
		elif spell and spell.hold_fire:
			_fire_held = true
		else:
			grimoire.try_cast(self, cast_direction)
	elif event.is_action_released("cast"):
		grimoire.release_aim()
		_fire_held = false

## View direction and eye position, for aimed spells.
func get_aim_direction() -> Vector3:
	cast_direction = -camera.global_basis.z
	return cast_direction

func get_aim_origin() -> Vector3:
	return camera.global_position

## Kicks the view up a little and shakes it (e.g. firing the sniper beam).
func add_recoil(amount: float) -> void:
	_pitch = clampf(_pitch + amount, -MAX_PITCH, MAX_PITCH)
	_shake = 1.0
	_apply_look()

## Camera shake (0..1), e.g. a heavy impact nearby.
func add_shake(amount: float) -> void:
	_shake = maxf(_shake, clampf(amount, 0.0, 1.0))

## A shove: horizontal part as decaying momentum (survives the movement code), vertical as a hop.
func add_knockback(v: Vector3) -> void:
	_dash_carry += Vector3(v.x, 0.0, v.z)
	velocity.y = maxf(velocity.y, v.y)

## Upward thrust (e.g. the Infernal Torrent aimed at the ground): adds `dv` to the vertical
## speed, but doesn't push it beyond `max_up`.
func add_lift(dv: float, max_up: float) -> void:
	if velocity.y < max_up:
		velocity.y = minf(velocity.y + dv, max_up)

## Sets the view direction (spawn / respawn).
func set_look(yaw: float, pitch: float) -> void:
	_yaw = wrapf(yaw, -PI, PI)
	_pitch = clampf(pitch, -MAX_PITCH, MAX_PITCH)
	_apply_look()

## Writes the view angles to the body and camera. The body only ever turns about the vertical.
func _apply_look() -> void:
	rotation = Vector3(0.0, _yaw, 0.0)
	var pitch := _pitch
	if is_dead():
		var e := 1.0 - pow(1.0 - _death_fall, 3.0)
		pitch = lerpf(_death_pitch, 1.1, e)
	camera.rotation = Vector3(pitch, 0.0, _roll)

## Pause menu "Reset view": levels the view and stops any leftover motion (momentum, dash,
## scope, shake, roll) where the player stands, without moving them.
func reset_view() -> void:
	grimoire.cancel_aim()
	_dash_t = -1.0
	_dash_carry = Vector3.ZERO
	dash_fx = 0.0
	scope = 0.0
	_scope_hold = 0.0
	_shake = 0.0
	_roll = 0.0
	velocity = Vector3.ZERO
	_cam_y = _camera_y
	_phys_prev_valid = false
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	camera.fov = _base_fov
	var flat := Vector3(-global_basis.z.x, 0.0, -global_basis.z.z)
	set_look(atan2(-flat.x, -flat.z) if flat.length_squared() > 0.0001 else _yaw, 0.0)

## Life paid for a spell (Spell.hp_cost): like damage, but never from anyone.
func spend_health(amount: float) -> void:
	take_damage(amount, Net.my_id)

func has_mana(amount: float) -> bool:
	return mana >= amount

func spend_mana(amount: float) -> void:
	mana = maxf(0.0, mana - amount)
	if amount > 0.0:
		_regen_wait = REGEN_DELAY

## from_id: peer id of the attacker (-1 = unknown / the world).
func take_damage(amount: float, from_id: int = -1) -> void:
	if health <= 0.0:
		return
	health = maxf(0.0, health - amount)
	damaged.emit(amount, from_id)
	if health <= 0.0:
		_die(from_id)

func is_dead() -> bool:
	return _dead > 0.0

## Struck down: tell the others, get knocked back away from the attacker while the view falls
## (others see the death animation), then respawn after DEATH_TIME.
func _die(from_id: int) -> void:
	died.emit(from_id)
	Net.send_event({"kind": "death", "by": from_id})
	grimoire.cancel_aim()
	_pulls.clear()
	_burn_time = 0.0
	_dash_t = -1.0
	_dash_carry = Vector3.ZERO
	_dead = DEATH_TIME
	_death_fall = 0.0
	_death_pitch = _pitch
	var away := global_basis.z
	var remotes := get_tree().current_scene.get_node_or_null("RemotePlayers")
	if remotes and remotes.has_method("avatar"):
		var a: Node3D = remotes.avatar(from_id)
		if a:
			away = global_position - a.global_position
	away.y = 0.0
	velocity = away.normalized() * DEATH_KNOCKBACK + Vector3.UP * 3.0

## Set ablaze (fire pool): burns for `seconds` (refreshed, never shortened), `dps` damage per
## second credited to `from_id`. Water puts it out.
func ignite(seconds: float, dps: float, from_id: int) -> void:
	if is_dead():
		return
	_burn_time = maxf(_burn_time, seconds)
	_burn_dps = maxf(_burn_dps if is_burning() else 0.0, dps)
	_burn_by = from_id

func is_burning() -> bool:
	return _burn_time > 0.0

## Seconds of burning left (HUD).
func get_burn_time() -> float:
	return _burn_time

func _update_burning(delta: float) -> void:
	if not is_burning():
		return
	if _swim > 0.3 or is_dead():
		_burn_time = 0.0
		return
	_burn_time = maxf(0.0, _burn_time - delta)
	_burn_tick -= delta
	if _burn_tick <= 0.0:
		_burn_tick = BURN_TICK
		take_damage(_burn_dps * BURN_TICK, _burn_by)

## Back at the waystone circle with full health and mana.
func _respawn() -> void:
	_dead = 0.0
	_death_fall = 0.0
	velocity = Vector3.ZERO
	var world := get_tree().current_scene.get_node_or_null("World")
	if world and world.has_method("place_player"):
		world.place_player(self)
	_roll = 0.0
	_pitch = 0.0
	_cam_y = _camera_y
	_phys_prev_valid = false
	_apply_look()
	health = max_health
	mana = max_mana

func confirm_hit(target_id: int) -> void:
	hit_landed.emit(target_id)
	# A decoy that was hit vanishes (for everyone).
	Decoy.struck(get_tree(), target_id)

func _on_net_event(from_id: int, event: Dictionary) -> void:
	match str(event.get("kind", "")):
		"hit":
			if int(event.get("target", -1)) == Net.my_id:
				take_damage(float(event.get("damage", 0.0)), from_id)
				# Optional extras: set alight (burn s, bdps) and shoved (push velocity).
				if event.has("burn") and not is_dead():
					ignite(float(event.burn), float(event.get("bdps", 0.0)), from_id)
				if event.has("push") and not is_dead():
					add_knockback(Net._to_vec(event.push))
		"chain":
			# Another player's chain holds us: we pull ourselves towards them (they can't move us).
			if int(event.get("tg", -1)) != Net.my_id or int(event.get("st", 0)) != ChainCast.Phase.TOWING \
					or is_dead() or _chain_ignore.has(from_id):
				return
			var remotes := get_tree().current_scene.get_node_or_null("RemotePlayers")
			var a: Node3D = remotes.avatar(from_id) if remotes and remotes.has_method("avatar") else null
			if a == null:
				return
			var key := "tow_%d" % from_id
			var fresh := not _pulls.has(key)
			set_pull(key, a.global_position + Vector3.UP * ChainCast.CHEST, float(event.get("sp", 13.0)), a)
			if fresh:
				chained.emit(from_id)
		"chain_end":
			clear_pull("tow_%d" % from_id)
			_chain_ignore.erase(from_id)
		"fireball":
			Fireball.explode(get_tree().current_scene, load("res://spells/fireball.tres"),
				Net._to_vec(event.get("p")), Net._to_vec(event.get("n")), from_id, null)
		"missile_boom":
			var ms := load(str(event.get("s", ""))) as MissileSpell
			if ms:
				Missile.explode(get_tree().current_scene, ms, Net._to_vec(event.get("p")), Net._to_vec(event.get("n")),
					from_id, null)
		"chain_break":
			# The one we held broke free.
			if int(event.get("owner", -1)) == Net.my_id:
				var chain := grimoire.get_channel() as ChainCast
				if chain and chain.target_id == from_id:
					chain.snap()


## Adds/refreshes a chain pull towards `point` (or `node`'s chest while it exists).
func set_pull(key: String, point: Vector3, speed: float, node: Node3D = null) -> void:
	var p: Dictionary = _pulls.get(key, {"over": 0.0})
	p["point"] = point
	p["node"] = node
	p["speed"] = speed
	p["age"] = 0.0
	_pulls[key] = p


func clear_pull(key: String) -> void:
	_pulls.erase(key)


## Seconds the pull has been overpowered by other forces (0 = it is winning).
func get_pull_overpower(key: String) -> float:
	return _pulls[key].over if _pulls.has(key) else 0.0


## Held by another player's chain.
func is_chained() -> bool:
	for key in _pulls:
		if key.begins_with("tow_"):
			return true
	return false


## Sums the chain pulls (as velocities) and tracks how long each has been overpowered: `own`
## is the body's own motion (walking, momentum, a dash). A pull is overpowered while own motion
## plus the other pulls leave it less than ChainSpell.OVERPOWER_FRACTION of its speed along
## the chain - sprinting away only slows it, a dash or a chain the other way stop it. A
## stranger's chain overpowered for ChainSpell.BREAK_TIME is broken (its caster is told).
func _update_pulls(delta: float, own: Vector3) -> Vector3:
	var vecs := {}
	var total := Vector3.ZERO
	for key in _pulls.keys():
		var p: Dictionary = _pulls[key]
		p.age += delta
		if p.age > PULL_TIMEOUT:
			_pulls.erase(key)
			continue
		if is_instance_valid(p.node):
			p.point = (p.node as Node3D).global_position + Vector3.UP * ChainCast.CHEST
		var to: Vector3 = p.point - global_position
		var v: Vector3 = to.normalized() * float(p.speed) if to.length() > 0.6 else Vector3.ZERO
		vecs[key] = v
		total += v
	for key in vecs:
		var p: Dictionary = _pulls[key]
		var v: Vector3 = vecs[key]
		var progress: float = v.normalized().dot(total + own) if v != Vector3.ZERO else INF
		if progress < float(p.speed) * ChainSpell.OVERPOWER_FRACTION:
			p.over += delta
		else:
			p.over = maxf(0.0, p.over - delta * 2.0)
		if key.begins_with("tow_") and p.over >= ChainSpell.BREAK_TIME:
			var by := int(key.trim_prefix("tow_"))
			Net.send_event({"kind": "chain_break", "owner": by})
			_pulls.erase(key)
			_chain_ignore[by] = CHAIN_IGNORE_TIME
			total -= v
	return total

## Gravity Field: forced down at `speed` m/s while this keeps being called (dashes and chain
## grapples are cut short).
func slam(speed: float) -> void:
	if is_dead():
		return
	_slam_t = 0.12
	_slam_speed = speed
	if is_dashing():
		_dash_t = -1.0
	clear_pull("grapple")


func is_slammed() -> bool:
	return _slam_t > 0.0


## Bounceshroom: launched with velocity `v` – the vertical part directly, the horizontal part as
## momentum (the movement code would overwrite it otherwise).
func bounce(v: Vector3) -> void:
	if is_dead():
		return
	_dash_t = -1.0
	velocity.y = v.y
	_dash_carry = Vector3(v.x, 0.0, v.z) + _dash_carry * 0.5
	_off_floor = 0.2


func heal(amount: float) -> void:
	health = minf(max_health, health + amount)

func is_dashing() -> bool:
	return _dash_t >= 0.0

## Where a dash goes: straight along the view, up and down included.
func get_dash_direction(look: Vector3) -> Vector3:
	return look.normalized() if look.length_squared() > 0.0001 else -camera.global_basis.z

## Dash `distance` metres along `dir` in `duration` seconds (gravity is suspended meanwhile).
func start_dash(dir: Vector3, distance: float, duration: float) -> void:
	dash_direction = dir.normalized()
	_dash_duration = maxf(duration, 0.05)
	# Mean of the speed profile below, so the dash covers `distance`.
	var mean := 1.0 - (1.0 - DASH_END_SPEED) * (1.0 - DASH_EASE_START) * 0.5
	_dash_speed = distance / (_dash_duration * mean)
	_dash_t = 0.0
	_dash_carry = Vector3.ZERO

func _process(delta: float) -> void:
	_place_camera()
	if is_dead():
		_dead -= delta
		if _dead <= 0.0:
			_respawn()
	# No regeneration while casting (a channel – chain, ward, torrent –, aiming, held fire) or
	# spending mana, and only REGEN_DELAY seconds after the last of it.
	if grimoire.is_channeling() or grimoire.is_aiming() or _fire_held:
		_regen_wait = REGEN_DELAY
	else:
		_regen_wait = maxf(0.0, _regen_wait - delta)
	if _regen_wait <= 0.0:
		mana = minf(max_mana, mana + mana_regen * delta)
	for id in _chain_ignore.keys():
		_chain_ignore[id] -= delta
		if _chain_ignore[id] <= 0.0:
			_chain_ignore.erase(id)
	if grimoire.is_aiming() and is_input_blocked():
		grimoire.cancel_aim()
	if _fire_held:
		var held := grimoire.get_selected_spell()
		if is_input_blocked() or is_dead() or not Input.is_action_pressed("cast"):
			_fire_held = false
		elif held and held.hold_fire and not grimoire.is_flipping():
			held.hold(self, grimoire, delta)
	_update_burning(delta)
	_net_timer -= delta
	if _net_timer <= 0.0:
		_net_timer = 1.0 / Net.SEND_RATE
		var flags := 0
		if _off_floor < 0.15:
			flags |= Net.FLAG_ON_FLOOR
		if _swim > 0.5:
			flags |= Net.FLAG_SWIMMING
		if is_dashing():
			flags |= Net.FLAG_DASHING
		if grimoire.is_aiming() and _aim_scope:
			flags |= Net.FLAG_AIMING
		if is_dead():
			flags |= Net.FLAG_DEAD
		if is_burning():
			flags |= Net.FLAG_BURNING
		Net.send_state(global_position + Vector3.UP * _bob, _yaw, _pitch, flags)

## Camera between the previous and the current physics position (see _phys_prev).
func _place_camera() -> void:
	var offset := Vector3.ZERO
	if _phys_prev_valid:
		var step := global_position - _phys_prev
		if step.length() < INTERP_MAX_STEP:
			var f := Engine.get_physics_interpolation_fraction()
			# From the current position back towards the previous one, in body space (yaw only).
			offset = global_basis.inverse() * (-step * (1.0 - f))
	camera.position = Vector3(0.0, _cam_y, _camera_z) + offset


func _physics_process(delta: float) -> void:
	_phys_prev = global_position
	_phys_prev_valid = true
	_off_floor = 0.0 if is_on_floor() else _off_floor + delta
	_slam_t = maxf(0.0, _slam_t - delta)
	if is_dashing():
		_dash_step(delta)
		return
	if is_dead():
		_dead_step(delta)
		return
	var swimming := _is_swimming()
	_swim = move_toward(_swim, 1.0 if swimming else 0.0, delta * 1.5)
	var controls := not is_input_blocked()
	if controls and Input.is_action_pressed("jump") and is_on_floor() and not swimming:
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if controls else Vector2.ZERO
	var sprint_held := controls and Input.is_action_pressed("sprint") and not (grimoire.is_aiming() and _aim_scope)
	var speed := SPEED * (SPRINT_MULTIPLIER if sprint_held else 1.0)
	speed = lerpf(speed, SPEED * SWIM_SPEED, _swim)
	speed *= lerpf(1.0, _aim_move, scope) * move_boost
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var own := direction * speed + _dash_carry
	var pull := _update_pulls(delta, own)
	if pull != Vector3.ZERO:
		# Hauled by a chain: the velocity turns towards own motion + pull; gravity fades out
		# with the pull's strength (a balanced tug of war lets the body drop).
		_pulled = true
		var hold := clampf(pull.length() / 10.0, 0.0, 1.0)
		var target := own + pull
		var vy := move_toward(velocity.y, pull.y, PULL_ACCEL * hold * delta)
		velocity = velocity.move_toward(Vector3(target.x, velocity.y, target.z), PULL_ACCEL * delta)
		velocity.y = vy
		if not is_on_floor():
			velocity.y -= gravity * (1.0 - hold) * delta
	else:
		if _pulled:
			# Let go: keep some of the swing as momentum.
			_pulled = false
			_dash_carry = Vector3(velocity.x, 0.0, velocity.z) * PULL_CARRY
		if not is_on_floor():
			velocity.y -= gravity * delta
		if direction:
			velocity.x = direction.x * speed + _dash_carry.x
			velocity.z = direction.z * speed + _dash_carry.z
		else:
			velocity.x = move_toward(velocity.x - _dash_carry.x, 0, speed) + _dash_carry.x
			velocity.z = move_toward(velocity.z - _dash_carry.z, 0, speed) + _dash_carry.z
	_dash_carry = _dash_carry.lerp(Vector3.ZERO, 1.0 - exp(-(4.0 if is_on_floor() else 1.5) * delta))
	if _slam_t > 0.0:
		# Gravity Field: dragged down hard.
		velocity.y = minf(velocity.y, -_slam_speed)
		_dash_carry *= 0.8

	move_and_slide()
	if is_on_wall():
		_dash_carry = _dash_carry.slide(get_wall_normal())
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	grimoire.set_move_amount(ground_speed / SPEED * float(Settings.get_value("view_bob")) * (1.0 - _swim) if is_on_floor() else 0.0)
	var sprinting := sprint_held and ground_speed > SPEED * 1.2 and not swimming
	_view_effects(delta, sprinting)
	_swim_bob(delta, ground_speed)


## Knocked back and sliding to a stop; no control.
func _dead_step(delta: float) -> void:
	_pulls.clear()
	if not is_on_floor():
		velocity.y -= gravity * delta
	var friction := 8.0 if is_on_floor() else 1.0
	velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	velocity.z = move_toward(velocity.z, 0.0, friction * delta)
	move_and_slide()
	_death_fall = minf(1.0, _death_fall + delta / 0.9)
	grimoire.set_move_amount(0.0)
	_view_effects(delta, false)
	_swim_bob(delta, 0.0)


func _dash_step(delta: float) -> void:
	_dash_t += delta
	var u := _dash_t / _dash_duration
	var factor := lerpf(1.0, DASH_END_SPEED, smoothstep(DASH_EASE_START, 1.0, u))
	var v := dash_direction * _dash_speed * factor
	velocity = v
	# Chains can't hold a dash, but it counts as pulling against them.
	_update_pulls(delta, v)
	move_and_slide()
	if u >= 1.0:
		_dash_t = -1.0
		var flat := Vector3(dash_direction.x, 0.0, dash_direction.z)
		_dash_carry = flat * _dash_speed * DASH_CARRY
		velocity.y = maxf(dash_direction.y, 0.0) * _dash_speed * DASH_CARRY_UP
		if is_on_wall():
			_dash_carry = _dash_carry.slide(get_wall_normal())
	grimoire.set_move_amount(0.0)
	_view_effects(delta, false)
	_swim_bob(delta, 0.0)


## Field of view: widening while sprinting and dashing, zoom while an aimed spell's scope is
## up; dash_fx for the HUD screen effect; recoil shake.
func _view_effects(delta: float, sprinting: bool) -> void:
	if is_dashing():
		dash_fx = minf(1.0, dash_fx + delta * 14.0)
	else:
		dash_fx = maxf(0.0, dash_fx - delta * 3.0)
	_sprint_fov = lerpf(_sprint_fov, 1.0 if sprinting else 0.0, 1.0 - exp(-5.0 * delta))
	var dash_ease := dash_fx * dash_fx * (3.0 - 2.0 * dash_fx)
	var fov := clampf(_base_fov + _sprint_fov * SPRINT_FOV + dash_ease * DASH_FOV, 1.0, 170.0)
	_scope_hold = maxf(0.0, _scope_hold - delta)
	var scoped := (grimoire.is_aiming() and _aim_scope) or _scope_hold > 0.0
	scope = move_toward(scope, 1.0 if scoped else 0.0, delta / SCOPE_TIME)
	if scope > 0.0:
		var zoom := lerpf(1.0, _aim_zoom, scope * scope * (3.0 - 2.0 * scope))
		fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(fov) * 0.5) / zoom))
	camera.fov = fov
	_shake = move_toward(_shake, 0.0, delta * 3.0)
	camera.h_offset = randf_range(-1.0, 1.0) * 0.03 * _shake * _shake
	camera.v_offset = randf_range(-1.0, 1.0) * 0.03 * _shake * _shake


func _is_swimming() -> bool:
	if _lake == null:
		_lake = get_tree().get_first_node_in_group("lake") as Lake
		if _lake == null:
			return false
	return _lake.depth_at(global_position - Vector3.UP * FOOT_OFFSET) > SWIM_DEPTH


## Floating in the water: the head rises and sinks slowly and the view rolls a little,
## a bit faster while paddling along.
func _swim_bob(delta: float, ground_speed: float) -> void:
	_swim_time += delta * (1.0 + ground_speed * 0.12)
	_bob = (sin(_swim_time * 1.9) * 0.07 + sin(_swim_time * 0.7 + 1.3) * 0.04) * _swim
	_cam_y = _camera_y + _bob
	# While dashing the view leans into sideways dashes.
	var lean := -dash_direction.dot(camera.global_basis.x) * 0.05 * dash_fx
	_roll = sin(_swim_time * 0.9) * 0.025 * _swim + lean
	# Keep the book out of the water; it trails back a little during a dash and drops out of
	# view while scoped.
	grimoire.hold_offset = Vector3(0.0, 0.07, 0.0) * _swim + Vector3(0.0, -0.025, 0.04) * dash_fx \
		+ Vector3(0.05, -0.3, 0.08) * scope
	if is_dead():
		# Knocked onto the back: the view drops to the ground, tips up to the sky and rolls,
		# and the book falls away.
		var e := 1.0 - pow(1.0 - _death_fall, 3.0)
		_cam_y = lerpf(_camera_y, -0.7, e)
		_roll = lerpf(0.0, 0.3, e)
		grimoire.hold_offset += Vector3(0.1, -0.5, 0.1) * e
	_apply_look()
