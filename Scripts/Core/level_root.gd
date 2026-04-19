extends Node2D
class_name LevelRoot

# ================================================================
# LEVEL ROOT
# Controla qué partes del exterior se congelan/ocultan cuando
# el player entra en un edificio.
#
# Estructura exterior:
# - OutsideAudiovisuals
# - OutsideActors
# - OutsideGameplay
# - OutsideBuildings
#
# Iluminación exterior:
# - SunLight      -> DirectionalLight2D (sombras + sol)
# - MoonLight     -> DirectionalLight2D (sombras + luna)
# - AmbientLight  -> DirectionalLight2D (tinte general de escena)
# ================================================================

@export_group("🔗 Level Structure")
@export var outside_freeze_paths: Array[NodePath] = []
@export var buildings_root_path: NodePath
@export var player_path: NodePath
@export var exterior_pcam_path: NodePath

@export_group("💡 Iluminación Ambiental")
@export var sun_path: NodePath
@export var moon_path: NodePath
@export var ambient_light_path: NodePath

@export_group("🌤 Lighting Profile")
@export var lighting_profile: LightingProfile2D

@export_group("🌙 Refuerzo visual nocturno")
@export var lights_background_path: NodePath
@export var lights_background_day_modulate: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var lights_background_night_modulate: Color = Color(1.0, 1.0, 1.0, 1.0)

var _active_building: Node2D = null
var _lights_background: CanvasItem = null


func _ready() -> void:
	call_deferred("_setup_exterior_camera")
	_setup_ambient_lighting()
	call_deferred("_apply_pending_portal_spawn")
	_setup_visual_night_boost()
	_update_visual_night_boost()


func _process(_delta: float) -> void:
	_update_visual_night_boost()


# ================================================================
# API PÚBLICA
# ================================================================

func set_player_inside_building(building: Node2D, inside: bool) -> void:
	if inside:
		_active_building = building
	else:
		_active_building = null

	_set_outside_frozen(inside)
	_set_buildings_visibility()


func get_active_building() -> Node2D:
	return _active_building


func is_player_inside_building() -> bool:
	return _active_building != null


# ================================================================
# ILUMINACIÓN
# ================================================================

func _setup_ambient_lighting() -> void:
	var sun: DirectionalLight2D = get_node_or_null(sun_path) as DirectionalLight2D
	var moon: DirectionalLight2D = get_node_or_null(moon_path) as DirectionalLight2D
	var ambient: DirectionalLight2D = get_node_or_null(ambient_light_path) as DirectionalLight2D

	if not is_instance_valid(sun):
		push_warning("LevelRoot: sun_path no válido o no es DirectionalLight2D.")
		return

	if not is_instance_valid(moon):
		push_warning("LevelRoot: moon_path no válido o no es DirectionalLight2D.")
		return

	if not is_instance_valid(ambient):
		push_warning("LevelRoot: ambient_light_path no válido o no es DirectionalLight2D.")
		return

	DayNightManager.registrar_luces(sun, moon, ambient, lighting_profile)


func _setup_visual_night_boost() -> void:
	_lights_background = get_node_or_null(lights_background_path) as CanvasItem


func _update_visual_night_boost() -> void:
	if not is_instance_valid(_lights_background):
		return

	var t: float = DayNightManager.get_ambient_night_factor()
	_lights_background.modulate = lights_background_day_modulate.lerp(
		lights_background_night_modulate,
		t
	)


# ================================================================
# EXTERIOR
# ================================================================

func _set_outside_frozen(freeze: bool) -> void:
	for path: NodePath in outside_freeze_paths:
		var node: Node = get_node_or_null(path)
		if not is_instance_valid(node):
			push_warning("LevelRoot: no se encontró nodo de freeze: %s" % str(path))
			continue

		_set_subtree_visible(node, not freeze)
		_set_subtree_process_mode(node, freeze)
		_set_subtree_audio_paused(node, freeze)


func _set_subtree_visible(node: Node, visible_value: bool) -> void:
	var canvas_item: CanvasItem = node as CanvasItem
	if canvas_item:
		canvas_item.visible = visible_value


func _set_subtree_process_mode(node: Node, freeze: bool) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED if freeze else Node.PROCESS_MODE_INHERIT


func _set_subtree_audio_paused(node: Node, paused: bool) -> void:
	if node is AudioStreamPlayer:
		var asp: AudioStreamPlayer = node as AudioStreamPlayer
		_pause_or_resume_audio_player(asp, paused)

	elif node is AudioStreamPlayer2D:
		var asp2d: AudioStreamPlayer2D = node as AudioStreamPlayer2D
		_pause_or_resume_audio_player_2d(asp2d, paused)

	for child: Node in node.get_children():
		_set_subtree_audio_paused(child, paused)


func _pause_or_resume_audio_player(player: AudioStreamPlayer, paused: bool) -> void:
	if paused:
		if not player.has_meta("_original_volume_db"):
			player.set_meta("_original_volume_db", player.volume_db)
		player.volume_db = -80.0
		player.stream_paused = true
	else:
		player.stream_paused = false
		if player.has_meta("_original_volume_db"):
			player.volume_db = float(player.get_meta("_original_volume_db"))
		else:
			player.volume_db = 0.0


func _pause_or_resume_audio_player_2d(player: AudioStreamPlayer2D, paused: bool) -> void:
	if paused:
		if not player.has_meta("_original_volume_db"):
			player.set_meta("_original_volume_db", player.volume_db)
		player.volume_db = -80.0
		player.stream_paused = true
	else:
		player.stream_paused = false
		if player.has_meta("_original_volume_db"):
			player.volume_db = float(player.get_meta("_original_volume_db"))
		else:
			player.volume_db = 0.0


# ================================================================
# EDIFICIOS
# ================================================================

func _set_buildings_visibility() -> void:
	var buildings_root: Node = get_node_or_null(buildings_root_path)
	if not is_instance_valid(buildings_root):
		push_warning("LevelRoot: no se encontró buildings_root_path")
		return

	for child: Node in buildings_root.get_children():
		var should_show: bool = (_active_building == null or child == _active_building)

		var canvas_item: CanvasItem = child as CanvasItem
		if canvas_item:
			canvas_item.visible = should_show

		child.process_mode = Node.PROCESS_MODE_INHERIT if should_show else Node.PROCESS_MODE_DISABLED


# ================================================================
# CÁMARA EXTERIOR
# ================================================================

func _setup_exterior_camera() -> void:
	var player: Node = get_node_or_null(player_path)
	var exterior_pcam: PhantomCamera2D = get_node_or_null(exterior_pcam_path) as PhantomCamera2D

	if not is_instance_valid(player):
		push_warning("LevelRoot: player_path no válido.")
		return

	if not is_instance_valid(exterior_pcam):
		push_warning("LevelRoot: exterior_pcam_path no válido.")
		return

	var camera_target: Node2D = player.get_node_or_null("CameraTarget") as Node2D
	if not is_instance_valid(camera_target):
		push_warning("LevelRoot: no se encontró CameraTarget dentro del player.")
		return

	exterior_pcam.set_follow_target(camera_target)


# ================================================================
# PORTAL SPAWN
# ================================================================

func _apply_pending_portal_spawn() -> void:
	if not PortalManager.has_pending_spawn():
		return

	var target_portal_id: String = PortalManager.get_pending_target_portal_id()
	if target_portal_id == "":
		PortalManager.clear_pending_spawn()
		return

	var player: Node2D = get_node_or_null(player_path) as Node2D
	if not is_instance_valid(player):
		push_warning("LevelRoot: no se encontró player para aplicar spawn de portal.")
		return

	var portals: Array = get_tree().get_nodes_in_group("scene_portal")

	for portal_variant in portals:
		var portal: Node2D = portal_variant as Node2D
		if not is_instance_valid(portal):
			continue

		if not portal.has_method("get_portal_id"):
			continue

		var portal_current_id: String = portal.get_portal_id()
		if portal_current_id != target_portal_id:
			continue

		if portal.has_method("get_spawn_global_position"):
			player.global_position = portal.get_spawn_global_position()
		else:
			player.global_position = portal.global_position

		if player is CharacterBody2D:
			(player as CharacterBody2D).velocity = Vector2.ZERO

		PortalManager.clear_pending_spawn()
		return

	push_warning("LevelRoot: no se encontró portal destino con id '%s'." % target_portal_id)
