extends Node

var _journal: Node = null
var _overlay: ColorRect = null

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_create_overlay()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle_mouse()
	if event.is_action_pressed("stats"):
		toggle_journal()
	# TEMPORAL — borrar después de probar
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F6:
			SaveManager.save_game(0)
			print("💾 Guardado en slot 0")
		if event.keycode == KEY_F7:
			SaveManager.load_game(0)
			print("📂 Cargando slot 0")


# ==============================================================================
# OVERLAY
# ==============================================================================
func _create_overlay() -> void:
	# CanvasLayer para el overlay oscuro detrás del journal
	var layer = CanvasLayer.new()
	layer.layer = 9  # justo debajo del journal (layer 10)
	layer.name = "OverlayLayer"
	add_child(layer)

	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.6)
	_overlay.anchors_preset = Control.PRESET_FULL_RECT
	_overlay.visible = false
	layer.add_child(_overlay)


# ==============================================================================
# JOURNAL
# ==============================================================================
func toggle_journal() -> void:
	if _journal == null:
		_journal = get_tree().get_first_node_in_group("journal")
	if _journal == null:
		push_warning("GameManager: journal no encontrado")
		return

	var opening = not _journal.visible

	if opening:
		_open_journal()
	else:
		_close_journal()


func _open_journal() -> void:
	var player = PlayerManager.player_instance

	if is_instance_valid(player):
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

	_journal.visible = true
	_overlay.visible = true
	show_mouse()


func _close_journal() -> void:
	_journal.visible = false
	_overlay.visible = false
	hide_mouse()

	var player = PlayerManager.player_instance
	if is_instance_valid(player):
		player.velocity = Vector2.ZERO

		if player.has_node("Movement"):
			var movement = player.get_node("Movement")
			movement.force_stop()
			movement.block_movement_input_until_release()
			movement.enabled = true

		# AnimationTree se reactiva DESPUÉS del bloqueo
		if player.has_node("AnimationTree"):
			player.get_node("AnimationTree").active = true


func _set_player_movement(enabled: bool) -> void:
	var player = PlayerManager.player_instance
	if not is_instance_valid(player): return
	if player.has_node("Movement"):
		player.get_node("Movement").enabled = enabled


# ==============================================================================
# RATÓN
# ==============================================================================
func toggle_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func hide_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func show_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
