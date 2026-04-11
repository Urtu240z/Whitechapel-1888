extends Control

signal manage_pageflip(give_control_to_book: bool)

@onready var label_title = $LabelTitle

var font_title = preload("res://Assets/Fonts/Cinzel.ttf")
var font_body  = preload("res://Assets/Fonts/IMFellEnglish.ttf")

var color_title       = Color("#8a5a2e")
var color_slot_bg     = Color("#b8955a66")
var color_slot_border = Color("#5a3a1aee")
var color_equipped    = Color("#5a7a30aa")

var _context_menu: Node = null

const SLOT_KEYS: Array = [
	"HEAD",
	"NECK_COLLAR",
	"NECK_PERFUME",
	"HAND_RIGHT",
	"BODY",
	"HAND_LEFT",
	"GLOVES",
	"SHOES",
]

# ================================================================
# READY
# ================================================================

func _ready() -> void:
	label_title.text = tr("JOURNAL_EQUIPMENT_TITLE")
	_apply_styles()
	_refresh_slots()

	if not InventoryManager.inventory_changed.is_connected(_refresh_slots):
		InventoryManager.inventory_changed.connect(_refresh_slots)

	GameManager.journal_closed.connect(_on_journal_closing)

	StateManager.state_changed.connect(func(_from, to):
		if to == StateManager.State.JOURNAL:
			if not InventoryManager.inventory_changed.is_connected(_refresh_slots):
				InventoryManager.inventory_changed.connect(_refresh_slots)
			_refresh_slots()
	)

# ================================================================
# REFRESH — actualiza los slots fijos de la escena
# ================================================================

func _refresh_slots() -> void:
	for slot_key in SLOT_KEYS:
		var slot_node := get_node_or_null(slot_key + "_Slot") as Control
		print("Slot %s: %s" % [slot_key, slot_node])
	if is_instance_valid(_context_menu):
		_context_menu.queue_free()
		_context_menu = null

	var equipped_all = InventoryManager.get_equipped_all()

	for slot_key in SLOT_KEYS:
		var slot_node := get_node_or_null(slot_key + "_Slot") as Control
		if not slot_node:
			push_warning("Journal_Page_4: slot '%s_Slot' no encontrado" % slot_key)
			continue

		var equip_slot: ItemData.EquipSlot = ItemData.EquipSlot[slot_key]
		var item_data: ItemData = equipped_all.get(equip_slot, null)

		_update_slot(slot_node, item_data, equip_slot)

func _update_slot(slot_node: Control, item_data: ItemData, equip_slot: ItemData.EquipSlot) -> void:
	var bg   := slot_node.get_node_or_null("BG") as ColorRect
	var icon := slot_node.get_node_or_null("Icon") as TextureRect
	var border := slot_node.get_node_or_null("Border") as ReferenceRect

	# Asegurar que los hijos no interceptan el input
	if bg:
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon:
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if border:
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if bg:
		bg.color = color_equipped if item_data else color_slot_bg

	if icon:
		icon.texture = item_data.icon if (item_data and item_data.icon) else null

	_disconnect_signals(slot_node)

	if item_data:
		slot_node.mouse_filter = Control.MOUSE_FILTER_STOP

		slot_node.mouse_entered.connect(func():
			if bg:
				bg.color = color_equipped.lightened(0.25)
		)
		slot_node.mouse_exited.connect(func():
			if bg:
				bg.color = color_equipped
		)
		slot_node.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_show_unequip_menu(item_data, equip_slot, slot_node.global_position)
		)
	else:
		slot_node.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _disconnect_signals(slot_node: Control) -> void:
	for c in slot_node.mouse_entered.get_connections():
		slot_node.mouse_entered.disconnect(c["callable"])
	for c in slot_node.mouse_exited.get_connections():
		slot_node.mouse_exited.disconnect(c["callable"])
	for c in slot_node.gui_input.get_connections():
		slot_node.gui_input.disconnect(c["callable"])

# ================================================================
# JOURNAL CLOSING
# ================================================================

func _on_journal_closing() -> void:
	_release_local_gui_state()
	if is_instance_valid(_context_menu):
		_context_menu.queue_free()
		_context_menu = null
	if InventoryManager.inventory_changed.is_connected(_refresh_slots):
		InventoryManager.inventory_changed.disconnect(_refresh_slots)

# ================================================================
# MENÚ CONTEXTUAL — DESEQUIPAR
# ================================================================

func _show_unequip_menu(item_data: ItemData, equip_slot: ItemData.EquipSlot, _slot_global_pos: Vector2) -> void:
	if is_instance_valid(_context_menu):
		_context_menu.queue_free()
		_context_menu = null

	var menu = PanelContainer.new()
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

	if equip_slot != ItemData.EquipSlot.NECK_PERFUME:
		_add_menu_button(vbox, tr("ITEM_UNEQUIP"), func():
			_context_menu = null
			menu.queue_free()
			var ok := InventoryManager.unequip(equip_slot)
			if not ok:
				_show_error(tr("ITEM_UNEQUIP_FULL"))
		)
	else:
		_add_menu_button(vbox, tr("ITEM_UNEQUIP_PERFUME_ACTIVE"), func():
			_context_menu = null
			menu.queue_free()
		)

	_add_menu_button(vbox, tr("ITEM_CANCEL"), func():
		_context_menu = null
		menu.queue_free()
	)

	add_child(menu)
	await get_tree().process_frame
	var sprite := get_node_or_null("Sprite2D")
	if sprite:
		var center = sprite.position
		menu.position = center - menu.size / 2.0
	else:
		menu.position = Vector2(size.x / 2.0 - menu.size.x / 2.0, size.y / 2.0 - menu.size.y / 2.0)

# ================================================================
# ERROR POPUP
# ================================================================

func _show_error(message: String) -> void:
	var existing = get_node_or_null("ErrorPopup")
	if existing:
		existing.queue_free()

	var popup = PanelContainer.new()
	popup.name = "ErrorPopup"
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#1e0808f0")
	style.border_color = Color("#a45a5a")
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
	lbl.custom_minimum_size = Vector2(200, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(lbl, font_body, 18, Color("#e8a0a0"))
	popup.add_child(lbl)
	add_child(popup)

	await get_tree().process_frame
	popup.position = Vector2(size.x / 2.0 - popup.size.x / 2.0, size.y / 2.0 - popup.size.y / 2.0)
	await get_tree().create_timer(2.5).timeout
	if is_instance_valid(popup):
		popup.queue_free()

# ================================================================
# NAVEGACIÓN — flechas para pasar página
# ================================================================

func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(_context_menu):
		return
	if event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		manage_pageflip.emit(true)
		BookAPI.next_page()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		manage_pageflip.emit(true)
		BookAPI.prev_page()
		get_viewport().set_input_as_handled()

# ================================================================
# HELPERS
# ================================================================

func _release_local_gui_state() -> void:
	var vp := get_viewport()
	if vp:
		vp.gui_release_focus()

func _add_menu_header(parent: Node, text: String) -> void:
	var header = PanelContainer.new()
	var header_style = StyleBoxFlat.new()
	header_style.bg_color = Color("#c8a45a")
	header_style.corner_radius_top_left = 6
	header_style.corner_radius_top_right = 6
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
	btn.focus_mode = Control.FOCUS_NONE
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

func _apply_styles() -> void:
	_style_label(label_title, font_body, 72, color_title)
	label_title.add_theme_constant_override("outline_size", 2)
	label_title.add_theme_color_override("font_outline_color", Color("#3a1a08"))

func _style_label(label: Label, font: FontFile, font_sz: int, color: Color) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_sz)
	label.add_theme_color_override("font_color", color)
