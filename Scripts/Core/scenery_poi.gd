extends Marker2D
class_name SceneryPOI

# ============================================================================
# SCENERY POI
# Punto de interés para el sistema de deambulación de companions.
# Se añade automáticamente al grupo "scenery_poi" en _ready().
# ============================================================================

@export_group("POI")
@export var poi_name: String = "Lugar"
@export var animation_on_arrive: String = "Idle"  # animación al llegar
@export var wait_time_min: float = 5.0
@export var wait_time_max: float = 15.0

@export_group("Disponibilidad")
@export var always_available: bool = true
@export var hour_open: float = 0.0
@export var hour_close: float = 24.0

@export_group("🏠 Interior")
@export var is_interior: bool = false
# Ruta al nodo BuildingEntrance del edificio
@export var building_entrance_path: NodePath = NodePath("")
# Área donde aparece la companion al entrar (ej: ExitArea del interior)
@export var interior_entry_path: NodePath = NodePath("")
# Área donde aparece la companion al salir (ej: EnterArea del exterior)
@export var exterior_entry_path: NodePath = NodePath("")

# ============================================================================
# READY
# ============================================================================
func _ready() -> void:
	add_to_group("scenery_poi")

# ============================================================================
# API
# ============================================================================
func is_available() -> bool:
	if always_available:
		return true
	var hour: float = DayNightManager.get_hour_float()
	return hour >= hour_open and hour < hour_close

func get_wait_time() -> float:
	return randf_range(wait_time_min, wait_time_max)

func get_building_entrance() -> Node:
	if not is_interior or building_entrance_path.is_empty():
		return null
	return get_node_or_null(building_entrance_path)

func get_interior_spawn() -> Vector2:
	var node := get_node_or_null(interior_entry_path)
	if node and node is Node2D:
		return (node as Node2D).global_position
	return global_position

func get_exterior_spawn() -> Vector2:
	var node := get_node_or_null(exterior_entry_path)
	if node and node is Node2D:
		return (node as Node2D).global_position
	return global_position
