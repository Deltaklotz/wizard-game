class_name UiTheme
extends RefCounted
## Shared look of the menus (pause menu, title screen): dark violet panels, gold trim,
## book-style serif font.

const GOLD := Color(0.78, 0.62, 0.32)
const TEXT := Color(0.9, 0.86, 0.78)
const TEXT_DIM := Color(0.66, 0.62, 0.56)


static func make() -> Theme:
	var t := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Palatino Linotype", "Book Antiqua", "Georgia", "Times New Roman", "serif"])
	t.default_font = font
	t.default_font_size = 19

	t.set_stylebox("panel", "PanelContainer", box(Color(0.07, 0.05, 0.09, 0.94), GOLD, 2, 12, 28))
	t.set_color("font_color", "Label", TEXT)

	var normal := box(Color(0.15, 0.1, 0.16), Color(0.45, 0.36, 0.22), 1, 7, 10)
	var hover := box(Color(0.25, 0.17, 0.23), GOLD, 1, 7, 10)
	var pressed := box(Color(0.33, 0.21, 0.28), GOLD, 2, 7, 10)
	var disabled := box(Color(0.1, 0.08, 0.1), Color(0.3, 0.26, 0.2), 1, 7, 10)
	var focus := box(Color(0, 0, 0, 0), Color(1.0, 0.85, 0.5), 2, 7, 10)
	focus.draw_center = false
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color(1.0, 0.93, 0.72))
		t.set_color("font_pressed_color", type, Color(1.0, 0.93, 0.72))
		t.set_color("font_focus_color", type, Color(1.0, 0.93, 0.72))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(state, "CheckButton", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_stylebox("focus", "CheckButton", focus)

	t.set_stylebox("panel", "TabContainer", box(Color(0.1, 0.07, 0.12, 0.9), Color(0.4, 0.32, 0.2), 1, 8, 6))
	t.set_stylebox("tab_selected", "TabContainer", box(Color(0.22, 0.15, 0.21), GOLD, 1, 6, 10))
	t.set_stylebox("tab_unselected", "TabContainer", box(Color(0.12, 0.08, 0.13), Color(0.35, 0.28, 0.18), 1, 6, 10))
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(0.18, 0.12, 0.18), Color(0.6, 0.48, 0.28), 1, 6, 10))
	t.set_color("font_selected_color", "TabContainer", Color(1.0, 0.9, 0.65))
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)

	var track := box(Color(0.2, 0.15, 0.2), Color(0.4, 0.32, 0.2), 1, 4, 0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := box(Color(0.62, 0.48, 0.25), Color(0.78, 0.62, 0.32), 1, 4, 0)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)

	t.set_stylebox("panel", "PopupMenu", box(Color(0.1, 0.07, 0.12, 0.98), GOLD, 1, 6, 8))
	t.set_stylebox("hover", "PopupMenu", box(Color(0.3, 0.2, 0.26), GOLD, 0, 4, 4))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color(1.0, 0.93, 0.72))

	var field := box(Color(0.1, 0.07, 0.11), Color(0.45, 0.36, 0.22), 1, 6, 9)
	var field_focus := box(Color(0.13, 0.09, 0.14), GOLD, 2, 6, 9)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM, 0.6))
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(GOLD, 0.35))
	return t


static func box(bg: Color, border: Color, border_w: int, radius: int, margin: float) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(border_w)
	b.set_corner_radius_all(radius)
	b.content_margin_left = margin * 1.6
	b.content_margin_right = margin * 1.6
	b.content_margin_top = margin
	b.content_margin_bottom = margin
	return b
