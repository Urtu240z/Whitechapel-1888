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

	_update_body_flip(player, player_in_range)

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

func unlock_facing() -> void:
	_state_locked = false

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
	if not is_instance_valid(player):
		return
	if not character_container:
			return

	if face_player_only_when_in_range and not player_in_range and not _state_locked:
		return

	var face_right: bool = _locked_facing_right

	if not _state_locked:
		face_right = player.global_position.x > npc.global_position.x

	_apply_facing(face_right)

# ============================================================================
# HELPERS
# ============================================================================
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
