extends Control

signal manage_pageflip(give_control_to_book: bool)

@onready var label_title    = $LabelTitle
@onready var grid_container = $GridContainer
@onready var label_count    = $LabelCount

var font_title = preload("res://Assets/Fonts/Cinzel.ttf")
var font_body  = preload("res://Assets/Fonts/IMFellEnglish.ttf")

var color_title       = Color("#8a5a2e")
var color_ink         = Color("#3a2510")
var color_muted       = Color("#7a5a30")
var color_slot_bg     = Color("#b8955a66")
var color_slot_border = Color("#5a3a1aee")
var color_slot_hover  = Color("#c8a45a")

const GRID_COLS   = 3
const TOTAL_SLOTS = 12
const SLOT_SIZE   = Vector2(100, 100)

var _drop_qty: int = 1
var _context_menu: Node = null
var _selected_slot: int = -1

# ================================================================
# READY
# ================================================================

func _ready() -> void:
	label_title.text = tr("JOURNAL_INVENTORY_TITLE")
	_apply_styles()
	_update()
	if not InventoryManager.inventory_changed.is_connected(_update):
		InventoryManager.inventory_changed.connect(_update)
	GameManager.journal_closed.connect(_on_journal_closing)
	InventoryManager.perfume_already_active.connect(func():
		_show_popup("¿Más perfume? Ya hueles como un burdel francés en llamas.")
	)

# ================================================================
# UPDATE
# ================================================================

func _update() -> void:
	_build_grid()
	var total = 0
	for entry in InventoryManager.get_pocket():
		if entry != null:
			total += entry["qty"]
	label_count.text = str(total) + " / " + str(TOTAL_SLOTS)

# ================================================================
# JOURNAL CLOSING
# ================================================================

func _on_journal_closing() -> void:
	if is_instance_valid(_context_menu):
		_context_menu.queue_free()
		_context_menu = null
	_selected_slot = -1

# ================================================================
# GRID
# ================================================================

func _build_grid() -> void:
	if is_instance_valid(_context_menu):
		_context_menu.queue_free()
		_context_menu = null

	for child in grid_container.get_children():
		child.queue_free()
	grid_container.columns = GRID_COLS

	var pocket = InventoryManager.get_pocket()
	for i in range(TOTAL_SLOTS):
		var entry = pocket[i] if i < pocket.size() else null
		grid_container.add_child(_make_slot(entry, i))

	_refresh_selection_highlight()

func _refresh_selection_highlight() -> void:
	for i in range(grid_container.get_child_count()):
		var slot_node = grid_container.get_child(i)
		if i == _selected_slot:
			slot_node.modulate = Color(1.3, 1.2, 0.6)
		else:
			slot_node.modulate = Color(1.0, 1.0, 1.0)

# ================================================================
# SLOT
# ================================================================

func _make_slot(entry, slot_index: int) -> Control:
	var slot = PanelContainer.new()
	slot.custom_minimum_size = SLOT_SIZE

	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = color_slot_bg
	style_normal.border_color = color_slot_border
	style_normal.set_border_width_all(3)
	style_normal.set_corner_radius_all(3)

	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = Color("#c8a45a44")
	style_hover.border_color = color_slot_hover
	style_hover.set_border_width_all(3)
	style_hover.set_corner_radius_all(3)

	slot.add_theme_stylebox_override("panel", style_normal)

	# Slot vacío — solo acepta drops
	if entry == null:
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.mouse_entered.connect(func():
			if _selected_slot != -1:
				slot.add_theme_stylebox_override("panel", style_hover)
		)
		slot.mouse_exited.connect(func():
			slot.add_theme_stylebox_override("panel", style_normal)
		)
		slot.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				if _selected_slot != -1:
					InventoryManager.move_item(_selected_slot, slot_index)
					_selected_slot = -1
		)
		return slot

	var item_data = InventoryManager.get_item_data(entry["id"])
	if item_data == null:
		return slot

	var qty = entry["qty"]

	var overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(overlay)
	slot.set_meta("overlay", overlay)

	if item_data.icon:
		var icon_rect = TextureRect.new()
		icon_rect.texture = item_data.icon
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_rect.set_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(icon_rect)
	else:
		var placeholder = Label.new()
		placeholder.text = item_data.display_name.left(3)
		_style_label(placeholder, font_body, 16, color_muted)
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(placeholder)

	if qty > 1:
		var qty_lbl = Label.new()
		qty_lbl.text = "x" + str(qty)
		_style_label(qty_lbl, font_body, 20, color_ink)
		qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		qty_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		qty_lbl.set_offset(SIDE_RIGHT, -4)
		qty_lbl.set_offset(SIDE_BOTTOM, -4)
		qty_lbl.add_theme_constant_override("outline_size", 6)
		qty_lbl.add_theme_color_override("font_outline_color", Color("#f5e6c8"))
		qty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(qty_lbl)

	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.mouse_entered.connect(func():
		if _selected_slot != -1:
			slot.add_theme_stylebox_override("panel", style_hover)
			return
		var tw = slot.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(slot, "modulate", Color(1.2, 1.1, 0.8), 0.4)
		tw.tween_property(slot, "modulate", Color(1.0, 1.0, 1.0), 0.4)
		slot.set_meta("hover_tween", tw)
		slot.add_theme_stylebox_override("panel", style_hover)
	)
	slot.mouse_exited.connect(func():
		if slot.has_meta("hover_tween"):
			slot.get_meta("hover_tween").kill()
			slot.remove_meta("hover_tween")
		if _selected_slot != slot_index:
			slot.modulate = Color(1.0, 1.0, 1.0)
		slot.add_theme_stylebox_override("panel", style_normal)
	)
	slot.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _selected_slot != -1:
				if _selected_slot != slot_index:
					InventoryManager.move_item(_selected_slot, slot_index)
				_selected_slot = -1
			else:
				_show_context_menu(item_data, slot_index, qty)
	)

	return slot

# ================================================================
# SELECCIÓN
# ================================================================

func _select_slot(slot_index: int) -> void:
	_selected_slot = slot_index
	_refresh_selection_highlight()

# ================================================================
# FADE
# ================================================================

func _use_with_fade(slot_index: int) -> void:
	await _fade_overlay(slot_index)
	InventoryManager.use_item_from_slot(slot_index)

func _drop_with_fade(slot_index: int, qty: int) -> void:
	await _fade_overlay(slot_index)
	InventoryManager.remove_item_from_slot(slot_index, qty)

func _fade_overlay(slot_index: int) -> void:
	if InventoryManager.inventory_changed.is_connected(_update):
		InventoryManager.inventory_changed.disconnect(_update)

	var slot_node = grid_container.get_child(slot_index)
	if is_instance_valid(slot_node) and slot_node.has_meta("overlay"):
		var overlay_node = slot_node.get_meta("overlay")
		if is_instance_valid(overlay_node):
			var tw = overlay_node.create_tween()
			tw.tween_property(overlay_node, "modulate:a", 0.0, 0.3)
			await tw.finished

	if not InventoryManager.inventory_changed.is_connected(_update):
		InventoryManager.inventory_changed.connect(_update)

# ================================================================
# POPUP
# ================================================================

func _show_popup(message: String) -> void:
	var existing = get_node_or_null("PopupMessage")
	if existing:
		existing.queue_free()

	var popup = PanelContainer.new()
	popup.name = "PopupMessage"
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#1e1208f0")
	style.border_color = Color("#c8a45a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	popup.add_theme_stylebox_override("panel", style)

	var lbl = Label.new()
	lbl.text = message
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.custom_minimum_size = Vector2(300, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(lbl, font_body, 22, Color("#e8d5a0"))
	popup.add_child(lbl)
	add_child(popup)

	await get_tree().process_frame
	var grid_rect = grid_container.get_rect()
	popup.position = grid_rect.get_center() - popup.size / 2.0

	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(popup):
		popup.queue_free()

# ================================================================
# CONTEXT MENU
# ================================================================

func _show_context_menu(item_data: ItemData, slot_index: int, qty: int) -> void:
	if is_instance_valid(_context_menu):
		_context_menu.queue_free()
		_context_menu = null

	var menu = PanelContainer.new()
	menu.name = "ContextMenu"
	_context_menu = menu

	var style = StyleBoxFlat.new()
	style.bg_color = Color("#1e1208f0")
	style.border_color = Color("#c8a45a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 8
	menu.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	menu.add_child(vbox)

	_add_menu_header(vbox, item_data.display_name.to_upper())

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer)

	if item_data.item_type == ItemData.ItemType.EQUIPPABLE:
		_add_menu_button(vbox, tr("ITEM_EQUIP"), func():
			_context_menu = null
			menu.queue_free()
			InventoryManager.use_item_from_slot(slot_index)
		)
	else:
		_add_menu_button(vbox, tr("ITEM_USE"), func():
			_context_menu = null
			menu.queue_free()
			_use_with_fade(slot_index)
		)

	_add_menu_button(vbox, tr("ITEM_MOVE"), func():
		_context_menu = null
		menu.queue_free()
		_select_slot(slot_index)
	)

	if qty > 1:
		_add_menu_button(vbox, tr("ITEM_DROP"), func():
			_on_drop_some(slot_index, qty, menu)
		)
	else:
		_add_menu_button(vbox, tr("ITEM_DROP"), func():
			_context_menu = null
			menu.queue_free()
			_drop_with_fade(slot_index, 1)
		)

	_add_menu_button(vbox, tr("ITEM_CANCEL"), func():
		_context_menu = null
		menu.queue_free()
	)

	add_child(menu)

	await get_tree().process_frame
	var grid_rect = grid_container.get_rect()
	menu.position = grid_rect.get_center() - menu.size / 2.0

func _on_drop_some(slot_index: int, max_qty: int, menu: Node) -> void:
	_drop_qty = 1

	for child in menu.get_children():
		child.queue_free()

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	menu.add_child(vbox)

	_add_menu_header(vbox, tr("ITEM_DROP_QTY").to_upper())

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer)

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)

	var qty_label = Label.new()
	qty_label.text = str(_drop_qty)
	qty_label.custom_minimum_size = Vector2(40, 0)
	_style_label(qty_label, font_title, 28, Color("#f5e6c8"))
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var btn_minus = Button.new()
	btn_minus.text = "−"
	btn_minus.custom_minimum_size = Vector2(40, 40)
	_style_qty_btn(btn_minus)
	btn_minus.pressed.connect(func():
		_drop_qty = max(1, _drop_qty - 1)
		qty_label.text = str(_drop_qty)
	)

	var btn_plus = Button.new()
	btn_plus.text = "+"
	btn_plus.custom_minimum_size = Vector2(40, 40)
	_style_qty_btn(btn_plus)
	btn_plus.pressed.connect(func():
		_drop_qty = min(max_qty, _drop_qty + 1)
		qty_label.text = str(_drop_qty)
	)

	hbox.add_child(btn_minus)
	hbox.add_child(qty_label)
	hbox.add_child(btn_plus)

	_add_menu_button(vbox, tr("ITEM_DROP_CONFIRM"), func():
		var qty_to_drop = _drop_qty
		_context_menu = null
		menu.queue_free()
		_drop_with_fade(slot_index, qty_to_drop)
	)
	_add_menu_button(vbox, tr("ITEM_CANCEL"), func():
		_context_menu = null
		menu.queue_free()
	)

# ================================================================
# HELPERS UI
# ================================================================

func _add_menu_header(parent: Node, text: String) -> void:
	var header = PanelContainer.new()
	var header_style = StyleBoxFlat.new()
	header_style.bg_color = Color("#c8a45a")
	header_style.corner_radius_top_left = 6
	header_style.corner_radius_top_right = 6
	header_style.corner_radius_bottom_left = 0
	header_style.corner_radius_bottom_right = 0
	header_style.content_margin_left = 16
	header_style.content_margin_right = 16
	header_style.content_margin_top = 10
	header_style.content_margin_bottom = 10
	header.add_theme_stylebox_override("panel", header_style)
	var lbl = Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(lbl, font_title, 20, Color("#1e1208"))
	header.add_child(lbl)
	parent.add_child(header)

func _add_menu_button(parent: Node, text: String, callback: Callable) -> void:
	var btn = Button.new()
	btn.text = text
	btn.flat = true
	btn.custom_minimum_size = Vector2(180, 40)
	btn.add_theme_color_override("font_color", Color("#e8d5a0"))
	btn.add_theme_color_override("font_hover_color", Color("#c8a45a"))
	btn.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	btn.add_theme_font_override("font", font_body)
	btn.add_theme_font_size_override("font_size", 18)
	btn.pressed.connect(callback)
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color("#c8a45a22")
	hover_style.set_border_width_all(0)
	btn.add_theme_stylebox_override("hover", hover_style)
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0, 0, 0, 0)
	normal_style.set_border_width_all(0)
	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_stylebox_override("pressed", normal_style)
	btn.add_theme_stylebox_override("focus", normal_style)
	parent.add_child(btn)

func _style_qty_btn(btn: Button) -> void:
	btn.add_theme_font_override("font", font_title)
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color("#e8d5a0"))
	btn.add_theme_color_override("font_hover_color", Color("#c8a45a"))
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color("#c8a45a22")
	hover_style.set_border_width_all(1)
	hover_style.border_color = Color("#c8a45a")
	hover_style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", hover_style)
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color("#3a2510aa")
	normal_style.set_border_width_all(1)
	normal_style.border_color = Color("#c8a45a66")
	normal_style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_stylebox_override("focus", normal_style)

func _apply_styles() -> void:
	_style_label(label_title, font_body, 72, color_title)
	label_title.add_theme_constant_override("outline_size", 2)
	label_title.add_theme_color_override("font_outline_color", Color("#3a1a08"))
	_style_label(label_count, font_title, 18, color_muted)

func _style_label(label: Label, font: FontFile, font_size: int, color: Color) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)

func _unhandled_key_input(event: InputEvent) -> void:
	if _selected_slot != -1 or is_instance_valid(_context_menu):
		return

	if event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		manage_pageflip.emit(true)
		BookAPI.next_page()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		manage_pageflip.emit(true)
		BookAPI.prev_page()
		get_viewport().set_input_as_handled()
