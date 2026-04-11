extends Node
class_name NPCCompanionMovement

# ============================================================================
# NPC COMPANION MOVEMENT
# Modo IDLE: estático.
# Modo WANDER: deambula entre SceneryPOIs del grupo "scenery_poi".
# Modo FOLLOW: sigue al player entre dist_min y dist_max.
# Gravedad gestionada desde npc_companion._physics_process.
# ============================================================================

enum Mode { IDLE, WANDER, FOLLOW }
enum WanderState { WALKING, WAITING, INSIDE }

# ============================================================================
# CONFIG — recibida via initialize()
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
var _wander_state: WanderState = WanderState.WALKING
var _target: Node2D = null

var _current_poi: SceneryPOI = null
var _last_poi: SceneryPOI = null
var _wait_timer: float = 0.0
var _inside_building: bool = false
var _current_entrance: Node = null

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
	_wander_state = WanderState.WALKING
	_pick_next_poi()

func stop_wander() -> void:
	if _mode == Mode.WANDER:
		_mode = Mode.IDLE
		if npc:
			npc.velocity.x = 0.0

func start_follow(target: Node2D) -> void:
	if _inside_building and _current_entrance:
		_exit_building()
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
# PROCESO — llamado desde npc_companion._physics_process
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
		WanderState.WALKING:
			_process_walk_to_poi(delta)
		WanderState.WAITING:
			_process_wait(delta)
		WanderState.INSIDE:
			npc.velocity.x = 0.0

func _process_walk_to_poi(delta: float) -> void:
	if not is_instance_valid(_current_poi):
		_pick_next_poi()
		return

	var diff: float = _current_poi.global_position.x - npc.global_position.x
	var dist: float = abs(diff)

	if dist < 12.0:
		npc.velocity.x = 0.0
		npc.global_position.x = _current_poi.global_position.x
		_on_arrived_at_poi()
		return

	var dir: float = sign(diff)
	npc.velocity.x = move_toward(npc.velocity.x, dir * walk_speed, walk_accel * delta)

func _process_wait(delta: float) -> void:
	npc.velocity.x = move_toward(npc.velocity.x, 0.0, walk_accel * delta)
	_wait_timer -= delta
	if _wait_timer <= 0.0:
		_pick_next_poi()

func _on_arrived_at_poi() -> void:
	if not is_instance_valid(_current_poi):
		_pick_next_poi()
		return

	if _current_poi.is_interior:
		_enter_building()
	else:
		_wander_state = WanderState.WAITING
		_wait_timer = _current_poi.get_wait_time()

func _enter_building() -> void:
	if not is_instance_valid(_current_poi):
		_pick_next_poi()
		return

	var entrance := _current_poi.get_building_entrance()
	if not entrance or not entrance.has_method("npc_enter"):
		# Sin entrance válido — esperar en la puerta
		_wander_state = WanderState.WAITING
		_wait_timer = _current_poi.get_wait_time()
		return

	_current_entrance = entrance
	_inside_building = true
	_wander_state = WanderState.INSIDE
	entrance.npc_enter(npc, _current_poi.get_interior_spawn())

	# Salir después del tiempo de espera
	var wait: float = _current_poi.get_wait_time()
	npc.get_tree().create_timer(wait).timeout.connect(_exit_building, CONNECT_ONE_SHOT)

func _exit_building() -> void:
	if not is_instance_valid(_current_entrance) or not _current_entrance.has_method("npc_exit"):
		_inside_building = false
		_current_entrance = null
		_pick_next_poi()
		return

	var exit_pos: Vector2 = _current_poi.get_exterior_spawn() if is_instance_valid(_current_poi) else npc.global_position
	_current_entrance.npc_exit(npc, exit_pos)
	_inside_building = false
	_current_entrance = null
	_pick_next_poi()

# ============================================================================
# SELECCIÓN DE POI — random sin repetir el último
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
	_wander_state = WanderState.WALKING

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
