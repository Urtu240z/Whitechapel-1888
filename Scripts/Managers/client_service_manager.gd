extends Node

# ================================================================
# CLIENT SERVICE MANAGER — Autoload
# ================================================================
# Orquesta el flujo especial de servicio con cliente.
#
# Flujo visual correcto:
# - Transición hacia client service: efectos visibles.
# - Animación / minijuego: efectos ocultos.
# - Transición de vuelta al mundo: efectos visibles.
# ================================================================

const CLIENT_TRANSITION_SCENE: PackedScene = preload("res://Scenes/Client_Transition/Client_Transition.tscn")

const LOCK_REASON: String = "client_service"
const AUDIO_REASON: String = "client_service"

const EFFECTS_TRANSITION_IN_REASON: String = "client_service_transition_in"
const EFFECTS_TRANSITION_OUT_REASON: String = "client_service_transition_out"
const EFFECTS_CONTENT_REASON: String = "client_service_content"

const FADE_OUT_TIME: float = 0.5
const FADE_IN_TIME: float = 0.5
const AUDIO_FADE_OUT_TIME: float = 0.5
const AUDIO_FADE_IN_TIME: float = 0.8

signal service_started(acto: String, tipo: String, client_skin_name: String)
signal service_finished(result: Dictionary)
signal service_failed(reason: String)
signal world_hidden
signal world_restored

var _active: bool = false
var _current_transition: Node = null
var _hidden_world: Node = null


# ================================================================
# READY
# ================================================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# ================================================================
# API
# ================================================================
func is_active() -> bool:
	return _active


func start_service(acto: String, tipo: String, client_skin_name: String = "NPC_ClientPoor") -> Dictionary:
	if _active:
		push_warning("ClientServiceManager.start_service(): ya hay un servicio activo.")
		service_failed.emit("already_active")
		return {}

	if not StateManager.can_start_client_service():
		push_warning("ClientServiceManager.start_service(): estado inválido: %s" % StateManager.current_name())
		service_failed.emit("invalid_state")
		return {}

	# Queremos que los efectos NO se corten durante el fade hacia negro.
	_effects_force_visible(EFFECTS_TRANSITION_IN_REASON)

	if not StateManager.change_to(StateManager.State.CLIENT_SERVICE, "start_client_service"):
		_effects_clear_force_visible(EFFECTS_TRANSITION_IN_REASON)
		service_failed.emit("state_change_failed")
		return {}

	_active = true
	service_started.emit(acto, tipo, client_skin_name)

	var world := get_tree().current_scene
	_hidden_world = world
	_current_transition = null

	PlayerManager.lock_player(LOCK_REASON, true)
	PlayerManager.force_stop()
	_sync_building_interior_audio()

	var result: Dictionary = {}

	# 1. Fade out audio mundo.
	await WorldAudioManager.fade_out_world_audio(AUDIO_FADE_OUT_TIME, AUDIO_REASON)

	# 2. Fade visual a negro.
	# Durante este fade, EffectsManager está forzado visible.
	await SceneManager.fade_out(FADE_OUT_TIME, true, "client_service_fade_out")

	# 3. A partir de pantalla negra, ocultamos efectos para animación/minijuego.
	_effects_suppress(EFFECTS_CONTENT_REASON)
	_effects_clear_force_visible(EFFECTS_TRANSITION_IN_REASON)

	# 4. Ocultar mundo y pausar árbol.
	_hide_world(world)
	get_tree().paused = true
	world_hidden.emit()

	# 5. Instanciar transición fuera del mundo.
	var transition := _create_transition()
	if transition == null:
		await _cleanup_service({}, "transition_create_failed")
		service_failed.emit("transition_create_failed")
		return {}

	_current_transition = transition

	# 6. Preparar transición con todo negro.
	if transition.has_method("prepare"):
		transition.prepare(acto, tipo, client_skin_name)
	else:
		push_error("ClientServiceManager: ClientTransition no tiene método prepare().")
		await _cleanup_service({}, "transition_missing_prepare")
		service_failed.emit("transition_missing_prepare")
		return {}

	# 7. Dar dos frames para cámara/local setup.
	await get_tree().process_frame
	await get_tree().process_frame

	# 8. Mostrar transición desde negro.
	# Los efectos siguen suprimidos aquí.
	SceneManager.snap_clear("client_service_show_transition")

	# 9. Arrancar animación/minijuego.
	if transition.has_method("play_transition"):
		transition.play_transition()
	else:
		push_error("ClientServiceManager: ClientTransition no tiene método play_transition().")
		await _cleanup_service({}, "transition_missing_play_transition")
		service_failed.emit("transition_missing_play_transition")
		return {}

	# 10. Esperar resultado.
	if not is_instance_valid(transition):
		push_error("ClientServiceManager: transition destruida antes de emitir finished.")
		await _cleanup_service({}, "transition_destroyed")
		service_failed.emit("transition_destroyed")
		return {}

	result = await transition.finished
	if result == null:
		result = {}

	# 11. Restaurar todo.
	await _cleanup_service(result, "finished")
	service_finished.emit(result)
	return result


# ================================================================
# CREACIÓN / MUNDO
# ================================================================
func _create_transition() -> Node:
	var transition := CLIENT_TRANSITION_SCENE.instantiate()
	if transition == null:
		push_error("ClientServiceManager: no se pudo instanciar ClientTransition.")
		return null

	transition.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	get_tree().root.add_child(transition)
	return transition


func _hide_world(world: Node) -> void:
	if not is_instance_valid(world):
		return

	world.visible = false


func _restore_world(world: Node) -> void:
	if not is_instance_valid(world):
		return

	world.visible = true
	world_restored.emit()


# ================================================================
# CLEANUP
# ================================================================
func _cleanup_service(_result: Dictionary = {}, reason: String = "cleanup") -> void:
	# Pantalla negra inmediata antes de destruir la escena de transición.
	SceneManager.snap_black("client_service_cleanup_black")

	# La animación/minijuego termina aquí.
	if is_instance_valid(_current_transition):
		_current_transition.queue_free()

	_current_transition = null

	# Reanudar árbol antes de restaurar mundo/audio.
	get_tree().paused = false

	# Restaurar mundo mientras aún está negro.
	_restore_world(_hidden_world)
	_hidden_world = null
	_sync_building_interior_audio()

	# Para la transición de vuelta:
	# - quitamos supresión del contenido
	# - forzamos efectos visibles aunque StateManager siga en CLIENT_SERVICE
	_effects_force_visible(EFFECTS_TRANSITION_OUT_REASON)
	_effects_restore(EFFECTS_CONTENT_REASON)

	# Restaurar audio del mundo.
	await WorldAudioManager.fade_in_world_audio(AUDIO_FADE_IN_TIME, AUDIO_REASON)

	# Fade visual de negro a transparente.
	# Durante este fade, los efectos vuelven a verse.
	await SceneManager.fade_in(FADE_IN_TIME, true, "client_service_fade_in")
	_sync_building_interior_audio()

	# Limpiar fuerza visual tras terminar la transición de vuelta.
	_effects_clear_force_visible(EFFECTS_TRANSITION_OUT_REASON)

	_active = false

	# Volver a gameplay.
	if StateManager.is_client_service():
		StateManager.return_to_gameplay("end_client_service_%s" % reason)
	else:
		StateManager.force_state(StateManager.State.GAMEPLAY, "client_service_cleanup_%s" % reason)

	PlayerManager.unlock_player(LOCK_REASON)
	PlayerManager.force_stop()


# ================================================================
# AUDIO HELPERS
# ================================================================
func _sync_building_interior_audio() -> void:
	if not is_instance_valid(WorldAudioManager):
		return

	if WorldAudioManager.has_method("sync_building_interior_audio"):
		WorldAudioManager.sync_building_interior_audio()


# ================================================================
# EFFECTS HELPERS
# ================================================================
func _effects_force_visible(reason: String) -> void:
	if not is_instance_valid(EffectsManager):
		return

	if EffectsManager.has_method("force_visible"):
		EffectsManager.force_visible(reason)


func _effects_clear_force_visible(reason: String) -> void:
	if not is_instance_valid(EffectsManager):
		return

	if EffectsManager.has_method("clear_force_visible"):
		EffectsManager.clear_force_visible(reason)


func _effects_suppress(reason: String) -> void:
	if not is_instance_valid(EffectsManager):
		return

	if EffectsManager.has_method("suppress_for_ui"):
		EffectsManager.suppress_for_ui(reason)


func _effects_restore(reason: String) -> void:
	if not is_instance_valid(EffectsManager):
		return

	if EffectsManager.has_method("restore_after_ui"):
		EffectsManager.restore_after_ui(reason)
