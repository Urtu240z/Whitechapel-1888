class_name NPCAudio
extends Node

@export var step_sounds: Array[AudioStream] = []
@export var talk_stream: AudioStream

@export var step_volume_db: float = -6.0:
	set(value):
		step_volume_db = value
		if step_player:
			step_player.volume_db = value

@export var talk_volume_db: float = -4.0:
	set(value):
		talk_volume_db = value
		if talk_player:
			talk_player.volume_db = value

@export var pitch_variation: float = 0.1
@export var positional: bool = true

@onready var step_player: AudioStreamPlayer2D = $StepPlayer
@onready var talk_player: AudioStreamPlayer2D = $Talk

func _ready() -> void:
	# Configuración inicial
	_apply_audio_settings()

func _apply_audio_settings() -> void:
	if step_player:
		step_player.volume_db = step_volume_db
		step_player.attenuation = 1.0 if positional else 0.0
	if talk_player:
		talk_player.stream = talk_stream
		talk_player.volume_db = talk_volume_db
		talk_player.attenuation = 1.0 if positional else 0.0

func play_step() -> void:
	if step_sounds.is_empty():
		return
	var sound = step_sounds.pick_random()
	step_player.stream = sound
	step_player.volume_db = step_volume_db
	step_player.pitch_scale = randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	step_player.play()

func play_talk() -> void:
	if not talk_player:
		return
	talk_player.volume_db = talk_volume_db
	talk_player.pitch_scale = randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	if not talk_player.playing:
		talk_player.play()

func stop_talk() -> void:
	if talk_player and talk_player.playing:
		talk_player.stop()

func set_talking(value: bool) -> void:
	if value:
		play_talk()
	else:
		stop_talk()
