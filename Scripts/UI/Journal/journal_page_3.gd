extends Node2D

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

const GRID_COLS   = 4
const GRID_ROWS   = 6
const TOTAL_SLOTS = GRID_COLS * GRID_ROWS
const SLOT_SIZE   = Vector2(64, 64)


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

	var style = StyleBoxFlat.new()
	style.bg_color = color_slot_bg
	style.border_color = color_slot_border
	style.set_border_width_all(3)
	style.set_corner_radius_all(3)
	slot.add_theme_stylebox_override("panel", style)

	if entry == null:
		return slot

	var item_data = entry["data"]
	var qty       = entry["qty"]

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)

	if item_data.icon:
		var icon_rect = TextureRect.new()
		icon_rect.texture = item_data.icon
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.custom_minimum_size = Vector2(40, 40)
		vbox.add_child(icon_rect)
	else:
		var placeholder = Label.new()
		placeholder.text = item_data.display_name.left(3)
		_style_label(placeholder, font_body, 11, color_muted)
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(placeholder)

	if qty > 1:
		var qty_lbl = Label.new()
		qty_lbl.text = "x" + str(qty)
		_style_label(qty_lbl, font_body, 13, color_ink)
		qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vbox.add_child(qty_lbl)

	slot.add_child(vbox)
	return slot


func _apply_styles() -> void:
	_style_label(label_title, font_body, 72, color_title)
	label_title.add_theme_constant_override("outline_size", 2)
	label_title.add_theme_color_override("font_outline_color", Color("#3a1a08"))
	_style_label(label_count, font_title, 18, color_muted)


func _style_label(label: Label, font: FontFile, size: int, color: Color) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
