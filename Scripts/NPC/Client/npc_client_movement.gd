extends Node
class_name NPCClientMovement

const NPCBuildingTravelScript = preload("res://Scripts/NPC/Common/npc_building_travel.gd")

# ============================================================================
# NPC CLIENT MOVEMENT
# Modo IDLE: estático.
# Modo WANDER: deambula entre SceneryPOIs con soporte de interiores.
# Modo FOLLOW: sigue al player manteniéndose entre dist_min y dist_max px.
# ============================================================================

enum Mode { IDLE, WANDER, FOLLOW }
enum WanderState {
	WALKING_EXTERIOR,
	WAITING,
	INSIDE_TO_POI,
	INSIDE_WAITING,
	INSIDE_TO_EXIT,
}

# ============================================================================
# SEÑALES
# ============================================================================
signal player_too_far_warning
signal player_too_far_cancel

# ============================================================================
# CONFIG
# ============================================================================
var follow_speed: float = 250.0
var follow_accel: float = 400.0
var dist_min: float = 200.0
var dist_max: float = 300.0
var dist_warning: float = 800.0
var dist_cancel: float = 1000.0
var gravity: float = 980.0

# ============================================================================
# ESTADO
# ============================================================================
var npc: CharacterBody2D = null
var is_frozen: bool = false
var _mode: Mode = Mode.IDLE
var _target: Node2D = null
var _warning_emitted: bool = false
var _warning_cooldown: float = 0.0
const WARNING_COOLDOWN_SECS: float = 10.0

var _wander_state: WanderState = WanderState.WALKING_EXTERIOR
var _current_poi: SceneryPOI = null
var _last_poi: SceneryPOI = null
var _wait_timer: float = 0.0
var _walk_target_x: float = 0.0
var _current_poi_target: Vector2 = Vector2.ZERO

var _building_travel = NPCBuildingTravelScript.new()

# ============================================================================
# INIT
# ============================================================================
func initialize(owner_npc: CharacterBody2D,
		p_speed: float = 250.0,
		p_accel: float = 400.0,
		p_dist_min: float = 200.0,
		p_dist_max: float = 300.0,
		p_gravity: float = 980.0,
		p_dist_warning: float = 800.0,
		p_dist_cancel: float = 1000.0) -> void:
	npc = owner_npc
	follow_speed  = p_speed
	follow_accel  = p_accel
	dist_min      = p_dist_min
	dist_max      = p_dist_max
	gravity       = p_gravity
	dist_warning  = p_dist_warning
	dist_cancel   = p_dist_cancel

	_building_travel.initialize(owner_npc)

# ============================================================================
# PROCESO
# ============================================================================
func _process(delta: float) -> void:
	if _warning_cooldown > 0.0:
		_warning_cooldown -= delta
		if _warning_cooldown <= 0.0:
			_warning_cooldown = 0.0
			_warning_emitted = false

# ============================================================================
# API
# ============================================================================
func freeze() -> void:
	is_frozen = true
	if npc:
		npc.velocity.x = 0.0

func unfreeze() -> void:
	is_frozen = false

func start_follow(target: Node2D) -> void:
	_release_current_poi_slot()

	if _building_travel.is_inside_building():
		_force_exit_building()

	_target = target
	_mode = Mode.FOLLOW

func stop_follow() -> void:
	_mode = Mode.IDLE
	_target = null
	if npc:
		npc.velocity.x = 0.0

func is_following() -> bool:
	return _mode == Mode.FOLLOW

func start_wander() -> void:
	if _mode == Mode.FOLLOW:
		return
	_mode = Mode.WANDER
	_pick_next_poi()

func stop_wander() -> void:
	if _mode == Mode.WANDER:
		_release_current_poi_slot()
		_mode = Mode.IDLE
		if npc:
			npc.velocity.x = 0.0

func is_moving() -> bool:
	return abs(npc.velocity.x) > 10.0 if npc else false

func get_facing_right() -> bool:
	if npc and abs(npc.velocity.x) > 5.0:
		return npc.velocity.x > 0.0
	return true

# ============================================================================
# PROCESO DE MOVIMIENTO
# ============================================================================
func process_movement(delta: float) -> void:
	if is_frozen or not npc:
		if npc:
			npc.velocity.x = 0.0
		return

	match _mode:
		Mode.IDLE:
			npc.velocity.x = move_toward(npc.velocity.x, 0.0, follow_accel * delta)
		Mode.WANDER:
			_process_wander(delta)
		Mode.FOLLOW:
			_process_follow_horizontal(delta)

# ============================================================================
# WANDER POR POIs
# ============================================================================
func _process_wander(delta: float) -> void:
	match _wander_state:
		WanderState.WALKING_EXTERIOR:
			_walk_toward(_walk_target_x, delta)
			if _arrived_at(_walk_target_x):
				_on_arrived_exterior()

		WanderState.WAITING:
			npc.velocity.x = move_toward(npc.velocity.x, 0.0, follow_accel * delta)
			_wait_timer -= delta
			if _wait_timer <= 0.0:
				_pick_next_poi()

		WanderState.INSIDE_TO_POI:
			_walk_toward(_walk_target_x, delta)
			if _arrived_at(_walk_target_x):
				_on_arrived_at_interior_poi()

		WanderState.INSIDE_WAITING:
			npc.velocity.x = move_toward(npc.velocity.x, 0.0, follow_accel * delta)
			_wait_timer -= delta
			if _wait_timer <= 0.0:
				_start_leaving_interior()

		WanderState.INSIDE_TO_EXIT:
			_walk_toward(_walk_target_x, delta)
			if _arrived_at(_walk_target_x):
				_do_exit_building()

func _on_arrived_exterior() -> void:
	if not is_instance_valid(_current_poi):
		_pick_next_poi()
		return

	if _current_poi.is_interior:
		_do_enter_building()
	else:
		_wander_state = WanderState.WAITING
		_wait_timer = _current_poi.get_wait_time()

func _do_enter_building() -> void:
	if not is_instance_valid(_current_poi):
		_pick_next_poi()
		return

	var entered: bool = _building_travel.enter_building_for_poi(_current_poi)

	if not entered:
		_wander_state = WanderState.WAITING
		_wait_timer = _current_poi.get_wait_time()
		return

	_walk_target_x = _current_poi_target.x
	_wander_state = WanderState.INSIDE_TO_POI

func _on_arrived_at_interior_poi() -> void:
	_wander_state = WanderState.INSIDE_WAITING
	_wait_timer = _current_poi.get_wait_time() if is_instance_valid(_current_poi) else 5.0

func _start_leaving_interior() -> void:
	var interior_exit_node: Node2D = _building_travel.get_interior_exit_node()

	if is_instance_valid(interior_exit_node):
		_walk_target_x = interior_exit_node.global_position.x
		_wander_state = WanderState.INSIDE_TO_EXIT
	else:
		_do_exit_building()

func _do_exit_building() -> void:
	var exterior_door_pos: Vector2 = npc.global_position

	if is_instance_valid(_current_poi):
		exterior_door_pos = _current_poi.get_exterior_door_pos()

	_building_travel.exit_current_building(exterior_door_pos)
	_release_current_poi_slot()
	_pick_next_poi()

func _force_exit_building() -> void:
	_building_travel.force_exit_to_poi_door()
	_release_current_poi_slot()

func _pick_next_poi() -> void:
	var previous_poi: SceneryPOI = _current_poi
	var all_pois := npc.get_tree().get_nodes_in_group("scenery_poi")
	var available: Array = []

	for poi in all_pois:
		if poi is SceneryPOI and poi.is_available() and poi != previous_poi and poi != _last_poi:
			available.append(poi)

	# Si no hay suficientes, al menos evita repetir el actual
	if available.is_empty():
		for poi in all_pois:
			if poi is SceneryPOI and poi.is_available() and poi != previous_poi:
				available.append(poi)

	# Si aún así no hay, ya acepta cualquiera
	if available.is_empty():
		for poi in all_pois:
			if poi is SceneryPOI and poi.is_available():
				available.append(poi)

	if available.is_empty():
		_mode = Mode.WANDER
		_wander_state = WanderState.WAITING
		_wait_timer = 1.0
		return

	_release_current_poi_slot()

	_last_poi = previous_poi
	_current_poi = available.pick_random()
	_reserve_current_poi_target()

	if _current_poi.is_interior:
		_walk_target_x = _current_poi.get_exterior_door_pos().x
	else:
		_walk_target_x = _current_poi_target.x

	_wander_state = WanderState.WALKING_EXTERIOR

# ============================================================================
# FOLLOW
# ============================================================================
func _process_follow_horizontal(delta: float) -> void:
	if not is_instance_valid(_target):
		stop_follow()
		return

	var dist: float = npc.global_position.distance_to(_target.global_position)

	if dist >= dist_cancel:
		player_too_far_cancel.emit()
		stop_follow()
		return
	elif dist >= dist_warning and not _warning_emitted:
		_warning_emitted = true
		_warning_cooldown = WARNING_COOLDOWN_SECS
		player_too_far_warning.emit()
	elif dist < dist_warning and _warning_cooldown <= 0.0:
		_warning_emitted = false

	if dist <= dist_min:
		npc.velocity.x = move_toward(npc.velocity.x, 0.0, follow_accel * delta)
	elif dist > dist_max:
		var dir_x: float = sign(_target.global_position.x - npc.global_position.x)
		npc.velocity.x = move_toward(npc.velocity.x, dir_x * follow_speed, follow_accel * delta)
	else:
		npc.velocity.x = move_toward(npc.velocity.x, 0.0, follow_accel * delta)

# ============================================================================
# HELPERS
# ============================================================================
func _walk_toward(target_x: float, delta: float) -> void:
	var diff: float = target_x - npc.global_position.x
	var dir: float = sign(diff)
	npc.velocity.x = move_toward(npc.velocity.x, dir * follow_speed, follow_accel * delta)

func _arrived_at(target_x: float) -> bool:
	return abs(npc.global_position.x - target_x) < 12.0

func _release_current_poi_slot() -> void:
	if is_instance_valid(_current_poi):
		_current_poi.release_target_position(npc)

func _reserve_current_poi_target() -> void:
	if is_instance_valid(_current_poi):
		_current_poi_target = _current_poi.reserve_target_position(npc)
	else:
		_current_poi_target = npc.global_position
