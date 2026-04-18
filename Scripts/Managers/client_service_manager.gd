extends Node
# =========================================================
# CLIENT SERVICE MANAGER
# Orquesta:
# - fade audio mundo
# - fade visual a negro
# - pausa del juego
# - client transition + minijuego
# - restauración del mundo
# =========================================================

const CLIENT_TRANSITION_SCENE := preload("res://Scenes/Client_Transition/Client_Transition.tscn")

signal world_hidden  # Emitida cuando el mundo está negro y pausado — momento seguro para queue_free NPCs

var _active: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func is_active() -> bool:
	return _active

func start_service(acto: String, tipo: String, client_skin_name: String = "NPC_ClientPoor") -> Dictionary:
	if _active:
		return {}

	if not StateManager.enter(StateManager.State.CLIENT_SERVICE):
		return {}

	_active = true

	var player = PlayerManager.player_instance
	var world = get_tree().current_scene
	var transition: Node = null
	var data: Dictionary = {}

	if is_instance_valid(player):
		player.disable_movement()
		player.velocity = Vector2.ZERO

	# 1. Fade out audio del mundo
	await WorldAudioManager.fade_out_world_audio(0.5)

	# 2. Fade visual a negro
	await SceneManager.fade_out(0.5)

	# 3. Ocultar mundo y pausar todo
	if is_instance_valid(world):
		world.visible = false

	get_tree().paused = true

	# Momento seguro — mundo negro y pausado. NPCs pueden hacer queue_free aquí.
	world_hidden.emit()

	# 4. Instanciar ClientTransition FUERA del mundo
	transition = CLIENT_TRANSITION_SCENE.instantiate()
	if transition == null:
		push_error("ClientServiceManager: no se pudo instanciar ClientTransition")
		await _cleanup_service(world, player, null)
		return {}

	transition.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	get_tree().root.add_child(transition)

	# 5. Preparar la transición MIENTRAS TODO SIGUE NEGRO
	transition.prepare(acto, tipo, client_skin_name)

	# 6. Dar 2 frames para que la Camera2D local + PhantomHost + PCam se asienten
	await get_tree().process_frame
	await get_tree().process_frame

	# 7. Mostrar desde negro ya con la cámara correcta
	SceneManager.snap_clear()

	# 8. Arrancar la animación ya visible
	transition.play_transition()

	# 9. Esperar resultado
	if not is_instance_valid(transition):
		push_error("ClientServiceManager: transition destruida antes de finished")
		await _cleanup_service(world, player, null)
		return {}

	data = await transition.finished

	# 10. Restaurar SIEMPRE todo antes de salir
	await _cleanup_service(world, player, transition)
	return data


func _cleanup_service(world: Node, player: Node, transition: Node) -> void:
	# Recuperar negro global inmediatamente
	SceneManager.snap_black()

	# Si la transición sigue viva, eliminarla
	if is_instance_valid(transition):
		transition.queue_free()

	# Reanudar árbol
	get_tree().paused = false

	# Restaurar mundo
	if is_instance_valid(world):
		world.visible = true

	# Restaurar audio del mundo
	await WorldAudioManager.fade_in_world_audio(0.8)

	# Fade visual de negro a transparente
	await SceneManager.fade_in(0.5)

	# Devolver control al player
	if is_instance_valid(player):
		player.enable_movement()
		player.velocity = Vector2.ZERO

	_active = false
	StateManager.exit(StateManager.State.CLIENT_SERVICE)
