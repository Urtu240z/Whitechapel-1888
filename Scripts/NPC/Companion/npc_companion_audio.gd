extends Node
class_name NPCCompanionAudio

# ============================================================================
# NPC COMPANION AUDIO
# Pasos según superficie detectada por SurfaceRay (RayCast2D hijo de Audio).
# Audio de conversación via Talk (AudioStreamPlayer2D).
# ============================================================================

# ============================================================================
# CONFIG
# ============================================================================
@export var step_sounds: Dictionary = {
	"stone": [],
	"wood":  [],
	"dirt":  [],
	"grass": [],
	"water": [],
}
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

# ============================================================================
# REFERENCIAS
# ============================================================================
@onready var step_player: AudioStreamPlayer2D = $StepPlayer
@onready var talk_player: AudioStreamPlayer2D = $Talk
@onready var surface_ray: RayCast2D = $SurfaceRay

# ============================================================================
# SUPERFICIE
# ============================================================================
const SURFACE_DEFAULT := "stone"
const VALID_SURFACES := ["stone", "wood", "dirt", "grass", "water"]

var current_surface: String = SURFACE_DEFAULT
var _companion: CharacterBody2D = null

# ============================================================================
# INIT
# ============================================================================
func initialize(owner_npc: CharacterBody2D) -> void:
	_companion = owner_npc
	if surface_ray:
		surface_ray.add_exception(owner_npc)
	_apply_audio_settings()

# ============================================================================
# PROCESS — detección de superficie
# ============================================================================
func _process(_delta: float) -> void:
	_update_surface()

func _update_surface() -> void:
	if not surface_ray or not surface_ray.is_colliding():
		return

	var collider = surface_ray.get_collider()
	if not collider:
		return

	var detected := SURFACE_DEFAULT

	if collider is TileMapLayer or collider is TileMap:
		var tile_pos: Vector2i = collider.local_to_map(
			collider.to_local(surface_ray.get_collision_point())
		)
		var tile_data: TileData = collider.get_cell_tile_data(0, tile_pos)
		if tile_data:
			var surface = tile_data.get_custom_data("surface_type")
			if surface != "":
				detected = surface
	elif collider.has_meta("surface_type"):
		detected = collider.get_meta("surface_type")

	if detected in VALID_SURFACES:
		current_surface = detected

# ============================================================================
# API
# ============================================================================
func play_step() -> void:
	if not step_player:
		return
	if _companion and not _companion.is_on_floor():
		return

	var sounds: Array = step_sounds.get(current_surface, [])
	if sounds.is_empty():
		sounds = step_sounds.get(SURFACE_DEFAULT, [])
	if sounds.is_empty():
		return

	step_player.stream = sounds.pick_random()
	step_player.volume_db = step_volume_db
	step_player.pitch_scale = randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	step_player.play()

# Acepta un argumento opcional porque la pista de animación
# puede estar llamándolo con 1 parámetro.
func play_random_step(_run: bool = false) -> void:
	play_step()

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
	if talk_player:
		if talk_stream:
			talk_player.stream = talk_stream
		talk_player.volume_db = talk_volume_db
