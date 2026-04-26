extends Node
class_name NPCAudioComponent

# ============================================================================
# NPC AUDIO COMPONENT
# ============================================================================
# Componente común para NPCClient, NPCCompanion y NPCService.
#
# Responsabilidad:
# - pasos simples
# - pasos por superficie si existe SurfaceRay
# - sonido de hablar
#
# Sin fallbacks legacy:
# - los NPCs deben tipar audio como NPCAudioComponent
# - los scripts viejos npc_client_audio / npc_companion_audio / npc_service_audio
#   se pueden archivar después de cambiar las escenas.
# ============================================================================

# ============================================================================
# CONFIG — PASOS
# ============================================================================
@export_group("Steps")
@export var use_surface_detection: bool = false
@export var require_on_floor_for_steps: bool = false

@export var step_sounds: Array[AudioStream] = []

@export var surface_step_sounds: Dictionary = {
	"stone": [],
	"wood": [],
	"dirt": [],
	"grass": [],
	"water": [],
}

@export var surface_default: String = "stone"

@export var step_volume_db: float = -6.0:
	set(value):
		step_volume_db = value
		if step_player:
			step_player.volume_db = value

# ============================================================================
# CONFIG — VOZ / HABLAR
# ============================================================================
@export_group("Talk")
@export var talk_stream: AudioStream

@export var talk_volume_db: float = -4.0:
	set(value):
		talk_volume_db = value
		if talk_player:
			talk_player.volume_db = value

# ============================================================================
# CONFIG — GENERAL
# ============================================================================
@export_group("General")
@export var pitch_variation: float = 0.08
@export var positional: bool = true

# ============================================================================
# REFERENCIAS
# ============================================================================
@onready var step_player: AudioStreamPlayer2D = get_node_or_null("StepPlayer")
@onready var talk_player: AudioStreamPlayer2D = get_node_or_null("Talk")
@onready var surface_ray: RayCast2D = get_node_or_null("SurfaceRay")

const VALID_SURFACES: Array[String] = ["stone", "wood", "dirt", "grass", "water"]

var current_surface: String = "stone"
var _owner_npc: CharacterBody2D = null


# ============================================================================
# INIT
# ============================================================================
func initialize(owner_npc: CharacterBody2D) -> void:
	if owner_npc == null:
		push_error("NPCAudioComponent.initialize(): owner_npc es null.")
		return

	_owner_npc = owner_npc
	current_surface = surface_default

	if use_surface_detection:
		if surface_ray == null:
			push_error("NPCAudioComponent '%s': use_surface_detection=true pero no existe SurfaceRay." % name)
		else:
			surface_ray.add_exception(owner_npc)

	_apply_audio_settings()


# ============================================================================
# PROCESS
# ============================================================================
func _process(_delta: float) -> void:
	if use_surface_detection:
		_update_surface()


# ============================================================================
# API — PASOS
# ============================================================================
func play_step(_run: bool = false) -> void:
	if step_player == null:
		push_error("NPCAudioComponent '%s': falta nodo StepPlayer." % name)
		return

	if require_on_floor_for_steps:
		if _owner_npc == null:
			push_error("NPCAudioComponent '%s': require_on_floor_for_steps=true pero owner_npc es null." % name)
			return

		if not _owner_npc.is_on_floor():
			return

	var selected_sound := _pick_step_sound()
	if selected_sound == null:
		return

	step_player.stream = selected_sound
	step_player.volume_db = step_volume_db
	step_player.pitch_scale = randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	step_player.play()


func play_random_step(_run: bool = false) -> void:
	# Alias para AnimationPlayer/AnimationTree que llamen a este método.
	play_step(_run)


# ============================================================================
# API — TALK
# ============================================================================
func play_talk() -> void:
	if talk_player == null:
		push_error("NPCAudioComponent '%s': falta nodo Talk." % name)
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
# SUPERFICIES
# ============================================================================
func _update_surface() -> void:
	if surface_ray == null:
		return

	if not surface_ray.is_colliding():
		return

	var collider = surface_ray.get_collider()
	if collider == null:
		return

	var detected := surface_default

	if collider is TileMapLayer:
		var tile_pos: Vector2i = collider.local_to_map(
			collider.to_local(surface_ray.get_collision_point())
		)

		var tile_data: TileData = collider.get_cell_tile_data(tile_pos)
		if tile_data:
			var surface = tile_data.get_custom_data("surface_type")
			if surface != null and str(surface) != "":
				detected = str(surface)

	elif collider is TileMap:
		var tile_pos_old: Vector2i = collider.local_to_map(
			collider.to_local(surface_ray.get_collision_point())
		)

		var tile_data_old: TileData = collider.get_cell_tile_data(0, tile_pos_old)
		if tile_data_old:
			var surface_old = tile_data_old.get_custom_data("surface_type")
			if surface_old != null and str(surface_old) != "":
				detected = str(surface_old)

	elif collider.has_meta("surface_type"):
		detected = str(collider.get_meta("surface_type"))

	if detected in VALID_SURFACES:
		current_surface = detected


func _pick_step_sound() -> AudioStream:
	if use_surface_detection:
		var sounds: Array = surface_step_sounds.get(current_surface, [])

		if sounds.is_empty():
			sounds = surface_step_sounds.get(surface_default, [])

		if sounds.is_empty():
			return null

		return sounds.pick_random() as AudioStream

	if step_sounds.is_empty():
		return null

	return step_sounds.pick_random()


# ============================================================================
# HELPERS
# ============================================================================
func _apply_audio_settings() -> void:
	if step_player:
		step_player.volume_db = step_volume_db
		step_player.attenuation = 1.0 if positional else 0.0

	if talk_player:
		if talk_stream:
			talk_player.stream = talk_stream

		talk_player.volume_db = talk_volume_db
		talk_player.attenuation = 1.0 if positional else 0.0
