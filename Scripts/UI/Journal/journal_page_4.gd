extends Node2D

@onready var label_title     = $LabelTitle
@onready var silhouette      = $Silhouette
@onready var slots_container = $SlotsContainer

var font_title = preload("res://Assets/Fonts/Cinzel.ttf")
var font_body  = preload("res://Assets/Fonts/IMFellEnglish.ttf")

var color_title       = Color("#8a5a2e")
var color_ink         = Color("#3a2510")
var color_muted       = Color("#7a5a30")
var color_slot_bg     = Color("#b8955a66")
var color_slot_border = Color("#5a3a1aee")
var color_equipped    = Color("#5a7a30aa")
var color_empty_text  = Color("#9a806088")

# Mapeo slot → clave de traducción
const SLOT_LABEL_KEYS = {
	"HEAD":         "JOURNAL_SLOT_HEAD",
	"NECK_COLLAR":  "JOURNAL_SLOT_NECK_COLLAR",
	"NECK_PERFUME": "JOURNAL_SLOT_NECK_PERFUME",
	"BODY":         "JOURNAL_SLOT_BODY",
	"GLOVES":       "JOURNAL_SLOT_GLOVES",
	"HAND_LEFT":    "JOURNAL_SLOT_HAND_LEFT",
	"HAND_RIGHT":   "JOURNAL_SLOT_HAND_RIGHT",
	"SHOES":        "JOURNAL_SLOT_SHOES",
}

const SLOT_SIZE = Vector2(56, 56)


func _ready() -> void:
	label_title.text = tr("JOURNAL_EQUIPMENT_TITLE")
	_apply_styles()
	_update()
	if not InventoryManager.inventory_changed.is_connected(_update):
		InventoryManager.inventory_changed.connect(_update)


func _update() -> void:
	_build_slots()


func _build_slots() -> void:
	for child in slots_container.get_children():
		if child is Control:
			child.queue_free()

	var equipped_all = InventoryManager.get_equipped_all()
	for slot_key in SLOT_LABEL_KEYS:
		var marker = slots_container.get_node_or_null(slot_key)
		if not marker:
			push_warning("Journal_Page_4: Marker2D '%s' no encontrado en SlotsContainer" % slot_key)
			continue
		var equip_slot: ItemData.EquipSlot = ItemData.EquipSlot[slot_key]
		var equipped: ItemData = equipped_all.get(equip_slot, null)
		_make_equipment_slot(slot_key, marker.position, equipped)


func _make_equipment_slot(slot_key: String, pos: Vector2, item_data) -> void:
	var container = Control.new()
	container.position = pos - SLOT_SIZE / 2.0
	container.custom_minimum_size = SLOT_SIZE
	container.size = SLOT_SIZE

	var bg = ColorRect.new()
	bg.size  = SLOT_SIZE
	bg.color = color_equipped if item_data else color_slot_bg
	container.add_child(bg)

	var border = ReferenceRect.new()
	border.size = SLOT_SIZE
	border.border_color = color_slot_border
	border.border_width = 3.0
	border.editor_only = false
	container.add_child(border)

	if item_data and item_data.icon:
		var icon = TextureRect.new()
		icon.texture = item_data.icon
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2(SLOT_SIZE.x - 8, SLOT_SIZE.y - 8)
		icon.position = Vector2(4, 4)
		container.add_child(icon)
	elif item_data:
		var lbl = Label.new()
		lbl.text = item_data.display_name.left(4)
		_style_label(lbl, font_body, 11, color_ink)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.size = SLOT_SIZE
		lbl.position = Vector2.ZERO
		container.add_child(lbl)

	slots_container.add_child(container)


func _apply_styles() -> void:
	_style_label(label_title, font_body, 72, color_title)
	label_title.add_theme_constant_override("outline_size", 2)
	label_title.add_theme_color_override("font_outline_color", Color("#3a1a08"))


func _style_label(label: Label, font: FontFile, size: int, color: Color) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
