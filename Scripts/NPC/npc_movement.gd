class_name NPCMovement
extends Node

@export var speed: float = 60.0
@export var acceleration: float = 200.0
@export var friction: float = 150.0
@export var wait_time_min: float = 1.0
@export var wait_time_max: float = 3.0
@export var move_time_min: float = 1.5
@export var move_time_max: float = 4.0

var direction := Vector2.ZERO
var velocity := Vector2.ZERO
var current_speed: float = 0.0
var move_timer: float = 0.0
var wait_timer: float = 0.0
var is_waiting: bool = false
var is_frozen: bool = false   # 💡 nuevo flag: bloquea movimiento totalmente

func _ready() -> void:
	_choose_new_direction()

func update_movement(delta: float) -> void:
	var npc := get_parent() as CharacterBody2D
	if not npc or is_frozen:
		npc.velocity = Vector2.ZERO
		return

	if is_waiting:
		wait_timer -= delta
		if wait_timer <= 0.0:
			is_waiting = false
			_choose_new_direction()
		_apply_velocity(npc, delta)
		return

	move_timer -= delta
	if move_timer <= 0.0:
		_start_waiting()
	else:
		current_speed = move_toward(current_speed, speed, acceleration * delta)
		velocity = direction * current_speed

	_apply_velocity(npc, delta)

func _apply_velocity(npc: CharacterBody2D, delta: float) -> void:
	if is_waiting:
		current_speed = move_toward(current_speed, 0.0, friction * delta)
	velocity = direction * current_speed
	npc.velocity = velocity
	npc.move_and_slide()

func _choose_new_direction() -> void:
	if randf() < 0.3:
		_start_waiting()
	else:
		direction = Vector2(1, 0) if randf() < 0.5 else Vector2(-1, 0)
		move_timer = randf_range(move_time_min, move_time_max)

func _start_waiting() -> void:
	is_waiting = true
	wait_timer = randf_range(wait_time_min, wait_time_max)
	current_speed = 0.0
	direction = Vector2.ZERO

# ---------------- Bloqueo / desbloqueo ---------------- #
func freeze() -> void:
	is_frozen = true
	current_speed = 0.0
	direction = Vector2.ZERO

func unfreeze() -> void:
	is_frozen = false
	_choose_new_direction()
