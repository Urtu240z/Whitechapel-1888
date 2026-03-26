extends Node

# ============================================================
# THOMAS AUDIO
# Audio mínimo: solo pasos mientras camina
# ============================================================

var thomas: ThomasController = null

@onready var step_player: AudioStreamPlayer2D = $StepPlayer

@export var step_interval: float = 0.42
@export var min_speed_for_steps: float = 10.0

var _step_timer: float = 0.0

func initialize(owner_node: ThomasController) -> void:
	thomas = owner_node

func update_audio() -> void:
	if not thomas or not step_player:
		return

	var delta := get_physics_process_delta_time()
	var speed: float = absf(thomas.velocity.x)

	if speed >= min_speed_for_steps:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_play_step()
			_step_timer = step_interval
	else:
		_step_timer = 0.0

func _play_step() -> void:
	if not step_player.stream:
		return

	step_player.pitch_scale = randf_range(0.96, 1.04)
	step_player.volume_db = randf_range(-4.0, -2.0)
	step_player.play()
