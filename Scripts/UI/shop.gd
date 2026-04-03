extends CanvasLayer
# ================================================================
# SHOP — shop.gd
# UI de tienda genérica para cualquier vendedor.
# Uso:
#   var shop = SHOP_SCENE.instantiate()
#   get_tree().root.add_child(shop)
#   shop.open(shop_name, items)
#
# items es un Array de Dictionaries:
#   { "id": "drink-cerveza", "max_qty": 5 }
# ================================================================

var font_title = preload("res://Assets/Fonts/Cinzel.ttf")
var font_body  = preload("res://Assets/Fonts/IMFellEnglish.ttf")

@onready var background: Control = $Background
@onready var shop_panel: PanelContainer = $Background/ShopPanel

var _shop_name: String = ""
var _items: Array = []
var _quantities: Dictionary = {}

signal shop_closed
signal items_purchased(purchased: Dictionary)  # { item_id: cantidad }

# ================================================================
# OPEN
# ================================================================

func open(shop_name: String, items: Array) -> void:
	_shop_name = shop_name
	_items = items
	_quantities.clear()
	for item in items:
		_quantities[item["id"]] = 0
	_build_ui()
	visible = true

# ================================================================
# BUILD UI
# ================================================================

func _build_ui() -> void:
	for child in shop_panel.get_children():
		child.queue_free()

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color("#1e1208f0")
	panel_style.border_color = Color("#c8a45a")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 0
	panel_style.content_margin_right = 0
	panel_style.content_margin_top = 0
	panel_style.content_margin_bottom = 16
	shop_panel.add_theme_stylebox_override("panel", panel_style)
	shop_panel.custom_minimum_size = Vector2(380, 0)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	shop_panel.add_child(vbox)

	# Cabecera
	var header = PanelContainer.new()
	var header_style = StyleBoxFlat.new()
	header_style.bg_color = Color("#c8a45a")
	header_style.corner_radius_top_left = 6
	header_style.corner_radius_top_right = 6
	header_style.corner_radius_bottom_left = 0
	header_style.corner_radius_bottom_right = 0
	header_style.content_margin_left = 16
	header_style.content_margin_right = 16
	header_style.content_margin_top = 12
	header_style.content_margin_bottom = 12
	header.add_theme_stylebox_override("panel", header_style)
	var title_lbl = Label.new()
	title_lbl.text = _shop_name.to_upper()
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(title_lbl, font_title, 22, Color("#1e1208"))
	header.add_child(title_lbl)
	vbox.add_child(header)

	var sep1 = HSeparator.new()
	sep1.add_theme_color_override("color", Color("#c8a45a66"))
	vbox.add_child(sep1)

	# Lista de items
	var items_vbox = VBoxContainer.new()
	items_vbox.add_theme_constant_override("separation", 0)
	var items_margin = MarginContainer.new()
	items_margin.add_theme_constant_override("margin_left", 12)
	items_margin.add_theme_constant_override("margin_right", 12)
	items_margin.add_theme_constant_override("margin_top", 8)
	items_margin.add_theme_constant_override("margin_bottom", 8)
	items_margin.add_child(items_vbox)
	vbox.add_child(items_margin)

	for item_entry in _items:
		var item_id: String = item_entry["id"]
		var item_data = InventoryManager.get_item_data(item_id)
		if item_data == null:
			continue
		_add_item_row(items_vbox, item_data, item_entry.get("max_qty", 10))

	var sep2 = HSeparator.new()
	sep2.add_theme_color_override("color", Color("#c8a45a66"))
	vbox.add_child(sep2)

	# Total y dinero
	var footer_margin = MarginContainer.new()
	footer_margin.add_theme_constant_override("margin_left", 16)
	footer_margin.add_theme_constant_override("margin_right", 16)
	footer_margin.add_theme_constant_override("margin_top", 10)
	footer_margin.add_theme_constant_override("margin_bottom", 10)
	vbox.add_child(footer_margin)

	var footer_vbox = VBoxContainer.new()
	footer_vbox.add_theme_constant_override("separation", 4)
	footer_margin.add_child(footer_vbox)

	var total_lbl = Label.new()
	total_lbl.name = "TotalLabel"
	_style_label(total_lbl, font_body, 18, Color("#e8d5a0"))
	total_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer_vbox.add_child(total_lbl)

	var money_lbl = Label.new()
	money_lbl.name = "MoneyLabel"
	_style_label(money_lbl, font_body, 16, Color("#c8a45a"))
	money_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer_vbox.add_child(money_lbl)

	_update_totals()

	var sep3 = HSeparator.new()
	sep3.add_theme_color_override("color", Color("#c8a45a66"))
	vbox.add_child(sep3)

	var btn_margin = MarginContainer.new()
	btn_margin.add_theme_constant_override("margin_left", 16)
	btn_margin.add_theme_constant_override("margin_right", 16)
	btn_margin.add_theme_constant_override("margin_top", 10)
	btn_margin.add_theme_constant_override("margin_bottom", 0)
	vbox.add_child(btn_margin)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 16)
	btn_margin.add_child(btn_hbox)

	var btn_buy = _make_button(tr("SHOP_BUY"), true)
	btn_buy.pressed.connect(_on_buy_pressed)
	btn_hbox.add_child(btn_buy)

	var btn_cancel = _make_button(tr("SHOP_CANCEL"), false)
	btn_cancel.pressed.connect(_on_cancel_pressed)
	btn_hbox.add_child(btn_cancel)

	await get_tree().process_frame
	var viewport_size = get_viewport().get_visible_rect().size
	shop_panel.position = (viewport_size - shop_panel.size) / 2.0

# ================================================================
# FILA DE ITEM
# ================================================================

func _add_item_row(parent: Node, item_data: ItemData, max_qty: int) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	if item_data.icon:
		var icon = TextureRect.new()
		icon.texture = item_data.icon
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)

	var name_lbl = Label.new()
	name_lbl.text = item_data.display_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_label(name_lbl, font_body, 17, Color("#e8d5a0"))
	row.add_child(name_lbl)

	var price_lbl = Label.new()
	var coste_chelines = item_data.cost / 12.0
	price_lbl.text = "%.1f s." % coste_chelines
	_style_label(price_lbl, font_body, 17, Color("#c8a45a"))
	row.add_child(price_lbl)

	var stock_lbl = Label.new()
	stock_lbl.text = "(%d)" % max_qty
	_style_label(stock_lbl, font_body, 15, Color("#9a806088"))
	row.add_child(stock_lbl)

	var btn_minus = _make_qty_btn("−")
	row.add_child(btn_minus)

	var qty_lbl = Label.new()
	qty_lbl.text = "0"
	qty_lbl.custom_minimum_size = Vector2(28, 0)
	qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(qty_lbl, font_title, 17, Color("#f5e6c8"))
	row.add_child(qty_lbl)

	var btn_plus = _make_qty_btn("+")
	row.add_child(btn_plus)

	var item_id = item_data.name
	btn_minus.pressed.connect(func():
		_quantities[item_id] = max(0, _quantities[item_id] - 1)
		qty_lbl.text = str(_quantities[item_id])
		stock_lbl.text = "(%d)" % (max_qty - _quantities[item_id])
		_update_totals()
	)
	btn_plus.pressed.connect(func():
		var item_data_check = InventoryManager.get_item_data(item_id)
		var max_allowed = min(max_qty, item_data_check.max_stack if item_data_check.max_stack > 0 else max_qty)
		_quantities[item_id] = min(max_allowed, _quantities[item_id] + 1)
		qty_lbl.text = str(_quantities[item_id])
		stock_lbl.text = "(%d)" % (max_qty - _quantities[item_id])
		_update_totals()
	)

	var row_margin = MarginContainer.new()
	row_margin.add_theme_constant_override("margin_top", 6)
	row_margin.add_theme_constant_override("margin_bottom", 6)
	row_margin.add_child(row)
	parent.add_child(row_margin)

# ================================================================
# TOTALES
# ================================================================

func _calculate_total() -> float:
	var total: float = 0.0
	for item_id in _quantities:
		var qty = _quantities[item_id]
		if qty <= 0:
			continue
		var item_data = InventoryManager.get_item_data(item_id)
		if item_data:
			total += (item_data.cost / 12.0) * qty
	return total

func _update_totals() -> void:
	var total = _calculate_total()
	var total_lbl = shop_panel.find_child("TotalLabel", true, false)
	var money_lbl = shop_panel.find_child("MoneyLabel", true, false)
	if total_lbl:
		total_lbl.text = tr("SHOP_TOTAL") % ["%.1f" % total]
	if money_lbl:
		money_lbl.text = tr("SHOP_MONEY") % ["%.1f" % PlayerStats.dinero]

# ================================================================
# COMPRAR
# ================================================================

func _on_buy_pressed() -> void:
	var total = _calculate_total()

	if total <= 0:
		_close()
		return

	if PlayerStats.dinero < total:
		_show_error(tr("SHOP_NO_MONEY"))
		return

	var items_to_add = []
	for item_id in _quantities:
		var qty = _quantities[item_id]
		if qty > 0:
			items_to_add.append({"id": item_id, "qty": qty})

	var slots_libres = 0
	for entry in InventoryManager.get_pocket():
		if entry == null:
			slots_libres += 1

	var slots_necesarios = 0
	for item_entry in items_to_add:
		if not InventoryManager.has_item(item_entry["id"]):
			slots_necesarios += 1

	if slots_necesarios > slots_libres:
		_show_error(tr("SHOP_NO_SPACE"))
		return

	# Cobrar
	PlayerStats.gastar_dinero(total)

	# Añadir items y registrar compra
	var purchased: Dictionary = {}
	for item_entry in items_to_add:
		var item_data = InventoryManager.get_item_data(item_entry["id"])
		var qty_inicial = item_data.usos_max if item_data.usos_max > 0 else item_entry["qty"]
		InventoryManager.add_item(item_entry["id"], qty_inicial)
		purchased[item_entry["id"]] = item_entry["qty"]

	items_purchased.emit(purchased)
	_close()

func _on_cancel_pressed() -> void:
	_close()

func _close() -> void:
	shop_closed.emit()
	queue_free()

# ================================================================
# ERROR
# ================================================================

func _show_error(message: String) -> void:
	var error_lbl = shop_panel.find_child("ErrorLabel", true, false)
	if error_lbl:
		error_lbl.text = message
		return

	var lbl = Label.new()
	lbl.name = "ErrorLabel"
	lbl.text = message
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(lbl, font_body, 15, Color("#ff6b6b"))
	var vbox = shop_panel.get_child(0)
	vbox.add_child(lbl)
	vbox.move_child(lbl, vbox.get_child_count() - 2)

	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(lbl):
		lbl.queue_free()

# ================================================================
# HELPERS UI
# ================================================================

func _make_button(text: String, primary: bool) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(120, 40)
	btn.add_theme_font_override("font", font_body)
	btn.add_theme_font_size_override("font_size", 18)

	var bg_color = Color("#c8a45a") if primary else Color("#3a2510aa")
	var font_color = Color("#1e1208") if primary else Color("#e8d5a0")

	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", font_color)

	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = bg_color
	normal_style.set_border_width_all(1)
	normal_style.border_color = Color("#c8a45a")
	normal_style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = bg_color.lightened(0.15)
	hover_style.set_border_width_all(1)
	hover_style.border_color = Color("#c8a45a")
	hover_style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("focus", normal_style)

	return btn

func _make_qty_btn(text: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(28, 28)
	btn.add_theme_font_override("font", font_title)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color("#e8d5a0"))
	btn.add_theme_color_override("font_hover_color", Color("#c8a45a"))

	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color("#3a2510aa")
	normal_style.set_border_width_all(1)
	normal_style.border_color = Color("#c8a45a66")
	normal_style.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color("#c8a45a22")
	hover_style.set_border_width_all(1)
	hover_style.border_color = Color("#c8a45a")
	hover_style.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("focus", normal_style)

	return btn

func _style_label(label: Label, font: FontFile, font_size: int, color: Color) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
