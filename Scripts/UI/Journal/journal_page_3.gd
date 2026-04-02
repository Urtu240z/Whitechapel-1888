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

func _ready() -> void:
	label_title.text = tr("JOURNAL_INVENTORY_TITLE")
	_apply_styles()
	_build_grid()
	_update()
	if not InventoryManager.inventory_changed.is_connected(_update):
		InventoryManager.inventory_changed.connect(_update)

func _update() -> void:
	_build_grid()
	var total = 0
	for qty in InventoryManager.get_pocket().values():
		total += qty
	label_count.text = str(total) + " / " + str(TOTAL_SLOTS)

func _build_grid() -> void:
	# Cerrar menú contextual si hay uno abierto
	var existing = get_node_or_null("ContextMenu")
	if existing:
		existing.queue_free()

	for child in grid_container.get_children():
		child.queue_free()
	grid_container.columns = GRID_COLS

	var pocket = InventoryManager.get_pocket()
	var items_list: Array = []
	for item_id in pocket:
		var item_data = InventoryManager.get_item_data(item_id)
		if item_data:
			items_list.append({"data": item_data, "qty": pocket[item_id]})

	for i in range(TOTAL_SLOTS):
		grid_container.add_child(_make_slot(items_list[i] if i < items_list.size() else null))

func _make_slot(entry) -> Control:
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

	if entry == null:
		return slot

	var item_data = entry["data"]
	var qty       = entry["qty"]

	# Contenedor relativo para posicionar icono y cantidad
	var overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(overlay)

	# Icono centrado y grande
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

	# Cantidad en esquina inferior derecha
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

	# Hover y clic
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.mouse_entered.connect(func():
		slot.add_theme_stylebox_override("panel", style_hover)
	)
	slot.mouse_exited.connect(func():
		slot.add_theme_stylebox_override("panel", style_normal)
	)
	slot.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_show_context_menu(item_data, slot.get_global_rect())
	)

	return slot

func _show_context_menu(item_data: ItemData, slot_rect: Rect2) -> void:
	var existing = get_node_or_null("ContextMenu")
	if existing:
		existing.queue_free()

	var menu = PanelContainer.new()
	menu.name = "ContextMenu"
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#2a1a08ee")
	style.border_color = Color("#c8a45a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	menu.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	menu.add_child(vbox)

	if item_data.item_type == ItemData.ItemType.EQUIPPABLE:
		_add_menu_button(vbox, tr("ITEM_EQUIP"), func(): _on_equip(item_data, menu))
	else:
		_add_menu_button(vbox, tr("ITEM_USE"), func(): _on_use(item_data, menu))

	_add_menu_button(vbox, tr("ITEM_DROP"), func(): _on_drop(item_data, menu))
	_add_menu_button(vbox, tr("ITEM_CANCEL"), func(): menu.queue_free())

	add_child(menu)

	# Posicionar — intentar a la derecha, si no cabe a la izquierda
	var _viewport_size = get_viewport().get_visible_rect().size
	var menu_pos = slot_rect.position + Vector2(slot_rect.size.x + 4, 0)
	menu.position = menu_pos - global_position

func _add_menu_button(parent: Node, text: String, callback: Callable) -> void:
	var btn = Button.new()
	btn.text = text
	btn.flat = false
	btn.custom_minimum_size = Vector2(120, 32)
	btn.add_theme_color_override("font_color", Color("#f5e6c8"))
	btn.add_theme_font_override("font", font_body)
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(callback)
	parent.add_child(btn)

func _on_use(item_data: ItemData, menu: Node) -> void:
	menu.queue_free()
	InventoryManager.use_item(item_data.name)

func _on_equip(item_data: ItemData, menu: Node) -> void:
	menu.queue_free()
	InventoryManager.equip(item_data.name)

func _on_drop(item_data: ItemData, menu: Node) -> void:
	menu.queue_free()
	InventoryManager.remove_item(item_data.name, 1)

func _apply_styles() -> void:
	_style_label(label_title, font_body, 72, color_title)
	label_title.add_theme_constant_override("outline_size", 2)
	label_title.add_theme_color_override("font_outline_color", Color("#3a1a08"))
	_style_label(label_count, font_title, 18, color_muted)

func _style_label(label: Label, font: FontFile, size: int, color: Color) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
