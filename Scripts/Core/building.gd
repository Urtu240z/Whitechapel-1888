extends Node2D
# ================================================================
# BUILDING — building.gd
# Script raíz de cada edificio instanciado.
# ================================================================
# ESTRUCTURA ESPERADA:
#
# Bar.tscn
# ├── building.gd  ← este script (nodo raíz)
# ├── Exterior (Sprite2D / Node2D)
# ├── BuildingEntrance (Node2D) ← enter_building.gd
# │   ├── EnterArea (Area2D)
# │   │   └── CollisionShape2D
# └── Interior (Node2D)
#     ├── TileMapLayer
#     │   ├── Wall (StaticBody2D)  ← metadata surface_type
#     │   └── ExitArea (Area2D)
#     ├── CameraLimits (Node2D)  ← opcional, para límites de cámara
#     │   ├── TopLeft (Marker2D)
#     │   └── BottomRight (Marker2D)
# ├── Audio (Node2D)  ← audio local del edificio (sin grupos globales)
#     ├── Ambient (AudioStreamPlayer2D)
#     └── Music (AudioStreamPlayer2D)
#
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
# READY — auto-registro en grupo
# ================================================================
func _ready() -> void:
	# Registro automático — no hace falta hacerlo a mano en el Inspector
	add_to_group("buildings")


# ================================================================
# 🏠 LÓGICA ESPECÍFICA DEL EDIFICIO
# ================================================================
func on_enter() -> bool:
	return true

func on_exit() -> bool:
	return true

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
