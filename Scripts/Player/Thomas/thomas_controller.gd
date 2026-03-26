extends CharacterBody2D
class_name ThomasController

# ============================================================
# THOMAS CONTROLLER
# Thomas controlado por escena:
# - gravedad
# - caminar a un punto
# - parar
# - mirar a izquierda/derecha
# - patrulla aleatoria horizontal
# ============================================================

# ============================================================
# AJUSTES
# ============================================================
@export_group("Movement")
@export var walk_speed: float = 90.0
@export var acceleration: float = 700.0
@export var friction: float = 900.0
@export var arrive_distance: float = 6.0

@export_group("Gravity")
@export var gravity_scale: float = 1.0

@export_group("Random Wander")
@export var random_wander_enabled: bool = true
@export var wander_min_x: float = -300.0
@export var wander_max_x: float = 300.0
@export var wander_wait_min: float = 1.0
@export var wander_wait_max: float = 3.0

# ============================================================
# REFERENCIAS
# ============================================================
@onready var animation_module = $Animation
@onready var audio_module = $Audio

# ============================================================
# ESTADO
# ============================================================
var enabled: bool = true
var target_position_x: float = 0.0
var has_target: bool = false
var facing_right: bool = true

var _wander_origin_x: float = 0.0
var _wander_wait_timer: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

func _ready() -> void:
	_wander_origin_x = global_position.x
	target_position_x = global_position.x

	if animation_module and animation_module.has_method("initialize"):
		animation_module.initialize(self)
	if audio_module and audio_module.has_method("initialize"):
		audio_module.initialize(self)

	_reset_wander_timer()

func _physics_process(delta: float) -> void:
	if not enabled:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		_apply_gravity(delta)
		move_and_slide()
		_update_modules()
		return

	# ------------------------------------------------------------
	# MOVIMIENTO HORIZONTAL
	# ------------------------------------------------------------
	if has_target:
		var distance: float = target_position_x - global_position.x

		if absf(distance) <= arrive_distance:
			has_target = false
			velocity.x = move_toward(velocity.x, 0.0, friction * delta)
			_reset_wander_timer()
		else:
			var dir: float = signf(distance)
			velocity.x = move_toward(velocity.x, dir * walk_speed, acceleration * delta)
			facing_right = dir > 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

		if random_wander_enabled:
			_wander_wait_timer -= delta
			if _wander_wait_timer <= 0.0:
				_pick_random_wander_target()

	# ------------------------------------------------------------
	# GRAVEDAD
	# ------------------------------------------------------------
	_apply_gravity(delta)

	move_and_slide()
	_update_modules()

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += _gravity * gravity_scale * delta
	else:
		if velocity.y > 0.0:
			velocity.y = 0.0

func _update_modules() -> void:
	if animation_module and animation_module.has_method("update_animation"):
		animation_module.update_animation()
	if audio_module and audio_module.has_method("update_audio"):
		audio_module.update_audio()

# ============================================================
# RANDOM WANDER
# ============================================================
func _pick_random_wander_target() -> void:
	var min_x: float = _wander_origin_x + wander_min_x
	var max_x: float = _wander_origin_x + wander_max_x
	var new_target: float = randf_range(min_x, max_x)
	walk_to_x(new_target)

func _reset_wander_timer() -> void:
	_wander_wait_timer = randf_range(wander_wait_min, wander_wait_max)

# ============================================================
# API DE ESCENA / CINEMÁTICA
# ============================================================
func walk_to_x(world_x: float) -> void:
	target_position_x = world_x
	has_target = true

func walk_to_node(node: Node2D) -> void:
	if not is_instance_valid(node):
		return
	walk_to_x(node.global_position.x)

func stop() -> void:
	has_target = false
	velocity.x = 0.0
	_reset_wander_timer()

func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled:
		stop()

func face_left() -> void:
	facing_right = false
	has_target = false
	velocity.x = 0.0
	if animation_module and animation_module.has_method("apply_facing"):
		animation_module.apply_facing()

func face_right() -> void:
	facing_right = true
	has_target = false
	velocity.x = 0.0
	if animation_module and animation_module.has_method("apply_facing"):
		animation_module.apply_facing()

func is_walking() -> bool:
	return absf(velocity.x) > 5.0

func wait_until_arrived() -> void:
	while has_target:
		await get_tree().physics_frame
