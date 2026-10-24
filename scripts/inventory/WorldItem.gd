class_name WorldItem
extends Node3D
## An item lying in the world (Inventory): a spell page hovering above the ground, slowly
## turning and bobbing, wrapped in its rarity aura (world_page_aura.gdshader: blue sheen, purple
## sparkles, shining golden rays, or Primordial's pulsing black fire) so its worth shows from a
## distance, with a light and motes (Primordial: dark motes spiralling in, violet sparks).
## Appears with a flash; collect() makes it fly to whoever took it and vanish.

const HOVER := 0.95
const PAGE_SIZE := Vector2(0.42, 0.6)
const SHADER := preload("res://shaders/vfx/world_page.gdshader")
const AURA_SHADER := preload("res://shaders/vfx/world_page_aura.gdshader")
const BEAM_SHADER := preload("res://shaders/vfx/loot_beam.gdshader")
## Light pillar above the page (rarity visible from afar): width and height in metres.
const BEAM_SIZE := Vector2(0.9, 9.0)
## Page size in the aura shader's units (AURA_CARD), the narrow core the light radiates from
## (hidden behind the page at any angle) and how far the aura reaches beyond the core.
const AURA_CARD := Vector2(58, 82)
const AURA_CORE := Vector2(12, 60)
const AURA_MARGIN := 62.0
const AURA_MARGIN_PRIMORDIAL := 80.0
const COLLECT_TIME := 0.35

var item: Resource

var _card: MeshInstance3D
var _light: OmniLight3D
var _motes: GPUParticles3D
var _beam: MeshInstance3D
var _aura: MeshInstance3D
var _t := 0.0
var _base := Vector3.ZERO
var _collect_to: Node3D
var _collect_t := -1.0
var _collect_from := Vector3.ZERO


static func create(parent: Node, it: Resource, pos: Vector3, fresh: bool) -> WorldItem:
	var w := WorldItem.new()
	w.item = it
	parent.add_child(w)
	w.global_position = pos
	w._base = pos
	if fresh:
		w._appear()
	return w


func _ready() -> void:
	var spell := item as Spell
	var color: Color = spell.get_rarity_color() if spell else Color(0.9, 0.85, 0.7)
	var primordial := spell != null and spell.rarity == Spell.Rarity.PRIMORDIAL
	_card = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = PAGE_SIZE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("ink", spell.page_texture if spell and spell.page_texture else null)
	mat.set_shader_parameter("glow_color", color)
	mat.set_shader_parameter("primordial", primordial)
	quad.material = mat
	_card.mesh = quad
	add_child(_card)
	if spell:
		_add_aura(spell, primordial)
		_add_beam(color, primordial)
	_light = OmniLight3D.new()
	_light.light_color = color if not primordial else Color(0.6, 0.35, 1.0)
	_light.omni_range = 3.0
	_light.light_energy = 1.2
	_light.light_volumetric_fog_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)
	if primordial:
		_motes = SpellFx.particles(self, 30, 1.6, false, false, Vector2(0.07, 0.07), Color(0.75, 0.5, 1.0), Color(1, 0.9, 1))
		var pm := _motes.process_material as ParticleProcessMaterial
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
		pm.emission_sphere_radius = 0.7
		pm.radial_accel_min = -1.2
		pm.radial_accel_max = -0.6
		pm.tangential_accel_min = 1.5
		pm.tangential_accel_max = 2.5
		pm.spread = 180.0
	else:
		_motes = SpellFx.particles(self, 16, 1.8, false, false, Vector2(0.06, 0.06), color, color.lightened(0.5))
		var pm := _motes.process_material as ParticleProcessMaterial
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = 0.35
		pm.emission_ring_inner_radius = 0.2
		pm.emission_ring_height = 0.05
		pm.direction = Vector3.UP
		pm.spread = 15.0
		pm.initial_velocity_min = 0.2
		pm.initial_velocity_max = 0.5
		_motes.position.y = -0.45
	_t = randf() * 10.0


## The rarity aura: one camera-facing billboard behind the page (shader keeps it behind), not
## turning with it, so it looks the same from every angle.
func _add_aura(spell: Spell, primordial: bool) -> void:
	var m := AURA_MARGIN_PRIMORDIAL if primordial else AURA_MARGIN
	var mat := ShaderMaterial.new()
	mat.shader = AURA_SHADER
	mat.set_shader_parameter("rarity", spell.rarity)
	mat.set_shader_parameter("color", spell.get_rarity_color())
	mat.set_shader_parameter("card_size", AURA_CORE)
	mat.set_shader_parameter("margin", m)
	mat.set_shader_parameter("seed", randf())
	var quad := QuadMesh.new()
	quad.size = PAGE_SIZE * (AURA_CORE + 2.0 * Vector2(m, m)) / AURA_CARD
	quad.material = mat
	_aura = MeshInstance3D.new()
	_aura.mesh = quad
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.extra_cull_margin = 1.0
	# A child of the item, not of the turning page.
	add_child(_aura)


func _add_beam(color: Color, primordial: bool) -> void:
	var quad := QuadMesh.new()
	quad.size = BEAM_SIZE
	var mat := ShaderMaterial.new()
	mat.shader = BEAM_SHADER
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("primordial", primordial)
	quad.material = mat
	_beam = MeshInstance3D.new()
	_beam.mesh = quad
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.extra_cull_margin = BEAM_SIZE.y
	_beam.position.y = BEAM_SIZE.y * 0.5 - HOVER
	add_child(_beam)


func _appear() -> void:
	var spell := item as Spell
	var color: Color = spell.get_rarity_color() if spell else Color.WHITE
	var root := SpellFx.effect_root(get_parent(), global_position, 1.0)
	var ring := SpellFx.ring(root, false, 1.4, color, color.lightened(0.5))
	ring.global_basis = Basis(Vector3.RIGHT, -PI * 0.5)
	SpellFx.animate_ring(ring, 0.5, 0.0)
	_card.scale = Vector3.ONE * 0.2
	create_tween().tween_property(_card, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func is_collected() -> bool:
	return _collect_t >= 0.0


## Taken: flies to `to` (the taker, if known) shrinking, then disappears.
func collect(to: Node3D) -> void:
	_collect_to = to
	_collect_t = 0.0
	_collect_from = global_position
	_motes.emitting = false


func _process(delta: float) -> void:
	_t += delta
	if _collect_t >= 0.0:
		_collect_t += delta
		var u := clampf(_collect_t / COLLECT_TIME, 0.0, 1.0)
		var target := _collect_from + Vector3.UP * 0.5
		if is_instance_valid(_collect_to):
			target = _collect_to.global_position + Vector3.UP * 0.3
		global_position = _collect_from.lerp(target, u * u)
		_card.scale = Vector3.ONE * (1.0 - u)
		if _beam:
			_beam.visible = false
		if _aura:
			_aura.scale = Vector3.ONE * maxf(1.0 - u, 0.001)
		_light.light_energy = 1.2 * (1.0 - u)
		if u >= 1.0:
			queue_free()
		return
	global_position = _base + Vector3.UP * sin(_t * 1.8) * 0.08
	_card.rotation = Vector3(sin(_t * 0.9) * 0.08, _t * 0.9, 0.0)
	_light.light_energy = 1.0 + 0.3 * sin(_t * 3.0)
