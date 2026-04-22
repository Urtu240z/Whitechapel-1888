extends Node2D
# ================================================================
# BUILDING — building.gd
# Script raíz de cada edificio instanciado.
# ================================================================

# ================================================================
# ⚙️ COMPORTAMIENTO
# ================================================================
@export_group("⚙️ Behaviour")
@export var enter_action: String = "interact"
@export var fade_time: float = 3.5

# ================================================================
# 🔊 AUDIO
# ================================================================
@export_group("🔊 Audio")
@export var open_sounds: Array[AudioStream] = []
@export var close_sounds: Array[AudioStream] = []
@export var sfx_volume_db_min: float = 0.0
@export var sfx_volume_db_max: float = 2.0

# ================================================================
# 🏷️ NOMBRES
# ================================================================
@export_group("🏷️ Names")
@export var building_name: String = ""
@export var street_name: String = ""

# ================================================================
# 🔗 SPAWNS
# Si se dejan vacíos, usa rutas por defecto.
# ================================================================
@export_group("🔗 Spawn Points")
@export var interior_spawn_path: NodePath
@export var exterior_spawn_path: NodePath

# ================================================================
# READY — auto-registro en grupo
# ================================================================
func _ready() -> void:
	add_to_group("buildings")

# ================================================================
# HELPERS
# ================================================================
func _resolve_node(path: NodePath, fallbacks: Array[String]) -> Node:
	if not path.is_empty():
		var resolved_from_path: Node = get_node_or_null(path)
		if resolved_from_path:
			return resolved_from_path

	for fallback: String in fallbacks:
		var resolved_from_fallback: Node = get_node_or_null(fallback)
		if resolved_from_fallback:
			return resolved_from_fallback

	return null

# ================================================================
# 🏠 LÓGICA ESPECÍFICA DEL EDIFICIO
# ================================================================
func on_enter() -> bool:
	return true

func on_exit() -> bool:
	return true

# ================================================================
# SPAWNS DEL PLAYER
# ================================================================
func get_interior_spawn() -> Marker2D:
	return _resolve_node(
		interior_spawn_path,
		[
			"Interior/InteriorSpawn",
			"Interior/SpawnPoints/InteriorSpawn"
		]
	) as Marker2D

func get_exterior_spawn() -> Marker2D:
	return _resolve_node(
		exterior_spawn_path,
		[
			"ExteriorSpawn",
			"SpawnPoints/ExteriorSpawn"
		]
	) as Marker2D

func get_interior_spawn_position(fallback_position: Vector2) -> Vector2:
	var marker: Marker2D = get_interior_spawn()
	if is_instance_valid(marker):
		return marker.global_position
	return fallback_position

func get_exterior_spawn_position(fallback_position: Vector2) -> Vector2:
	var marker: Marker2D = get_exterior_spawn()
	if is_instance_valid(marker):
		return marker.global_position
	return fallback_position

# ================================================================
# CÁMARA INTERIOR
# ================================================================
func get_interior_camera_limits() -> Dictionary:
	var top_left: Marker2D = get_node_or_null("Interior/CameraLimits/TopLeft") as Marker2D
	var bottom_right: Marker2D = get_node_or_null("Interior/CameraLimits/BottomRight") as Marker2D

	if top_left and bottom_right:
		return {
			"left": int(top_left.global_position.x),
			"top": int(top_left.global_position.y),
			"right": int(bottom_right.global_position.x),
			"bottom": int(bottom_right.global_position.y),
		}

	return {}

func get_interior_pcam() -> PhantomCamera2D:
	return get_node_or_null("Interior/InteriorPhantomCamera2D") as PhantomCamera2D

func setup_interior_pcam(player: Node) -> void:
	var pcam: PhantomCamera2D = get_interior_pcam()
	if not is_instance_valid(pcam):
		return

	var camera_target: Node2D = player.get_node_or_null("CameraTarget") as Node2D
	if not is_instance_valid(camera_target):
		return

	pcam.set_follow_target(camera_target)

func apply_interior_pcam_limits() -> void:
	var pcam: PhantomCamera2D = get_interior_pcam()
	if not is_instance_valid(pcam):
		return

	var limits: Dictionary = get_interior_camera_limits()
	if limits.is_empty():
		return

	pcam.set_limit_left(limits["left"])
	pcam.set_limit_top(limits["top"])
	pcam.set_limit_right(limits["right"])
	pcam.set_limit_bottom(limits["bottom"])
