extends Node
class_name NPCCompanionMovement

# ============================================================================
# NPC COMPANION MOVEMENT
# Modo IDLE: estático.
# Modo WANDER: ping-pong entre waypoints del mapa.
# Modo FOLLOW: sigue al player entre dist_min y dist_max.
# Gravedad gestionada desde npc_companion._physics_process.
# ============================================================================

enum Mode { IDLE, WANDER, FOLLOW }

# ============================================================================
# CONFIG — recibida via initialize()
# ============================================================================
var walk_speed: float = 120.0
var walk_accel: float = 300.0
var follow_speed: float = 200.0
var dist_min: float = 150.0
var dist_max: float = 350.0
var wait_time: float = 3.0

# ============================================================================
# ESTADO
# ============================================================================
var npc: CharacterBody2D = null
var is_frozen: bool = false
var _mode: Mode = Mode.IDLE
var _target: Node2D = null

# Waypoints
var _waypoint_nodes: Array = []
var _current_idx: int = 0
var _direction: int = 1   # 1 = avanzando, -1 = retrocediendo
var _waiting: bool = false
var _wait_timer: float = 0.0

# ============================================================================
# INIT
# ============================================================================
func initialize(owner_npc: CharacterBody2D,
		p_walk_speed: float = 120.0,
		p_walk_accel: float = 300.0,
		p_follow_speed: float = 200.0,
		p_dist_min: float = 150.0,
		p_dist_max: float = 350.0,
		p_waypoints: Array[NodePath] = [],
		p_wait_time: float = 3.0) -> void:
	npc = owner_npc
	walk_speed   = p_walk_speed
	walk_accel   = p_walk_accel
	follow_speed = p_follow_speed
	dist_min     = p_dist_min
	dist_max     = p_dist_max
	wait_time    = p_wait_time

	# Resolver waypoints desde NodePath
	_waypoint_nodes = []
	for np in p_waypoints:
		var node = npc.get_node_or_null(np)
		if node:
			_waypoint_nodes.append(node)
		else:
			push_warning("NPCCompanionMovement: waypoint no encontrado: %s" % np)

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
	if _waypoint_nodes.is_empty():
		_mode = Mode.IDLE
		return
	_mode = Mode.WANDER
	_waiting = false

func stop_wander() -> void:
	if _mode == Mode.WANDER:
		_mode = Mode.IDLE
		if npc:
			npc.velocity.x = 0.0

func start_follow(target: Node2D) -> void:
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

func _process_wander(delta: float) -> void:
	if _waypoint_nodes.is_empty():
		npc.velocity.x = move_toward(npc.velocity.x, 0.0, walk_accel * delta)
		return

	if _waiting:
		npc.velocity.x = move_toward(npc.velocity.x, 0.0, walk_accel * delta)
		_wait_timer -= delta
		if _wait_timer <= 0.0:
			_waiting = false
			_advance_waypoint()
		return

	var target: Node2D = _waypoint_nodes[_current_idx]
	if not is_instance_valid(target):
		npc.velocity.x = 0.0
		return

	var diff: float = target.global_position.x - npc.global_position.x
	var dist: float = abs(diff)

	if dist < 8.0:
		npc.velocity.x = 0.0
		npc.global_position.x = target.global_position.x
		_waiting = true
		_wait_timer = wait_time
		return

	var dir: float = sign(diff)
	npc.velocity.x = move_toward(npc.velocity.x, dir * walk_speed, walk_accel * delta)

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

# ============================================================================
# WAYPOINTS — ping-pong
# ============================================================================
func _advance_waypoint() -> void:
	if _waypoint_nodes.size() <= 1:
		return
	_current_idx += _direction
	if _current_idx >= _waypoint_nodes.size():
		_direction = -1
		_current_idx = _waypoint_nodes.size() - 2
	elif _current_idx < 0:
		_direction = 1
		_current_idx = 1
