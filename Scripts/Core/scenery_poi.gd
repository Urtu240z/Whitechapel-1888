extends Marker2D
class_name SceneryPOI

# ============================================================================
# SCENERY POI
# Punto de interés para companions / clients.
# Para POIs de exterior: coloca el Marker2D en el mapa exterior.
# Para POIs de interior: coloca el Marker2D DENTRO del nodo Interior del edificio.
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
@export var building_entrance_path: NodePath = NodePath("")

@export_group("👥 Crowd Spread")
@export var use_spread_positions: bool = true
@export var slot_spacing: float = 36.0
@export var slot_count: int = 5
@export var slot_jitter: float = 8.0

# npc instance id -> slot index
var _slot_reservations: Dictionary = {}

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

func get_exterior_door_pos() -> Vector2:
	var entrance := get_building_entrance()
	if not entrance:
		return global_position

	var building_root: Node = entrance.get_parent()
	var fallback_position: Vector2 = entrance.global_position

	var enter_area := entrance.get_node_or_null("EnterArea") as Node2D
	if enter_area:
		fallback_position = enter_area.global_position

	if is_instance_valid(building_root) and building_root.has_method("get_exterior_spawn_position"):
		return building_root.get_exterior_spawn_position(fallback_position)

	return fallback_position


func get_interior_door_pos() -> Vector2:
	var entrance := get_building_entrance()
	if not entrance:
		return global_position

	var building_root: Node = entrance.get_parent()
	var fallback_position: Vector2 = global_position

	var exit_node: Node2D = get_interior_exit_node()
	if exit_node:
		fallback_position = exit_node.global_position

	if is_instance_valid(building_root) and building_root.has_method("get_interior_spawn_position"):
		return building_root.get_interior_spawn_position(fallback_position)

	return fallback_position


func get_interior_exit_node() -> Node2D:
	var entrance := get_building_entrance()
	if not entrance:
		return null

	var building_root := entrance.get_parent()
	if not is_instance_valid(building_root):
		return null

	var paths: Array[String] = [
		"Interior/TileMapLayer/ExitArea",
		"Interior/ExitArea",
		"Interior/SpawnPoints/ExitArea"
	]

	for path: String in paths:
		var node := building_root.get_node_or_null(path) as Node2D
		if node:
			return node

	return null


func get_interior_node() -> Node2D:
	var entrance := get_building_entrance()
	if not entrance:
		return null

	var building_root := entrance.get_parent()
	return building_root.get_node_or_null("Interior") as Node2D

# ============================================================================
# CROWD SPREAD
# ============================================================================
func reserve_target_position(npc: Node) -> Vector2:
	if not is_instance_valid(npc):
		return global_position

	if not use_spread_positions or slot_count <= 1:
		return global_position

	var npc_id: int = npc.get_instance_id()

	if _slot_reservations.has(npc_id):
		return _position_for_slot(int(_slot_reservations[npc_id]))

	var used_slots: Array[int] = []
	for value in _slot_reservations.values():
		used_slots.append(int(value))

	var slot_order: Array[int] = _build_slot_order()

	for slot_index in slot_order:
		if not used_slots.has(slot_index):
			_slot_reservations[npc_id] = slot_index
			return _position_for_slot(slot_index)

	# Fallback: si están todos ocupados, usa uno aleatorio cercano
	return global_position + Vector2(randf_range(-slot_spacing, slot_spacing), 0.0)

func release_target_position(npc: Node) -> void:
	if not is_instance_valid(npc):
		return

	var npc_id: int = npc.get_instance_id()
	if _slot_reservations.has(npc_id):
		_slot_reservations.erase(npc_id)

func _build_slot_order() -> Array[int]:
	var order: Array[int] = []
	var half: int = int(floor(slot_count / 2.0))

	order.append(0)
	for i in range(1, half + 1):
		order.append(i)
		order.append(-i)

	while order.size() > slot_count:
		order.pop_back()

	return order

func _position_for_slot(slot_index: int) -> Vector2:
	var jitter: float = randf_range(-slot_jitter, slot_jitter)
	return global_position + Vector2(slot_index * slot_spacing + jitter, 0.0)
