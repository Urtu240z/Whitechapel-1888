extends Node
# ================================================================
# GAME MANAGER — Autoload
# Input global, journal, pausa, cursor.
# ================================================================

const PAUSE_MENU_SCENE := preload("res://Scenes/UI/Pause_Menu.tscn")

signal journal_closed

var _journal = null
var _pause_menu = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_custom_cursor()

func _set_custom_cursor() -> void:
	var cursor = preload("res://Assets/Images/UI/cursor.png")
	Input.set_custom_mouse_cursor(cursor, Input.CURSOR_ARROW, Vector2(78, 6))

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		print("🖱️ Click recibido en GameManager, estado: ", StateManager.State.keys()[StateManager.current()])
	if event.is_action_pressed("ui_cancel"):
		_handle_cancel()
		return

	if event.is_action_pressed("stats"):
		toggle_journal()
		return

	if not StateManager.is_gameplay():
		return

	if OS.is_debug_build() and event is InputEventKey and event.pressed:
		if event.keycode == KEY_F6:
			InventoryManager.add_item("food-pan", 2)
			InventoryManager.add_item("drink-cerveza", 1)
			InventoryManager.add_item("drug-laudano", 1)
			print("🎒 Items de prueba añadidos")

# ==============================================================================
# ESC / PAUSA
# ==============================================================================
func _handle_cancel() -> void:
	_refresh_pause_menu()
	_refresh_journal()

	if _pause_menu != null and _pause_menu.get("is_open"):
		_pause_menu.close()
		return

	if _journal != null and _journal.get("is_open"):
		if not _is_journal_transitioning():
			_close_journal()
		return

	if not StateManager.can_enter(StateManager.State.PAUSED):
		return

	_open_pause_menu()


func _open_pause_menu() -> void:
	_refresh_pause_menu()

	if _pause_menu == null:
		push_warning("GameManager: no se pudo crear el menú de pausa")
		return

	var player = PlayerManager.player_instance
	if is_instance_valid(player):
		player.velocity = Vector2.ZERO
		if player.has_node("Audio"):
			var audio = player.get_node("Audio")
			if audio.has_node("StepPlayer"):
				audio.get_node("StepPlayer").stop()
			if audio.has_node("BreathRun"):
				audio.get_node("BreathRun").stop()

	StateManager.enter(StateManager.State.PAUSED)
	_pause_menu.open()


func _refresh_pause_menu() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		return
	_pause_menu = get_tree().get_first_node_in_group("pause_menu")
	if _pause_menu != null and is_instance_valid(_pause_menu):
		return
	var current_scene = get_tree().current_scene
	if current_scene == null:
		return
	_pause_menu = PAUSE_MENU_SCENE.instantiate()
	current_scene.add_child(_pause_menu)


# ==============================================================================
# JOURNAL
# ==============================================================================
func toggle_journal() -> void:
	_refresh_journal()

	if _journal == null:
		push_warning("GameManager: journal no encontrado")
		return

	if not _journal.has_method("open") or not _journal.has_method("close"):
		push_error("GameManager: el nodo del grupo 'journal' no tiene la API correcta")
		return

	if _journal.get("is_open"):
		if _is_journal_transitioning():
			return
		_close_journal()
		return

	if not StateManager.can_enter(StateManager.State.JOURNAL):
		return

	_open_journal()


func _open_journal() -> void:
	var player = PlayerManager.player_instance
	if is_instance_valid(player):
		player.disable_movement()
		player.velocity = Vector2.ZERO
		if player.has_node("Movement"):
			var movement = player.get_node("Movement")
			movement.enabled = false
			movement.force_stop()
		if player.has_node("AnimationTree"):
			player.get_node("AnimationTree").active = false
		if player.has_node("Audio"):
			var audio = player.get_node("Audio")
			if audio.has_node("StepPlayer"):
				audio.get_node("StepPlayer").stop()
			if audio.has_node("BreathRun"):
				audio.get_node("BreathRun").stop()

	StateManager.enter(StateManager.State.JOURNAL)
	_journal.open()


func _close_journal() -> void:
	# Importante: cerrar primero el journal para que deje de procesar input
	# ANTES de volver a GAMEPLAY.
	await _journal.close()
	journal_closed.emit()
	StateManager.exit(StateManager.State.JOURNAL)

	var player = PlayerManager.player_instance
	if is_instance_valid(player):
		player.enable_movement()
		player.velocity = Vector2.ZERO
		if player.has_node("Movement"):
			var movement = player.get_node("Movement")
			movement.force_stop()
			movement.block_movement_input_until_release()
			movement.enabled = true
		if player.has_node("AnimationTree"):
			player.get_node("AnimationTree").active = true

	get_viewport().gui_release_focus()
	await get_tree().process_frame
	get_viewport().gui_release_focus()


func _refresh_journal() -> void:
	if _journal == null or not is_instance_valid(_journal):
		_journal = get_tree().get_first_node_in_group("journal")


func _is_journal_transitioning() -> bool:
	if _journal == null:
		return false
	if _journal.has_method("is_transitioning"):
		return _journal.is_transitioning()
	return bool(_journal.get("_transitioning"))


# ==============================================================================
# RATÓN — mantenemos las funciones para compatibilidad
# pero el ratón lo gestiona StateManager
# ==============================================================================
func hide_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func show_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
