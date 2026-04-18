extends Node2D
class_name LevelRoot

# ================================================================
# LEVEL ROOT
# Controla qué partes del exterior se congelan/ocultan cuando
# el player entra en un edificio.
#
# Con la nueva estructura:
# - OutsideAudiovisuals   -> exterior visual + audio exterior
# - OutsideActors         -> clients, companions, etc
# - OutsideGameplay       -> portals, hide zones, POIs...
# - OutsideBuildings      -> edificios persistentes
# ================================================================

@export_group("🔗 Level Structure")
@export var outside_freeze_paths: Array[NodePath] = []
@export var buildings_root_path: NodePath
@export var player_path: NodePath
@export var exterior_pcam_path: NodePath

var _active_building: Node2D = null


func _ready() -> void:
	call_deferred("_setup_exterior_camera")


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
