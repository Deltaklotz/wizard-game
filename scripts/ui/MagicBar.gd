class_name MagicBar
extends ColorRect
## One ornate resource bar (shaders/ui/magic_bar.gdshader). Losses leave a pale "ghost"
## that lingers briefly and then drains after the real value; gains fill smoothly.

const PAD := 20.0
const GHOST_HOLD := 0.45

var value := 1.0
var max_value := 1.0

var _shown := 1.0
var _ghost := 1.0
var _ghost_hold := 0.0
var _flash := 0.0
var _shake := 0.0
var _mat: ShaderMaterial
var _label: Label
var _base_x := 0.0


func _init(deep: Color, bright: Color, phase: float, bar_size: Vector2) -> void:
	custom_minimum_size = bar_size + Vector2.ONE * PAD * 2.0
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/ui/magic_bar.gdshader")
	_mat.set_shader_parameter("rect_size", custom_minimum_size)
	_mat.set_shader_parameter("pad", PAD)
	_mat.set_shader_parameter("deep", deep)
	_mat.set_shader_parameter("bright", bright)
	_mat.set_shader_parameter("phase", phase)
	material = _mat
	_label = Label.new()
	_label.theme = UiTheme.make()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85, 0.9))
	_label.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.06, 0.85))
	_label.add_theme_constant_override("outline_size", 5)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector2(PAD, PAD)
	_label.size = bar_size - Vector2(bar_size.y * 0.55, 0.0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func set_values(current: float, maximum: float) -> void:
	max_value = maxf(maximum, 0.001)
	var v := clampf(current / max_value, 0.0, 1.0)
	if v < value - 0.0005:
		# A loss: keep the ghost where it was and restart its hold timer.
		_ghost = maxf(_ghost, _shown)
		_ghost_hold = GHOST_HOLD
	value = v
	_label.text = "%d / %d" % [roundi(current), roundi(maximum)]


## White-hot pulse and a little shake, e.g. when a spell fails for lack of mana.
func pulse() -> void:
	_flash = 1.0
	_shake = 1.0


func _process(delta: float) -> void:
	# Drops snap quickly, refills ease in.
	var rate := 18.0 if value < _shown else 6.0
	_shown = lerpf(_shown, value, 1.0 - exp(-rate * delta))
	if _ghost_hold > 0.0:
		_ghost_hold -= delta
	else:
		_ghost = move_toward(_ghost, _shown, delta * 0.6)
	_ghost = maxf(_ghost, _shown)
	_flash = move_toward(_flash, 0.0, delta * 2.5)
	_shake = move_toward(_shake, 0.0, delta * 3.0)
	_mat.set_shader_parameter("fill", _shown)
	_mat.set_shader_parameter("ghost", _ghost)
	_mat.set_shader_parameter("flash", _flash)
	pivot_offset = size * 0.5
	position.x = _base_x + sin(_shake * 38.0) * 4.0 * _shake


func set_base_x(x: float) -> void:
	_base_x = x
	position.x = x
