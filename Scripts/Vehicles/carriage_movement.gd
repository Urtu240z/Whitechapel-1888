extends Node2D
class_name CarMovement

# ===============================
# 🚗 CONFIGURATION
# ===============================
@export var speed_min: float = 50.0
@export var speed_max: float = 150.0
@export var wait_min: float = 1.0
@export var wait_max: float = 3.0
@export var flip_sprite: bool = true
@export var draw_path_in_editor: bool = true

# Optional: names of nodes placed in the main scene
@export var start_point_name: String = "StartPoint_A"
@export var end_point_name: String = "EndPoint_A"

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var sprite_root: Node2D = $Sprites

var start_point: Node2D
var end_point: Node2D

var _speed: float = 0.0
var _waiting: bool = false
var _source: Vector2
var _target: Vector2
var _dir: Vector2 = Vector2.ZERO
var _base_sprite_scale_x: float = 1.0

# ===============================
# ⚙️ INITIALIZATION
# ===============================
func _ready() -> void:
	randomize()

	# 🔍 Find points in the parent or main scene
	start_point = get_tree().get_root().find_child(start_point_name, true, false)
	end_point = get_tree().get_root().find_child(end_point_name, true, false)

	if not start_point or not end_point:
		push_warning("❌ StartPoint or EndPoint not found in the scene.")
		return

	# Store their global positions
	_source = start_point.global_position
	_target = end_point.global_position

	# ✅ Keep the current editor position! (don't override it)
	# Just decide direction based on which point is to the right.
	var dist_to_start = global_position.distance_to(_source)
	var dist_to_end = global_position.distance_to(_target)

	if dist_to_end > dist_to_start:
		_target = _source
	else:
		_target = _target  # Go toward EndPoint if placed closer to Start

	_set_direction_to(_target)
	_speed = randf_range(speed_min, speed_max)

	if sprite_root:
		_base_sprite_scale_x = sprite_root.scale.x

	if animation_player and animation_player.has_animation("Run"):
		animation_player.play("Run")

	queue_redraw()

# ===============================
# 🔁 MAIN LOOP
# ===============================
func _process(delta: float) -> void:
	if _waiting or not start_point or not end_point:
		return

	var to_target: Vector2 = _target - global_position
	var step_dist: float = _speed * delta

	# If we reached the target (or passed it slightly)
	if to_target.length() <= step_dist:
		global_position = _target
		await _turn_around()
		return

	global_position += _dir * step_dist

# ===============================
# 🔄 TURN AROUND & WAIT
# ===============================
func _turn_around() -> void:
	_waiting = true
	await get_tree().create_timer(randf_range(wait_min, wait_max)).timeout

	# Swap direction between points
	var prev_target := _target
	_target = _source
	_source = prev_target
	_set_direction_to(_target)
	_speed = randf_range(speed_min, speed_max)
	_waiting = false

# ===============================
# 🧭 DIRECTION / FLIP
# ===============================
func _set_direction_to(target_pos: Vector2) -> void:
	_dir = (target_pos - global_position).normalized() if target_pos != global_position else Vector2.RIGHT
	if flip_sprite and sprite_root:
		if abs(_dir.x) > 0.0001:
			sprite_root.scale.x = sign(_dir.x) * abs(_base_sprite_scale_x)

# ===============================
# 🎨 DEBUG LINE
# ===============================
func _draw() -> void:
	if not draw_path_in_editor or not start_point or not end_point:
		return
	draw_line(to_local(start_point.global_position), to_local(end_point.global_position), Color(1, 1, 0, 0.9), 2.0)
