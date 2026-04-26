extends Node

# ================================================================
# GAME MANAGER — Autoload
# ================================================================
# Responsabilidad:
# - Input global.
# - Pause menu.
# - Journal.
# - Debug menu.
# - Cursor global.
#
# No toca internals del player directamente.
# Para player usa PlayerManager.
# Para estados usa StateManager.
# ================================================================

const PAUSE_MENU_SCENE := preload("res://Scenes/UI/Pause_Menu.tscn")
const DEBUG_MENU_SCENE := preload("res://Scenes/UI/Debug_Menu.tscn")
const CUSTOM_CURSOR := preload("res://Assets/Images/UI/cursor.png")

signal journal_opened
signal journal_closed
signal pause_requested

var _journal: Node = null
var _pause_menu: Node = null
var _debug_menu: Node = null

var _journal_close_in_progress: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_custom_cursor()
	_ensure_debug_menu()


func _set_custom_cursor() -> void:
	Input.set_custom_mouse_cursor(CUSTOM_CURSOR, Input.CURSOR_ARROW, Vector2(78, 6))


# ================================================================
# INPUT GLOBAL
# ================================================================
func _input(event: InputEvent) -> void:
	if _should_ignore_global_input():
		return

	if event.is_action_pressed("ui_cancel"):
		_handle_cancel()
		get_viewport().set_input_as_handled()
		return

	# Tu acción real de journal es "stats" según project.godot.
	if event.is_action_pressed("stats"):
		toggle_journal()
		get_viewport().set_input_as_handled()
		return

	if InputMap.has_action("debug_toggle_menu") and event.is_action_pressed("debug_toggle_menu"):
		toggle_debug_menu()
		get_viewport().set_input_as_handled()
		return


func _should_ignore_global_input() -> bool:
	return (
		StateManager.is_client_service()
		or StateManager.is_transitioning()
		or StateManager.is_cutscene()
		or StateManager.is_game_over()
	)


# ================================================================
# ESC / PAUSA
# ================================================================
func _handle_cancel() -> void:
	_refresh_pause_menu()
	_refresh_journal()

	if StateManager.is_debug_menu():
		close_debug_menu()
		return

	if _is_pause_menu_open():
		if _pause_menu.has_method("close"):
			_pause_menu.close()
		else:
			_close_pause_menu()
		return

	if _is_journal_open():
		if not _is_journal_transitioning():
			_close_journal()
		return

	if not StateManager.can_open_pause():
		return

	_open_pause_menu()


func _open_pause_menu() -> void:
	_refresh_pause_menu()

	if _pause_menu == null or not is_instance_valid(_pause_menu):
		push_warning("GameManager: no se pudo crear el menú de pausa.")
		return

	if _is_pause_menu_open():
		return

	if not StateManager.push_state(StateManager.State.PAUSED, "pause"):
		return

	PlayerManager.lock_player("pause_menu", true)
	PlayerManager.force_stop()
	PlayerManager.stop_motion_audio()

	pause_requested.emit()

	if _pause_menu.has_method("open"):
		_pause_menu.open()
	elif _pause_menu.has_method("open_menu"):
		_pause_menu.open_menu()
	else:
		_pause_menu.visible = true


func _close_pause_menu() -> void:
	_refresh_pause_menu()

	if _pause_menu:
		if _pause_menu.has_method("close"):
			_pause_menu.close()
		elif _pause_menu.has_method("close_menu"):
			_pause_menu.close_menu()
		else:
			_pause_menu.visible = false

	PlayerManager.unlock_player("pause_menu")

	if StateManager.is_paused():
		StateManager.pop_state("close_pause_menu")


func _refresh_pause_menu() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		return

	_pause_menu = get_tree().get_first_node_in_group("pause_menu")
	if _pause_menu != null and is_instance_valid(_pause_menu):
		return

	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	_pause_menu = PAUSE_MENU_SCENE.instantiate()
	_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	current_scene.add_child(_pause_menu)

	if not _pause_menu.is_in_group("pause_menu"):
		_pause_menu.add_to_group("pause_menu")


func _is_pause_menu_open() -> bool:
	if _pause_menu == null or not is_instance_valid(_pause_menu):
		return false

	var value = _pause_menu.get("is_open")
	if value == null:
		return false

	return bool(value)


# ================================================================
# JOURNAL
# ================================================================
func toggle_journal() -> void:
	_refresh_journal()

	if _journal == null or not is_instance_valid(_journal):
		push_warning("GameManager: journal no encontrado.")
		return

	if not _journal.has_method("open") or not _journal.has_method("close"):
		push_error("GameManager: el nodo del grupo 'journal' no tiene la API correcta: open()/close().")
		return

	if _is_journal_open():
		if _is_journal_transitioning() or _journal_close_in_progress:
			return
		_close_journal()
		return

	if not StateManager.can_open_journal():
		return

	_open_journal()


func _open_journal() -> void:
	if _journal == null or not is_instance_valid(_journal):
		return

	if _is_journal_transitioning() or _journal_close_in_progress:
		return

	if not StateManager.push_state(StateManager.State.JOURNAL, "open_journal"):
		return

	PlayerManager.lock_player("journal", true)
	PlayerManager.force_stop()
	PlayerManager.stop_motion_audio()
	PlayerManager.set_animation_tree_active(false)

	_journal.open()
	journal_opened.emit()


func _close_journal() -> void:
	if _journal == null or not is_instance_valid(_journal):
		return

	if _journal_close_in_progress:
		return

	_journal_close_in_progress = true

	await _journal.close()

	if StateManager.is_journal():
		StateManager.pop_state("close_journal")

	PlayerManager.unlock_player("journal")
	PlayerManager.set_animation_tree_active(true)
	PlayerManager.force_stop()
	PlayerManager.block_movement_input_until_release()

	journal_closed.emit()
	_journal_close_in_progress = false

	get_viewport().gui_release_focus()
	await get_tree().process_frame
	get_viewport().gui_release_focus()


func _refresh_journal() -> void:
	if _journal != null and is_instance_valid(_journal):
		return

	_journal = get_tree().get_first_node_in_group("journal")


func _is_journal_open() -> bool:
	if _journal == null or not is_instance_valid(_journal):
		return false

	var value = _journal.get("is_open")
	if value == null:
		return false

	return bool(value)


func _is_journal_transitioning() -> bool:
	if _journal == null or not is_instance_valid(_journal):
		return false

	if _journal.has_method("is_transitioning"):
		return bool(_journal.is_transitioning())

	var value = _journal.get("_transitioning")
	if value == null:
		return false

	return bool(value)


# ================================================================
# DEBUG MENU
# ================================================================
func _ensure_debug_menu() -> void:
	if not OS.is_debug_build():
		return

	if _debug_menu != null and is_instance_valid(_debug_menu):
		return

	_debug_menu = get_tree().get_first_node_in_group("debug_menu")
	if _debug_menu != null and is_instance_valid(_debug_menu):
		return

	_debug_menu = DEBUG_MENU_SCENE.instantiate()
	_debug_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child.call_deferred(_debug_menu)


func toggle_debug_menu() -> void:
	if not OS.is_debug_build():
		return

	_ensure_debug_menu()

	if _debug_menu == null or not is_instance_valid(_debug_menu):
		push_warning("GameManager: DebugMenu no encontrado.")
		return

	if _debug_menu.has_method("toggle_debug_menu"):
		_debug_menu.toggle_debug_menu()
	elif _debug_menu.has_method("toggle"):
		_debug_menu.toggle()
	else:
		_debug_menu.visible = not _debug_menu.visible


func close_debug_menu() -> void:
	if _debug_menu == null or not is_instance_valid(_debug_menu):
		_ensure_debug_menu()

	if _debug_menu and is_instance_valid(_debug_menu):
		if _debug_menu.has_method("close_debug_menu"):
			_debug_menu.close_debug_menu()
		elif _debug_menu.has_method("close"):
			_debug_menu.close()
		else:
			_debug_menu.visible = false


# ================================================================
# RATÓN — wrappers
# ================================================================
func hide_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func show_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ================================================================
# API
# ================================================================
func is_journal_open() -> bool:
	return StateManager.is_journal()


func is_pause_open() -> bool:
	return StateManager.is_paused()


func is_debug_open() -> bool:
	return StateManager.is_debug_menu()
