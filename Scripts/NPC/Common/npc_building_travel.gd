extends RefCounted
class_name NPCBuildingTravel

# ============================================================================
# NPC BUILDING TRAVEL
# Lógica común para cualquier NPC móvil que pueda entrar/salir de edificios.
# Lo usarán companion, client y más adelante policía si hace falta.
# ============================================================================
# RESPONSABILIDAD:
# - Entrar al edificio usando la API del BuildingEntrance
# - Salir del edificio usando la API del BuildingEntrance
# - Mantener el estado actual de interior/exterior
# ============================================================================
# NO HACE:
# - elegir POIs
# - seguir al player
# - decidir cuándo esperar
# - lógica social del NPC
# ============================================================================

var npc: CharacterBody2D = null

var _inside_building: bool = false
var _current_poi: SceneryPOI = null
var _current_entrance: Node = null
var _interior_exit_node: Node2D = null


# ============================================================================
# INIT
# ============================================================================
func initialize(owner_npc: CharacterBody2D) -> void:
	npc = owner_npc


# ============================================================================
# API
# ============================================================================
func is_inside_building() -> bool:
	return _inside_building

func get_current_poi() -> SceneryPOI:
	return _current_poi

func get_current_entrance() -> Node:
	return _current_entrance

func get_interior_exit_node() -> Node2D:
	return _interior_exit_node


# ============================================================================
# ENTRAR
# ============================================================================
func enter_building_for_poi(poi: SceneryPOI) -> bool:
	if not is_instance_valid(npc):
		return false

	if not is_instance_valid(poi):
		return false

	if not poi.is_interior:
		return false

	var entrance: Node = poi.get_building_entrance()
	if not is_instance_valid(entrance):
		return false

	if not entrance.has_method("npc_enter"):
		push_warning("NPCBuildingTravel: el BuildingEntrance no tiene npc_enter()")
		return false

	_current_poi = poi
	_current_entrance = entrance
	_interior_exit_node = poi.get_interior_exit_node()
	_inside_building = true

	entrance.npc_enter(npc, poi.get_interior_door_pos())
	return true


# ============================================================================
# SALIR
# ============================================================================
func exit_current_building(exterior_position: Vector2) -> bool:
	if not is_instance_valid(npc):
		return false

	if not _inside_building:
		return false

	if not is_instance_valid(_current_entrance):
		_clear_state()
		return false

	if not _current_entrance.has_method("npc_exit"):
		push_warning("NPCBuildingTravel: el BuildingEntrance no tiene npc_exit()")
		_clear_state()
		return false

	_current_entrance.npc_exit(npc, exterior_position)
	_clear_state()
	return true


func force_exit_to_poi_door() -> bool:
	if not _inside_building:
		return false

	if is_instance_valid(_current_poi):
		return exit_current_building(_current_poi.get_exterior_door_pos())

	return exit_current_building(npc.global_position)


# ============================================================================
# RESET
# ============================================================================
func _clear_state() -> void:
	_inside_building = false
	_current_poi = null
	_current_entrance = null
	_interior_exit_node = null
