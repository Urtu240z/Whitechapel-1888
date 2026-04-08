extends Node
class_name NPCClientMovement
# ============================================================================
# NPC CLIENT MOVEMENT
# Modo IDLE: estático.
# Modo FOLLOW: sigue al player manteniéndose entre dist_min y dist_max px.
# Gravedad siempre activa — se aplica desde npc_client._physics_process.
# ============================================================================

enum Mode { IDLE, WANDER, FOLLOW }

# ============================================================================
# SEÑALES
# ============================================================================
signal player_too_far_warning   # Emitida una vez al superar dist_warning
signal player_too_far_cancel    # Emitida una vez al superar dist_cancel

# ============================================================================
# CONFIG — recibida desde npc_client.gd via initialize()
# No editar aquí — ajustar desde el Inspector de NPCClient.
# ============================================================================
var follow_speed: float = 250.0
var follow_accel: float = 400.0
var dist_min: float = 200.0
var dist_max: float = 300.0
var dist_warning: float = 800.0   # grito
var dist_cancel: float = 1000.0   # cancelar trato
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

# Wander
var _wander_target_x: float = 0.0
var _wander_wait_timer: float = 0.0
var _wander_origin_x: float = 0.0
const WANDER_DIST_MIN: float = 600.0   # 10s a 600px/s
const WANDER_DIST_MAX: float = 6000.0
const WANDER_WAIT_MIN: float = 5.0
const WANDER_WAIT_MAX: float = 5.0
const WANDER_SPEED: float = 600.0

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

# ============================================================================
# PROCESO — cooldown del grito
# ============================================================================
func _process(delta: float) -> void:
	if _warning_cooldown > 0.0:
		_warning_cooldown -= delta
		if _warning_cooldown <= 0.0:
			_warning_cooldown = 0.0
			_warning_emitted = false  # puede volver a gritar

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
	_wander_origin_x = npc.global_position.x
	_mode = Mode.WANDER
	_pick_wander_target()

func stop_wander() -> void:
	if _mode == Mode.WANDER:
		_mode = Mode.IDLE
		npc.velocity.x = 0.0

func _pick_wander_target() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var dist: float = rng.randf_range(WANDER_DIST_MIN, WANDER_DIST_MAX)
	var dir: float = 1.0 if rng.randf() > 0.5 else -1.0
	_wander_target_x = _wander_origin_x + dist * dir
	# NO resetear timer aquí — lo gestiona _process_wander

# ============================================================================
# PROCESO — llamado desde npc_client._physics_process
# Solo gestiona velocidad horizontal. Gravedad y move_and_slide van en npc_client.
# ============================================================================
func process_movement(delta: float) -> void:
	if is_frozen or not npc:
		npc.velocity.x = 0.0
		return

	match _mode:
		Mode.IDLE:
			npc.velocity.x = move_toward(npc.velocity.x, 0.0, follow_accel * delta)
		Mode.WANDER:
			_process_wander(delta)
		Mode.FOLLOW:
			_process_follow_horizontal(delta)

func _process_wander(delta: float) -> void:
	# Esperando — frenar y contar timer
	if _wander_wait_timer > 0.0:
		_wander_wait_timer -= delta
		npc.velocity.x = move_toward(npc.velocity.x, 0.0, follow_accel * delta)
		return

	var diff: float = _wander_target_x - npc.global_position.x

	# Llegó al objetivo — poner timer y elegir nuevo destino
	if abs(diff) < 15.0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_wander_wait_timer = rng.randf_range(WANDER_WAIT_MIN, WANDER_WAIT_MAX)
		_pick_wander_target()
		return

	# Moverse hacia el objetivo
	var dir_x: float = sign(diff)
	npc.velocity.x = move_toward(npc.velocity.x, dir_x * WANDER_SPEED, follow_accel * delta)

func _process_follow_horizontal(delta: float) -> void:
	if not is_instance_valid(_target):
		stop_follow()
		return

	var dist: float = npc.global_position.distance_to(_target.global_position)

	# Umbrales de distancia
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
func is_moving() -> bool:
	return abs(npc.velocity.x) > 10.0 if npc else false

func get_facing_right() -> bool:
	# Dirección basada en velocidad — usada por animación en modo WANDER
	if abs(npc.velocity.x) > 5.0:
		return npc.velocity.x > 0.0
	return true  # default
