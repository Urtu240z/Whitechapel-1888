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
var _npcs_inside: Array[CharacterBody2D] = []

# ================================================================
# READY
# ================================================================
func _resolve(path: NodePath, fallback: String) -> Node:
	if not path.is_empty():
		var resolved_node: Node = get_node_or_null(path)
		if resolved_node:
			return resolved_node
		push_warning("BuildingEntrance: NodePath '%s' no encontrado, usando fallback '%s'" % [str(path), fallback])

	return get_node_or_null(fallback)

func _ready() -> void:
	_config = get_parent()

	_audio_sfx = AudioStreamPlayer2D.new()
	add_child(_audio_sfx)

	# Nodos internos fijos
	_enter_area = get_node_or_null("EnterArea")
	_door_glow = get_node_or_null("DoorGlow")

	# Nodos externos con fallback
	_interior = _resolve(interior_path, "../Interior") as Node2D
	_exit_area = _resolve(exit_area_path, "../Interior/TileMapLayer/ExitArea") as Area2D
	_walls = _resolve(walls_path, "../Interior/TileMapLayer/Wall") as StaticBody2D
	_inside_audio = _resolve(audio_path, "../Audio")

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

	var player: Node = PlayerManager.player_instance
	if not player:
		push_error("BuildingEntrance: PlayerManager.player_instance es null")
		return

	player.disable_movement()

	var fade_total: float = _config.fade_time
	var fade_half: float = fade_total * 0.5
	var nombre_duracion: float = fade_total * (2.0 / 3.0)
	var nombre_margen: float = (fade_total - nombre_duracion) * 0.5

	_mostrar_nombre_con_fade(_config.building_name, nombre_margen, nombre_duracion)
	await SceneManager.fade_out(fade_half)

	_config.setup_interior_pcam(player)
	_config.apply_interior_pcam_limits()

	var interior_pcam: PhantomCamera2D = _config.get_interior_pcam()
	if is_instance_valid(interior_pcam):
		interior_pcam.priority = 20

	_set_level_inside_state(true)

	var exterior: Node = get_parent().get_node_or_null("Exterior")
	if exterior and exterior is CanvasItem:
		(exterior as CanvasItem).visible = false

	if _interior:
		_interior.visible = true
		_interior.modulate.a = 1.0

	_set_walls_enabled(true)

	await SceneManager.fade_in(fade_half)

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

	var player: Node = PlayerManager.player_instance
	if not player:
		push_error("BuildingEntrance: PlayerManager.player_instance es null")
		return

	player.disable_movement()

	var fade_total: float = _config.fade_time
	var fade_half: float = fade_total * 0.5
	var nombre_duracion: float = fade_total * (2.0 / 3.0)
	var nombre_margen: float = (fade_total - nombre_duracion) * 0.5

	_mostrar_nombre_con_fade(_config.street_name, nombre_margen, nombre_duracion)
	await SceneManager.fade_out(fade_half)

	var interior_pcam: PhantomCamera2D = _config.get_interior_pcam()
	if is_instance_valid(interior_pcam):
		interior_pcam.priority = 0

	_set_inside_audio_paused(true)

	if _interior:
		_interior.visible = false
		_interior.modulate.a = 0.0

	_set_walls_enabled(false)

	var exterior: Node = get_parent().get_node_or_null("Exterior")
	if exterior and exterior is CanvasItem:
		(exterior as CanvasItem).visible = true

	_set_level_inside_state(false)

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

	var fade_nombre: float = duracion * 0.2
	var visible_puro: float = duracion - fade_nombre * 2.0

	var tween: Tween = _name_label.create_tween()
	tween.tween_interval(delay)
	tween.tween_property(lbl, "modulate:a", 1.0, fade_nombre)
	tween.tween_interval(visible_puro)
	tween.tween_property(lbl, "modulate:a", 0.0, fade_nombre)
	tween.tween_callback(_limpiar_nombre)

func _limpiar_nombre() -> void:
	if _name_label:
		_name_label.queue_free()
		_name_label = null

# ================================================================
# AUDIO INTERIOR DEL EDIFICIO
# ================================================================
func _start_inside_audio() -> void:
	if not _inside_audio:
		return

	var tween: Tween = create_tween().set_parallel(true)

	for child: Node in _inside_audio.get_children():
		if child is AudioStreamPlayer:
			var asp := child as AudioStreamPlayer
			asp.volume_db = -40.0
			asp.play()
			tween.tween_property(asp, "volume_db", 0.0, _config.fade_time * 0.8)
		elif child is AudioStreamPlayer2D:
			var asp2d := child as AudioStreamPlayer2D
			asp2d.volume_db = -40.0
			asp2d.play()
			tween.tween_property(asp2d, "volume_db", 0.0, _config.fade_time * 0.8)

func _set_inside_audio_paused(paused: bool) -> void:
	if not _inside_audio:
		return

	for child: Node in _inside_audio.get_children():
		if child is AudioStreamPlayer:
			var asp := child as AudioStreamPlayer
			if paused:
				if not asp.has_meta("_original_volume_db"):
					asp.set_meta("_original_volume_db", asp.volume_db)
				asp.volume_db = -80.0
				asp.stream_paused = true
			else:
				asp.stream_paused = false
				if asp.has_meta("_original_volume_db"):
					asp.volume_db = float(asp.get_meta("_original_volume_db"))
				else:
					asp.volume_db = 0.0

		elif child is AudioStreamPlayer2D:
			var asp2d := child as AudioStreamPlayer2D
			if paused:
				if not asp2d.has_meta("_original_volume_db"):
					asp2d.set_meta("_original_volume_db", asp2d.volume_db)
				asp2d.volume_db = -80.0
				asp2d.stream_paused = true
			else:
				asp2d.stream_paused = false
				if asp2d.has_meta("_original_volume_db"):
					asp2d.volume_db = float(asp2d.get_meta("_original_volume_db"))
				else:
					asp2d.volume_db = 0.0

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
# Fallback temporal si la escena no usa LevelRoot todavía.
# ================================================================
func _set_level_inside_state(inside: bool) -> void:
	var current_scene: Node = get_tree().current_scene
	if is_instance_valid(current_scene) and current_scene.has_method("set_player_inside_building"):
		current_scene.set_player_inside_building(get_parent(), inside)
	else:
		_freeze_world(inside)

func _freeze_world(freeze: bool) -> void:
	var world: Node = get_tree().current_scene.find_child("World", true, false)
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
			func(v: float): mat.set_shader_parameter("glow_strength", v),
			float(mat.get_shader_parameter("glow_strength")),
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

# ================================================================
# FORZAR ESTADO INTERIOR
# ================================================================
func force_inside_state(inside: bool) -> void:
	_inside = inside

	if _interior:
		_interior.visible = inside
		_interior.modulate.a = 1.0 if inside else 0.0

	_set_walls_enabled(inside)
	_set_level_inside_state(inside)

	var exterior: Node = get_parent().get_node_or_null("Exterior")
	if exterior and exterior is CanvasItem:
		(exterior as CanvasItem).visible = not inside

	var player: Node = PlayerManager.player_instance
	if is_instance_valid(player):
		var interior_pcam: PhantomCamera2D = _config.get_interior_pcam()

		if inside:
			_config.setup_interior_pcam(player)
			_config.apply_interior_pcam_limits()
			if is_instance_valid(interior_pcam):
				interior_pcam.priority = 20
		else:
			if is_instance_valid(interior_pcam):
				interior_pcam.priority = 0

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

func _get_npc_fade_target(npc: CharacterBody2D) -> CanvasItem:
	if not is_instance_valid(npc):
		return null

	var character_container := npc.get_node_or_null("CharacterContainer") as CanvasItem
	if character_container:
		return character_container

	return npc as CanvasItem

func _set_canvas_item_modulate(item: CanvasItem, color: Color) -> void:
	if item:
		item.modulate = color

func _tween_npc_reappear_visual(tween: Tween, fade_target: CanvasItem) -> void:
	if not fade_target:
		return

	_apply_npc_reappear_progress(fade_target, 0.0)

	tween.tween_method(
		func(v: float) -> void:
			_apply_npc_reappear_progress(fade_target, v),
		0.0,
		1.0,
		npc_fade_time
	)

func _tween_npc_disappear_visual(tween: Tween, fade_target: CanvasItem) -> void:
	if not fade_target:
		return

	_apply_npc_disappear_progress(fade_target, 0.0)

	tween.tween_method(
		func(v: float) -> void:
			_apply_npc_disappear_progress(fade_target, v),
		0.0,
		1.0,
		npc_fade_time
	)

func _apply_npc_reappear_progress(fade_target: CanvasItem, t: float) -> void:
	if not fade_target:
		return

	t = clamp(t, 0.0, 1.0)

	var reveal_start: float = clamp(npc_color_reveal_start, 0.0, 0.99)
	var color_t: float = 0.0

	if t >= reveal_start:
		color_t = (t - reveal_start) / (1.0 - reveal_start)

	# Alpha sube de 0 a 1 desde el inicio.
	# El color se queda negro hasta reveal_start, luego pasa a blanco.
	fade_target.modulate = Color(color_t, color_t, color_t, t)


func _apply_npc_disappear_progress(fade_target: CanvasItem, t: float) -> void:
	if not fade_target:
		return

	t = clamp(t, 0.0, 1.0)

	# t = 0  -> color normal, alpha 1
	# t = 1  -> negro, alpha 0
	var dark_t: float = min(t / 0.2, 1.0)
	var alpha_t: float = 1.0 - t

	var rgb: float = 1.0 - dark_t
	fade_target.modulate = Color(rgb, rgb, rgb, alpha_t)

func npc_enter(npc: CharacterBody2D, interior_position: Vector2) -> void:
	if npc in _npcs_inside:
		return

	_npcs_inside.append(npc)

	var original_parent: Node = npc.get_parent()
	npc.set_meta("_original_parent_path", str(original_parent.get_path()))

	_set_npc_transit_active(npc, true)

	var fade_target: CanvasItem = _get_npc_fade_target(npc)
	var tween: Tween = create_tween()

	_tween_npc_disappear_visual(tween, fade_target)

	tween.tween_callback(func():
		var old_global_transform: Transform2D = npc.global_transform

		if is_instance_valid(original_parent):
			original_parent.remove_child(npc)

		if _interior:
			_interior.add_child(npc)

		npc.global_transform = old_global_transform
		npc.global_position = interior_position
		npc.velocity = Vector2.ZERO

		_play_npc_door_sfx(_config.open_sounds)
	)

	_tween_npc_reappear_visual(tween, fade_target)

	tween.tween_callback(func():
		npc.velocity = Vector2.ZERO
		_set_npc_transit_active(npc, false)
	)

func npc_exit(npc: CharacterBody2D, exterior_position: Vector2) -> void:
	if not npc in _npcs_inside:
		return

	_npcs_inside.erase(npc)

	var original_path: String = str(npc.get_meta("_original_parent_path", ""))
	var original_parent: Node = null

	if original_path != "":
		original_parent = get_node_or_null(original_path)

	if not original_parent:
		original_parent = get_tree().current_scene

	_set_npc_transit_active(npc, true)

	var fade_target: CanvasItem = _get_npc_fade_target(npc)
	var tween: Tween = create_tween()

	_tween_npc_disappear_visual(tween, fade_target)

	tween.tween_callback(func():
		var old_global_transform: Transform2D = npc.global_transform

		var current_parent: Node = npc.get_parent()
		if is_instance_valid(current_parent):
			current_parent.remove_child(npc)

		original_parent.add_child(npc)

		npc.global_transform = old_global_transform
		npc.global_position = exterior_position
		npc.velocity = Vector2.ZERO

		_play_npc_door_sfx(_config.close_sounds)
	)

	_tween_npc_reappear_visual(tween, fade_target)

	tween.tween_callback(func():
		npc.velocity = Vector2.ZERO
		_set_npc_transit_active(npc, false)
	)
