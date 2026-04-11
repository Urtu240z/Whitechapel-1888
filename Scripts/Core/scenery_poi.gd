extends Marker2D
class_name SceneryPOI

# ============================================================================
# SCENERY POI
# Punto de interés para companions.
# Para POIs de exterior: coloca el Marker2D en el mapa exterior.
# Para POIs de interior: coloca el Marker2D DENTRO del nodo Interior del edificio.
#   El companion caminará hasta la puerta exterior, teleportará al interior,
#   caminará hasta este Marker2D, esperará, y volverá a salir.
# ============================================================================

@export_group("POI")
@export var poi_name: String = "Lugar"
@export var animation_on_arrive: String = "Idle"
@export var wait_time_min: float = 5.0
@export var wait_time_max: float = 15.0

@export_group("Disponibilidad")
@export var always_available: bool = true
@export var hour_open: float = 0.0
@export var hour_close: float = 24.0

@export_group("🏠 Interior")
@export var is_interior: bool = false
# NodePath al nodo BuildingEntrance del edificio
# Desde aquí se obtiene: EnterArea (exterior) y el root del edificio (para Interior/ExitArea)
@export var building_entrance_path: NodePath = NodePath("")

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

# Posición de la puerta exterior (donde la companion camina antes de entrar)
func get_exterior_door_pos() -> Vector2:
	var entrance := get_building_entrance()
	if not entrance:
		return global_position
	var enter_area := entrance.get_node_or_null("EnterArea") as Node2D
	return enter_area.global_position if enter_area else entrance.global_position

# Posición de spawn dentro del interior (justo al entrar por la puerta interior)
func get_interior_door_pos() -> Vector2:
	var entrance := get_building_entrance()
	if not entrance:
		return global_position
	# ExitArea está en: hermano del BuildingEntrance → Interior/TileMapLayer/ExitArea
	var building_root := entrance.get_parent()
	var exit_area := building_root.get_node_or_null("Interior/TileMapLayer/ExitArea") as Node2D
	return exit_area.global_position if exit_area else global_position

# Nodo ExitArea del interior (companion camina hasta aquí antes de salir)
func get_interior_exit_node() -> Node2D:
	var entrance := get_building_entrance()
	if not entrance:
		return null
	var building_root := entrance.get_parent()
	return building_root.get_node_or_null("Interior/TileMapLayer/ExitArea") as Node2D

# Nodo Interior del edificio (para reparentar la companion)
func get_interior_node() -> Node2D:
	var entrance := get_building_entrance()
	if not entrance:
		return null
	var building_root := entrance.get_parent()
	return building_root.get_node_or_null("Interior") as Node2D
