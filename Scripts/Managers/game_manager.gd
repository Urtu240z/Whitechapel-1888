extends Node

const PAUSE_MENU_SCENE := preload("res://Scenes/UI/Pause_Menu.tscn")

signal journal_closed

var _journal = null
var _pause_menu = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_handle_cancel()
		return

	# Mientras el juego está pausado, no dejamos pasar más atajos globales
	if get_tree().paused:
		return

	if event.is_action_pressed("stats"):
		toggle_journal()

	if OS.is_debug_build() and event is InputEventKey and event.pressed:
		if event.keycode == KEY_F6:
			InventoryManager.add_item("pan", 2)
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

	if not _can_open_pause():
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

	_pause_menu.open()


func _can_open_pause() -> bool:
	# No durante transiciones duras del juego
	if SceneManager != null and SceneManager.has_method("is_transitioning"):
		if SceneManager.is_transitioning():
			return false

	if SaveManager != null and SaveManager.has_method("is_busy"):
		if SaveManager.is_busy():
			return false

	if _is_building_transition_active():
		return false

	if _is_journal_transitioning():
		return false

	return true


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

	# Si ya está abierto, cerrar siempre está permitido
	if _journal.get("is_open"):
		if _is_journal_transitioning():
			return
		_close_journal()
		return

	# Si está cerrado, antes de abrir comprobamos guards
	if not _can_open_journal():
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

	show_mouse()
	_journal.open()


func _close_journal() -> void:
	hide_mouse()
	journal_closed.emit()

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

	_journal.close()


func _refresh_journal() -> void:
	if _journal == null or not is_instance_valid(_journal):
		_journal = get_tree().get_first_node_in_group("journal")


func _can_open_journal() -> bool:
	if get_tree().paused:
		return false

	# El propio journal no debe estar animándose
	if _is_journal_transitioning():
		return false

	# No abrir durante fade / cambio de escena
	if SceneManager != null and SceneManager.has_method("is_transitioning"):
		if SceneManager.is_transitioning():
			return false

	# No abrir durante save/load
	if SaveManager != null and SaveManager.has_method("is_busy"):
		if SaveManager.is_busy():
			return false

	# No abrir durante transiciones de edificios
	if _is_building_transition_active():
		return false

	# No abrir si el player está bloqueado por otro sistema
	var player = PlayerManager.player_instance
	if is_instance_valid(player):
		if not player.can_move:
			return false

	return true


func _is_journal_transitioning() -> bool:
	if _journal == null:
		return false

	if _journal.has_method("is_transitioning"):
		return _journal.is_transitioning()

	return bool(_journal.get("_transitioning"))


func _is_building_transition_active() -> bool:
	for building in get_tree().get_nodes_in_group("buildings"):
		var entrance = building.get_node_or_null("BuildingEntrance")
		if not is_instance_valid(entrance):
			continue

		if entrance.has_method("is_transitioning"):
			if entrance.is_transitioning():
				return true
		else:
			if bool(entrance.get("_transitioning")):
				return true

	return false


# ==============================================================================
# RATÓN
# ==============================================================================
func hide_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func show_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
