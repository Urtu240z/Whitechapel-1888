extends Control

signal manage_pageflip(give_control_to_book: bool)

@onready var label_title:    Label          = $LabelTitle
@onready var grid_container: GridContainer  = $GridContainer
@onready var label_count:    Label          = $LabelCount
@onready var _desc_label:    Label          = $DescPanel/DescLabel

var font_title = preload("res://Assets/Fonts/Cinzel.ttf")
var font_body  = preload("res://Assets/Fonts/IMFellEnglish.ttf")

var _drop_qty: int = 1
var _context_menu: Node = null
var _selected_slot: int = -1
var _perfume_claves: Array = []
var _perfume_index: int = 0

# ================================================================
# READY
# ================================================================

func _ready() -> void:
	label_title.text = tr("JOURNAL_INVENTORY_TITLE")
	_show_desc_default()
	_update()

	if not InventoryManager.inventory_changed.is_connected(_update):
		InventoryManager.inventory_changed.connect(_update)

	GameManager.journal_closed.connect(_on_journal_closing)

	StateManager.state_changed.connect(func(_from, to):
		if to == StateManager.State.JOURNAL:
			if not InventoryManager.inventory_changed.is_connected(_update):
				InventoryManager.inventory_changed.connect(_update)
			_update()
	)

	InventoryManager.perfume_already_active.connect(func():
		if _perfume_index == 0:
			_perfume_claves = [
				"PERFUME_POPUP_1", "PERFUME_POPUP_2", "PERFUME_POPUP_3",
				"PERFUME_POPUP_4", "PERFUME_POPUP_5", "PERFUME_POPUP_6",
			]
			_perfume_claves.shuffle()
		_show_popup(tr(_perfume_claves[_perfume_index]))
		_perfume_index = (_perfume_index + 1) % _perfume_claves.size()
	)

# ================================================================
# DESCRIPCIÓN
# ================================================================

func _show_desc(item_data: ItemData, qty: int) -> void:
	if not is_instance_valid(_desc_label):
		return
	var text := item_data.display_name + "\n"
	if not item_data.description.is_empty():
		text += tr(item_data.description) + "\n"
	if item_data.item_type == ItemData.ItemType.EQUIPPABLE:
		if item_data.usos_max > 0:
			text += "\nUsos restantes: %d / %d" % [qty, item_data.usos_max]
		if item_data.duracion_horas > 0:
			text += "\nDuración: %.0f horas" % item_data.duracion_horas
		if item_data.sex_appeal_bonus != 0:
			text += "\nSex appeal: %+.0f" % item_data.sex_appeal_bonus
		if item_data.higiene_bonus != 0:
			text += "\nHigiene: %+.0f" % item_data.higiene_bonus
		if item_data.nervios_bonus != 0:
			text += "\nNervios: %+.0f" % item_data.nervios_bonus
	else:
		for stat in item_data.effects.keys():
			var val: float = item_data.effects[stat]
			text += "\n%s: %+.0f" % [stat, val]
	_desc_label.text = text.strip_edges()

func _show_desc_default() -> void:
	if is_instance_valid(_desc_label):
		_desc_label.text = "Pasa el cursor sobre un objeto\npara ver su descripción."

func _hide_desc() -> void:
	_show_desc_default()

# ================================================================
# UPDATE
# ================================================================

func _update() -> void:
	if not StateManager.is_state(StateManager.State.JOURNAL):
		label_count.text = _get_total_count()
		return
	_refresh_slots()
	label_count.text = _get_total_count()

func _get_total_count() -> String:
	var total := 0
	for entry in InventoryManager.get_pocket():
		if entry != null:
			total += entry["qty"]
	return str(total) + " / " + str(InventoryManager.get_slots_activos())

# ================================================================
# JOURNAL CLOSING
# ================================================================

func _on_journal_closing() -> void:
	_release_local_gui_state()
	_hide_desc()
	if is_instance_valid(_context_menu):
		_context_menu.queue_free()
		_context_menu = null
	_selected_slot = -1
	if InventoryManager.inventory_changed.is_connected(_update):
		InventoryManager.inventory_changed.disconnect(_update)

# ================================================================
# SLOTS — actualizar contenido de los nodos fijos
# ================================================================

func _refresh_slots() -> void:
	_hide_desc()
	if is_instance_valid(_context_menu):
		_context_menu.queue_free()
		_context_menu = null

	var slots_activos := InventoryManager.get_slots_activos()
	var pocket := InventoryManager.get_pocket()

	for i in range(12):
		var slot_node := grid_container.get_node_or_null("Slot%d" % i) as Control
		if not slot_node:
			continue

		# Mostrar u ocultar según bolso
		slot_node.visible = (i < slots_activos)

		var icon   := slot_node.get_node("Icon") as TextureRect
		var qty_lbl := slot_node.get_node("QtyLabel") as Label

		var entry = pocket[i] if i < pocket.size() else null

		if entry == null:
			# Slot vacío
			icon.texture = null
			qty_lbl.text = ""
			qty_lbl.visible = false
			_setup_empty_slot(slot_node, i)
		else:
			var item_data := InventoryManager.get_item_data(entry["id"])
			if not item_data:
				continue
			var qty: int = entry["qty"]

			icon.texture = item_data.icon

			# Contador — perfumes no muestran qty en el slot
			if item_data.usos_max > 0:
				qty_lbl.text = ""
				qty_lbl.visible = false
			elif qty > 1:
				qty_lbl.text = "x" + str(qty)
				qty_lbl.visible = true
			else:
				qty_lbl.text = ""
				qty_lbl.visible = false

			_setup_filled_slot(slot_node, i, item_data, qty)

	_refresh_selection_highlight()

func _setup_empty_slot(slot_node: Control, slot_index: int) -> void:
	# Limpiar señales anteriores
	_disconnect_slot_signals(slot_node)

	slot_node.mouse_filter = Control.MOUSE_FILTER_STOP
	slot_node.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _selected_slot != -1:
				InventoryManager.move_item(_selected_slot, slot_index)
				_selected_slot = -1
	)

func _setup_filled_slot(slot_node: Control, slot_index: int, item_data: ItemData, qty: int) -> void:
	_disconnect_slot_signals(slot_node)

	slot_node.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg_node := slot_node.get_node_or_null("BG") as ColorRect
	var base_color := bg_node.color if bg_node else Color.WHITE
	var hover_color := Color(0.85, 0.65, 0.2, 0.7)

	slot_node.mouse_entered.connect(func():
		if _selected_slot != -1:
			return
		if bg_node:
			bg_node.color = hover_color
		_show_desc(item_data, qty)
	)
	slot_node.mouse_exited.connect(func():
		if _selected_slot != slot_index:
			slot_node.modulate = Color(1.0, 1.0, 1.0)
			if bg_node:
				bg_node.color = base_color
		_hide_desc()
	)
	slot_node.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _selected_slot != -1:
				if _selected_slot != slot_index:
					InventoryManager.move_item(_selected_slot, slot_index)
				_selected_slot = -1
				_refresh_slots()
			else:
				_show_context_menu(item_data, slot_index, qty)
	)

func _disconnect_slot_signals(slot_node: Control) -> void:
	for c in slot_node.mouse_entered.get_connections():
		slot_node.mouse_entered.disconnect(c["callable"])
	for c in slot_node.mouse_exited.get_connections():
		slot_node.mouse_exited.disconnect(c["callable"])
	for c in slot_node.gui_input.get_connections():
		slot_node.gui_input.disconnect(c["callable"])

func _refresh_selection_highlight() -> void:
	for i in range(12):
		var slot_node := grid_container.get_node_or_null("Slot%d" % i) as Control
		if slot_node:
			slot_node.modulate = Color(1.3, 1.2, 0.6) if i == _selected_slot else Color(1.0, 1.0, 1.0)

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
	await _fade_slot(slot_index)
	InventoryManager.use_item_from_slot(slot_index)

func _drop_with_fade(slot_index: int, qty: int) -> void:
	await _fade_slot(slot_index)
	InventoryManager.remove_item_from_slot(slot_index, qty)

func _fade_slot(slot_index: int) -> void:
	if InventoryManager.inventory_changed.is_connected(_update):
		InventoryManager.inventory_changed.disconnect(_update)

	var slot_node := grid_container.get_node_or_null("Slot%d" % slot_index) as Control
	if is_instance_valid(slot_node):
		var tw := slot_node.create_tween()
		tw.tween_property(slot_node, "modulate:a", 0.0, 0.3)
		await tw.finished
		slot_node.modulate.a = 1.0

	if not InventoryManager.inventory_changed.is_connected(_update):
		InventoryManager.inventory_changed.connect(_update)

# ================================================================
# POPUP
# ================================================================

func _show_popup(message: String) -> void:
	var existing := get_node_or_null("PopupMessage")
	if existing:
		existing.queue_free()

	var popup := PanelContainer.new()
	popup.name = "PopupMessage"
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1e1208f0")
	style.border_color = Color("#c8a45a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	popup.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.text = message
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.custom_minimum_size = Vector2(300, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", font_body)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color("#e8d5a0"))
	popup.add_child(lbl)
	add_child(popup)

	await get_tree().process_frame
	var grid_rect := grid_container.get_rect()
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

	var menu := PanelContainer.new()
	menu.name = "ContextMenu"
	_context_menu = menu

	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1e1208f0")
	style.border_color = Color("#c8a45a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 8
	menu.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	menu.add_child(vbox)

	_add_menu_header(vbox, item_data.display_name.to_upper())

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer)

	if item_data.item_type == ItemData.ItemType.EQUIPPABLE:
		_add_menu_button(vbox, tr("ITEM_EQUIP"), func():
			_context_menu = null
			menu.queue_free()
			_release_local_gui_state()
			call_deferred("_equip_deferred", slot_index)
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
	var grid_rect := grid_container.get_rect()
	menu.position = grid_rect.get_center() - menu.size / 2.0

func _equip_deferred(slot_index: int) -> void:
	InventoryManager.use_item_from_slot(slot_index)

func _release_local_gui_state() -> void:
	var vp := get_viewport()
	if vp:
		vp.gui_release_focus()

func _on_drop_some(slot_index: int, max_qty: int, menu: Node) -> void:
	_drop_qty = 1
	for child in menu.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	menu.add_child(vbox)

	_add_menu_header(vbox, tr("ITEM_DROP_QTY").to_upper())

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)

	var qty_label := Label.new()
	qty_label.text = str(_drop_qty)
	qty_label.custom_minimum_size = Vector2(40, 0)
	qty_label.add_theme_font_override("font", font_title)
	qty_label.add_theme_font_size_override("font_size", 28)
	qty_label.add_theme_color_override("font_color", Color("#f5e6c8"))
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var btn_minus := Button.new()
	btn_minus.text = "−"
	btn_minus.custom_minimum_size = Vector2(40, 40)
	_style_qty_btn(btn_minus)
	btn_minus.pressed.connect(func():
		_drop_qty = max(1, _drop_qty - 1)
		qty_label.text = str(_drop_qty)
	)

	var btn_plus := Button.new()
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
		var qty_to_drop := _drop_qty
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
	var header := PanelContainer.new()
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = Color("#c8a45a")
	header_style.corner_radius_top_left = 6
	header_style.corner_radius_top_right = 6
	header_style.content_margin_left = 16
	header_style.content_margin_right = 16
	header_style.content_margin_top = 10
	header_style.content_margin_bottom = 10
	header.add_theme_stylebox_override("panel", header_style)
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", font_title)
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color("#1e1208"))
	header.add_child(lbl)
	parent.add_child(header)

func _add_menu_button(parent: Node, text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(180, 40)
	btn.add_theme_color_override("font_color", Color("#e8d5a0"))
	btn.add_theme_color_override("font_hover_color", Color("#c8a45a"))
	btn.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	btn.add_theme_font_override("font", font_body)
	btn.add_theme_font_size_override("font_size", 18)
	btn.pressed.connect(callback)
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color("#c8a45a22")
	hover_style.set_border_width_all(0)
	btn.add_theme_stylebox_override("hover", hover_style)
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0, 0, 0, 0)
	normal_style.set_border_width_all(0)
	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_stylebox_override("pressed", normal_style)
	btn.add_theme_stylebox_override("focus", normal_style)
	parent.add_child(btn)

func _style_qty_btn(btn: Button) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_override("font", font_title)
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color("#e8d5a0"))
	btn.add_theme_color_override("font_hover_color", Color("#c8a45a"))
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color("#c8a45a22")
	hover_style.set_border_width_all(1)
	hover_style.border_color = Color("#c8a45a")
	hover_style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", hover_style)
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color("#3a2510aa")
	normal_style.set_border_width_all(1)
	normal_style.border_color = Color("#c8a45a66")
	normal_style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_stylebox_override("focus", normal_style)

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
