extends CanvasLayer

# ================================================================
# JOURNAL — script puente para Journal.tscn actual
# Compatible con GameManager:
# - open()
# - close()
# - is_open
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

	# Muy importante: dejar el PageFlip completamente desactivado
	# mientras el journal está cerrado. Invisible no basta.
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

	_set_book_input_enabled(true)

	# Forzar slots de página derecha activos — el handshake de PageFlip2D
	# solo da foco a página 3, pero página 4 también necesita input
	call_deferred("_force_right_page_input")

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
	_transitioning = false

func _force_right_page_input() -> void:
	for slot_name in ["Slot1", "Slot2", "Slot3", "Slot4"]:
		var sv = book.find_child(slot_name, true, false)
		if sv is SubViewport:
			print("Slot %s — gui_disable_input: %s — children: %s" % [slot_name, sv.gui_disable_input, sv.get_children()])

func close() -> void:
	if not is_open or _transitioning:
		return

	_transitioning = true
	is_open = false

	# Cortar input YA, antes de la animación de cierre.
	_set_book_input_enabled(false)
	_release_all_viewport_focus()
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
	# 1) Intentar la API del addon si existe
	if is_instance_valid(book) and book.has_method("_pageflip_set_input_enabled"):
		book._pageflip_set_input_enabled(enabled)

	# 2) Blindaje real: aunque el addon falle, desactivamos el nodo
	#    y los SubViewports para que no sigan tragando input ocultos.
	if is_instance_valid(book):
		book.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
		book.set_process(enabled)
		book.set_physics_process(enabled)
		book.set_process_input(enabled)
		book.set_process_unhandled_input(enabled)
		book.set_process_unhandled_key_input(enabled)
		book.set_process_shortcut_input(enabled)

	for sv in _get_pageflip_subviewports():
		sv.gui_disable_input = not enabled
		sv.physics_object_picking = enabled
		sv.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
		sv.set_process(enabled)
		sv.set_physics_process(enabled)
		sv.set_process_input(enabled)
		sv.set_process_unhandled_input(enabled)
		sv.set_process_unhandled_key_input(enabled)
		sv.set_process_shortcut_input(enabled)

		for child in sv.get_children():
			_set_node_input_enabled_recursive(child, enabled)

	if OS.is_debug_build():
		print("📖 Journal PageFlip input enabled:", enabled)
		for sv in _get_pageflip_subviewports():
			print("   - ", sv.name, " gui_disable_input=", sv.gui_disable_input, " process_mode=", sv.process_mode)


func _set_node_input_enabled_recursive(node: Node, enabled: bool) -> void:
	node.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	node.set_process(enabled)
	node.set_physics_process(enabled)
	node.set_process_input(enabled)
	node.set_process_unhandled_input(enabled)
	node.set_process_unhandled_key_input(enabled)
	node.set_process_shortcut_input(enabled)
	for child in node.get_children():
		_set_node_input_enabled_recursive(child, enabled)


func _get_pageflip_subviewports() -> Array:
	var result: Array = []
	if not is_instance_valid(book):
		return result
	for slot_name in ["Slot1", "Slot2", "Slot3", "Slot4"]:
		var sv = book.find_child(slot_name, true, false)
		if sv is SubViewport:
			result.append(sv)
	return result


func _release_all_viewport_focus() -> void:
	get_viewport().gui_release_focus()
	for sv in _get_pageflip_subviewports():
		sv.gui_release_focus()


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
	if is_instance_valid(page_3):
		if is_instance_valid(page_3._context_menu):
			page_3._context_menu.queue_free()
			page_3._context_menu = null
		return

	# Buscar en los SubViewports del addon
	for sv in _get_pageflip_subviewports():
		for child in sv.get_children():
			if child.has_method("_build_grid"):
				if is_instance_valid(child._context_menu):
					child._context_menu.queue_free()
					child._context_menu = null
				return
