extends Node2D
# ================================================================
# BUILDING ENTRANCE — enter_building.gd
# Nodo: BuildingEntrance (hijo del nodo raíz del edificio)
# Lee su configuración del padre (building.gd)
# ================================================================
# ESTRUCTURA ESPERADA:
# Edificio (Node2D) ← building.gd
# ├── Exterior
# ├── Interior (Node2D)
# │   ├── TileMapLayer
# │   │   ├── Wall (StaticBody2D)
# │   │   └── ExitArea (Area2D)
# │   ├── CameraLimits (Node2D, opcional)
# │   │   ├── TopLeft (Marker2D)
# │   │   └── BottomRight (Marker2D)
# ├── Audio (Node2D) ← audio local del edificio
# │   ├── Ambient (AudioStreamPlayer2D)
# │   └── Music (AudioStreamPlayer2D)
# └── BuildingEntrance (Node2D) ← este script
#     └── EnterArea (Area2D)
# ================================================================

# ================================================================
# NODOS INTERNOS
# ================================================================

var _enter_area: Area2D = null
var _exit_area: Area2D = null
var _interior: Node2D = null
var _walls: StaticBody2D = null
var _inside_audio: Node = null   # Audio del edificio (local)
var _audio_sfx: AudioStreamPlayer2D = null

# Config del padre (building.gd)
var _config: Node = null

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

	_audio_sfx = AudioStreamPlayer2D.new()
	add_child(_audio_sfx)

	# Nodos por ruta local — no por grupos globales
	_enter_area    = get_node_or_null("EnterArea")
	_interior      = get_node_or_null("../Interior")
	_exit_area     = get_node_or_null("../Interior/TileMapLayer/ExitArea")
	_walls         = get_node_or_null("../Interior/TileMapLayer/Wall")
	_inside_audio  = get_node_or_null("../Audio")  # Audio local del edificio

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

	# Mostrar nombre del edificio durante el fade
	_mostrar_nombre(_config.building_name)
	await SceneManager._fade_out(_config.fade_time * 0.5)
	_limpiar_nombre()

	# Congelar exterior
	_freeze_world(true)
	var exterior = get_parent().get_node_or_null("Exterior")
	if exterior:
		exterior.visible = false

	# Pausar audio exterior
	_set_exterior_audio_paused(true)

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

	await SceneManager._fade_in(_config.fade_time * 0.5)

	# Audio interior — primera vez play, resto unpause
	if not _interior_audio_started:
		_interior_audio_started = true
		_start_inside_audio()
	else:
		_set_inside_audio_paused(false)

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

	# Fade out + pause audio interior
	_mostrar_nombre(_config.street_name)
	await SceneManager._fade_out(_config.fade_time * 0.5)
	_limpiar_nombre()

	_set_inside_audio_paused(true)

	# Ocultar interior
	if _interior:
		_interior.visible = false
	_set_walls_enabled(false)

	# Restaurar exterior
	var exterior = get_parent().get_node_or_null("Exterior")
	if exterior:
		exterior.visible = true
	_freeze_world(false)

	# Reanudar audio exterior
	_set_exterior_audio_paused(false)

	# Restaurar zoom y límites
	if camera:
		camera.zoom = _config.zoom_out
		if not _original_limits.is_empty():
			camera.limit_left   = _original_limits["left"]
			camera.limit_top    = _original_limits["top"]
			camera.limit_right  = _original_limits["right"]
			camera.limit_bottom = _original_limits["bottom"]

	await SceneManager._fade_in(_config.fade_time * 0.5)

	player.enable_movement()

# ================================================================
# NOMBRE EN PANTALLA
# ================================================================

var _name_label: CanvasLayer = null

func _mostrar_nombre(nombre: String) -> void:
	if nombre.is_empty():
		return
	_name_label = CanvasLayer.new()
	_name_label.layer = 20
	var lbl := Label.new()
	lbl.text = nombre
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	var font := load("res://Assets/Fonts/IMFellEnglish.ttf") as FontFile
	if font:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", 36)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
	_name_label.add_child(lbl)
	get_tree().root.add_child(_name_label)

func _limpiar_nombre() -> void:
	if _name_label:
		_name_label.queue_free()
		_name_label = null

# ================================================================
# AUDIO LOCAL (referencia directa, sin grupos globales)
# ================================================================

func _start_inside_audio() -> void:
	if not _inside_audio:
		return
	for child in _inside_audio.get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer2D:
			child.volume_db = -40.0
			child.play()
	# Fade a volumen normal
	var tw := create_tween().set_parallel(true)
	for child in _inside_audio.get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer2D:
			tw.tween_property(child, "volume_db", 0.0, _config.fade_time * 0.8)

func _set_inside_audio_paused(paused: bool) -> void:
	if not _inside_audio:
		return
	for child in _inside_audio.get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer2D:
			if paused:
				child.volume_db = -80.0
				child.stream_paused = true
			else:
				child.stream_paused = false
				child.volume_db = 0.0

func _set_exterior_audio_paused(paused: bool) -> void:
	for node in get_tree().get_nodes_in_group("audio_exterior"):
		for child in node.get_children():
			if child is AudioStreamPlayer or child is AudioStreamPlayer2D:
				if paused:
					child.volume_db = -80.0
					child.stream_paused = true
				else:
					child.stream_paused = false
					child.volume_db = 0.0

# ================================================================
# AUDIO SFX (abrir/cerrar puerta)
# ================================================================

func _play_sfx(sounds: Array[AudioStream]) -> void:
	if sounds.is_empty() or not _audio_sfx:
		return
	_audio_sfx.stream = sounds.pick_random()
	_audio_sfx.pitch_scale = randf_range(0.95, 1.05)
	_audio_sfx.volume_db = randf_range(-2.0, 0.0)
	_audio_sfx.play()

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
# CONGELAR MUNDO EXTERIOR
# ================================================================

func _freeze_world(freeze: bool) -> void:
	var world = get_tree().current_scene.find_child("World", true, false)
	if not world:
		return
	for child in world.get_children():
		if child == get_parent():
			continue
		child.visible = not freeze
		child.process_mode = Node.PROCESS_MODE_DISABLED if freeze else Node.PROCESS_MODE_INHERIT
