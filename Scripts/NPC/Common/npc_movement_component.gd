extends Node
class_name NPCMovementComponent

const NPCBuildingTravelScript = preload("res://Scripts/NPC/Common/npc_building_travel.gd")

# ============================================================================
# NPC MOVEMENT COMPONENT
# ============================================================================
# Componente común de movimiento para NPCs.
#
# Responsabilidad:
# - Exponer una API común para Animation/Conversation/roles.
# - Gestionar modo STATIC, WANDER y FOLLOW.
# - Compartir lógica de POIs/interiores entre Client, Companion y futuros NPCs.
#
# No decide el rol narrativo del NPC.
# Un Service, Client, Companion, Police o Vendor puede usar este componente
# con distinta configuración.
# ============================================================================

enum Mode { STATIC, WANDER, FOLLOW, PATROL, CHASE }
enum WanderState {
	WALKING_EXTERIOR,
	WAITING,
	INSIDE_TO_POI,
	INSIDE_WAITING,
	INSIDE_TO_EXIT,
}
enum FollowStyle { BAND, SMOOTH }

# ============================================================================
# SEÑALES
# ============================================================================
signal player_too_far_warning
signal player_too_far_cancel
signal mode_changed(new_mode: int)

# ============================================================================
# CONFIG — CAPACIDADES
# ============================================================================
@export_group("Capabilities")
@export var can_wander: bool = true
@export var can_follow: bool = true
@export var can_use_pois: bool = true
@export var allow_building_travel: bool = true

# ============================================================================
# CONFIG — MOVIMIENTO
# ============================================================================
@export_group("Movement")
@export var walk_speed: float = 120.0
@export var walk_accel: float = 300.0
@export var follow_speed: float = 200.0
@export var follow_accel: float = 400.0
@export var dist_min: float = 150.0
@export var dist_max: float = 350.0
@export var arrival_margin: float = 12.0

# ============================================================================
# CONFIG — FOLLOW
# ============================================================================
@export_group("Follow")
@export var follow_style: FollowStyle = FollowStyle.SMOOTH
@export var use_distance_warning: bool = false
@export var dist_warning: float = 800.0
@export var dist_cancel: float = 1000.0
@export var warning_cooldown_secs: float = 10.0

# ============================================================================
# ESTADO PÚBLICO ESPERADO POR ANIMATION
# ============================================================================
var npc: CharacterBody2D = null
var is_frozen: bool = false

# ============================================================================
# ESTADO INTERNO
# ============================================================================
var _mode: Mode = Mode.STATIC
var _wander_state: WanderState = WanderState.WALKING_EXTERIOR
var _target: Node2D = null
var _facing_right: bool = true

var _current_poi: SceneryPOI = null
var _last_poi: SceneryPOI = null
var _wait_timer: float = 0.0
var _walk_target_x: float = 0.0
var _current_poi_target: Vector2 = Vector2.ZERO

var _warning_emitted: bool = false
var _warning_cooldown: float = 0.0

# Mientras BuildingEntrance.npc_enter()/npc_exit() están ejecutando su fade y reparent,
# el movement no debe avanzar estados ni llamar varias veces al portal.
var _building_transition_active: bool = false

var _building_travel: NPCBuildingTravel = NPCBuildingTravelScript.new()


# ============================================================================
# INIT
# ============================================================================
func initialize(owner_npc: CharacterBody2D) -> void:
	if owner_npc == null:
		push_error("NPCMovementComponent '%s': owner_npc es null." % name)
		return

	npc = owner_npc
	_building_travel.initialize(owner_npc)


func configure_static() -> void:
	can_wander = false
	can_follow = false
	can_use_pois = false
	allow_building_travel = false
	use_distance_warning = false
	stop_all()


func configure_for_client(
		p_follow_speed: float,
		p_follow_accel: float,
		p_dist_min: float,
		p_dist_max: float,
		_p_gravity: float,
		p_dist_warning: float,
		p_dist_cancel: float
	) -> void:
	# El client antiguo usaba follow_speed/follow_accel también para caminar entre POIs.
	walk_speed = p_follow_speed
	walk_accel = p_follow_accel
	follow_speed = p_follow_speed
	follow_accel = p_follow_accel
	dist_min = p_dist_min
	dist_max = p_dist_max
	dist_warning = p_dist_warning
	dist_cancel = p_dist_cancel
	follow_style = FollowStyle.BAND
	use_distance_warning = true
	can_wander = true
	can_follow = true
	can_use_pois = true
	allow_building_travel = true


func configure_for_companion(
		p_walk_speed: float,
		p_walk_accel: float,
		p_follow_speed: float,
		p_dist_min: float,
		p_dist_max: float
	) -> void:
	walk_speed = p_walk_speed
	walk_accel = p_walk_accel
	follow_speed = p_follow_speed
	follow_accel = p_walk_accel
	dist_min = p_dist_min
	dist_max = p_dist_max
	follow_style = FollowStyle.SMOOTH
	use_distance_warning = false
	can_wander = true
	can_follow = true
	can_use_pois = true
	allow_building_travel = true


# ============================================================================
# PROCESS
# ============================================================================
func _process(delta: float) -> void:
	if _warning_cooldown <= 0.0:
		return

	_warning_cooldown -= delta
	if _warning_cooldown <= 0.0:
		_warning_cooldown = 0.0
		_warning_emitted = false


# ============================================================================
# API GENERAL
# ============================================================================
func freeze() -> void:
	is_frozen = true
	_stop_horizontal_motion()


func unfreeze() -> void:
	is_frozen = false


func stop_all() -> void:
	_release_current_poi_slot()
	_target = null
	_set_mode(Mode.STATIC)
	_stop_horizontal_motion()
	_reset_distance_warning()


func set_static() -> void:
	stop_all()


func get_mode() -> int:
	return _mode


func is_following() -> bool:
	return _mode == Mode.FOLLOW


func is_wandering() -> bool:
	return _mode == Mode.WANDER


func is_static() -> bool:
	return _mode == Mode.STATIC


func is_moving() -> bool:
	return abs(npc.velocity.x) > 10.0 if npc else false


func get_facing_right() -> bool:
	if npc and abs(npc.velocity.x) > 5.0:
		return npc.velocity.x > 0.0

	return _facing_right


func set_facing_right(value: bool) -> void:
	_facing_right = value


# ============================================================================
# API WANDER
# ============================================================================
func start_wander() -> void:
	if not can_wander:
		return

	if not can_use_pois:
		set_static()
		return

	if _mode == Mode.FOLLOW:
		return

	_target = null
	_set_mode(Mode.WANDER)
	_pick_next_poi()


func stop_wander() -> void:
	if _mode != Mode.WANDER:
		return

	_release_current_poi_slot()
	_set_mode(Mode.STATIC)
	_stop_horizontal_motion()


# ============================================================================
# API FOLLOW
# ============================================================================
func start_follow(target: Node2D) -> void:
	if not can_follow:
		return

	if target == null:
		return

	_release_current_poi_slot()

	if allow_building_travel and _building_travel.is_inside_building():
		_force_exit_building()

	_target = target
	_reset_distance_warning()
	_set_mode(Mode.FOLLOW)


func stop_follow() -> void:
	if _mode != Mode.FOLLOW:
		return

	_target = null
	_reset_distance_warning()
	_set_mode(Mode.STATIC)
	_stop_horizontal_motion()


# ============================================================================
# MOVEMENT TICK
# ============================================================================
func process_movement(delta: float) -> void:
	if not is_instance_valid(npc):
		return

	if _building_transition_active or bool(npc.get_meta("_building_transit_active", false)):
		_stop_horizontal_motion()
		return

	if is_frozen:
		_stop_horizontal_motion()
		return

	match _mode:
		Mode.STATIC:
			_stop_horizontal_motion(delta)

		Mode.WANDER:
			_process_wander(delta)

		Mode.FOLLOW:
			_process_follow(delta)

		_:
			# Reservado para futuros PATROL/CHASE sin romper la API actual.
			_stop_horizontal_motion(delta)


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
			_stop_horizontal_motion(delta)
			_wait_timer -= delta
			if _wait_timer <= 0.0:
				_pick_next_poi()

		WanderState.INSIDE_TO_POI:
			_walk_toward(_walk_target_x, delta)
			if _arrived_at(_walk_target_x):
				_on_arrived_at_interior_poi()

		WanderState.INSIDE_WAITING:
			_stop_horizontal_motion(delta)
			_wait_timer -= delta
			if _wait_timer <= 0.0:
				_start_leaving_interior()

		WanderState.INSIDE_TO_EXIT:
			_walk_toward(_walk_target_x, delta)
			if _arrived_at(_walk_target_x):
				_do_exit_building()


func _on_arrived_exterior() -> void:
	if _building_transition_active:
		_stop_horizontal_motion()
		return

	if not is_instance_valid(_current_poi):
		_pick_next_poi()
		return

	if _current_poi.is_interior and allow_building_travel:
		_do_enter_building()
	else:
		_wander_state = WanderState.WAITING
		_wait_timer = _current_poi.get_wait_time()


func _do_enter_building() -> void:
	if _building_transition_active:
		return

	if not is_instance_valid(_current_poi):
		_pick_next_poi()
		return

	_building_transition_active = true
	_stop_horizontal_motion()

	var entered: bool = await _building_travel.enter_building_for_poi(_current_poi)

	_building_transition_active = false

	if not is_instance_valid(npc):
		return

	if not is_instance_valid(_current_poi):
		_pick_next_poi()
		return

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
	if _building_transition_active:
		return

	if not is_instance_valid(npc):
		return

	_building_transition_active = true
	_stop_horizontal_motion()

	var exterior_door_pos: Vector2 = npc.global_position
	if is_instance_valid(_current_poi):
		exterior_door_pos = _current_poi.get_exterior_door_pos()

	await _building_travel.exit_current_building(exterior_door_pos)

	_building_transition_active = false

	if not is_instance_valid(npc):
		return

	_release_current_poi_slot()
	_pick_next_poi()


func _force_exit_building() -> void:
	if _building_transition_active:
		return

	_building_transition_active = true
	_stop_horizontal_motion()

	await _building_travel.force_exit_to_poi_door()

	_building_transition_active = false

	if not is_instance_valid(npc):
		return

	_release_current_poi_slot()


func _pick_next_poi() -> void:
	if not is_instance_valid(npc):
		return

	var previous_poi: SceneryPOI = _current_poi
	var all_nodes: Array[Node] = npc.get_tree().get_nodes_in_group("scenery_poi")
	var available: Array[SceneryPOI] = []

	for node_a: Node in all_nodes:
		var poi_a: SceneryPOI = node_a as SceneryPOI
		if poi_a and poi_a.is_available() and poi_a != previous_poi and poi_a != _last_poi:
			available.append(poi_a)

	# Si no hay suficientes, al menos evita repetir el actual.
	if available.is_empty():
		for node_b: Node in all_nodes:
			var poi_b: SceneryPOI = node_b as SceneryPOI
			if poi_b and poi_b.is_available() and poi_b != previous_poi:
				available.append(poi_b)

	# Si aún así no hay, acepta cualquiera disponible.
	if available.is_empty():
		for node_c: Node in all_nodes:
			var poi_c: SceneryPOI = node_c as SceneryPOI
			if poi_c and poi_c.is_available():
				available.append(poi_c)

	if available.is_empty():
		_set_mode(Mode.WANDER)
		_wander_state = WanderState.WAITING
		_wait_timer = 1.0
		return

	_release_current_poi_slot()

	_last_poi = previous_poi
	_current_poi = available.pick_random() as SceneryPOI
	_reserve_current_poi_target()

	if _current_poi.is_interior and allow_building_travel:
		_walk_target_x = _current_poi.get_exterior_door_pos().x
	else:
		_walk_target_x = _current_poi_target.x

	_wander_state = WanderState.WALKING_EXTERIOR


# ============================================================================
# FOLLOW
# ============================================================================
func _process_follow(delta: float) -> void:
	if not is_instance_valid(_target):
		stop_follow()
		return

	if use_distance_warning:
		var full_dist: float = npc.global_position.distance_to(_target.global_position)
		if _process_distance_warning(full_dist):
			return

	match follow_style:
		FollowStyle.BAND:
			_process_follow_band(delta)
		FollowStyle.SMOOTH:
			_process_follow_smooth(delta)


func _process_follow_band(delta: float) -> void:
	var dist: float = npc.global_position.distance_to(_target.global_position)

	if dist <= dist_min:
		_stop_horizontal_motion(delta)
	elif dist > dist_max:
		var dir_x: float = sign(_target.global_position.x - npc.global_position.x)
		_set_horizontal_velocity(dir_x * follow_speed, follow_accel, delta)
	else:
		_stop_horizontal_motion(delta)


func _process_follow_smooth(delta: float) -> void:
	var diff: float = _target.global_position.x - npc.global_position.x
	var dist: float = abs(diff)

	if dist <= dist_min:
		_stop_horizontal_motion(delta)
		return

	var denom: float = max(dist_max, 0.001)
	var t: float = clamp((dist - dist_min) / denom, 0.0, 1.0)
	var speed: float = lerp(walk_speed, follow_speed, t)
	var dir_x: float = sign(diff)
	_set_horizontal_velocity(dir_x * speed, follow_accel, delta)


func _process_distance_warning(distance_to_target: float) -> bool:
	if distance_to_target >= dist_cancel:
		player_too_far_cancel.emit()
		stop_follow()
		return true

	if distance_to_target >= dist_warning and not _warning_emitted:
		_warning_emitted = true
		_warning_cooldown = warning_cooldown_secs
		player_too_far_warning.emit()
		return false

	if distance_to_target < dist_warning and _warning_cooldown <= 0.0:
		_warning_emitted = false

	return false


# ============================================================================
# HELPERS
# ============================================================================
func _walk_toward(target_x: float, delta: float) -> void:
	var diff: float = target_x - npc.global_position.x
	var dir: float = sign(diff)
	_set_horizontal_velocity(dir * walk_speed, walk_accel, delta)


func _arrived_at(target_x: float) -> bool:
	return abs(npc.global_position.x - target_x) < arrival_margin


func _set_horizontal_velocity(target_velocity_x: float, accel: float, delta: float) -> void:
	if not is_instance_valid(npc):
		return

	npc.velocity.x = move_toward(npc.velocity.x, target_velocity_x, accel * delta)
	if abs(npc.velocity.x) > 5.0:
		_facing_right = npc.velocity.x > 0.0


func _stop_horizontal_motion(delta: float = 0.0) -> void:
	if not is_instance_valid(npc):
		return

	if delta <= 0.0:
		npc.velocity.x = 0.0
		return

	var accel: float = max(walk_accel, follow_accel)
	npc.velocity.x = move_toward(npc.velocity.x, 0.0, accel * delta)


func _release_current_poi_slot() -> void:
	if is_instance_valid(_current_poi) and is_instance_valid(npc):
		_current_poi.release_target_position(npc)


func _reserve_current_poi_target() -> void:
	if is_instance_valid(_current_poi) and is_instance_valid(npc):
		_current_poi_target = _current_poi.reserve_target_position(npc)
	else:
		_current_poi_target = npc.global_position if is_instance_valid(npc) else Vector2.ZERO


func _reset_distance_warning() -> void:
	_warning_emitted = false
	_warning_cooldown = 0.0


func _set_mode(new_mode: Mode) -> void:
	if _mode == new_mode:
		return

	_mode = new_mode
	mode_changed.emit(_mode)
