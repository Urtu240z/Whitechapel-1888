extends Node
class_name NPCServiceAudio

# ============================================================================
# NPC SERVICE AUDIO
# Audio sencillo para NPCs de servicio.
# Preparado para voz / pasos / pequeños sonidos si más adelante los necesitas.
# ============================================================================

# ============================================================================
# CONFIG
# ============================================================================
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

@export var pitch_variation: float = 0.08
@export var positional: bool = true

# ============================================================================
# REFERENCIAS
# ============================================================================
@onready var step_player: AudioStreamPlayer2D = $StepPlayer
@onready var talk_player: AudioStreamPlayer2D = $Talk

# ============================================================================
# INIT
# ============================================================================
func initialize(_owner_npc: CharacterBody2D) -> void:
	_apply_audio_settings()

# ============================================================================
# API
# ============================================================================
func play_step() -> void:
	if not step_player or step_sounds.is_empty():
		return

	step_player.stream = step_sounds.pick_random()
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

# ============================================================================
# HELPERS
# ============================================================================
func _apply_audio_settings() -> void:
	if step_player:
		step_player.volume_db = step_volume_db
		step_player.attenuation = 1.0 if positional else 0.0

	if talk_player:
		talk_player.stream = talk_stream
		talk_player.volume_db = talk_volume_db
		talk_player.attenuation = 1.0 if positional else 0.0
