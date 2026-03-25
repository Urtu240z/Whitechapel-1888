@tool
class_name BookAPI
extends RefCounted

## Versión simplificada de BookAPI.
## Solo navegación: next/prev page, go_to_page, go_to_spread.
## Sin portadas, sin cierre, sin escenas interactivas.

static var _current_book: PageFlip2D


# ==============================================================================
# SETUP
# ==============================================================================

## Registra el libro activo. Llamado automáticamente por PageFlip2D en _ready.
static func set_current_book(book: PageFlip2D) -> void:
	_current_book = book


## Devuelve el libro activo, o null si no hay ninguno.
static func get_current_book() -> PageFlip2D:
	return _current_book


# ==============================================================================
# NAVEGACIÓN
# ==============================================================================

## Pasa a la siguiente página. No hace nada si está animando o es la última.
static func next_page() -> void:
	if is_instance_valid(_current_book):
		_current_book.next_page()


## Vuelve a la página anterior. No hace nada si está animando o es la primera.
static func prev_page() -> void:
	if is_instance_valid(_current_book):
		_current_book.prev_page()


## Navega a un número de página específico (índice base 1).
## [b]ASYNC:[/b] Usar con 'await' si animated es true.
## [param page_num]: Número de página (1 = primera textura en pages_paths).
static func go_to_page(page_num: int = 1, animated: bool = true) -> void:
	var book = _current_book
	if not is_instance_valid(book): return

	var safe_page = max(1, page_num)
	var target_spread = int(safe_page / 2.0)
	target_spread = clampi(target_spread, 0, book.total_spreads - 1)

	await go_to_spread(book, target_spread, animated)


## Navega a un spread concreto por índice.
## [b]ASYNC:[/b] Usar con 'await' si animated es true.
static func go_to_spread(book: PageFlip2D, target_spread: int, animated: bool = true) -> void:
	if not is_instance_valid(book): return

	var final_target = clampi(target_spread, 0, book.total_spreads - 1)
	var diff = final_target - book.current_spread

	if diff == 0: return

	if not animated:
		# Teleport instantáneo
		book.current_spread = final_target
		book.call("_update_static_visuals_immediate")
	else:
		if book.is_animating: return

		var original_speed = book.anim_player.speed_scale
		var steps = abs(diff)
		var dynamic_speed = remap(float(steps), 0.0, float(book.total_spreads), 1.5, 10.0)
		book.anim_player.speed_scale = dynamic_speed

		var going_forward = diff > 0
		for i in range(steps):
			if not is_instance_valid(book): break
			if going_forward: book.next_page()
			else: book.prev_page()
			if book.anim_player.is_playing():
				await book.anim_player.animation_finished
			else:
				await book.get_tree().process_frame

		if is_instance_valid(book):
			book.anim_player.speed_scale = original_speed


# ==============================================================================
# ESTADO
# ==============================================================================

## Devuelve true si el libro está animando.
static func is_busy(book_instance: PageFlip2D = null) -> bool:
	var book = book_instance if book_instance else _current_book
	if not is_instance_valid(book): return false
	return book.is_animating


## Localiza el controlador PageFlip2D desde cualquier nodo hijo.
static func find_book_controller(caller_node: Node) -> PageFlip2D:
	var current = caller_node
	while current:
		if current is PageFlip2D:
			return current
		current = current.get_parent()
	return null
