extends CanvasLayer
## Inventory screen (Inventory), opened with the "inventory" action (Tab): the satchel panel in
## the upper left and, below, the hotbar = the grimoire's 10 pages (open page lifted, number keys
## 1-0 above). The hotbar only shows while the inventory is open – in play you flip the book.
## Cards show their page art with a thin outline in the rarity colour (the flashy rarity auras
## belong to pages lying in the world, WorldItem). Drag cards between slots (they swap), drag one
## outside the panels to drop it into the world, hover for a tooltip. The hotbar only takes spell
## pages; the open page can't be moved while it is aimed or held.
##
## Laid out in a 1080-high virtual space, scaled to the window.

@export var player_path: NodePath

const CARD := Vector2(58, 82)
const HOTBAR_GAP := 12.0
const BAG_GAP := 14.0
const BAG_COLUMNS := 4
const BAG_PAD := 26.0
const BOTTOM := 30.0
## Keep the hotbar clear of the mana/health bars (bottom left, Hud) in pixels.
const BARS_RIGHT := 470.0
const PARCHMENT := Color(0.93, 0.86, 0.7)
const PRIMORDIAL_PAPER := Color(0.08, 0.05, 0.11)
const INK_SHADER := preload("res://shaders/ui/primordial_ink.gdshader")

var _player: Node
var _inv: Inventory
var _open := false
var _root: Control
var _hotbar: Control
var _bag_panel: Control
var _tooltip: PanelContainer
var _tip_name: Label
var _tip_rarity: Label
var _tip_desc: Label
var _tip_stats: GridContainer
var _hover_slot: Vector2i = Vector2i(-1, -1)
## "[E] Pick up <name>" near a page on the ground.
var _prompt: Label
var _prompt_flash := 0.0
## Vector2i(container, index) -> {"slot", "card", "card_style", "well_style", "art", "color", "hover", "sel"}
var _slots := {}


func _ready() -> void:
	layer = 30
	add_to_group("inventory_ui")
	_player = get_node_or_null(player_path)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.make()
	add_child(_root)
	# Dropping a card anywhere outside the panels throws it into the world.
	_root.set_drag_forwarding(Callable(), _can_drop_outside, _drop_outside)
	_build_hotbar()
	_build_bag()
	_build_tooltip()
	_build_prompt()
	_root.resized.connect(_layout)
	if _player:
		_inv = _player.get("inventory")
		_inv.changed.connect(_refresh)
		_inv.full.connect(func() -> void: _prompt_flash = 1.0)
		(_player.get("grimoire") as Grimoire).page_changed.connect(func(_p: int, _s: Spell) -> void: _refresh())
	_layout()
	_refresh()


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_bag_panel.visible = true
	_hotbar.visible = true
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	_bag_panel.visible = false
	_hotbar.visible = false
	_tooltip.visible = false
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _can_open() -> bool:
	if _player == null or _player.process_mode == Node.PROCESS_MODE_DISABLED or get_tree().paused:
		return false
	for group in ["pause_menu", "map_overlay"]:
		var ui := get_tree().get_first_node_in_group(group)
		if ui and ui.is_open():
			return false
	return not _player.is_dead()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory") and not event.is_echo():
		if _open:
			close()
			get_viewport().set_input_as_handled()
		elif _can_open():
			open()
			get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed("pause") and not event.is_echo():
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _player == null:
		return
	# Hidden under the pause menu and map; closes if the player dies.
	var menu_open: bool = _player.is_menu_open()
	_root.visible = not menu_open
	if _open and (menu_open or _player.is_dead()):
		close()
	if _tooltip.visible:
		_place_tooltip()
	_update_prompt()


# --- Building ---------------------------------------------------------------------------

func _build_hotbar() -> void:
	_hotbar = Control.new()
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hotbar)
	for i in 10:
		var s := _make_slot(Inventory.HOTBAR, i)
		s.position = Vector2(i * (CARD.x + HOTBAR_GAP), 0)
		_hotbar.add_child(s)
		var key := Label.new()
		key.text = str((i + 1) % 10)
		key.add_theme_font_size_override("font_size", 15)
		key.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75, 0.85))
		key.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.03))
		key.add_theme_constant_override("outline_size", 5)
		key.position = Vector2(4, -22)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.add_child(key)
	_hotbar.size = Vector2(10 * CARD.x + 9 * HOTBAR_GAP, CARD.y)
	_hotbar.visible = false


func _build_bag() -> void:
	var rows := ceili(float(Inventory.BAG_SIZE) / BAG_COLUMNS)
	var grid_size := Vector2(BAG_COLUMNS * CARD.x + (BAG_COLUMNS - 1) * BAG_GAP, rows * CARD.y + (rows - 1) * BAG_GAP)
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.05, 0.06, 0.82)
	style.border_color = Color(0.78, 0.62, 0.34, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 12
	panel.add_theme_stylebox_override("panel", style)
	panel.size = grid_size + Vector2(BAG_PAD * 2.0, BAG_PAD * 2.0 + 56.0 + 34.0)
	_bag_panel = panel
	_root.add_child(panel)
	var title := Label.new()
	title.text = "Satchel"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.62))
	title.position = Vector2(BAG_PAD, 14)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)
	var line := ColorRect.new()
	line.color = Color(0.78, 0.62, 0.34, 0.5)
	line.position = Vector2(BAG_PAD, 56)
	line.size = Vector2(grid_size.x, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(line)
	for i in Inventory.BAG_SIZE:
		var s := _make_slot(Inventory.BAG, i)
		s.position = Vector2(BAG_PAD, BAG_PAD + 50.0) + Vector2(i % BAG_COLUMNS, i / BAG_COLUMNS) * (CARD + Vector2(BAG_GAP, BAG_GAP))
		panel.add_child(s)
	var hint := Label.new()
	hint.text = "Drag to move  ·  drag outside to drop"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.85, 0.78, 0.65, 0.7))
	hint.position = Vector2(BAG_PAD, panel.size.y - 38)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hint)
	panel.visible = false


func _make_slot(container: int, index: int) -> Control:
	var slot := Control.new()
	slot.size = CARD
	slot.custom_minimum_size = CARD
	var well := Panel.new()
	var ws := StyleBoxFlat.new()
	ws.bg_color = Color(0.0, 0.0, 0.0, 0.32)
	ws.border_color = Color(0.85, 0.78, 0.62, 0.22)
	ws.set_border_width_all(1)
	ws.set_corner_radius_all(5)
	well.add_theme_stylebox_override("panel", ws)
	well.size = CARD
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(well)
	var card := Panel.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = PARCHMENT
	cs.set_corner_radius_all(5)
	cs.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", cs)
	card.size = CARD
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(card)
	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size = CARD
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(art)
	var ref := Vector2i(container, index)
	_slots[ref] = {"slot": slot, "card": card, "card_style": cs, "well_style": ws, "art": art,
		"color": Color.WHITE, "hover": false, "sel": false}
	slot.set_drag_forwarding(_get_drag.bind(ref), _can_drop.bind(ref), _drop.bind(ref))
	slot.mouse_entered.connect(func() -> void: _set_hover(ref, true))
	slot.mouse_exited.connect(func() -> void: _set_hover(ref, false))
	return slot


func _build_tooltip() -> void:
	_tooltip = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.04, 0.05, 0.94)
	style.border_color = Color(0.78, 0.62, 0.34)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	_tooltip.add_theme_stylebox_override("panel", style)
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_child(box)
	_tip_name = _tip_label(26)
	_tip_rarity = _tip_label(16)
	_tip_desc = _tip_label(16)
	_tip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_desc.custom_minimum_size = Vector2(320, 0)
	_tip_desc.add_theme_color_override("font_color", Color(0.88, 0.83, 0.74))
	_tip_stats = GridContainer.new()
	_tip_stats.columns = 2
	_tip_stats.add_theme_constant_override("h_separation", 18)
	_tip_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in [_tip_name, _tip_rarity, _tip_desc, _tip_stats]:
		box.add_child(c)
	_tooltip.visible = false
	_root.add_child(_tooltip)


func _tip_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_prompt() -> void:
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 26)
	_prompt.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.03))
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.visible = false
	_root.add_child(_prompt)


func _update_prompt() -> void:
	_prompt_flash = move_toward(_prompt_flash, 0.0, get_process_delta_time() * 1.5)
	var target: Dictionary = _inv.get_pickup_target() if _inv and not _open else {}
	_prompt.visible = not target.is_empty()
	if not _prompt.visible:
		return
	var item: Resource = (target.node as WorldItem).item
	var spell := item as Spell
	var name := spell.spell_name if spell else "item"
	var key := Settings.binding_text("interact")
	if _prompt_flash > 0.0:
		_prompt.text = "No room in the satchel"
		_prompt.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	else:
		_prompt.text = "[%s]  Pick up %s" % [key, name]
		_prompt.add_theme_color_override("font_color", Color(1.0, 0.94, 0.8))
	var view := _root.size
	_prompt.size = Vector2(view.x, 40)
	_prompt.position = Vector2(0, view.y * 0.7)


func _layout() -> void:
	var view := _root.size
	var s := view.y / 1080.0
	for c in [_hotbar, _bag_panel, _tooltip]:
		c.scale = Vector2.ONE * s
	var hw := _hotbar.size.x * s
	_hotbar.position = Vector2(maxf((view.x - hw) * 0.5, BARS_RIGHT * s + 24.0), view.y - (BOTTOM + CARD.y) * s)
	_bag_panel.position = Vector2(64, 70) * s


# --- Content ----------------------------------------------------------------------------

func _refresh() -> void:
	if _inv == null:
		return
	var current := _inv.grimoire.current_page
	for ref: Vector2i in _slots:
		var e: Dictionary = _slots[ref]
		var item := _inv.get_item(ref.x, ref.y)
		var spell := item as Spell
		_show_card(e, item)
		var sel := ref.x == Inventory.HOTBAR and ref.y == current
		if ref.x == Inventory.HOTBAR:
			(e.slot as Control).position.y = -8.0 if sel else 0.0
		e.sel = sel
		_style_card(e)


## Card visuals for an item (shared with the drag preview).
func _show_card(e: Dictionary, item: Resource) -> void:
	var spell := item as Spell
	var rarity := -1 if item == null else (spell.rarity if spell else 0)
	(e.card as Control).visible = item != null
	(e.art as TextureRect).texture = spell.page_texture if spell else null
	var primordial := rarity == Spell.Rarity.PRIMORDIAL
	(e.card_style as StyleBoxFlat).bg_color = PRIMORDIAL_PAPER if primordial else PARCHMENT
	# Primordial ink glows pale violet on the scorched page.
	var art := e.art as TextureRect
	if primordial and art.material == null:
		var ink := ShaderMaterial.new()
		ink.shader = INK_SHADER
		art.material = ink
	elif not primordial:
		art.material = null
	e.color = spell.get_rarity_color() if spell else Color(0.85, 0.78, 0.62)
	_style_card(e)


## Thin outline in the rarity colour, a little stronger on hover / for the open page.
func _style_card(e: Dictionary) -> void:
	var lit: bool = e.hover or e.sel
	var c: Color = e.color
	var cs := e.card_style as StyleBoxFlat
	cs.border_color = c.lightened(0.25) if lit else c
	cs.set_border_width_all(3 if lit else 2)
	var ws := e.well_style as StyleBoxFlat
	ws.border_color = Color(1.0, 0.9, 0.7, 0.6) if lit else Color(0.85, 0.78, 0.62, 0.22)


func _set_hover(ref: Vector2i, on: bool) -> void:
	var e: Dictionary = _slots[ref]
	e.hover = on
	_style_card(e)
	if on:
		_hover_slot = ref
		_show_tooltip(_inv.get_item(ref.x, ref.y) if _inv else null)
	elif _hover_slot == ref:
		_hover_slot = Vector2i(-1, -1)
		_tooltip.visible = false


func _show_tooltip(item: Resource) -> void:
	var spell := item as Spell
	if spell == null or not _open:
		_tooltip.visible = false
		return
	var rc := spell.get_rarity_color()
	_tip_name.text = spell.spell_name
	_tip_name.add_theme_color_override("font_color", rc.lightened(0.25) if spell.rarity != Spell.Rarity.PRIMORDIAL else Color(0.85, 0.7, 1.0))
	_tip_rarity.text = "%s spell page" % spell.get_rarity_name()
	_tip_rarity.add_theme_color_override("font_color", rc)
	_tip_desc.text = spell.description
	for c in _tip_stats.get_children():
		_tip_stats.remove_child(c)
		c.queue_free()
	for line in spell.get_stats():
		var k := _tip_label(16)
		k.text = str(line[0])
		k.add_theme_color_override("font_color", Color(0.75, 0.68, 0.56))
		var v := _tip_label(16)
		v.text = str(line[1])
		v.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85))
		_tip_stats.add_child(k)
		_tip_stats.add_child(v)
	_tooltip.visible = true
	_tooltip.reset_size()
	_place_tooltip()


func _place_tooltip() -> void:
	var view := _root.size
	var size := _tooltip.size * _tooltip.scale
	var pos := _root.get_local_mouse_position() + Vector2(24, 18)
	if pos.x + size.x > view.x - 8.0:
		pos.x = _root.get_local_mouse_position().x - size.x - 18.0
	pos.y = clampf(pos.y, 8.0, view.y - size.y - 8.0)
	_tooltip.position = pos


# --- Drag and drop ------------------------------------------------------------------------

func _get_drag(_at: Vector2, ref: Vector2i) -> Variant:
	if not _open or _inv == null:
		return null
	var item := _inv.get_item(ref.x, ref.y)
	if item == null or _inv.is_locked(ref.x, ref.y):
		return null
	_tooltip.visible = false
	var preview := Control.new()
	var holder := _make_preview(item)
	holder.position = -CARD * 0.5
	preview.add_child(holder)
	preview.scale = _hotbar.scale * 1.08
	_root.set_drag_preview(preview)
	return {"inventory_slot": ref}


func _make_preview(item: Resource) -> Control:
	var tmp := _make_slot(-1, -1)
	_show_card(_slots[Vector2i(-1, -1)], item)
	_slots.erase(Vector2i(-1, -1))
	tmp.modulate.a = 0.92
	return tmp


func _can_drop(_at: Vector2, data: Variant, ref: Vector2i) -> bool:
	if not (data is Dictionary and data.has("inventory_slot")):
		return false
	var from: Vector2i = data.inventory_slot
	return _inv.can_move(from.x, from.y, ref.x, ref.y)


func _drop(_at: Vector2, data: Variant, ref: Vector2i) -> void:
	var from: Vector2i = data.inventory_slot
	_inv.move(from.x, from.y, ref.x, ref.y)


func _can_drop_outside(at: Vector2, data: Variant) -> bool:
	if not (_open and data is Dictionary and data.has("inventory_slot")):
		return false
	# Not over the satchel panel or the hotbar row (those cancel the drag instead).
	return not _bag_panel.get_global_rect().has_point(at) and not _hotbar.get_global_rect().grow(20).has_point(at)


func _drop_outside(_at: Vector2, data: Variant) -> void:
	var from: Vector2i = data.inventory_slot
	_inv.drop(from.x, from.y)
