extends Node2D
# ================================================================
# BUILDING ENTRANCE — enter_building.gd
# Nodo: BuildingEntrance (hijo del nodo raíz del edificio)
# ================================================================
# Responsabilidad:
# - Entrada/salida del player a interiores del mismo escenario.
# - Activar/desactivar interior, colisiones, cámara interior y audio.
# - Delegar control del player a PlayerManager.
# - Delegar fade/título de transición a SceneManager.
# - Exponer API npc_enter()/npc_exit() para NPCBuildingTravel.
# ================================================================

const PLAYER_LOCK_REASON: String = "building_transition"
const FALLBACK_TITLE_LAYER: int = 1100
const FALLBACK_TITLE_FONT_PATH: String = "res://Assets/Fonts/IMFellEnglish.ttf"

# ================================================================
# NODOS INTERNOS
# ================================================================
var _enter_area: Area2D = null
var _exit_area: Area2D = null
var _interior: Node2D = null
var _walls: StaticBody2D = null
var _inside_audio: Node = null
var _audio_sfx: AudioStreamPlayer2D = null
var _door_glow: Node2D = null

# Config del padre (building.gd)
var _config: Node = null

# ================================================================
# 🔗 NODE REFERENCES — asignar desde el Inspector si quieres
# Si están vacíos, usa fallbacks.
# ================================================================
@export_group("🔗 Node References")
@export var interior_path: NodePath
@export var exit_area_path: NodePath
@export var walls_path: NodePath
@export var audio_path: NodePath

# ================================================================
# 🚶 NPC TRANSIT
# ================================================================
@export_group("🚶 NPC Transit")
@export var npc_fade_time: float = 0.22
@export var npc_play_door_sfx: bool = true
@export var npc_color_reveal_start: float = 0.8

# ================================================================
# ESTADO
# ================================================================
var _inside: bool = false
var _player_near_enter: bool = false
var _player_near_exit: bool = false
var _transitioning: bool = false
var _interior_audio_started: bool = false

var _fallback_title_layer: CanvasLayer = null


# ================================================================
# READY
# ================================================================
func _ready() -> void:
	_config = get_parent()

	_audio_sfx = AudioStreamPlayer2D.new()
	_audio_sfx.name = "BuildingDoorSFX"
	add_child(_audio_sfx)

	_enter_area = get_node_or_null("EnterArea") as Area2D
	_door_glow = get_node_or_null("DoorGlow") as Node2D

	_interior = _resolve_many(interior_path, ["../Interior"]) as Node2D
	_exit_area = _resolve_many(exit_area_path, ["../Interior/ExitArea", "../Interior/TileMapLayer/ExitArea"]) as Area2D
	_walls = _resolve_many(walls_path, ["../Interior/Collisions/Wall", "../Interior/TileMapLayer/Wall"]) as StaticBody2D
	_inside_audio = _resolve_many(audio_path, ["../Audio"])

	if _interior:
		_interior.visible = false
		_interior.modulate.a = 0.0

	# Interiores offscreen: las colisiones quedan activas aunque el interior esté oculto.
	# Si se desactivan, los NPCs que entran solos caen al vacío mientras el player está fuera.
	_set_walls_enabled(true)
	_connect_area_signals()


func _resolve_many(path: NodePath, fallbacks: Array[String]) -> Node:
	if not path.is_empty():
		var resolved_from_path: Node = get_node_or_null(path)
		if resolved_from_path:
			return resolved_from_path
		push_warning("BuildingEntrance: NodePath '%s' no encontrado, usando fallbacks." % str(path))

	for fallback: String in fallbacks:
		var resolved_from_fallback: Node = get_node_or_null(fallback)
		if resolved_from_fallback:
			return resolved_from_fallback

	return null


func _connect_area_signals() -> void:
	if _enter_area:
		if not _enter_area.body_entered.is_connected(_on_enter_area_entered):
			_enter_area.body_entered.connect(_on_enter_area_entered)
		if not _enter_area.body_exited.is_connected(_on_enter_area_exited):
			_enter_area.body_exited.connect(_on_enter_area_exited)

	if _exit_area:
		if not _exit_area.body_entered.is_connected(_on_exit_area_entered):
			_exit_area.body_entered.connect(_on_exit_area_entered)
		if not _exit_area.body_exited.is_connected(_on_exit_area_exited):
			_exit_area.body_exited.connect(_on_exit_area_exited)


func _sync_player_area_state_after_spawn() -> void:
	# Al teletransportar al player entre spawn interior/exterior, Godot no siempre
	# emite body_entered para el Area2D donde ya aparece colocado.
	# Recalculamos manualmente si está dentro del área correcta para que pueda
	# volver a pulsar F sin tener que salir y reentrar en el área.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var player: Node2D = PlayerManager.get_player_node2d()
	_player_near_enter = false
	_player_near_exit = false

	if is_instance_valid(player):
		_player_near_enter = _area_contains_body(_enter_area, player)
		_player_near_exit = _area_contains_body(_exit_area, player)

	if _inside and _player_near_exit:
		_register_interaction()
		return

	if not _inside and _player_near_enter:
		_set_door_glow(true)
		_register_interaction()
		return

	InteractionManager.unregister(self)


func _area_contains_body(area: Area2D, body: Node) -> bool:
	if not is_instance_valid(area) or not is_instance_valid(body):
		return false

	for overlapping_body: Node in area.get_overlapping_bodies():
		if overlapping_body == body:
			return true

	return false


# ================================================================
# DETECCIÓN DE ÁREAS / INTERACCIÓN
# ================================================================
func _on_enter_area_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_near_enter = true
		_set_door_glow(true)
		_register_interaction()


func _on_enter_area_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_near_enter = false
		_set_door_glow(false)
		InteractionManager.unregister(self)


func _on_exit_area_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_near_exit = true
		_register_interaction()


func _on_exit_area_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_near_exit = false
		InteractionManager.unregister(self)


func _register_interaction() -> void:
	InteractionManager.register(
		self,
		InteractionManager.Priority.BUILDING,
		_on_interact,
		get_interaction_label()
	)


func get_interaction_label() -> String:
	if _inside:
		return "Salir"

	if _config and _config.get("building_name") != null:
		var building_name: String = str(_config.get("building_name")).strip_edges()
		if not building_name.is_empty():
			return "Entrar"

	return "Entrar"


func _on_interact() -> void:
	if _transitioning:
		return

	if not StateManager.can_interact():
		return

	if not _inside and _player_near_enter:
		if _config and _config.has_method("on_enter"):
			if not _config.on_enter():
				return

		_transitioning = true
		await _enter()
		_transitioning = false
		return

	if _inside and _player_near_exit:
		if _config and _config.has_method("on_exit"):
			if not _config.on_exit():
				return

		_transitioning = true
		await _exit()
		_transitioning = false


# ================================================================
# ENTRAR
# ================================================================
func _enter() -> void:
	var player: Node = PlayerManager.get_player()
	if not is_instance_valid(player):
		push_error("BuildingEntrance: no hay player registrado en PlayerManager.")
		return

	_inside = true
	_play_sfx(_get_audio_stream_array("open_sounds"))
	_lock_player_for_transition()

	var fade_total: float = _get_config_float("fade_time", 0.8)
	var fade_half: float = fade_total * 0.5

	_show_transition_title(_get_config_string("building_name", ""), fade_total)
	await SceneManager.fade_out(fade_half, true, "building_enter_fade_out")

	_setup_interior_camera(player)

	var interior_spawn: Vector2 = _get_interior_spawn_position(player.global_position)
	PlayerManager.set_player_position(interior_spawn, true)

	_set_level_inside_state(true)
	_set_exterior_visible(false)
	_set_interior_visible(true)
	_set_walls_enabled(true)

	await SceneManager.fade_in(fade_half, true, "building_enter_fade_in")

	_resume_inside_audio_after_enter()
	await _sync_player_area_state_after_spawn()
	_unlock_player_after_transition()


# ================================================================
# SALIR
# ================================================================
func _exit() -> void:
	var player: Node = PlayerManager.get_player()
	if not is_instance_valid(player):
		push_error("BuildingEntrance: no hay player registrado en PlayerManager.")
		return

	_inside = false
	_play_sfx(_get_audio_stream_array("close_sounds"))
	_lock_player_for_transition()

	var fade_total: float = _get_config_float("fade_time", 0.8)
	var fade_half: float = fade_total * 0.5

	_show_transition_title(_get_config_string("street_name", ""), fade_total)
	await SceneManager.fade_out(fade_half, true, "building_exit_fade_out")

	_disable_interior_camera()
	_set_inside_audio_paused(true)
	_set_interior_visible(false)
	# Mantener colisiones interiores activas: el Interior debe estar físicamente offscreen.
	_set_walls_enabled(true)
	_set_exterior_visible(true)

	var exterior_spawn: Vector2 = _get_exterior_spawn_position(player.global_position)
	PlayerManager.set_player_position(exterior_spawn, true)

	_set_level_inside_state(false)

	await SceneManager.fade_in(fade_half, true, "building_exit_fade_in")

	await _sync_player_area_state_after_spawn()
	_unlock_player_after_transition()


func _lock_player_for_transition() -> void:
	PlayerManager.lock_player(PLAYER_LOCK_REASON, true)
	PlayerManager.force_stop()
	PlayerManager.stop_motion_audio()


func _unlock_player_after_transition() -> void:
	PlayerManager.unlock_player(PLAYER_LOCK_REASON)
	PlayerManager.force_stop()
	PlayerManager.block_movement_input_until_release()


# ================================================================
# TÍTULO DE TRANSICIÓN
# ================================================================
func _show_transition_title(title: String, total_duration: float) -> void:
	var clean_title: String = title.strip_edges()
	if clean_title.is_empty():
		return

	if SceneManager.has_method("show_transition_title"):
		SceneManager.show_transition_title(clean_title, total_duration)
		return

	# Fallback por si la escena aún no tiene SceneManager.show_transition_title().
	_show_transition_title_fallback(clean_title, total_duration)


func _show_transition_title_fallback(title: String, total_duration: float) -> void:
	_clear_transition_title_fallback()

	_fallback_title_layer = CanvasLayer.new()
	_fallback_title_layer.name = "BuildingTransitionTitleLayer"
	_fallback_title_layer.layer = FALLBACK_TITLE_LAYER
	get_tree().root.add_child(_fallback_title_layer)

	var lbl := Label.new()
	lbl.text = title
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)

	var font := load(FALLBACK_TITLE_FONT_PATH) as FontFile
	if font:
		lbl.add_theme_font_override("font", font)

	lbl.add_theme_font_size_override("font_size", 36)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
	lbl.modulate.a = 0.0
	_fallback_title_layer.add_child(lbl)

	var title_duration: float = total_duration * (2.0 / 3.0)
	var title_delay: float = (total_duration - title_duration) * 0.5
	var fade_title: float = title_duration * 0.2
	var visible_time: float = max(title_duration - fade_title * 2.0, 0.0)

	var tween := _fallback_title_layer.create_tween()
	tween.tween_interval(title_delay)
	tween.tween_property(lbl, "modulate:a", 1.0, fade_title)
	tween.tween_interval(visible_time)
	tween.tween_property(lbl, "modulate:a", 0.0, fade_title)
	tween.tween_callback(_clear_transition_title_fallback)


func _clear_transition_title_fallback() -> void:
	if _fallback_title_layer and is_instance_valid(_fallback_title_layer):
		_fallback_title_layer.queue_free()

	_fallback_title_layer = null


# ================================================================
# CÁMARA / SPAWNS
# ================================================================
func _setup_interior_camera(player: Node) -> void:
	if not _config:
		return

	if _config.has_method("setup_interior_pcam"):
		_config.setup_interior_pcam(player)

	if _config.has_method("apply_interior_pcam_limits"):
		_config.apply_interior_pcam_limits()

	var interior_pcam: PhantomCamera2D = null
	if _config.has_method("get_interior_pcam"):
		interior_pcam = _config.get_interior_pcam()

	if is_instance_valid(interior_pcam):
		interior_pcam.visible = true
		interior_pcam.priority = 20


func _disable_interior_camera() -> void:
	if not _config:
		return

	var interior_pcam: PhantomCamera2D = null
	if _config.has_method("get_interior_pcam"):
		interior_pcam = _config.get_interior_pcam()

	if is_instance_valid(interior_pcam):
		interior_pcam.priority = 0


func _get_interior_spawn_position(fallback_position: Vector2) -> Vector2:
	if _config and _config.has_method("get_interior_spawn_position"):
		return _config.get_interior_spawn_position(fallback_position)

	return fallback_position


func _get_exterior_spawn_position(fallback_position: Vector2) -> Vector2:
	if _config and _config.has_method("get_exterior_spawn_position"):
		return _config.get_exterior_spawn_position(fallback_position)

	return fallback_position


# ================================================================
# SPAWNS PARA NPCs
# ================================================================
# Los NPCs usan los mismos puntos de entrada/salida que el player.
# Esto evita depender de ExitArea como punto de aparición interior,
# que en algunos edificios no coincide con el punto seguro de spawn.
func get_npc_interior_spawn_position(fallback_position: Vector2) -> Vector2:
	return _get_interior_spawn_position(fallback_position)


func get_npc_exterior_spawn_position(fallback_position: Vector2) -> Vector2:
	return _get_exterior_spawn_position(fallback_position)


# ================================================================
# VISIBILIDAD INTERIOR / EXTERIOR
# ================================================================
func _set_interior_visible(value: bool) -> void:
	if not _interior:
		return

	_interior.visible = value
	_interior.modulate.a = 1.0 if value else 0.0


func _set_exterior_visible(value: bool) -> void:
	var exterior: Node = get_parent().get_node_or_null("Exterior")
	if exterior and exterior is CanvasItem:
		(exterior as CanvasItem).visible = value


# ================================================================
# AUDIO INTERIOR DEL EDIFICIO
# ================================================================
func _resume_inside_audio_after_enter() -> void:
	if not _interior_audio_started:
		_interior_audio_started = true
		_start_inside_audio()
	else:
		_set_inside_audio_paused(false)


func _start_inside_audio() -> void:
	if not _inside_audio:
		return

	var tween: Tween = create_tween().set_parallel(true)
	var fade_time: float = _get_config_float("fade_time", 0.8) * 0.8

	for child: Node in _inside_audio.get_children():
		if child is AudioStreamPlayer:
			var asp := child as AudioStreamPlayer
			asp.volume_db = -40.0
			asp.play()
			tween.tween_property(asp, "volume_db", 0.0, fade_time)
		elif child is AudioStreamPlayer2D:
			var asp2d := child as AudioStreamPlayer2D
			asp2d.volume_db = -40.0
			asp2d.play()
			tween.tween_property(asp2d, "volume_db", 0.0, fade_time)


func _set_inside_audio_paused(paused: bool) -> void:
	if not _inside_audio:
		return

	for child: Node in _inside_audio.get_children():
		if child is AudioStreamPlayer:
			_set_audio_player_paused(child as AudioStreamPlayer, paused)
		elif child is AudioStreamPlayer2D:
			_set_audio_player_2d_paused(child as AudioStreamPlayer2D, paused)


func _set_audio_player_paused(player: AudioStreamPlayer, paused: bool) -> void:
	if paused:
		if not player.has_meta("_original_volume_db"):
			player.set_meta("_original_volume_db", player.volume_db)
		player.volume_db = -80.0
		player.stream_paused = true
		return

	player.stream_paused = false
	if player.has_meta("_original_volume_db"):
		player.volume_db = float(player.get_meta("_original_volume_db"))
	else:
		player.volume_db = 0.0


func _set_audio_player_2d_paused(player: AudioStreamPlayer2D, paused: bool) -> void:
	if paused:
		if not player.has_meta("_original_volume_db"):
			player.set_meta("_original_volume_db", player.volume_db)
		player.volume_db = -80.0
		player.stream_paused = true
		return

	player.stream_paused = false
	if player.has_meta("_original_volume_db"):
		player.volume_db = float(player.get_meta("_original_volume_db"))
	else:
		player.volume_db = 0.0


# ================================================================
# AUDIO SFX
# ================================================================
func _play_sfx(sounds: Array[AudioStream]) -> void:
	if sounds.is_empty() or not _audio_sfx:
		return

	_audio_sfx.stream = sounds.pick_random()
	_audio_sfx.pitch_scale = randf_range(0.95, 1.05)
	_audio_sfx.volume_db = randf_range(
		_get_config_float("sfx_volume_db_min", 0.0),
		_get_config_float("sfx_volume_db_max", 2.0)
	)
	_audio_sfx.play()


func _play_npc_door_sfx(sounds: Array[AudioStream]) -> void:
	if not npc_play_door_sfx:
		return
	_play_sfx(sounds)


# ================================================================
# COLISIONES
# ================================================================
func _set_walls_enabled(enabled: bool) -> void:
	if not is_instance_valid(_walls):
		return

	for shape: Node in _walls.get_children():
		if shape is CollisionShape2D:
			(shape as CollisionShape2D).disabled = not enabled


# ================================================================
# CONGELAR MUNDO EXTERIOR
# ================================================================
func _set_level_inside_state(inside: bool) -> void:
	var current_scene: Node = get_tree().current_scene
	if is_instance_valid(current_scene) and current_scene.has_method("set_player_inside_building"):
		current_scene.set_player_inside_building(get_parent(), inside)
	else:
		_freeze_world(inside)

	if PlayerManager and PlayerManager.has_method("refresh_detection_from_world"):
		PlayerManager.refresh_detection_from_world()


func _freeze_world(freeze: bool) -> void:
	var current_scene: Node = get_tree().current_scene
	if not is_instance_valid(current_scene):
		return

	var world: Node = current_scene.find_child("World", true, false)
	if not world:
		return

	for child: Node in world.get_children():
		if child == get_parent():
			continue

		var canvas_item: CanvasItem = child as CanvasItem
		if canvas_item:
			canvas_item.visible = not freeze

		child.process_mode = Node.PROCESS_MODE_DISABLED if freeze else Node.PROCESS_MODE_INHERIT


# ================================================================
# GLOW DE PUERTA
# ================================================================
var _glow_tween: Tween = null


func _set_door_glow(active: bool) -> void:
	if not is_instance_valid(_door_glow):
		return

	var mat: ShaderMaterial = _door_glow.material as ShaderMaterial
	if not mat:
		return

	if _glow_tween:
		_glow_tween.kill()
		_glow_tween = null

	if active:
		_glow_pulse(mat)
	else:
		_glow_tween = create_tween()
		_glow_tween.tween_method(
			func(v: float) -> void:
				mat.set_shader_parameter("glow_strength", v),
			float(mat.get_shader_parameter("glow_strength")),
			0.0,
			0.2
		)


func _glow_pulse(mat: ShaderMaterial) -> void:
	_glow_tween = create_tween().set_loops()
	_glow_tween.tween_method(
		func(v: float) -> void:
			mat.set_shader_parameter("glow_strength", v),
		0.0,
		2.0,
		0.7
	)
	_glow_tween.tween_method(
		func(v: float) -> void:
			mat.set_shader_parameter("glow_strength", v),
		2.0,
		0.0,
		0.7
	)


# ================================================================
# FORZAR ESTADO INTERIOR — usado por SaveManager
# ================================================================
func force_inside_state(inside: bool) -> void:
	_inside = inside

	_set_interior_visible(inside)
	# Las colisiones interiores permanecen activas siempre; el nodo Interior está offscreen.
	_set_walls_enabled(true)
	_set_level_inside_state(inside)
	_set_exterior_visible(not inside)

	var player: Node = PlayerManager.get_player()
	if is_instance_valid(player):
		if inside:
			_setup_interior_camera(player)
		else:
			_disable_interior_camera()

	if inside:
		_resume_inside_audio_after_enter()
	else:
		_set_inside_audio_paused(true)


func is_inside() -> bool:
	return _inside


func is_transitioning() -> bool:
	return _transitioning


# ================================================================
# NPCs — entrar/salir sin afectar al player
# ================================================================
func npc_enter(npc: CharacterBody2D, interior_position: Vector2) -> void:
	if not is_instance_valid(npc):
		return

	if _is_npc_in_building_transit(npc):
		return

	_set_npc_transit_active(npc, true)
	_play_npc_door_sfx(_get_audio_stream_array("open_sounds"))

	var fade_target: CanvasItem = _get_npc_fade_target(npc)
	await _fade_npc_out(fade_target)

	_remember_npc_original_parent(npc)
	_reparent_npc_to_interior(npc)
	npc.global_position = interior_position
	npc.velocity = Vector2.ZERO

	if _inside:
		await _fade_npc_in(fade_target)
	else:
		_reset_npc_visual(fade_target)

	_set_npc_transit_active(npc, false)


func npc_exit(npc: CharacterBody2D, exterior_position: Vector2) -> void:
	if not is_instance_valid(npc):
		return

	if _is_npc_in_building_transit(npc):
		return

	_set_npc_transit_active(npc, true)
	_play_npc_door_sfx(_get_audio_stream_array("close_sounds"))

	var fade_target: CanvasItem = _get_npc_fade_target(npc)
	if _inside:
		await _fade_npc_out(fade_target)

	_reparent_npc_to_original_parent(npc)
	npc.global_position = exterior_position
	npc.velocity = Vector2.ZERO

	if not _inside:
		await _fade_npc_in(fade_target)
	else:
		_reset_npc_visual(fade_target)

	npc.remove_meta("_original_parent_path")
	_set_npc_transit_active(npc, false)


func _is_npc_in_building_transit(npc: CharacterBody2D) -> bool:
	if not is_instance_valid(npc):
		return false
	return bool(npc.get_meta("_building_transit_active", false))


func _set_npc_transit_active(npc: CharacterBody2D, active: bool) -> void:
	if not is_instance_valid(npc):
		return

	npc.set_meta("_building_transit_active", active)
	npc.velocity = Vector2.ZERO

	if npc.has_node("Movement"):
		var movement := npc.get_node("Movement")
		if movement:
			if active and movement.has_method("freeze"):
				movement.freeze()
			elif not active and movement.has_method("unfreeze"):
				movement.unfreeze()


func _remember_npc_original_parent(npc: CharacterBody2D) -> void:
	if not is_instance_valid(npc):
		return

	if npc.has_meta("_original_parent_path"):
		return

	var parent: Node = npc.get_parent()
	if is_instance_valid(parent):
		npc.set_meta("_original_parent_path", str(parent.get_path()))


func _reparent_npc_to_interior(npc: CharacterBody2D) -> void:
	if not is_instance_valid(npc):
		return

	if not is_instance_valid(_interior):
		return

	if npc.get_parent() == _interior:
		return

	_reparent_keep_global(npc, _interior)


func _reparent_npc_to_original_parent(npc: CharacterBody2D) -> void:
	if not is_instance_valid(npc):
		return

	var target_parent: Node = _get_npc_original_parent(npc)
	if not is_instance_valid(target_parent):
		target_parent = _get_default_npc_exterior_parent()

	if not is_instance_valid(target_parent):
		return

	if npc.get_parent() == target_parent:
		return

	_reparent_keep_global(npc, target_parent)


func _get_npc_original_parent(npc: CharacterBody2D) -> Node:
	if not is_instance_valid(npc):
		return null

	var original_path_value: Variant = npc.get_meta("_original_parent_path", "")
	var original_path: String = str(original_path_value)
	if original_path.strip_edges().is_empty():
		return null

	return get_node_or_null(NodePath(original_path))


func _get_default_npc_exterior_parent() -> Node:
	var current_scene: Node = get_tree().current_scene
	if not is_instance_valid(current_scene):
		return null

	var outside_actors: Node = current_scene.find_child("OutsideActors", true, false)
	if is_instance_valid(outside_actors):
		return outside_actors

	var world: Node = current_scene.find_child("World", true, false)
	if is_instance_valid(world):
		return world

	return current_scene


func _reparent_keep_global(node: Node2D, new_parent: Node) -> void:
	if not is_instance_valid(node) or not is_instance_valid(new_parent):
		return

	# CRÍTICO:
	# Al meter NPCs dentro de Interior, no basta con conservar solo global_position.
	# Si Interior o alguno de sus padres tiene escala/rotación, el NPC hereda esa transformación
	# y puede aparecer gigante o quedarse bloqueado con colliders.
	# Conservamos el Transform2D global completo, igual que hacía el sistema antiguo.
	var old_global_transform: Transform2D = node.global_transform
	var old_parent: Node = node.get_parent()
	if is_instance_valid(old_parent):
		old_parent.remove_child(node)

	new_parent.add_child(node)
	node.global_transform = old_global_transform


func _get_npc_fade_target(npc: CharacterBody2D) -> CanvasItem:
	if not is_instance_valid(npc):
		return null

	var character_container := npc.get_node_or_null("CharacterContainer") as CanvasItem
	if character_container:
		return character_container

	return npc as CanvasItem


func _fade_npc_out(fade_target: CanvasItem) -> void:
	if not fade_target:
		return

	var start_color: Color = fade_target.modulate
	var end_color: Color = Color(start_color.r, start_color.g, start_color.b, 0.0)

	var tween := create_tween()
	tween.tween_property(fade_target, "modulate", end_color, npc_fade_time)
	await tween.finished


func _fade_npc_in(fade_target: CanvasItem) -> void:
	if not fade_target:
		return

	_apply_npc_reappear_progress(fade_target, 0.0)

	var tween := create_tween()
	tween.tween_method(
		func(v: float) -> void:
			_apply_npc_reappear_progress(fade_target, v),
		0.0,
		1.0,
		npc_fade_time
	)
	await tween.finished
	_reset_npc_visual(fade_target)


func _reset_npc_visual(fade_target: CanvasItem) -> void:
	if fade_target:
		fade_target.modulate = Color(1, 1, 1, 1)


func _apply_npc_reappear_progress(fade_target: CanvasItem, progress: float) -> void:
	if not fade_target:
		return

	var alpha: float = progress
	var saturation_progress: float = clamp(
		(progress - npc_color_reveal_start) / max(0.0001, 1.0 - npc_color_reveal_start),
		0.0,
		1.0
	)

	var grey_value: float = lerp(0.35, 1.0, saturation_progress)
	fade_target.modulate = Color(grey_value, grey_value, grey_value, alpha)


# ================================================================
# CONFIG HELPERS
# ================================================================
func _get_config_float(property_name: String, fallback: float) -> float:
	if not _config:
		return fallback

	var value: Variant = _config.get(property_name)
	if value == null:
		return fallback

	return float(value)


func _get_config_string(property_name: String, fallback: String) -> String:
	if not _config:
		return fallback

	var value: Variant = _config.get(property_name)
	if value == null:
		return fallback

	return str(value)


func _get_audio_stream_array(property_name: String) -> Array[AudioStream]:
	var result: Array[AudioStream] = []
	if not _config:
		return result

	var value: Variant = _config.get(property_name)
	if value is Array:
		for item: Variant in value:
			if item is AudioStream:
				result.append(item as AudioStream)

	return result
