extends CanvasLayer

# ================================================================
# JOURNAL — script puente para Journal.tscn actual
# Compatible con GameManager:
# - open()
# - close()
# - is_open
#
# NO sustituye al addon PageFlip.
# Solo controla visibilidad, pequeña animación de entrada/salida
# y habilita/deshabilita input del libro cuando toca.
# ================================================================
signal journal_closing
# ================================================================
# NODOS
# ================================================================
@onready var overlay: ColorRect = $Overlay
@onready var book_root: Node2D = $Node2D
@onready var book: Node = $Node2D/PageFlip2D

# ================================================================
# ESTADO
# ================================================================
var is_open: bool = false
var _transitioning: bool = false
var _base_scale: Vector2

@export var reset_to_first_spread_on_open: bool = false
@export var overlay_alpha: float = 0.6

# ================================================================
# READY
# ================================================================
func _ready() -> void:
	_base_scale = book_root.scale

	visible = false
	is_open = false
	_transitioning = false

	overlay.visible = true
	overlay.modulate.a = 0.0

	book_root.modulate.a = 0.0

	_set_book_input_enabled(false)

# ================================================================
# API PÚBLICA
# ================================================================
func open() -> void:
	if is_open or _transitioning:
		return

	_transitioning = true
	is_open = true
	visible = true

	if reset_to_first_spread_on_open:
		_go_to_first_spread_instant()

	book_root.scale = _base_scale * 0.92
	book_root.modulate.a = 0.0
	overlay.modulate.a = 0.0

	var tw = create_tween().set_parallel(true)
	tw.tween_property(overlay, "modulate:a", overlay_alpha, 0.18)
	tw.tween_property(book_root, "scale", _base_scale, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(book_root, "modulate:a", 1.0, 0.18)

	await tw.finished

	_set_book_input_enabled(true)
	_transitioning = false


func close() -> void:
	if not is_open or _transitioning:
		return

	_transitioning = true
	is_open = false
	_set_book_input_enabled(false)
	journal_closing.emit()
	_close_inventory_menu()

	var tw = create_tween().set_parallel(true)
	tw.tween_property(overlay, "modulate:a", 0.0, 0.14)
	tw.tween_property(book_root, "scale", _base_scale * 0.92, 0.16) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(book_root, "modulate:a", 0.0, 0.14)

	await tw.finished

	visible = false
	book_root.scale = _base_scale
	_transitioning = false

# ================================================================
# HELPERS
# ================================================================
func _set_book_input_enabled(enabled: bool) -> void:
	if is_instance_valid(book) and book.has_method("_pageflip_set_input_enabled"):
		book._pageflip_set_input_enabled(enabled)


func _go_to_first_spread_instant() -> void:
	if not is_instance_valid(book):
		return

	if "current_spread" in book:
		book.current_spread = 0

	if book.has_method("_update_static_visuals_immediate"):
		book._update_static_visuals_immediate()

func is_transitioning() -> bool:
	return _transitioning

func _close_inventory_menu() -> void:
	var page_3 = book.find_child("JournalPage3", true, false)
	if not is_instance_valid(page_3):
		# Buscar en los SubViewports del addon
		for slot in ["Slot1", "Slot2", "Slot3", "Slot4"]:
			var sv = book.find_child(slot, true, false)
			if sv:
				for child in sv.get_children():
					if child.has_method("_build_grid"):
						if is_instance_valid(child._context_menu):
							child._context_menu.queue_free()
							child._context_menu = null
						return
