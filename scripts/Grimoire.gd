class_name Grimoire
extends Node3D
## An open spell book held at the right side of the player's view.
## Each spell occupies one page (a two-page spread); the mouse wheel flips between them.
##
## Book-local frame: +X to the right page, -X to the left page, the spine runs along Z
## (-Z = head/top of the pages, +Z = tail/bottom), +Y points out of the pages.

signal page_changed(page_index: int, spell: Spell)
signal page_flip_started(from_page: int, to_page: int)
signal spell_cast(spell: Spell)
signal cast_failed(spell: Spell, reason: CastBlock)
signal aim_started(spell: Spell)
## fired = false when the aim was cancelled.
signal aim_ended(spell: Spell, fired: bool)

enum CastBlock { NONE, FLIPPING, EMPTY_PAGE, ON_COOLDOWN, NOT_ENOUGH_MANA, SPELL_REFUSED, NOT_ENOUGH_LIFE }

## Pages = hotbar slots (number keys 1-0).
@export_range(1, 64) var page_count: int = 10
## Spell per page. Null entries are blank pages.
@export var spells: Array[Spell] = []
@export var flip_duration: float = 0.42

const PAGE_W := 0.12
const PAGE_H := 0.17
const COVER_T := 0.0035
const COVER_M := 0.005
const GUTTER := 0.006
const SPINE_SAG := 0.007
const LEAF_T := 0.0009
const BASE_STACK := 0.0025
const FLIP_START_ANGLE := 0.04
const FLIP_CURL := 1.4
## A jump over several pages takes at most this many times a single flip: all the leaves slip
## over together, staggered, each taking LEAF_SHARE of the whole flip.
const MULTI_FLIP_TIME := 1.25
const LEAF_SHARE := 0.6

var current_page: int = 0

var _cooldowns: Dictionary = {}
## Arcane circle behind each spell symbol = its cooldown: on casting it is spun hard and coasts
## to a stop exactly when the spell is ready (see circle_angle). Per spell: resting angle, the
## angle the current spin started from and how far it turns in total (radians).
var _circle_rest: Dictionary = {}
var _circle_from: Dictionary = {}
var _circle_turn: Dictionary = {}
## The spell drawn on the right page (whose circle turns), and the stop glow.
var _right_spell: Spell
var _flash_t := -1.0
var _last_circle_angle := 0.0
## Spin speed right after casting (rad/s).
const CIRCLE_START_SPEED := 4.0 * TAU
## Only spells with longer cooldowns glow when their circle stops.
const FLASH_MIN_COOLDOWN := 3.0
const FLASH_TIME := 1.0
## Hold-to-aim state (Spell.aimed): the spell being aimed, its caster, time aimed, release asked.
var _aim_spell: Spell
var _aim_caster: Node
var _aim_time := 0.0
var _aim_release := false
var _aim_preview: Node
## A spell effect that is still running (e.g. a chain); flips are blocked and casting
## again calls its cancel() instead.
var _channel: Node
var _face_textures: Dictionary = {}

## Flip state: seconds into the running flip (-1 = none), its pages and direction, the page the
## book should end up on (wheel / number keys; reached by the next flip), and the leaves in
## flight: [{"mi", "mat", "start", "src_h", "dst_h", "landed"}].
var _flip_t: float = -1.0
var _flip_from: int = 0
var _flip_to: int = 0
var _flip_dir: int = 0
var _flip_total := 0.0
var _flip_leaf_time := 0.0
var _flip_landed := 0
var _target_page: int = 0
var _leaves: Array = []

var _rest_xform: Transform3D
## Extra offset from the resting pose in camera space, e.g. held up out of the water while swimming.
var hold_offset := Vector3.ZERO
var _sway := Vector2.ZERO
var _sway_target := Vector2.ZERO
var _bob_phase: float = 0.0
var _bob_amount: float = 0.0
var _kick: float = 0.0
var _shake: float = 0.0

var _book: Node3D
var _block_l: MeshInstance3D
var _block_r: MeshInstance3D
var _leaf: MeshInstance3D
var _cast_origin: Marker3D
var _cast_light: OmniLight3D

var _mat_leather: StandardMaterial3D
var _mat_leather_dark: StandardMaterial3D
var _mat_brass: StandardMaterial3D
var _mat_cloth: StandardMaterial3D
var _mat_gem: StandardMaterial3D
var _mat_edge: ShaderMaterial
var _mat_page_l: ShaderMaterial
var _mat_page_r: ShaderMaterial
var _mat_leaf: ShaderMaterial


func _ready() -> void:
	spells.resize(page_count)
	current_page = clampi(current_page, 0, page_count - 1)
	_target_page = current_page
	_rest_xform = transform
	_create_materials()
	_book = Node3D.new()
	_book.name = "Book"
	add_child(_book)
	_build_covers()
	_build_spine()
	_build_blocks()
	_build_leaf()
	_build_ribbon()
	_build_clasp()
	_cast_origin = Marker3D.new()
	_cast_origin.name = "CastOrigin"
	_cast_origin.position = Vector3(0.0, 0.05, -0.01)
	_book.add_child(_cast_origin)
	_cast_light = OmniLight3D.new()
	_cast_light.light_color = Color(0.6, 0.45, 1.0)
	_cast_light.light_energy = 0.0
	_cast_light.omni_range = 0.6
	_cast_origin.add_child(_cast_light)
	_set_stack(current_page, page_count - 1 - current_page)
	_apply_face(_mat_page_l, "", current_page * 2)
	_apply_face(_mat_page_r, "", current_page * 2 + 1)


func _process(delta: float) -> void:
	for spell in _cooldowns.keys():
		var before: float = _cooldowns[spell]
		_cooldowns[spell] = maxf(0.0, before - delta)
		if before > 0.0 and _cooldowns[spell] <= 0.0:
			_circle_rest[spell] = fmod(_circle_from.get(spell, 0.0) + _circle_turn.get(spell, 0.0), TAU)
			_circle_turn.erase(spell)
			if spell == _right_spell and (spell as Spell).cooldown > FLASH_MIN_COOLDOWN:
				_flash_t = 0.0
	_update_circle(delta)
	_update_flip(delta)
	_update_aim(delta)
	_update_motion(delta)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func get_selected_spell() -> Spell:
	return get_spell_on_page(current_page)


func get_spell_on_page(page: int) -> Spell:
	if page < 0 or page >= spells.size():
		return null
	return spells[page]


func has_spell_on_page(page: int = current_page) -> bool:
	return get_spell_on_page(page) != null


func is_spell_selected(spell: Spell) -> bool:
	return spell != null and not is_flipping() and get_selected_spell() == spell


func set_spell(page: int, spell: Spell) -> void:
	if page < 0 or page >= page_count:
		return
	spells[page] = spell
	if page == current_page and not is_flipping():
		_apply_face(_mat_page_r, "", page * 2 + 1)
		page_changed.emit(current_page, spell)


## Override the artwork on a single page face (face 2*page = left page, 2*page+1 = right page).
func set_face_texture(face: int, texture: Texture2D) -> void:
	if texture:
		_face_textures[face] = texture
	else:
		_face_textures.erase(face)
	if not is_flipping():
		_apply_face(_mat_page_l, "", current_page * 2)
		_apply_face(_mat_page_r, "", current_page * 2 + 1)


func is_flipping() -> bool:
	return _flip_t >= 0.0


func get_cooldown_remaining(spell: Spell) -> float:
	return _cooldowns.get(spell, 0.0)


func flip_next() -> void:
	flip(1)


func flip_previous() -> void:
	flip(-1)


## Flip one page forward/back. Requests made mid-flip add up, and the next flip turns all the
## remaining pages at once.
func flip(direction: int) -> void:
	direction = signi(direction)
	if direction == 0 or is_aiming() or is_channeling():
		return
	_target_page = clampi(_target_page + direction, 0, page_count - 1)
	_try_start_flip()


## Flips straight to `page` (number keys): every page on the way slips over together, in about
## the time of a single flip.
func go_to_page(page: int) -> void:
	if page < 0 or page >= page_count or is_aiming() or is_channeling():
		return
	_target_page = page
	_try_start_flip()


func get_cast_block_reason(caster: Node = null) -> CastBlock:
	if is_flipping():
		return CastBlock.FLIPPING
	var spell := get_selected_spell()
	if spell == null:
		return CastBlock.EMPTY_PAGE
	if get_cooldown_remaining(spell) > 0.0:
		return CastBlock.ON_COOLDOWN
	if caster and caster.has_method("has_mana") and not caster.has_mana(spell.mana_cost):
		return CastBlock.NOT_ENOUGH_MANA
	if spell.hp_cost > 0.0 and caster and "health" in caster and caster.health <= spell.hp_cost:
		return CastBlock.NOT_ENOUGH_LIFE
	if not spell.can_cast(caster, self):
		return CastBlock.SPELL_REFUSED
	return CastBlock.NONE


func can_cast(caster: Node = null) -> bool:
	return get_cast_block_reason(caster) == CastBlock.NONE


func try_cast(caster: Node, direction: Vector3) -> bool:
	var spell := get_selected_spell()
	var reason := get_cast_block_reason(caster)
	if reason != CastBlock.NONE:
		_shake = 1.0
		cast_failed.emit(spell, reason)
		return false
	if caster and caster.has_method("spend_mana"):
		caster.spend_mana(spell.mana_cost)
	if spell.hp_cost > 0.0 and caster and caster.has_method("spend_health"):
		caster.spend_health(spell.hp_cost)
	_start_cooldown(spell)
	spell.cast(caster, get_cast_origin(), direction)
	_kick = maxf(_kick, spell.cast_kick)
	spell_cast.emit(spell)
	return true


## Starts aiming the selected (aimed) spell. Mana and cooldown are checked now but spent on
## firing. The caster must implement get_aim_direction().
func start_aim(caster: Node) -> bool:
	if is_aiming():
		return false
	var spell := get_selected_spell()
	var reason := get_cast_block_reason(caster)
	if reason != CastBlock.NONE:
		_shake = 1.0
		cast_failed.emit(spell, reason)
		return false
	_aim_spell = spell
	_aim_caster = caster
	_aim_time = 0.0
	_aim_release = false
	_aim_preview = spell.make_preview(caster)
	aim_started.emit(spell)
	return true


## Fires as soon as the spell's minimum aim time is reached (at once if it already is).
func release_aim() -> void:
	if is_aiming():
		_aim_release = true


## Drops the aim without casting (nothing is spent).
func cancel_aim() -> void:
	if not is_aiming():
		return
	var spell := _aim_spell
	_aim_spell = null
	_aim_caster = null
	_free_preview()
	aim_ended.emit(spell, false)


func is_aiming() -> bool:
	return _aim_spell != null


func get_aimed_spell() -> Spell:
	return _aim_spell


## 0..1 towards the minimum aim time (1 when there is none).
func get_aim_progress() -> float:
	if not is_aiming():
		return 0.0
	return 1.0 if _aim_spell.min_aim_time <= 0.0 else clampf(_aim_time / _aim_spell.min_aim_time, 0.0, 1.0)


func is_aim_released() -> bool:
	return _aim_release


func _update_aim(delta: float) -> void:
	if not is_aiming():
		return
	_aim_time += delta
	if not is_instance_valid(_aim_caster):
		cancel_aim()
		return
	if _aim_release and _aim_time >= _aim_spell.min_aim_time:
		var spell := _aim_spell
		var caster := _aim_caster
		_aim_spell = null
		_aim_caster = null
		_free_preview()
		# Mana/cooldown were checked when aiming began; mana may have been spent meanwhile.
		var fired := try_cast(caster, caster.get_aim_direction())
		aim_ended.emit(spell, fired)


## A long-running spell effect claims the book until end_channel(); it needs a cancel() method.
func begin_channel(node: Node) -> void:
	_channel = node


func end_channel(node: Node) -> void:
	if _channel == node:
		_channel = null


func is_channeling() -> bool:
	return is_instance_valid(_channel)


func get_channel() -> Node:
	return _channel if is_instance_valid(_channel) else null


## Ends the running channel the way the spell decides (the chain snaps).
func cancel_channel() -> void:
	if is_channeling():
		_channel.cancel()


func _free_preview() -> void:
	if is_instance_valid(_aim_preview):
		_aim_preview.queue_free()
	_aim_preview = null


func get_cast_origin() -> Transform3D:
	return _cast_origin.global_transform


## Called by the player with mouse motion so the book lags behind the view.
func add_look_sway(relative: Vector2) -> void:
	_sway_target = (_sway_target + relative * 0.00012).limit_length(0.03)


## 0 = standing still, 1 = full walking speed.
func set_move_amount(amount: float) -> void:
	_bob_amount = clampf(amount, 0.0, 1.0)


# ---------------------------------------------------------------------------
# Flipping
# ---------------------------------------------------------------------------

func _try_start_flip() -> void:
	if not is_flipping() and _target_page != current_page:
		_start_flip(_target_page)


## Turns every page between the current one and `to`: one leaf per page, lifting off the source
## stack top first, staggered so they fan over and land one on another.
func _start_flip(to: int) -> void:
	var n := absi(to - current_page)
	var dir := signi(to - current_page)
	_flip_from = current_page
	_flip_to = to
	_flip_dir = dir
	_flip_t = 0.0
	_flip_landed = 0
	_flip_total = flip_duration * (1.0 if n == 1 else MULTI_FLIP_TIME)
	_flip_leaf_time = _flip_total if n == 1 else _flip_total * LEAF_SHARE
	var stagger := 0.0 if n == 1 else (_flip_total - _flip_leaf_time) / float(n - 1)
	var left := current_page
	var right := page_count - 1 - current_page
	# The source stack loses all the turning leaves at once; the destination stack grows as they land.
	var src_rest := (right - n) if dir > 0 else (left - n)
	var dst_rest := left if dir > 0 else right
	for k in n:
		var lo := (_flip_from + k) if dir > 0 else (_flip_from - 1 - k)
		var mat := _mat_leaf.duplicate() as ShaderMaterial
		_apply_face(mat, "front_", lo * 2 + 1)
		_apply_face(mat, "back_", lo * 2 + 2)
		var mi := _leaf_instance(k)
		mi.material_override = mat
		mi.visible = true
		_leaves.append({"mi": mi, "mat": mat, "start": stagger * k,
			"src_h": _stack_peak(_stack_thickness(src_rest + n - 1 - k)) + LEAF_T,
			"dst_h": _stack_peak(_stack_thickness(dst_rest + k)), "landed": false})
	# The page the leaves reveal: the target's page on the source side.
	if dir > 0:
		_apply_face(_mat_page_r, "", to * 2 + 1)
		_set_stack(left, src_rest)
	else:
		_apply_face(_mat_page_l, "", to * 2)
		_set_stack(src_rest, right)
	for leaf in _leaves:
		_update_leaf(leaf, 0.0)
	page_flip_started.emit(_flip_from, _flip_to)


## Leaf mesh instances, created on demand (they share the leaf mesh).
var _leaf_pool: Array[MeshInstance3D] = []

func _leaf_instance(k: int) -> MeshInstance3D:
	while _leaf_pool.size() <= k:
		var mi := _add_mesh(_book, _leaf.mesh, Vector3.ZERO)
		mi.custom_aabb = _leaf.custom_aabb
		mi.visible = false
		_leaf_pool.append(mi)
	return _leaf_pool[k]


func _update_flip(delta: float) -> void:
	if not is_flipping():
		return
	_flip_t += delta
	for leaf in _leaves:
		if leaf.landed:
			continue
		var t := clampf((_flip_t - leaf.start) / _flip_leaf_time, 0.0, 1.0)
		_update_leaf(leaf, t)
		if t >= 1.0:
			# Landed: it joins the destination stack.
			leaf.landed = true
			(leaf.mi as MeshInstance3D).visible = false
			_flip_landed += 1
			var src_rest := (page_count - 1 - _flip_from - _leaves.size()) if _flip_dir > 0 else (_flip_from - _leaves.size())
			if _flip_dir > 0:
				_set_stack(_flip_from + _flip_landed, src_rest)
			else:
				_set_stack(src_rest, page_count - 1 - _flip_from + _flip_landed)
	if _flip_landed >= _leaves.size():
		_finish_flip()


func _update_leaf(leaf: Dictionary, t: float) -> void:
	var e := t * t * (3.0 - 2.0 * t)
	var a0 := FLIP_START_ANGLE
	var a := lerpf(a0, PI - a0, e) if _flip_dir > 0 else lerpf(PI - a0, a0, e)
	# The free edge trails behind the root, so the leaf bows against the motion.
	var curl := -float(_flip_dir) * FLIP_CURL * sin(PI * e) / PAGE_W
	var mat := leaf.mat as ShaderMaterial
	mat.set_shader_parameter("angle", a)
	mat.set_shader_parameter("curl", curl)
	(leaf.mi as MeshInstance3D).position.y = lerpf(leaf.src_h, leaf.dst_h, e) + 0.0004


func _finish_flip() -> void:
	_flip_t = -1.0
	for leaf in _leaves:
		(leaf.mi as MeshInstance3D).visible = false
	_leaves.clear()
	current_page = _flip_to
	_set_stack(current_page, page_count - 1 - current_page)
	_apply_face(_mat_page_l, "", current_page * 2)
	_apply_face(_mat_page_r, "", current_page * 2 + 1)
	page_changed.emit(current_page, get_selected_spell())
	# More pages were requested meanwhile: turn them all in one go.
	_try_start_flip()


## Cooldown starts: the spell's circle gets a hard spin that coasts to a stop exactly when the
## cooldown ends. The angle follows a cubic ease-out over the cooldown, like a spun wheel slowing
## under friction: CIRCLE_START_SPEED at first, then ever slower, zero at the end. (Total turn
## = start speed × cooldown / 3, so the start speed is the same for every spell.)
func _start_cooldown(spell: Spell) -> void:
	_circle_from[spell] = circle_angle(spell)
	_circle_turn[spell] = CIRCLE_START_SPEED * spell.cooldown / 3.0
	_cooldowns[spell] = spell.cooldown


## Current turn of a spell's arcane circle (radians).
func circle_angle(spell: Spell) -> float:
	var remaining := get_cooldown_remaining(spell)
	if remaining <= 0.0 or not _circle_turn.has(spell):
		return _circle_rest.get(spell, 0.0)
	var u := 1.0 - remaining / maxf(spell.cooldown, 0.001)
	var k := 1.0 - u
	return _circle_from[spell] + _circle_turn[spell] * (1.0 - k * k * k)


func _update_circle(delta: float) -> void:
	var flash := 0.0
	if _flash_t >= 0.0:
		_flash_t += delta
		# Quick swell, slow fade.
		flash = _flash_t / 0.12 if _flash_t < 0.12 else exp(-(_flash_t - 0.12) * 4.5)
		if _flash_t > FLASH_TIME:
			_flash_t = -1.0
	if _right_spell:
		var a := circle_angle(_right_spell)
		_mat_page_r.set_shader_parameter("circle_angle", a)
		_mat_page_r.set_shader_parameter("circle_blur", clampf(absf(a - _last_circle_angle), 0.0, 0.6))
		_last_circle_angle = a
	_mat_page_r.set_shader_parameter("circle_flash", flash)


func _apply_face(mat: ShaderMaterial, prefix: String, face: int) -> void:
	var seed_name := "seed" if prefix.is_empty() else prefix + "seed"
	var tex_name := "page_content" if prefix.is_empty() else prefix + "content"
	var strength_name := "content_strength" if prefix.is_empty() else prefix + "strength"
	var tex: Texture2D = _face_textures.get(face)
	if tex == null and face % 2 == 1:
		var spell := get_spell_on_page(floori(face / 2.0))
		if spell:
			tex = spell.page_texture
	mat.set_shader_parameter(seed_name, float(face))
	mat.set_shader_parameter(tex_name, tex)
	mat.set_shader_parameter(strength_name, 1.0 if tex else 0.0)
	# The arcane circle behind a spell symbol.
	var face_spell: Spell = get_spell_on_page(floori(face / 2.0)) if face % 2 == 1 else null
	mat.set_shader_parameter(prefix + "circle_strength", 1.0 if face_spell else 0.0)
	if face_spell:
		mat.set_shader_parameter(prefix + "circle_color", face_spell.theme_color)
		mat.set_shader_parameter(prefix + "circle_angle", circle_angle(face_spell))
	if mat == _mat_page_r:
		if face_spell != _right_spell:
			_flash_t = -1.0
		_right_spell = face_spell


# ---------------------------------------------------------------------------
# Hand-held motion
# ---------------------------------------------------------------------------

func _update_motion(delta: float) -> void:
	_sway_target = _sway_target.lerp(Vector2.ZERO, 1.0 - exp(-6.0 * delta))
	_sway = _sway.lerp(_sway_target, 1.0 - exp(-14.0 * delta))
	_bob_phase += delta * lerpf(1.2, 8.5, _bob_amount)
	_kick = move_toward(_kick, 0.0, delta * 4.0)
	_shake = move_toward(_shake, 0.0, delta * 3.0)
	var bob_strength := lerpf(0.0015, 0.007, _bob_amount)
	var offset := Vector3(-_sway.x, _sway.y, 0.0)
	offset += Vector3(sin(_bob_phase) * bob_strength, -absf(cos(_bob_phase)) * bob_strength, 0.0)
	offset += Vector3(sin(_shake * 40.0) * 0.006 * _shake, 0.0, 0.0)
	offset += Vector3(0.0, 0.012, -0.035) * _kick * _kick
	offset += hold_offset
	var rot := Basis(Vector3.UP, _sway.x * 4.0) * Basis(Vector3.RIGHT, -_sway.y * 4.0 - _kick * 0.15)
	transform = Transform3D(rot * _rest_xform.basis, _rest_xform.origin + offset)
	_cast_light.light_energy = _kick * 0.9


# ---------------------------------------------------------------------------
# Page stack geometry
# ---------------------------------------------------------------------------

func _stack_thickness(leaves: int) -> float:
	return BASE_STACK + maxi(leaves, 0) * LEAF_T


func _profile_bottom(x: float) -> float:
	var ax := absf(x)
	if ax >= GUTTER:
		return 0.0
	return -SPINE_SAG * 0.5 * (1.0 + cos(PI * ax / GUTTER))


## Height of the top page at distance x from the spine for a stack of thickness t.
func _profile_top(x: float, t: float) -> float:
	var ax := absf(x)
	var rise := 1.0 - exp(-ax / (PAGE_W * 0.06))
	var u := ax / PAGE_W
	var y := lerpf(-SPINE_SAG * 0.55, t, rise) - t * 0.18 * u * u
	return maxf(y, _profile_bottom(ax) + 0.0006)


func _stack_peak(t: float) -> float:
	var peak := -1.0
	for i in 32:
		peak = maxf(peak, _profile_top(PAGE_W * i / 31.0, t))
	return peak


func _set_stack(left_leaves: int, right_leaves: int) -> void:
	_block_l.mesh = _make_block_mesh(_stack_thickness(left_leaves), true)
	_block_r.mesh = _make_block_mesh(_stack_thickness(right_leaves), false)


func _make_block_mesh(t: float, mirror: bool) -> ArrayMesh:
	var n := 28
	var xs := PackedFloat32Array()
	var tops := PackedFloat32Array()
	var bots := PackedFloat32Array()
	for i in n:
		var x := 0.0004 + (PAGE_W - 0.0004) * pow(float(i) / (n - 1), 1.7)
		xs.append(x)
		tops.append(_profile_top(x, t))
		bots.append(_profile_bottom(x))
	var st_top := _new_st()
	var st_side := _new_st()
	_emit_profile(st_top, st_side, xs, tops, bots, -PAGE_H * 0.5, PAGE_H * 0.5, mirror, false)
	var mesh := ArrayMesh.new()
	_commit(st_top, mesh, _mat_page_l if mirror else _mat_page_r)
	_commit(st_side, mesh, _mat_edge)
	return mesh


# ---------------------------------------------------------------------------
# Model construction
# ---------------------------------------------------------------------------

func _create_materials() -> void:
	var grain := FastNoiseLite.new()
	grain.noise_type = FastNoiseLite.TYPE_CELLULAR
	grain.frequency = 0.08
	grain.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var grain_tex := NoiseTexture2D.new()
	grain_tex.width = 256
	grain_tex.height = 256
	grain_tex.seamless = true
	grain_tex.as_normal_map = true
	grain_tex.bump_strength = 3.0
	grain_tex.noise = grain

	var mottle := FastNoiseLite.new()
	mottle.frequency = 0.02
	var mottle_tex := NoiseTexture2D.new()
	mottle_tex.width = 256
	mottle_tex.height = 256
	mottle_tex.seamless = true
	mottle_tex.noise = mottle
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.16, 0.05, 0.04))
	ramp.set_color(1, Color(0.36, 0.13, 0.08))
	mottle_tex.color_ramp = ramp

	_mat_leather = StandardMaterial3D.new()
	_mat_leather.albedo_texture = mottle_tex
	_mat_leather.normal_enabled = true
	_mat_leather.normal_texture = grain_tex
	_mat_leather.normal_scale = 0.6
	_mat_leather.roughness = 0.72
	_mat_leather.uv1_triplanar = true
	_mat_leather.uv1_scale = Vector3(18, 18, 18)

	_mat_leather_dark = _mat_leather.duplicate() as StandardMaterial3D
	_mat_leather_dark.albedo_color = Color(0.55, 0.5, 0.5)
	_mat_leather_dark.roughness = 0.6

	_mat_brass = StandardMaterial3D.new()
	_mat_brass.albedo_color = Color(0.78, 0.58, 0.28)
	_mat_brass.metallic = 1.0
	_mat_brass.roughness = 0.33

	_mat_cloth = StandardMaterial3D.new()
	_mat_cloth.albedo_color = Color(0.45, 0.06, 0.1)
	_mat_cloth.roughness = 0.8
	_mat_cloth.cull_mode = BaseMaterial3D.CULL_DISABLED

	_mat_gem = StandardMaterial3D.new()
	_mat_gem.albedo_color = Color(0.35, 0.15, 0.8)
	_mat_gem.metallic = 0.4
	_mat_gem.roughness = 0.05
	_mat_gem.emission_enabled = true
	_mat_gem.emission = Color(0.5, 0.3, 1.0)
	_mat_gem.emission_energy_multiplier = 0.6
	var glow := ShaderMaterial.new()
	glow.shader = preload("res://shaders/magic_glow.gdshader")
	glow.set_shader_parameter("glow_color", Color(0.65, 0.45, 1.0))
	_mat_gem.next_pass = glow

	_mat_edge = ShaderMaterial.new()
	_mat_edge.shader = preload("res://shaders/grimoire_page_edge.gdshader")
	var page_shader := preload("res://shaders/grimoire_page.gdshader")
	_mat_page_l = ShaderMaterial.new()
	_mat_page_l.shader = page_shader
	_mat_page_r = ShaderMaterial.new()
	_mat_page_r.shader = page_shader
	_mat_leaf = ShaderMaterial.new()
	_mat_leaf.shader = preload("res://shaders/grimoire_leaf.gdshader")


func _build_covers() -> void:
	var width := PAGE_W + COVER_M - GUTTER
	var depth := PAGE_H + COVER_M * 2.0
	var cover_mesh := _make_slab(width, depth, COVER_T, 0.004, 0.0009, _mat_leather)
	var corner_mesh := _make_slab(0.016, 0.016, COVER_T + 0.0012, 0.003, 0.0005, _mat_brass)
	var rivet := SphereMesh.new()
	rivet.radius = 0.0013
	rivet.height = 0.0016
	rivet.is_hemisphere = true
	rivet.radial_segments = 10
	rivet.rings = 4
	for side in [-1.0, 1.0]:
		var cover := _add_mesh(_book, cover_mesh, Vector3(side * (GUTTER + width * 0.5), -COVER_T * 0.5, 0.0))
		cover.name = "CoverLeft" if side < 0.0 else "CoverRight"
		# Brass corner guards on the outer corners, with a rivet on the outside face.
		for zs in [-1.0, 1.0]:
			var cx: float = side * (PAGE_W + COVER_M - 0.0074)
			var cz: float = zs * (PAGE_H * 0.5 + COVER_M - 0.0074)
			_add_mesh(_book, corner_mesh, Vector3(cx, -COVER_T * 0.5, cz))
			var r := _add_mesh(_book, rivet, Vector3(cx - side * 0.002, -COVER_T - 0.0006, cz - zs * 0.002))
			r.rotation.x = PI
			r.material_override = _mat_brass
	# Decorative embossed frame on the outside of both boards.
	var frame := _make_slab(width - 0.02, depth - 0.02, 0.0006, 0.006, 0.0003, _mat_leather_dark)
	for side in [-1.0, 1.0]:
		_add_mesh(_book, frame, Vector3(side * (GUTTER + width * 0.5), -COVER_T - 0.0002, 0.0))
	var boss := _make_gem(0.009, 0.004, 0.003, 8)
	var boss_mi := _add_mesh(_book, boss, Vector3(PAGE_W * 0.55 + GUTTER, -COVER_T - 0.0005, 0.0))
	boss_mi.rotation.x = PI
	boss_mi.material_override = _mat_brass


func _build_spine() -> void:
	var z0 := -PAGE_H * 0.5 - COVER_M
	var z1 := PAGE_H * 0.5 + COVER_M
	var xs := PackedFloat32Array()
	var tops := PackedFloat32Array()
	var bots := PackedFloat32Array()
	for i in 17:
		var x := lerpf(-GUTTER, GUTTER, i / 16.0)
		xs.append(x)
		tops.append(_profile_bottom(x))
		bots.append(_profile_bottom(x) - COVER_T)
	var st := _new_st()
	_emit_profile(st, st, xs, tops, bots, z0, z1, false, true)
	var spine := ArrayMesh.new()
	_commit(st, spine, _mat_leather)
	var spine_mi := _add_mesh(_book, spine, Vector3.ZERO)
	spine_mi.name = "Spine"

	# Raised bands across the spine, running over the hinge onto the boards.
	var band_st := _new_st()
	var bx := PackedFloat32Array()
	var btop := PackedFloat32Array()
	var bbot := PackedFloat32Array()
	for i in 21:
		var x := lerpf(-GUTTER - 0.004, GUTTER + 0.004, i / 20.0)
		var outer := _profile_bottom(x) - COVER_T
		var bulge := 0.0018 * (0.5 + 0.5 * cos(PI * x / (GUTTER + 0.004)))
		bx.append(x)
		btop.append(outer + 0.0003)
		bbot.append(outer - 0.0006 - bulge)
	for bz in [-0.058, -0.02, 0.02, 0.058]:
		_emit_profile(band_st, band_st, bx, btop, bbot, bz - 0.003, bz + 0.003, false, true)
	var bands := ArrayMesh.new()
	_commit(band_st, bands, _mat_leather_dark)
	var bands_mi := _add_mesh(_book, bands, Vector3.ZERO)
	bands_mi.name = "SpineBands"

	# Woven headbands at the top and bottom of the text block.
	var headband := CylinderMesh.new()
	headband.top_radius = 0.0019
	headband.bottom_radius = 0.0019
	headband.height = GUTTER * 1.6
	headband.radial_segments = 10
	headband.rings = 1
	for zs in [-1.0, 1.0]:
		var hb := _add_mesh(_book, headband, Vector3(0.0, -SPINE_SAG * 0.7, zs * (PAGE_H * 0.5 - 0.0008)))
		hb.rotation.z = PI * 0.5
		hb.material_override = _mat_cloth


func _build_blocks() -> void:
	_block_l = MeshInstance3D.new()
	_block_l.name = "PagesLeft"
	_book.add_child(_block_l)
	_block_r = MeshInstance3D.new()
	_block_r.name = "PagesRight"
	_book.add_child(_block_r)


func _build_leaf() -> void:
	var st := _new_st()
	var segs := 32
	var z0 := -PAGE_H * 0.5
	for i in segs:
		var xa := (PAGE_W - 0.001) * i / segs
		var xb := (PAGE_W - 0.001) * (i + 1) / segs
		for j in 2:
			var za := z0 + PAGE_H * j * 0.5
			var zb := za + PAGE_H * 0.5
			_quad(st, [Vector3(xa, 0, za), Vector3(xb, 0, za), Vector3(xb, 0, zb), Vector3(xa, 0, zb)],
				Vector3.UP,
				[Vector2(xa / PAGE_W, (za - z0) / PAGE_H), Vector2(xb / PAGE_W, (za - z0) / PAGE_H),
				Vector2(xb / PAGE_W, (zb - z0) / PAGE_H), Vector2(xa / PAGE_W, (zb - z0) / PAGE_H)])
	var mesh := ArrayMesh.new()
	_commit(st, mesh, _mat_leaf)
	_leaf = _add_mesh(_book, mesh, Vector3.ZERO)
	_leaf.name = "FlippingLeaf"
	# The vertex shader moves the leaf far from its flat rest pose.
	_leaf.custom_aabb = AABB(Vector3(-PAGE_W * 1.2, -0.05, -PAGE_H), Vector3(PAGE_W * 2.4, PAGE_W * 1.3, PAGE_H * 2.0))
	_leaf.visible = false


func _build_ribbon() -> void:
	var tail := PAGE_H * 0.5
	var pts := PackedVector3Array([
		Vector3(-0.001, -SPINE_SAG * 0.45, tail - 0.03),
		Vector3(-0.002, -SPINE_SAG * 0.3, tail + 0.001),
		Vector3(-0.012, -0.01, tail + 0.009),
		Vector3(-0.026, -0.028, tail + 0.012),
		Vector3(-0.034, -0.05, tail + 0.006),
	])
	var mesh := _make_strip(_smooth_path(pts, 6), Vector3(1, 0, 0.3), 0.0055, 0.0, _mat_cloth)
	var ribbon := _add_mesh(_book, mesh, Vector3.ZERO)
	ribbon.name = "Bookmark"


func _build_clasp() -> void:
	var edge := PAGE_W + COVER_M
	# Brass anchor plate the strap is riveted to, on the outside of the right board.
	var anchor := _make_slab(0.018, 0.028, 0.001, 0.003, 0.0004, _mat_brass)
	_add_mesh(_book, anchor, Vector3(edge - 0.012, -COVER_T - 0.0005, 0.0))
	var pts := PackedVector3Array([
		Vector3(edge - 0.02, -COVER_T - 0.0014, 0.0),
		Vector3(edge - 0.002, -COVER_T - 0.0016, 0.0),
		Vector3(edge + 0.007, -0.009, 0.003),
		Vector3(edge + 0.01, -0.03, 0.009),
		Vector3(edge + 0.007, -0.052, 0.014),
	])
	var path := _smooth_path(pts, 6)
	var side := Vector3(0, 0, 1)
	var strap := _add_mesh(_book, _make_strip(path, side, 0.022, 0.0018, _mat_leather), Vector3.ZERO)
	strap.name = "ClaspStrap"

	# Clasp plate + gem hanging from the end of the strap.
	var end := path[path.size() - 1]
	var tangent := (end - path[path.size() - 3]).normalized()
	var s := (side - tangent * side.dot(tangent)).normalized()
	var normal := s.cross(tangent)
	var plate_basis := Basis(tangent, normal, s)
	var plate := _add_mesh(_book, _make_slab(0.03, 0.026, 0.0025, 0.006, 0.0008, _mat_brass), end + tangent * 0.01)
	plate.basis = plate_basis
	var gem := _add_mesh(_book, _make_gem(0.0065, 0.003, 0.005, 8), end + tangent * 0.011 + normal * 0.0012)
	gem.basis = plate_basis
	gem.material_override = _mat_gem
	var ring := TorusMesh.new()
	ring.inner_radius = 0.0068
	ring.outer_radius = 0.0082
	ring.rings = 24
	ring.ring_segments = 8
	var ring_mi := _add_mesh(_book, ring, end + tangent * 0.011 + normal * 0.0012)
	ring_mi.basis = plate_basis
	ring_mi.material_override = _mat_brass
	for k in [-1.0, 1.0]:
		var rivet := SphereMesh.new()
		rivet.radius = 0.0012
		rivet.height = 0.0024
		var rv := _add_mesh(_book, rivet, end + tangent * (0.011 + k * 0.011) + normal * 0.0012)
		rv.material_override = _mat_brass


# ---------------------------------------------------------------------------
# Mesh helpers
# ---------------------------------------------------------------------------

func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _commit(st: SurfaceTool, mesh: ArrayMesh, mat: Material) -> void:
	st.generate_tangents()
	st.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


## Emits a triangle, fixing the winding so it faces along the supplied normals
## (Godot treats clockwise triangles as front-facing).
static func _tri(st: SurfaceTool, p: Array, n: Array, uv: Array) -> void:
	var order := [0, 1, 2]
	var face_n: Vector3 = n[0] + n[1] + n[2]
	if (p[1] - p[0]).cross(p[2] - p[0]).dot(face_n) > 0.0:
		order = [0, 2, 1]
	for i in order:
		st.set_normal(n[i])
		st.set_uv(uv[i])
		st.add_vertex(p[i])


## Quad p0..p3 in loop order. normal may be a single Vector3 or an Array of four.
static func _quad(st: SurfaceTool, p: Array, normal, uv: Array) -> void:
	var n: Array = normal if normal is Array else [normal, normal, normal, normal]
	_tri(st, [p[0], p[1], p[2]], [n[0], n[1], n[2]], [uv[0], uv[1], uv[2]])
	_tri(st, [p[0], p[2], p[3]], [n[0], n[2], n[3]], [uv[0], uv[2], uv[3]])


static func _curve_normal(xs: PackedFloat32Array, ys: PackedFloat32Array, i: int, s: float) -> Vector3:
	var a := maxi(i - 1, 0)
	var b := mini(i + 1, xs.size() - 1)
	var slope := (ys[b] - ys[a]) / (xs[b] - xs[a])
	return Vector3(-slope * s, 1.0, 0.0).normalized()


## Extrudes a 2D cross-section (tops/bots over xs) along Z. Used for the page stacks,
## the spine and its bands. st_top gets the upper surface, st_side everything else.
func _emit_profile(st_top: SurfaceTool, st_side: SurfaceTool, xs: PackedFloat32Array, tops: PackedFloat32Array,
		bots: PackedFloat32Array, z0: float, z1: float, mirror: bool, with_bottom: bool) -> void:
	var s := -1.0 if mirror else 1.0
	var n := xs.size()
	var zlen := z1 - z0
	for i in n - 1:
		var xa := xs[i] * s
		var xb := xs[i + 1] * s
		var ua := absf(xs[i]) / PAGE_W
		var ub := absf(xs[i + 1]) / PAGE_W
		var na := _curve_normal(xs, tops, i, s)
		var nb := _curve_normal(xs, tops, i + 1, s)
		_quad(st_top, [Vector3(xa, tops[i], z0), Vector3(xb, tops[i + 1], z0), Vector3(xb, tops[i + 1], z1), Vector3(xa, tops[i], z1)],
			[na, nb, nb, na], [Vector2(ua, 0), Vector2(ub, 0), Vector2(ub, 1), Vector2(ua, 1)])
		if with_bottom:
			var ba := -_curve_normal(xs, bots, i, s)
			var bb := -_curve_normal(xs, bots, i + 1, s)
			_quad(st_side, [Vector3(xa, bots[i], z0), Vector3(xb, bots[i + 1], z0), Vector3(xb, bots[i + 1], z1), Vector3(xa, bots[i], z1)],
				[ba, bb, bb, ba], [Vector2(ua, 0), Vector2(ub, 0), Vector2(ub, 1), Vector2(ua, 1)])
		for cap in [[z0, -1.0], [z1, 1.0]]:
			var z: float = cap[0]
			_quad(st_side, [Vector3(xa, bots[i], z), Vector3(xb, bots[i + 1], z), Vector3(xb, tops[i + 1], z), Vector3(xa, tops[i], z)],
				Vector3(0, 0, cap[1]),
				[Vector2(ua, bots[i]), Vector2(ub, bots[i + 1]), Vector2(ub, tops[i + 1]), Vector2(ua, tops[i])])
	for end in [[0, -1.0], [n - 1, 1.0]]:
		var i: int = end[0]
		var x := xs[i] * s
		_quad(st_side, [Vector3(x, bots[i], z0), Vector3(x, tops[i], z0), Vector3(x, tops[i], z1), Vector3(x, bots[i], z1)],
			Vector3(end[1] * s, 0, 0),
			[Vector2(0, bots[i]), Vector2(0, tops[i]), Vector2(zlen / PAGE_W, tops[i]), Vector2(zlen / PAGE_W, bots[i])])


## Rounded, bevelled plate lying in XZ, centered on the origin.
func _make_slab(sx: float, sz: float, t: float, radius: float, bevel: float, mat: Material) -> ArrayMesh:
	var outer := _rounded_rect(sx * 0.5, sz * 0.5, radius)
	var inner := _rounded_rect(sx * 0.5 - bevel, sz * 0.5 - bevel, radius - bevel)
	var h := t * 0.5
	var st := _new_st()
	var cnt := outer.size()
	for i in cnt:
		var j := (i + 1) % cnt
		var o0: Vector2 = outer[i][0]
		var o1: Vector2 = outer[j][0]
		var i0: Vector2 = inner[i][0]
		var i1: Vector2 = inner[j][0]
		var d0: Vector2 = outer[i][1]
		var d1: Vector2 = outer[j][1]
		var uvo0 := Vector2(o0.x / sx + 0.5, o0.y / sz + 0.5)
		var uvo1 := Vector2(o1.x / sx + 0.5, o1.y / sz + 0.5)
		var uvi0 := Vector2(i0.x / sx + 0.5, i0.y / sz + 0.5)
		var uvi1 := Vector2(i1.x / sx + 0.5, i1.y / sz + 0.5)
		var side0 := Vector3(d0.x, 0, d0.y)
		var side1 := Vector3(d1.x, 0, d1.y)
		for ys in [1.0, -1.0]:
			var up := Vector3(0, ys, 0)
			# Face fan.
			_tri(st, [Vector3(0, h * ys, 0), Vector3(i0.x, h * ys, i0.y), Vector3(i1.x, h * ys, i1.y)],
				[up, up, up], [Vector2(0.5, 0.5), uvi0, uvi1])
			# Bevel.
			var bn0 := (side0 + up).normalized()
			var bn1 := (side1 + up).normalized()
			_quad(st, [Vector3(i0.x, h * ys, i0.y), Vector3(i1.x, h * ys, i1.y), Vector3(o1.x, (h - bevel) * ys, o1.y), Vector3(o0.x, (h - bevel) * ys, o0.y)],
				[bn0, bn1, bn1, bn0], [uvi0, uvi1, uvo1, uvo0])
		_quad(st, [Vector3(o0.x, h - bevel, o0.y), Vector3(o1.x, h - bevel, o1.y), Vector3(o1.x, -h + bevel, o1.y), Vector3(o0.x, -h + bevel, o0.y)],
			[side0, side1, side1, side0], [uvo0, uvo1, uvo1 + Vector2(0, 0.02), uvo0 + Vector2(0, 0.02)])
	var mesh := ArrayMesh.new()
	_commit(st, mesh, mat)
	return mesh


## Returns [[point, outward_normal], ...] around a rounded rectangle.
static func _rounded_rect(hx: float, hz: float, r: float) -> Array:
	r = clampf(r, 0.0001, minf(hx, hz))
	var pts := []
	var corners := [Vector2(hx - r, hz - r), Vector2(-hx + r, hz - r), Vector2(-hx + r, -hz + r), Vector2(hx - r, -hz + r)]
	var segs := 5
	for c in 4:
		for k in segs + 1:
			var a := (c + float(k) / segs) * PI * 0.5
			var d := Vector2(cos(a), sin(a))
			pts.append([corners[c] + d * r, d])
	return pts


## Faceted cut gem, table facing +Y.
func _make_gem(r: float, crown: float, pavilion: float, sides: int) -> ArrayMesh:
	var st := _new_st()
	var center := Vector3(0, crown * 0.3, 0)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var g0 := Vector3(cos(a0), 0, sin(a0)) * r
		var g1 := Vector3(cos(a1), 0, sin(a1)) * r
		var t0 := Vector3(cos(a0) * r * 0.55, crown, sin(a0) * r * 0.55)
		var t1 := Vector3(cos(a1) * r * 0.55, crown, sin(a1) * r * 0.55)
		var tip := Vector3(0, -pavilion, 0)
		_gem_face(st, [Vector3(0, crown, 0), t0, t1], center)
		_gem_face(st, [t0, g0, g1], center)
		_gem_face(st, [t0, g1, t1], center)
		_gem_face(st, [g0, tip, g1], center)
	var mesh := ArrayMesh.new()
	_commit(st, mesh, _mat_gem)
	return mesh


static func _gem_face(st: SurfaceTool, p: Array, center: Vector3) -> void:
	var n: Vector3 = (p[1] - p[0]).cross(p[2] - p[0]).normalized()
	if n.dot((p[0] + p[1] + p[2]) / 3.0 - center) < 0.0:
		n = -n
	_tri(st, p, [n, n, n], [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE])


static func _smooth_path(pts: PackedVector3Array, sub: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var last := pts.size() - 1
	for i in last:
		var p0 := pts[maxi(i - 1, 0)]
		var p3 := pts[mini(i + 2, last)]
		for k in sub:
			out.append(pts[i].cubic_interpolate(pts[i + 1], p0, p3, float(k) / sub))
	out.append(pts[last])
	return out


## Flat strap/ribbon swept along a path. thickness 0 makes a single two-sided sheet.
func _make_strip(path: PackedVector3Array, side_hint: Vector3, width: float, thickness: float, mat: Material) -> ArrayMesh:
	var st := _new_st()
	var cnt := path.size()
	var sides := []
	var normals := []
	for i in cnt:
		var tangent := (path[mini(i + 1, cnt - 1)] - path[maxi(i - 1, 0)]).normalized()
		var s := (side_hint - tangent * side_hint.dot(tangent)).normalized()
		sides.append(s * width * 0.5)
		normals.append(s.cross(tangent))
	var h := thickness * 0.5
	for i in cnt - 1:
		var j := i + 1
		var u0 := float(i) / (cnt - 1)
		var u1 := float(j) / (cnt - 1)
		var a: Vector3 = path[i]
		var b: Vector3 = path[j]
		var sa: Vector3 = sides[i]
		var sb: Vector3 = sides[j]
		var na: Vector3 = normals[i]
		var nb: Vector3 = normals[j]
		var faces := [1.0, -1.0] if thickness > 0.0 else [1.0]
		for f in faces:
			_quad(st, [a - sa + na * h * f, b - sb + nb * h * f, b + sb + nb * h * f, a + sa + na * h * f],
				[na * f, nb * f, nb * f, na * f], [Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1)])
		if thickness > 0.0:
			for e in [1.0, -1.0]:
				var ea: Vector3 = sa.normalized() * e
				var eb: Vector3 = sb.normalized() * e
				_quad(st, [a + sa * e + na * h, b + sb * e + nb * h, b + sb * e - nb * h, a + sa * e - na * h],
					[ea, eb, eb, ea], [Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 0.1), Vector2(u0, 0.1)])
	var mesh := ArrayMesh.new()
	_commit(st, mesh, mat)
	return mesh
