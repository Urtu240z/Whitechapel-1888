@tool
extends Node
class_name NPCAnimationComponent

# ============================================================================
# NPC ANIMATION COMPONENT
# ============================================================================
# Componente común para:
# - NPCClient
# - NPCCompanion
# - NPCService
#
# Sustituye:
# - npc_client_animation.gd
# - npc_companion_animation.gd
# - npc_service_animation.gd
#
# Requiere en el NPC:
# - AnimationTree
# - CharacterContainer
#
# Opcional según configuración:
# - Movement, si use_walk_state = true o use_movement_facing = true
# - AnimationPlayer, si se usan ataques
#
# Sin fallbacks silenciosos:
# - Si falta algo necesario según configuración, push_error().
# ============================================================================


# ============================================================================
# SEÑALES
# ============================================================================
signal attack_finished
signal attack_hit(attack_type: String)


# ============================================================================
# CONFIG — GENERAL
# ============================================================================
@export_group("General")
@export var initial_state: String = "Idle"
@export var idle_state: String = "Idle"
@export var walk_state: String = "Walk"

@export var animation_tree_path: NodePath = NodePath("../AnimationTree")
@export var character_container_path: NodePath = NodePath("../CharacterContainer")
@export var movement_path: NodePath = NodePath("../Movement")
@export var animation_player_path: NodePath = NodePath("../AnimationPlayer")


# ============================================================================
# CONFIG — MOVEMENT
# ============================================================================
@export_group("Movement")
@export var use_walk_state: bool = true
@export var use_movement_facing: bool = true


# ============================================================================
# CONFIG — COUNTER BEHAVIOUR
# ============================================================================
@export_group("Counter Behaviour")
@export var use_counter_behavior: bool = false
@export var counter_idle_state: String = "Idle_Counter"


# ============================================================================
# CONFIG — FACING
# ============================================================================
@export_group("Facing")
@export var flip_body_with_player: bool = true
@export var face_player_only_when_in_range: bool = true


# ============================================================================
# CONFIG — ATTACK
# ============================================================================
@export_group("Attack")
@export var attack_locks_state: bool = true


# ============================================================================
# REFERENCIAS
# ============================================================================
var npc: CharacterBody2D = null
var anim_tree: AnimationTree = null
var character_container: Node2D = null
var movement: Node = null
var anim_player: AnimationPlayer = null

var playback: AnimationNodeStateMachinePlayback = null


# ============================================================================
# ESTADO
# ============================================================================
var _player_near: bool = false
var _state_locked: bool = false
var _locked_facing_right: bool = true
var _base_scale: Vector2 = Vector2.ONE
var _is_attacking: bool = false

var _reported_missing_movement: bool = false
var _reported_bad_movement_api: bool = false


# ============================================================================
# READY
# ============================================================================
func _ready() -> void:
	npc = get_parent() as CharacterBody2D
	_cache_nodes()

	if character_container:
		_refresh_base_scale()

	if Engine.is_editor_hint():
		set_process(false)
		return


# ============================================================================
# INIT
# ============================================================================
func initialize(owner_npc: CharacterBody2D, facing_right: bool = true) -> void:
	if owner_npc == null:
		push_error("NPCAnimationComponent '%s': owner_npc es null." % name)
		return

	npc = owner_npc
	_cache_nodes()

	if anim_tree == null:
		push_error("NPCAnimationComponent '%s': falta AnimationTree en ruta %s." % [
			name,
			str(animation_tree_path)
		])
		return

	if character_container == null:
		push_error("NPCAnimationComponent '%s': falta CharacterContainer en ruta %s." % [
			name,
			str(character_container_path)
		])
		return

	_refresh_base_scale()

	anim_tree.active = true
	playback = anim_tree["parameters/playback"]

	if playback == null:
		push_error("NPCAnimationComponent '%s': AnimationTree no tiene parameters/playback." % name)
		return

	playback.travel(initial_state)
	_apply_facing(facing_right)


func _cache_nodes() -> void:
	anim_tree = get_node_or_null(animation_tree_path) as AnimationTree
	character_container = get_node_or_null(character_container_path) as Node2D
	movement = get_node_or_null(movement_path)
	anim_player = get_node_or_null(animation_player_path) as AnimationPlayer


# ============================================================================
# UPDATE
# ============================================================================
func update_service(_delta: float, player: Node2D, player_in_range: bool) -> void:
	if playback == null:
		return

	if use_counter_behavior and not _state_locked:
		_update_counter_state(player_in_range)

	if use_walk_state:
		_update_walk_state()

	_update_body_flip(player, player_in_range)


func _update_walk_state() -> void:
	if playback == null:
		return

	if _state_locked:
		return

	if movement == null:
		_report_missing_movement_once()
		return

	if not _movement_has_required_api_for_walk():
		_report_bad_movement_api_once()
		return

	if bool(movement.get("is_frozen")):
		_travel_if_needed(idle_state)
		return

	var is_moving: bool = bool(movement.call("is_moving"))

	if is_moving:
		_travel_if_needed(walk_state)
	else:
		_travel_if_needed(idle_state)


func _update_counter_state(player_in_range: bool) -> void:
	if playback == null:
		return

	if player_in_range == _player_near:
		return

	_player_near = player_in_range

	if _player_near:
		playback.travel(idle_state)
	else:
		playback.travel(counter_idle_state)


# ============================================================================
# API
# ============================================================================
func force_idle_counter() -> void:
	_player_near = false

	if playback == null:
		return

	if use_counter_behavior:
		playback.travel(counter_idle_state)
	else:
		playback.travel(idle_state)


func lock_facing(facing_right: bool) -> void:
	_state_locked = true
	_locked_facing_right = facing_right
	_apply_facing(facing_right)

	if playback:
		playback.start(idle_state)


func unlock_facing() -> void:
	_state_locked = false


func preview_facing(facing_right: bool) -> void:
	_cache_nodes()

	if character_container == null:
		return

	_refresh_base_scale()
	_apply_facing(facing_right)


func is_attacking() -> bool:
	return _is_attacking


func play_attack(attack_type: String = "Kick") -> void:
	if playback == null:
		push_error("NPCAnimationComponent '%s': no puede atacar porque playback es null." % name)
		attack_finished.emit()
		return

	if anim_player == null:
		push_error("NPCAnimationComponent '%s': no puede esperar ataque porque falta AnimationPlayer." % name)
		attack_finished.emit()
		return

	if not anim_player.has_animation(attack_type):
		push_error("NPCAnimationComponent '%s': AnimationPlayer no tiene animación '%s'." % [
			name,
			attack_type
		])
		attack_finished.emit()
		return

	_is_attacking = true

	if attack_locks_state:
		_state_locked = true

	playback.travel(attack_type)

	var finished: StringName = &""
	while str(finished) != attack_type:
		finished = await anim_player.animation_finished

	_is_attacking = false

	if attack_locks_state:
		_state_locked = false

	attack_finished.emit()


# ============================================================================
# BODY FLIP
# ============================================================================
func _update_body_flip(player: Node2D, player_in_range: bool) -> void:
	if not flip_body_with_player:
		return

	if character_container == null:
		return

	if _state_locked:
		_apply_facing(_locked_facing_right)
		return

	if use_movement_facing:
		if movement == null:
			_report_missing_movement_once()
		elif _movement_has_required_api_for_facing():
			if not bool(movement.call("is_following")) and bool(movement.call("is_moving")):
				_apply_facing(bool(movement.call("get_facing_right")))
				return
		else:
			_report_bad_movement_api_once()

	if face_player_only_when_in_range and not player_in_range:
		return

	if is_instance_valid(player) and npc:
		_apply_facing(player.global_position.x > npc.global_position.x)


# ============================================================================
# HELPERS
# ============================================================================
func _travel_if_needed(state_name: String) -> void:
	if playback == null:
		return

	if playback.get_current_node() != state_name:
		playback.start(state_name)


func _refresh_base_scale() -> void:
	if character_container == null:
		return

	_base_scale = character_container.scale
	_base_scale.x = abs(_base_scale.x)
	_base_scale.y = abs(_base_scale.y)

	if is_zero_approx(_base_scale.x):
		_base_scale.x = 1.0

	if is_zero_approx(_base_scale.y):
		_base_scale.y = 1.0


func _apply_facing(facing_right: bool) -> void:
	if character_container == null:
		return

	character_container.scale.x = _base_scale.x if facing_right else -_base_scale.x
	character_container.scale.y = _base_scale.y


func _movement_has_required_api_for_walk() -> bool:
	return (
		movement != null
		and movement.has_method("is_moving")
		and movement.get("is_frozen") != null
	)


func _movement_has_required_api_for_facing() -> bool:
	return (
		movement != null
		and movement.has_method("is_moving")
		and movement.has_method("is_following")
		and movement.has_method("get_facing_right")
	)


func _report_missing_movement_once() -> void:
	if _reported_missing_movement:
		return

	_reported_missing_movement = true
	push_error("NPCAnimationComponent '%s': use_walk_state/use_movement_facing requiere nodo Movement en ruta %s." % [
		name,
		str(movement_path)
	])


func _report_bad_movement_api_once() -> void:
	if _reported_bad_movement_api:
		return

	_reported_bad_movement_api = true
	push_error("NPCAnimationComponent '%s': Movement no expone la API requerida: is_frozen, is_moving(), is_following(), get_facing_right()." % name)


# ============================================================================
# LLAMADO DESDE ANIMATIONPLAYER
# ============================================================================
func _emit_attack_hit(attack_type: String) -> void:
	attack_hit.emit(attack_type)
