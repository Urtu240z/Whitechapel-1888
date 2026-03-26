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

# ================================================================
# ⚙️ COMPORTAMIENTO
# ================================================================
@export_group("⚙️ Behaviour")
@export var enter_action: String = "interact"
@export var fade_time: float = 0.8

# ================================================================
# 📷 CÁMARA
# ================================================================
@export_group("📷 Camera")
@export var zoom_in: Vector2 = Vector2(1.7, 1.7)
@export var zoom_out: Vector2 = Vector2(1.445, 1.445)

# ================================================================
# 🔊 AUDIO
# ================================================================
@export_group("🔊 Audio")
@export var open_sounds: Array[AudioStream] = []
@export var close_sounds: Array[AudioStream] = []
@export var sfx_volume_db_min: float = -2.0
@export var sfx_volume_db_max: float = 0.0

# ================================================================
# 🏷️ NOMBRES
# Aparecen en pantalla durante el fundido de entrada/salida
# ================================================================
@export_group("🏷️ Names")
@export var building_name: String = ""  # ej: "The Ten Bells"
@export var street_name: String = ""    # ej: "Commercial Street"

# ================================================================
# 🏠 LÓGICA ESPECÍFICA DEL EDIFICIO
# Sobrescribe estas funciones en scripts heredados si necesitas
# comportamiento especial (ej: hostal cobra dinero al entrar)
# ================================================================

func _ready() -> void:
	pass

# Llamada por BuildingEntrance justo antes de entrar
# Devuelve true para permitir la entrada, false para bloquearla
func on_enter() -> bool:
	return true

# Llamada por BuildingEntrance justo antes de salir
# Devuelve true para permitir la salida, false para bloquearla
func on_exit() -> bool:
	return true

# Devuelve los límites de cámara del interior
# Busca CameraLimits/TopLeft y CameraLimits/BottomRight en Interior
func get_interior_camera_limits() -> Dictionary:
	var top_left = get_node_or_null("Interior/CameraLimits/TopLeft")
	var bottom_right = get_node_or_null("Interior/CameraLimits/BottomRight")
	if top_left and bottom_right:
		return {
			"left":   int(top_left.global_position.x),
			"top":    int(top_left.global_position.y),
			"right":  int(bottom_right.global_position.x),
			"bottom": int(bottom_right.global_position.y),
		}
	return {}
