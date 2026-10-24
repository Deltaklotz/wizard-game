class_name SwordPreview
extends Node3D
## Landing preview while the Sword Wall is held (caster only, freed by the Grimoire when the
## aim ends): a golden ghost of the sword standing where it will land, and its footprint
## projected onto the ground (Decal).

const FOOTPRINT_SIZE := Vector2i(256, 64)

static var _footprint: ImageTexture

var _spell: SwordSpell
var _caster: Node3D


func setup(spell: SwordSpell, caster: Node3D) -> void:
	_spell = spell
	_caster = caster
	top_level = true
	add_child(SwordWall.make_sword(true))
	var decal := Decal.new()
	decal.size = Vector3(SwordModel.HALF_WIDTH * 2.0 + 1.6, 8.0, 2.4)
	decal.texture_albedo = footprint_texture()
	decal.texture_emission = decal.texture_albedo
	decal.emission_energy = 2.0
	decal.modulate = SwordWall.COLOR
	decal.albedo_mix = 0.6
	add_child(decal)
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	if not is_instance_valid(_caster):
		return
	var land := _spell.find_landing(_caster)
	global_transform = Transform3D(SwordWall.ground_basis(land.facing), land.point)


## Soft glowing slot with a bright rim and tick marks along it (drawn once).
static func footprint_texture() -> ImageTexture:
	if _footprint:
		return _footprint
	var w := FOOTPRINT_SIZE.x
	var h := FOOTPRINT_SIZE.y
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			# Distance to a rounded slot (texture covers the decal; the slot is the blade).
			var px := (float(x) / (w - 1) * 2.0 - 1.0) * (SwordModel.HALF_WIDTH + 0.8)
			var py := (float(y) / (h - 1) * 2.0 - 1.0) * 1.2
			var qx := maxf(absf(px) - SwordModel.HALF_WIDTH + 0.3, 0.0)
			var d := Vector2(qx, absf(py)).length() - 0.3
			var rim := exp(-pow(d / 0.08, 2.0))
			var fill := (1.0 - smoothstep(-0.3, 0.0, d)) * 0.35
			var halo := exp(-maxf(d, 0.0) * 3.0) * 0.25
			var tick := 0.0
			if absf(py) < 0.75 and d > 0.0 and fmod(absf(px) + 0.25, 0.5) < 0.08:
				tick = (1.0 - smoothstep(0.1, 0.45, d)) * 0.8
			var a := clampf(maxf(maxf(rim, fill), maxf(halo, tick)), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_footprint = ImageTexture.create_from_image(img)
	return _footprint
