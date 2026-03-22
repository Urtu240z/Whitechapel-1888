extends Node2D
# ================================================================
# BUILDING ENTRANCE — enter_building.gd
# Nodo: BuildingEntrance (Node2D), hijo del nodo raíz del edificio.
# Lee su configuración del padre (building.gd).
# ================================================================

# ================================================================
# NODOS INTERNOS
# ================================================================

var _enter_area: Area2D = null
var _exit_area: Area2D = null
var _interior: Node2D = null
var _walls: StaticBody2D = null
var _outside_audio: Node = null
var _inside_audio: Node = null

# Config leída del padre (building.gd)
var _config: Node = null
var _audio: AudioStreamPlayer2D = null

# ================================================================
# ESTADO
# ================================================================

var _inside: bool = false
var _player_near_enter: bool = false
var _player_near_exit: bool = false
var _transitioning: bool = false
var _original_limits: Dictionary = {}
var _interior_audio_started: bool = false

# ================================================================
# READY
# ================================================================

func _ready() -> void:
	_config = get_parent()

	_audio = AudioStreamPlayer2D.new()
	add_child(_audio)

	# Nodos opcionales — no peta si faltan
	_enter_area    = get_node_or_null("EnterArea")
	_interior      = get_node_or_null("../Interior")
	_exit_area     = get_node_or_null("../Interior/TileMapLayer/ExitArea")
	_walls         = get_node_or_null("../Interior/TileMapLayer/Wall")
	_outside_audio = get_node_or_null("../Interior/OutsideAudio")
	_inside_audio  = get_node_or_null("../Interior/InsideAudio")

	if _interior:
		_interior.visible = false
		_interior.modulate.a = 0.0
	_set_walls_enabled(false)

	if _enter_area:
		_enter_area.body_entered.connect(_on_enter_area_entered)
		_enter_area.body_exited.connect(_on_enter_area_exited)
	if _exit_area:
		_exit_area.body_entered.connect(_on_exit_area_entered)
		_exit_area.body_exited.connect(_on_exit_area_exited)

# ================================================================
# INPUT
# ================================================================

func _process(_delta: float) -> void:
	if _transitioning or not Input.is_action_just_pressed(_config.enter_action):
		return

	if not _inside and _player_near_enter:
		if not _config.on_enter():
			return
		_transitioning = true
		await _enter()
		_transitioning = false

	elif _inside and _player_near_exit:
		if not _config.on_exit():
			return
		_transitioning = true
		await _exit()
		_transitioning = false

# ================================================================
# DETECCIÓN DE ÁREAS
# ================================================================

func _on_enter_area_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_near_enter = true

func _on_enter_area_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_near_enter = false

func _on_exit_area_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_near_exit = true

func _on_exit_area_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_near_exit = false

# ================================================================
# ENTRAR
# ================================================================

func _enter() -> void:
	_inside = true
	_play_sfx(_config.open_sounds)

	var player = PlayerManager.player_instance
	if not player:
		push_error("BuildingEntrance: PlayerManager.player_instance es null")
		return
	var camera: Camera2D = player.get_node_or_null("Camera2D")

	player.disable_movement()

	# Fade a negro
	await SceneManager._fade_out(_config.fade_time * 0.5)
	# Pausar audio exterior
	_set_group_audio_paused("audio_exterior", true)

	# Congelar exterior mientras está negro
	_freeze_world(true)
	var exterior = get_parent().get_node_or_null("Exterior")
	if exterior:
		exterior.visible = false

	# Mostrar interior
	if _interior:
		_interior.visible = true
		_interior.modulate.a = 1.0
	_set_walls_enabled(true)

	# Zoom y límites de cámara
	if camera:
		camera.zoom = _config.zoom_in
		_original_limits = {
			"left": camera.limit_left, "top": camera.limit_top,
			"right": camera.limit_right, "bottom": camera.limit_bottom
		}
		var limits = _config.get_interior_camera_limits()
		if not limits.is_empty():
			camera.limit_left   = limits["left"]
			camera.limit_top    = limits["top"]
			camera.limit_right  = limits["right"]
			camera.limit_bottom = limits["bottom"]

	# Fade de vuelta
	await SceneManager._fade_in(_config.fade_time * 0.5)

	# Audio
	# Arrancar y hacer fade de audio interior
	# Primera vez: arrancar. Siguientes: reanudar
	if not _interior_audio_started:
		_interior_audio_started = true
		_start_audio_group("audio_interior")
	else:
		_set_group_audio_paused("audio_interior", false)
	var tw_audio := create_tween().set_parallel(true)
	_fade_audio_group_by_group("audio_interior", 0.0, _config.fade_time * 0.8, tw_audio)

	player.enable_movement()
# ================================================================
# SALIR
# ================================================================

func _exit() -> void:
	_inside = false
	_play_sfx(_config.close_sounds)

	var player = PlayerManager.player_instance
	if not player:
		push_error("BuildingEntrance: PlayerManager.player_instance es null")
		return
	var camera: Camera2D = player.get_node_or_null("Camera2D")

	player.disable_movement()

	# Fade a negro
	await SceneManager._fade_out(_config.fade_time * 0.5)
	# Fade out y stop audio interior
	var tw_stop := create_tween().set_parallel(true)
	_fade_audio_group_by_group("audio_interior", -40.0, _config.fade_time * 0.4, tw_stop)
	await tw_stop.finished
	_set_group_audio_paused("audio_interior", true)

	# Ocultar interior mientras está negro
	if _interior:
		_interior.visible = false
	_set_walls_enabled(false)

	# Restaurar fachada exterior
	var exterior = get_parent().get_node_or_null("Exterior")
	if exterior:
		exterior.visible = true

	# Descongelar exterior
	_freeze_world(false)

	# Restaurar zoom y límites
	if camera:
		camera.zoom = _config.zoom_out
		if not _original_limits.is_empty():
			camera.limit_left   = _original_limits["left"]
			camera.limit_top    = _original_limits["top"]
			camera.limit_right  = _original_limits["right"]
			camera.limit_bottom = _original_limits["bottom"]

	# Fade de vuelta
	await SceneManager._fade_in(_config.fade_time * 0.5)
	# Reanudar audio exterior
	_set_group_audio_paused("audio_exterior", false)

	# Audio

	player.enable_movement()
func _init_audio_group(root: Node, volume_db: float) -> void:
	if not root:
		return
	for child in root.get_children():
		if child is AudioStreamPlayer2D:
			child.volume_db = volume_db
			child.playing = true

func _fade_audio_group(root: Node, target_db: float, duration: float, tw: Tween, play_if_stopped := false) -> void:
	if not root:
		return
	for child in root.get_children():
		if child is AudioStreamPlayer2D:
			if play_if_stopped and not child.playing:
				child.playing = true
			tw.tween_property(child, "volume_db", target_db, duration)

func _play_sfx(sounds: Array[AudioStream]) -> void:
	if sounds.is_empty() or not _audio:
		return
	_audio.stream = sounds.pick_random()
	_audio.pitch_scale = randf_range(0.95, 1.05)
	_audio.volume_db = randf_range(-2.0, 0.0)
	_audio.play()

# ================================================================
# COLISIONES
# ================================================================

func _set_walls_enabled(enabled: bool) -> void:
	if not is_instance_valid(_walls):
		return
	for shape in _walls.get_children():
		if shape is CollisionShape2D:
			shape.disabled = not enabled

# ================================================================
# VISIBILIDAD DE GRUPOS
# ================================================================

func _set_group_visibility(group_name: String, value: bool) -> void:
	for node in get_tree().get_nodes_in_group(group_name):
		if node is CanvasItem:
			node.visible = value

# ================================================================
# CONGELAR / DESCONGELAR MUNDO EXTERIOR
# ================================================================

func _freeze_world(freeze: bool) -> void:
	# Busca el nodo World en la escena
	var world = get_tree().current_scene.find_child("World", true, false)
	if not world:
		return
	for child in world.get_children():
		# No tocar el edificio en el que estamos entrando
		if child == get_parent():
			continue
		child.visible = not freeze
		child.process_mode = Node.PROCESS_MODE_DISABLED if freeze else Node.PROCESS_MODE_INHERIT

# ================================================================
# AUDIO POR GRUPOS
# ================================================================

func _start_audio_group(group_name: String) -> void:
	for node in get_tree().get_nodes_in_group(group_name):
		for child in node.get_children():
			if child is AudioStreamPlayer or child is AudioStreamPlayer2D:
				child.volume_db = -40.0
				child.play()

func _stop_audio_group(group_name: String) -> void:
	for node in get_tree().get_nodes_in_group(group_name):
		for child in node.get_children():
			if child is AudioStreamPlayer or child is AudioStreamPlayer2D:
				child.stop()

func _set_group_audio_paused(group_name: String, paused: bool) -> void:
	for node in get_tree().get_nodes_in_group(group_name):
		for child in node.get_children():
			if child is AudioStreamPlayer or child is AudioStreamPlayer2D:
				if paused:
					child.volume_db = -80.0
					child.stream_paused = true
				else:
					child.stream_paused = false
					child.volume_db = 0.0

func _fade_audio_group_by_group(group_name: String, target_db: float, duration: float, tw: Tween) -> void:
	for node in get_tree().get_nodes_in_group(group_name):
		for child in node.get_children():
			if child is AudioStreamPlayer or child is AudioStreamPlayer2D:
				tw.tween_property(child, "volume_db", target_db, duration)
