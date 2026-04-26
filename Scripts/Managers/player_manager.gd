extends Node
# ================================================================
# PLAYER MANAGER — Autoload
# ================================================================
# Autoridad/fachada para acceder y controlar al player.
#
# Responsabilidades:
# - Registrar la instancia actual de Nell.
# - Crear/asegurar player si una escena lo necesita.
# - Mover/spawnear al player sin que cada script toque nodos internos.
# - Bloquear/desbloquear control por motivos concretos.
# - Aplicar bloqueo automático según StateManager.
# - Centralizar stop de movimiento/audio.
#
# No debe:
# - Gestionar fades. Eso es SceneManager.
# - Decidir estados globales. Eso es StateManager.
# - Aplicar daño. Eso es DamageManager.
# ================================================================

signal player_registered(player: MainPlayer)
signal player_unregistered(player: MainPlayer)
signal player_lock_changed(is_locked: bool, reasons: PackedStringArray)
signal player_position_changed(position: Vector2)
signal player_detection_state_changed(can_be_detected: bool)

const PLAYER_SCENE: PackedScene = preload("res://Scenes/Player/Player.tscn")
const STATE_LOCK_REASON: String = "state_manager"

# Se mantiene público porque muchos scripts aún leen PlayerManager.player_instance.
# A partir de ahora, para código nuevo usa get_player().
var player_instance: MainPlayer = null

var _locks: Dictionary = {}
var _last_can_be_detected: bool = true


# ================================================================
# READY
# ================================================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if StateManager and not StateManager.state_changed.is_connected(_on_state_changed):
		StateManager.state_changed.connect(_on_state_changed)

	_refresh_state_lock()
	_refresh_detection_state()


# ================================================================
# REGISTRO
# ================================================================
func register_player(player: MainPlayer) -> void:
	if not is_instance_valid(player):
		push_warning("PlayerManager.register_player(): player inválido.")
		return

	if is_instance_valid(player_instance) and player_instance != player:
		push_warning("PlayerManager: ya había un player registrado. Se reemplaza la referencia.")

	player_instance = player

	if not player_instance.is_in_group("player"):
		player_instance.add_to_group("player")

	if not player_instance.tree_exiting.is_connected(_on_player_tree_exiting):
		player_instance.tree_exiting.connect(_on_player_tree_exiting.bind(player_instance))

	_refresh_state_lock()
	_apply_control_lock()
	_refresh_detection_state()
	player_registered.emit(player_instance)


func unregister_player(player: MainPlayer) -> void:
	if not is_instance_valid(player):
		return

	if player_instance != player:
		return

	var old_player := player_instance
	player_instance = null
	player_unregistered.emit(old_player)


func _on_player_tree_exiting(player: MainPlayer) -> void:
	if player_instance == player:
		player_unregistered.emit(player)
		player_instance = null


# ================================================================
# GETTERS
# ================================================================
func has_player() -> bool:
	return is_instance_valid(player_instance)


func get_player() -> MainPlayer:
	if not is_instance_valid(player_instance):
		return null
	return player_instance


func get_player_node2d() -> Node2D:
	if not is_instance_valid(player_instance):
		return null
	return player_instance as Node2D


func get_player_position() -> Vector2:
	if not is_instance_valid(player_instance):
		return Vector2.ZERO
	return player_instance.global_position


func get_camera_target() -> Node2D:
	var player := get_player()
	if not player:
		return null
	return player.get_node_or_null("CameraTarget") as Node2D


func get_character_container() -> Node2D:
	var player := get_player()
	if not player:
		return null
	return player.get_node_or_null("CharacterContainer") as Node2D


# ================================================================
# DETECCIÓN / POLICÍA / MUNDO
# ================================================================
func is_player_hidden() -> bool:
	return StateManager != null and StateManager.is_hiding()


func is_player_inside_building() -> bool:
	var scene := get_tree().current_scene
	if is_instance_valid(scene) and scene.has_method("is_player_inside_building"):
		return bool(scene.call("is_player_inside_building"))
	return false


func get_active_building() -> Node2D:
	var scene := get_tree().current_scene
	if is_instance_valid(scene) and scene.has_method("get_active_building"):
		return scene.call("get_active_building") as Node2D
	return null


func can_player_be_detected(include_inside_buildings: bool = false) -> bool:
	if not has_player():
		return false

	if is_player_locked():
		return false

	if is_player_hidden():
		return false

	if is_player_inside_building() and not include_inside_buildings:
		return false

	if StateManager == null:
		return true

	return (
		StateManager.current() == StateManager.State.GAMEPLAY
		or StateManager.current() == StateManager.State.HIDING
	)


func get_detection_position() -> Vector2:
	var camera_target := get_camera_target()
	if is_instance_valid(camera_target):
		return camera_target.global_position
	return get_player_position()


func _refresh_detection_state() -> void:
	var detectable := can_player_be_detected()
	if detectable == _last_can_be_detected:
		return

	_last_can_be_detected = detectable
	player_detection_state_changed.emit(_last_can_be_detected)


# ================================================================
# CREACIÓN / SPAWN
# ================================================================
func ensure_player(parent: Node, spawn_position: Vector2 = Vector2.ZERO) -> MainPlayer:
	if parent == null:
		push_error("PlayerManager.ensure_player(): parent es null.")
		return null

	if not is_instance_valid(player_instance):
		player_instance = PLAYER_SCENE.instantiate() as MainPlayer

	if not is_instance_valid(player_instance):
		push_error("PlayerManager.ensure_player(): no se pudo instanciar Player.tscn.")
		return null

	if not player_instance.is_inside_tree():
		parent.add_child(player_instance)

	set_player_position(spawn_position, true)
	_refresh_state_lock()
	_apply_control_lock()

	return player_instance


func set_player_position(position: Vector2, stop_motion: bool = true) -> void:
	var player := get_player()
	if not player:
		push_warning("PlayerManager.set_player_position(): no hay player registrado.")
		return

	if stop_motion:
		force_stop()

	player.global_position = position
	player_position_changed.emit(position)


func move_player_by(offset: Vector2, stop_motion: bool = true) -> void:
	var player := get_player()
	if not player:
		return
	set_player_position(player.global_position + offset, stop_motion)


# ================================================================
# BLOQUEO DE CONTROL
# ================================================================
func lock_player(reason: String, stop_motion: bool = true) -> void:
	var clean_reason := _clean_reason(reason)
	_locks[clean_reason] = true

	if stop_motion:
		force_stop()

	_apply_control_lock()


func unlock_player(reason: String) -> void:
	var clean_reason := _clean_reason(reason)

	if _locks.has(clean_reason):
		_locks.erase(clean_reason)

	_apply_control_lock()


func clear_locks() -> void:
	_locks.clear()
	_refresh_state_lock()
	_apply_control_lock()


func is_player_locked() -> bool:
	return not _locks.is_empty()


func has_lock(reason: String) -> bool:
	return _locks.has(_clean_reason(reason))


func get_lock_reasons() -> PackedStringArray:
	var result := PackedStringArray()
	for key in _locks.keys():
		result.append(str(key))
	return result


func refresh_control_from_state() -> void:
	_refresh_state_lock()
	_apply_control_lock()
	_refresh_detection_state()


func refresh_detection_from_world() -> void:
	_refresh_detection_state()


func _on_state_changed(_from_state, _to_state) -> void:
	_refresh_state_lock()
	_apply_control_lock()
	_refresh_detection_state()


func _refresh_state_lock() -> void:
	if not StateManager:
		return

	if StateManager.can_move_player():
		_locks.erase(STATE_LOCK_REASON)
	else:
		_locks[STATE_LOCK_REASON] = true


func _apply_control_lock() -> void:
	var player := get_player()
	var locked := is_player_locked()

	if player:
		if locked:
			_disable_player_control(player)
		else:
			_enable_player_control(player)

		player_lock_changed.emit(locked, get_lock_reasons())

	_refresh_detection_state()


func _disable_player_control(player: MainPlayer) -> void:
	if not is_instance_valid(player):
		return

	if player.has_method("disable_movement"):
		player.disable_movement()
	else:
		player.set("can_move", false)

	force_stop()


func _enable_player_control(player: MainPlayer) -> void:
	if not is_instance_valid(player):
		return

	if player.has_method("enable_movement"):
		player.enable_movement()
	else:
		player.set("can_move", true)

	force_stop()
	block_movement_input_until_release()


func _clean_reason(reason: String) -> String:
	var clean := reason.strip_edges()
	if clean.is_empty():
		return "unknown"
	return clean


# ================================================================
# MOVIMIENTO / AUDIO / ANIMACIÓN
# ================================================================
func force_stop() -> void:
	var player := get_player()
	if not player:
		return

	if player is CharacterBody2D:
		(player as CharacterBody2D).velocity = Vector2.ZERO

	var movement := player.get_node_or_null("Movement")
	if movement and movement.has_method("force_stop"):
		movement.force_stop()

	stop_motion_audio()


func block_movement_input_until_release() -> void:
	var player := get_player()
	if not player:
		return

	var movement := player.get_node_or_null("Movement")
	if movement and movement.has_method("block_movement_input_until_release"):
		movement.block_movement_input_until_release()


func stop_motion_audio() -> void:
	var player := get_player()
	if not player:
		return

	var audio := player.get_node_or_null("Audio")
	if not audio:
		return

	_stop_audio_player(audio.get_node_or_null("StepPlayer"))
	_stop_audio_player(audio.get_node_or_null("BreathRun"))


func stop_all_player_audio() -> void:
	var player := get_player()
	if not player:
		return

	var audio := player.get_node_or_null("Audio")
	if not audio:
		return

	for child in audio.get_children():
		_stop_audio_player(child)


func _stop_audio_player(node: Node) -> void:
	if node == null:
		return

	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stop()
	elif node is AudioStreamPlayer2D:
		(node as AudioStreamPlayer2D).stop()


func set_animation_tree_active(active: bool) -> void:
	var player := get_player()
	if not player:
		return

	var animation_tree := player.get_node_or_null("AnimationTree")
	if animation_tree:
		animation_tree.set("active", active)


func force_idle_animation() -> void:
	var player := get_player()
	if not player:
		return

	var animation := player.get_node_or_null("Animation")
	if animation and animation.has_method("force_idle"):
		animation.force_idle()
	elif player.has_method("disable_movement"):
		# disable_movement ya fuerza idle en tu Player actual.
		player.disable_movement()


# ================================================================
# OUTFIT
# ================================================================
func set_outfit(outfit_id: String) -> void:
	var player := get_player()
	if not player:
		push_warning("PlayerManager.set_outfit(): no hay player registrado.")
		return

	if player.has_method("set_outfit"):
		player.set_outfit(outfit_id)
	else:
		push_warning("PlayerManager.set_outfit(): el player no tiene set_outfit().")


func get_outfit() -> String:
	var player := get_player()
	if not player:
		return "London"

	var outfit = player.get("default_outfit")
	if outfit != null:
		return str(outfit)

	return "London"


# ================================================================
# EFECTOS FÍSICOS BÁSICOS
# ================================================================
func apply_knockback(direction: Vector2, force: float) -> void:
	var player := get_player()
	if not player:
		return

	if player is CharacterBody2D:
		(player as CharacterBody2D).velocity += direction.normalized() * force


# ================================================================
# LEGACY CONTROLADO
# ================================================================
# Este flujo antiguo queda aquí solo para escenas que aún lo llamen.
# El objetivo es mover transiciones reales a SceneManager/ScenePortal.
# ================================================================
func enter_building(
	scene_path: String,
	spawn_position: Vector2,
	open_sound: AudioStream = null,
	close_sound: AudioStream = null,
	fade_time: float = 0.5
) -> void:
	push_warning("PlayerManager.enter_building() es legacy. Usa SceneManager/ScenePortal cuando migremos escenas.")

	if SceneManager.is_transitioning():
		push_warning("PlayerManager: transición ya en curso, ignorando.")
		return

	if open_sound:
		_play_sfx(open_sound)

	await SceneManager.fade_out(fade_time)
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	ensure_player(get_tree().current_scene, spawn_position)

	if close_sound:
		await get_tree().create_timer(0.25).timeout
		_play_sfx(close_sound)

	await SceneManager.fade_in(fade_time)


func _play_sfx(stream: AudioStream) -> void:
	if stream == null:
		return

	var sfx := AudioStreamPlayer.new()
	sfx.stream = stream
	sfx.bus = "SFX"
	get_tree().root.add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)
