extends Node
class_name NPCCompanionMovement

# ============================================================================
# NPC COMPANION MOVEMENT
# Modo WANDER: deambula entre SceneryPOIs con soporte de interiores.
# Modo FOLLOW: sigue al player.
#
# FLUJO INTERIOR:
# 1. WALKING_EXTERIOR  → camina a puerta exterior (EnterArea)
# 2. Teleport          → aparece en puerta interior (ExitArea), reparent a Interior
# 3. INSIDE_TO_POI     → camina al Marker2D del POI dentro del interior
# 4. INSIDE_WAITING    → espera en el POI
# 5. INSIDE_TO_EXIT    → camina de vuelta al ExitArea interior
# 6. Teleport          → aparece en EnterArea exterior, reparent al padre original
# 7. Pick next POI
# ============================================================================

enum Mode { IDLE, WANDER, FOLLOW }
enum WanderState {
	WALKING_EXTERIOR,   # caminando a poi exterior o a puerta exterior
	WAITING,            # esperando en poi exterior
	INSIDE_TO_POI,      # dentro, caminando al marker del poi
	INSIDE_WAITING,     # dentro, esperando en el poi
	INSIDE_TO_EXIT,     # dentro, volviendo a la puerta de salida
}

# ============================================================================
# CONFIG
# ============================================================================
var walk_speed: float = 120.0
var walk_accel: float = 300.0
var follow_speed: float = 200.0
var dist_min: float = 150.0
var dist_max: float = 350.0

# ============================================================================
# ESTADO
# ============================================================================
var npc: CharacterBody2D = null
var is_frozen: bool = false
var _mode: Mode = Mode.IDLE
var _wander_state: WanderState = WanderState.WALKING_EXTERIOR
var _target: Node2D = null

var _current_poi: SceneryPOI = null
var _last_poi: SceneryPOI = null
var _wait_timer: float = 0.0
var _walk_target_x: float = 0.0

var _inside_building: bool = false
var _original_parent: Node = null
var _interior_exit_node: Node2D = null

# ============================================================================
# INIT
# ============================================================================
func initialize(owner_npc: CharacterBody2D,
		p_walk_speed: float = 120.0,
		p_walk_accel: float = 300.0,
		p_follow_speed: float = 200.0,
		p_dist_min: float = 150.0,
		p_dist_max: float = 350.0) -> void:
	npc = owner_npc
	walk_speed   = p_walk_speed
	walk_accel   = p_walk_accel
	follow_speed = p_follow_speed
	dist_min     = p_dist_min
	dist_max     = p_dist_max

# ============================================================================
# API
# ============================================================================
func freeze() -> void:
	is_frozen = true
	if npc:
		npc.velocity.x = 0.0

func unfreeze() -> void:
	is_frozen = false

func start_wander() -> void:
	if _mode == Mode.FOLLOW:
		return
	_mode = Mode.WANDER
	_pick_next_poi()

func stop_wander() -> void:
	if _mode == Mode.WANDER:
		_mode = Mode.IDLE
		if npc:
			npc.velocity.x = 0.0

func start_follow(target: Node2D) -> void:
	if _inside_building:
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

func is_moving() -> bool:
	return abs(npc.velocity.x) > 10.0 if npc else false

func get_facing_right() -> bool:
	if npc and abs(npc.velocity.x) > 5.0:
		return npc.velocity.x > 0.0
	return true

# ============================================================================
# PROCESO
# ============================================================================
func process_movement(delta: float) -> void:
	if is_frozen or not npc:
		npc.velocity.x = 0.0
		return

	match _mode:
		Mode.IDLE:
			npc.velocity.x = move_toward(npc.velocity.x, 0.0, walk_accel * delta)
		Mode.WANDER:
			_process_wander(delta)
		Mode.FOLLOW:
			_process_follow(delta)

# ============================================================================
# WANDER
# ============================================================================
func _process_wander(delta: float) -> void:
	match _wander_state:
		WanderState.WALKING_EXTERIOR:
			_walk_toward(_walk_target_x, delta)
			if _arrived_at(_walk_target_x):
				_on_arrived_exterior()

		WanderState.WAITING:
			npc.velocity.x = move_toward(npc.velocity.x, 0.0, walk_accel * delta)
			_wait_timer -= delta
			if _wait_timer <= 0.0:
				_pick_next_poi()

		WanderState.INSIDE_TO_POI:
			_walk_toward(_walk_target_x, delta)
			if _arrived_at(_walk_target_x):
				_on_arrived_at_interior_poi()

		WanderState.INSIDE_WAITING:
			npc.velocity.x = move_toward(npc.velocity.x, 0.0, walk_accel * delta)
			_wait_timer -= delta
			if _wait_timer <= 0.0:
				_start_leaving_interior()

		WanderState.INSIDE_TO_EXIT:
			_walk_toward(_walk_target_x, delta)
			if _arrived_at(_walk_target_x):
				_do_exit_building()

# ============================================================================
# LLEGADA EXTERIOR
# ============================================================================
func _on_arrived_exterior() -> void:
	if not is_instance_valid(_current_poi):
		_pick_next_poi()
		return

	if _current_poi.is_interior:
		_do_enter_building()
	else:
		# POI exterior — esperar y siguiente
		_wander_state = WanderState.WAITING
		_wait_timer = _current_poi.get_wait_time()

# ============================================================================
# ENTRAR AL EDIFICIO
# ============================================================================
func _do_enter_building() -> void:
	if not is_instance_valid(_current_poi):
		_pick_next_poi()
		return

	var interior_node: Node2D = _current_poi.get_interior_node()
	var interior_door_pos: Vector2 = _current_poi.get_interior_door_pos()
	_interior_exit_node = _current_poi.get_interior_exit_node()

	if not interior_node:
		# Sin interior válido — esperar en la puerta
		_wander_state = WanderState.WAITING
		_wait_timer = _current_poi.get_wait_time()
		return

	# Guardar padre original y reparentar al Interior
	_original_parent = npc.get_parent()
	_inside_building = true
	_original_parent.remove_child(npc)
	interior_node.add_child(npc)
	npc.global_position = interior_door_pos

	# Caminar hacia el POI dentro del interior
	_walk_target_x = _current_poi.global_position.x
	_wander_state = WanderState.INSIDE_TO_POI

# ============================================================================
# LLEGADA AL POI INTERIOR
# ============================================================================
func _on_arrived_at_interior_poi() -> void:
	_wander_state = WanderState.INSIDE_WAITING
	_wait_timer = _current_poi.get_wait_time() if is_instance_valid(_current_poi) else 5.0

# ============================================================================
# SALIR DEL EDIFICIO
# ============================================================================
func _start_leaving_interior() -> void:
	if is_instance_valid(_interior_exit_node):
		_walk_target_x = _interior_exit_node.global_position.x
		_wander_state = WanderState.INSIDE_TO_EXIT
	else:
		_do_exit_building()

func _do_exit_building() -> void:
	var exterior_door_pos: Vector2 = Vector2.ZERO
	if is_instance_valid(_current_poi):
		exterior_door_pos = _current_poi.get_exterior_door_pos()

	# Reparentar de vuelta al padre original
	var current_parent := npc.get_parent()
	if current_parent:
		current_parent.remove_child(npc)
	if is_instance_valid(_original_parent):
		_original_parent.add_child(npc)
	else:
		npc.get_tree().current_scene.add_child(npc)

	npc.global_position = exterior_door_pos
	_inside_building = false
	_original_parent = null
	_interior_exit_node = null
	_pick_next_poi()

func _force_exit_building() -> void:
	if not _inside_building:
		return
	var current_parent := npc.get_parent()
	if current_parent:
		current_parent.remove_child(npc)
	if is_instance_valid(_original_parent):
		_original_parent.add_child(npc)
	else:
		npc.get_tree().current_scene.add_child(npc)
	_inside_building = false
	_original_parent = null
	_interior_exit_node = null

# ============================================================================
# SELECCIÓN DE POI
# ============================================================================
func _pick_next_poi() -> void:
	var all_pois := npc.get_tree().get_nodes_in_group("scenery_poi")
	var available: Array = []

	for poi in all_pois:
		if poi is SceneryPOI and poi.is_available() and poi != _last_poi:
			available.append(poi)

	if available.is_empty():
		for poi in all_pois:
			if poi is SceneryPOI and poi.is_available():
				available.append(poi)

	if available.is_empty():
		_mode = Mode.IDLE
		return

	_last_poi = _current_poi
	_current_poi = available.pick_random()

	if _current_poi.is_interior:
		# Caminar a la puerta exterior del edificio primero
		_walk_target_x = _current_poi.get_exterior_door_pos().x
	else:
		# Caminar directamente al POI
		_walk_target_x = _current_poi.global_position.x

	_wander_state = WanderState.WALKING_EXTERIOR

# ============================================================================
# HELPERS DE MOVIMIENTO
# ============================================================================
func _walk_toward(target_x: float, delta: float) -> void:
	var diff: float = target_x - npc.global_position.x
	var dir: float = sign(diff)
	npc.velocity.x = move_toward(npc.velocity.x, dir * walk_speed, walk_accel * delta)

func _arrived_at(target_x: float) -> bool:
	return abs(npc.global_position.x - target_x) < 12.0

# ============================================================================
# FOLLOW
# ============================================================================
func _process_follow(delta: float) -> void:
	if not is_instance_valid(_target):
		stop_follow()
		return

	var diff: float = _target.global_position.x - npc.global_position.x
	var dist: float = abs(diff)

	if dist <= dist_min:
		npc.velocity.x = move_toward(npc.velocity.x, 0.0, walk_accel * delta)
		return

	var dir: float = sign(diff)
	var speed: float = lerp(walk_speed, follow_speed,
		clamp((dist - dist_min) / dist_max, 0.0, 1.0))
	npc.velocity.x = move_toward(npc.velocity.x, dir * speed, walk_accel * delta)
