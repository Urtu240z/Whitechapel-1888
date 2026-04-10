@tool
extends Node
class_name NPCClientAnimation

# ============================================================================
# NPC CLIENT ANIMATION
# Los clientes no tienen comportamiento de mostrador.
# use_counter_behavior = false por defecto.
# ============================================================================

# ============================================================================
# CONFIG
# ============================================================================
@export_group("Counter Behaviour")
@export var use_counter_behavior: bool = false
@export var initial_state: String = "Idle"

@export_group("Facing")
@export var flip_body_with_player: bool = true
@export var face_player_only_when_in_range: bool = true

# ============================================================================
# REFERENCIAS
# ============================================================================
@onready var npc: CharacterBody2D = get_parent() as CharacterBody2D
@onready var anim_tree: AnimationTree = $"../AnimationTree"
@onready var character_container: Node2D = $"../CharacterContainer"

# ============================================================================
# ESTADO
# ============================================================================
var playback: AnimationNodeStateMachinePlayback = null

var _player_near: bool = false
var _state_locked: bool = false
var _locked_facing_right: bool = true
var _base_scale: Vector2 = Vector2.ONE
var _is_attacking: bool = false

signal attack_finished
signal attack_hit(attack_type: String)


# ============================================================================
# READY
# ============================================================================
func _ready() -> void:
	if character_container:
		_refresh_base_scale()

	if Engine.is_editor_hint():
		set_process(false)
		return

# ============================================================================
# INIT
# ============================================================================
func initialize(_owner_npc: CharacterBody2D, facing_right: bool = true) -> void:
	if character_container:
		_refresh_base_scale()

	if anim_tree:
		anim_tree.active = true
		playback = anim_tree["parameters/playback"]

	if playback:
		playback.travel(initial_state)

	_apply_facing(facing_right)

# ============================================================================
# UPDATE
# ============================================================================
func update_service(_delta: float, player: Node2D, player_in_range: bool) -> void:
	if use_counter_behavior and not _state_locked:
		_update_counter_state(player_in_range)

	_update_walk_state()
	_update_body_flip(player, player_in_range)

func _update_walk_state() -> void:
	if playback == null or _state_locked:
		return

	var movement := npc.get_node_or_null("Movement") as NPCClientMovement
	if not movement:
		return

	# Si está frozen, forzar Idle siempre
	if movement.is_frozen:
		var frozen_current: String = playback.get_current_node()
		if frozen_current != "Idle":
			playback.start("Idle")
		return

	var is_moving: bool = movement.is_moving()
	var current: String = playback.get_current_node()

	if is_moving and current != "Walk":
		playback.start("Walk")
	elif not is_moving and current != "Idle":
		playback.start("Idle")

# ============================================================================
# EDITOR PREVIEW
# ============================================================================
func preview_facing(facing_right: bool) -> void:
	if character_container == null:
		return

	_refresh_base_scale()
	_apply_facing(facing_right)

# ============================================================================
# API
# ============================================================================
func force_idle_counter() -> void:
	_player_near = false
	if playback:
		playback.travel("Idle")

func lock_facing(facing_right: bool) -> void:
	_state_locked = true
	_locked_facing_right = facing_right
	_apply_facing(facing_right)
	# Forzar Idle al bloquear — evita que la animación de walk quede activa
	if playback:
		playback.start("Idle")

func unlock_facing() -> void:
	_state_locked = false

func play_attack(attack_type: String = "Kick") -> void:
	if not playback:
		attack_finished.emit()
		return

	_is_attacking = true
	_state_locked = true
	playback.travel(attack_type)

	# Esperar específicamente a que termine "Kick" o "Slap"
	var anim_player: AnimationPlayer = npc.get_node_or_null("AnimationPlayer")
	if anim_player:
		var finished: String = ""
		while finished != attack_type:
			finished = await anim_player.animation_finished

	_is_attacking = false
	_state_locked = false
	attack_finished.emit()

# ============================================================================
# COUNTER STATE
# ============================================================================
func _update_counter_state(player_in_range: bool) -> void:
	if playback == null:
		return

	if player_in_range == _player_near:
		return

	_player_near = player_in_range

	if _player_near:
		playback.travel("Idle")
	else:
		playback.travel("Idle_Counter")

# ============================================================================
# BODY FLIP
# ============================================================================
func _update_body_flip(player: Node2D, player_in_range: bool) -> void:
	if not flip_body_with_player:
		return
	if not character_container:
		return

	if _state_locked:
		_apply_facing(_locked_facing_right)
		return

	# En modo wander — girar según dirección de movimiento
	var movement := npc.get_node_or_null("Movement") as NPCClientMovement
	if movement and movement.is_following() == false and movement.is_moving():
		_apply_facing(movement.get_facing_right())
		return

	# Fuera de rango del player — no actualizar facing
	if face_player_only_when_in_range and not player_in_range:
		return

	if is_instance_valid(player):
		_apply_facing(player.global_position.x > npc.global_position.x)

# ============================================================================
# HELPERS
# ============================================================================
func _emit_attack_hit(attack_type: String) -> void:
	attack_hit.emit(attack_type)

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
