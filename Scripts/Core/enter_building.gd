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
#     ├── EnterArea (Area2D)
#     └── DoorGlow (Sprite2D / Polygon2D)
# ================================================================

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
# 🔗 NODE REFERENCES — asignar desde el Inspector
# Si están vacíos, se usan las rutas por defecto como fallback.
# ================================================================
@export_group("🔗 Node References")
@export var interior_path: NodePath
@export var exit_area_path: NodePath
@export var walls_path: NodePath
@export var audio_path: NodePath

# ================================================================
# ESTADO
# ================================================================

var _inside: bool = false
var _player_near_enter: bool = false
var _player_near_exit: bool = false
var _transitioning: bool = false
var _original_limits: Dictionary = {}
var _interior_audio_started: bool = false
var _original_limit_enabled: bool = false

# ================================================================
# READY
# ================================================================

# Resuelve un NodePath exportado con fallback a una ruta por defecto.
func _resolve(path: NodePath, fallback: String) -> Node:
	if not path.is_empty():
		var n = get_node_or_null(path)
		if n:
			return n
		push_warning("BuildingEntrance: NodePath '%s' no encontrado, usando fallback '%s'" % [str(path), fallback])
	return get_node_or_null(fallback)

func _ready() -> void:
	_config = get_parent()

	_audio_sfx = AudioStreamPlayer2D.new()
	add_child(_audio_sfx)

	# Nodos internos fijos (hijos directos)
	_enter_area = get_node_or_null("EnterArea")
	_door_glow  = get_node_or_null("DoorGlow")

	# Nodos externos — usar NodePath del Inspector si está asignado,
	# si no usar la ruta por defecto como fallback.
	_interior     = _resolve(interior_path,  "../Interior")
	_exit_area    = _resolve(exit_area_path, "../Interior/TileMapLayer/ExitArea")
	_walls        = _resolve(walls_path,     "../Interior/TileMapLayer/Wall")
	_inside_audio = _resolve(audio_path,     "../Audio")

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
# DETECCIÓN DE ÁREAS
# ================================================================

func _on_enter_area_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_near_enter = true
		_set_door_glow(true)
		InteractionManager.register(self, InteractionManager.Priority.BUILDING, _on_interact)

func _on_enter_area_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_near_enter = false
		_set_door_glow(false)
		InteractionManager.unregister(self)

func _on_exit_area_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_near_exit = true
		InteractionManager.register(self, InteractionManager.Priority.BUILDING, _on_interact)

func _on_exit_area_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_near_exit = false
		InteractionManager.unregister(self)

func _on_interact() -> void:
	if _transitioning:
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

	var fade_total: float = _config.fade_time
	var fade_half: float = fade_total * 0.5
	var nombre_duracion: float = fade_total * (2.0 / 3.0)
	var nombre_margen: float = (fade_total - nombre_duracion) * 0.5

	# Nombre en paralelo al fade total — centrado
	_mostrar_nombre_con_fade(_config.building_name, nombre_margen, nombre_duracion)
	await SceneManager.fade_out(fade_half)

	# Cambios de escena
	_freeze_world(true)
	var exterior = get_parent().get_node_or_null("Exterior")
	if exterior:
		exterior.visible = false
	_set_exterior_audio_paused(true)
	if _interior:
		_interior.visible = true
		_interior.modulate.a = 1.0
	_set_walls_enabled(true)
	if camera:
		camera.zoom = _config.zoom_in

		_original_limit_enabled = camera.limit_enabled
		_original_limits = {
			"left": camera.limit_left,
			"top": camera.limit_top,
			"right": camera.limit_right,
			"bottom": camera.limit_bottom
		}

		var limits = _config.get_interior_camera_limits()
		if not limits.is_empty():
			camera.limit_enabled = true
			camera.limit_left = limits["left"]
			camera.limit_top = limits["top"]
			camera.limit_right = limits["right"]
			camera.limit_bottom = limits["bottom"]
			camera.reset_smoothing()
			camera.force_update_scroll()

	await SceneManager.fade_in(fade_half)

	# Audio interior
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

	var fade_total: float = _config.fade_time
	var fade_half: float = fade_total * 0.5
	var nombre_duracion: float = fade_total * (2.0 / 3.0)
	var nombre_margen: float = (fade_total - nombre_duracion) * 0.5

	# Nombre en paralelo al fade total — centrado
	_mostrar_nombre_con_fade(_config.street_name, nombre_margen, nombre_duracion)
	await SceneManager.fade_out(fade_half)

	_set_inside_audio_paused(true)
	if _interior:
		_interior.visible = false
	_set_walls_enabled(false)
	var exterior = get_parent().get_node_or_null("Exterior")
	if exterior:
		exterior.visible = true
	_freeze_world(false)
	_set_exterior_audio_paused(false)
	if camera:
		camera.zoom = _config.zoom_out
		if not _original_limits.is_empty():
			camera.limit_left = _original_limits["left"]
			camera.limit_top = _original_limits["top"]
			camera.limit_right = _original_limits["right"]
			camera.limit_bottom = _original_limits["bottom"]
			camera.limit_enabled = _original_limit_enabled
			camera.reset_smoothing()
			camera.force_update_scroll()

	await SceneManager.fade_in(fade_half)

	player.enable_movement()

# ================================================================
# NOMBRE EN PANTALLA
# ================================================================

var _name_label: CanvasLayer = null

func _mostrar_nombre_con_fade(nombre: String, delay: float, duracion: float) -> void:
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
	lbl.modulate.a = 0.0
	_name_label.add_child(lbl)
	get_tree().root.add_child(_name_label)

	# fade_nombre = 20% de la duración para cada fade in/out del texto
	var fade_nombre: float = duracion * 0.2
	var visible_puro: float = duracion - fade_nombre * 2.0
	var tw := _name_label.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(lbl, "modulate:a", 1.0, fade_nombre)
	tw.tween_interval(visible_puro)
	tw.tween_property(lbl, "modulate:a", 0.0, fade_nombre)
	tw.tween_callback(_limpiar_nombre)

func _limpiar_nombre() -> void:
	if _name_label:
		_name_label.queue_free()
		_name_label = null

# ================================================================
# AUDIO LOCAL
# ================================================================

func _start_inside_audio() -> void:
	if not _inside_audio:
		return
	for child in _inside_audio.get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer2D:
			child.volume_db = -40.0
			child.play()
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
# AUDIO SFX
# ================================================================

func _play_sfx(sounds: Array[AudioStream]) -> void:
	if sounds.is_empty() or not _audio_sfx:
		return
	_audio_sfx.stream = sounds.pick_random()
	_audio_sfx.pitch_scale = randf_range(0.95, 1.05)
	_audio_sfx.volume_db = randf_range(_config.sfx_volume_db_min, _config.sfx_volume_db_max)
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

# ================================================================
# GLOW DE PUERTA
# ================================================================

var _glow_tween: Tween = null

func _set_door_glow(active: bool) -> void:
	if not is_instance_valid(_door_glow):
		return
	var mat := _door_glow.material as ShaderMaterial
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
			func(v: float): mat.set_shader_parameter("glow_strength", v),
			mat.get_shader_parameter("glow_strength"),
			0.0,
			0.2
		)

func _glow_pulse(mat: ShaderMaterial) -> void:
	_glow_tween = create_tween().set_loops()
	_glow_tween.tween_method(
		func(v: float): mat.set_shader_parameter("glow_strength", v),
		0.0, 2.0, 0.7
	)
	_glow_tween.tween_method(
		func(v: float): mat.set_shader_parameter("glow_strength", v),
		2.0, 0.0, 0.7
	)

func force_inside_state(inside: bool) -> void:
	print("🏠 FORZANDO ESTADO INTERIOR: ", inside, " en el edificio: ", _config.building_name)
	_inside = inside

	# 1. Visibilidad y colisiones
	if _interior:
		_interior.visible = inside
		_interior.modulate.a = 1.0 if inside else 0.0

	_set_walls_enabled(inside)
	_freeze_world(inside)

	var exterior = get_parent().get_node_or_null("Exterior")
	if exterior:
		exterior.visible = not inside

	# 2. Audio exterior — pausar al entrar, reanudar al salir
	_set_exterior_audio_paused(inside)

	# 3. Cámara
	var player = PlayerManager.player_instance
	if is_instance_valid(player):
		var camera: Camera2D = player.get_node_or_null("Camera2D")
		if camera:
			if inside:
				# Guardar límites originales ANTES de sobreescribirlos,
				# igual que hace _enter() — necesario para que _exit() los restaure
				_original_limit_enabled = camera.limit_enabled
				_original_limits = {
					"left":   camera.limit_left,
					"top":    camera.limit_top,
					"right":  camera.limit_right,
					"bottom": camera.limit_bottom,
				}

				camera.zoom = _config.zoom_in
				var limits = _config.get_interior_camera_limits()
				if not limits.is_empty():
					camera.limit_enabled = true
					camera.limit_left   = limits["left"]
					camera.limit_top    = limits["top"]
					camera.limit_right  = limits["right"]
					camera.limit_bottom = limits["bottom"]
					camera.reset_smoothing()      # ← evita deslizamiento fantasma
					camera.force_update_scroll()
			else:
				camera.zoom = _config.zoom_out
				if not _original_limits.is_empty():
					camera.limit_left    = _original_limits["left"]
					camera.limit_top     = _original_limits["top"]
					camera.limit_right   = _original_limits["right"]
					camera.limit_bottom  = _original_limits["bottom"]
					camera.limit_enabled = _original_limit_enabled
					camera.reset_smoothing()
					camera.force_update_scroll()

	# 4. Audio interior
	if inside:
		if not _interior_audio_started:
			_interior_audio_started = true
			_start_inside_audio()
		else:
			_set_inside_audio_paused(false)
	else:
		_set_inside_audio_paused(true)

func is_transitioning() -> bool:
	return _transitioning

# ================================================================
# NPCs — entrar/salir sin afectar al player
# ================================================================
var _npcs_inside: Array = []

func npc_enter(npc: CharacterBody2D, interior_position: Vector2) -> void:
	print("npc_enter — pos: ", interior_position, " npc scale antes: ", npc.scale)

	if npc in _npcs_inside:
		return
	_npcs_inside.append(npc)
	# Reparentar al interior para heredar su visibilidad
	var original_parent := npc.get_parent()
	npc.set_meta("_original_parent_path", str(original_parent.get_path()))
	original_parent.remove_child(npc)
	if _interior:
		_interior.add_child(npc)
	npc.global_position = interior_position
	print("npc scale después de reparent: ", npc.scale)

func npc_exit(npc: CharacterBody2D, exterior_position: Vector2) -> void:
	if not npc in _npcs_inside:
		return
	_npcs_inside.erase(npc)
	var original_path: String = npc.get_meta("_original_parent_path", "")
	var original_parent: Node = null
	if original_path != "":
		original_parent = get_node_or_null(original_path)
	if not original_parent:
		original_parent = get_tree().current_scene
	npc.get_parent().remove_child(npc)
	original_parent.add_child(npc)
	npc.global_position = exterior_position

func get_npcs_inside() -> Array:
	return _npcs_inside.duplicate()
