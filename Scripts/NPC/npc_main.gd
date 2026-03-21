extends CharacterBody2D
class_name NPC

# ===============================
# 🎛️ GLOBAL CONFIGURATION
# ===============================
@export_category("⚙️ NPC Configuration")
@export var personalize: bool = false  # If disabled, NPC will randomize its own stats

# --- Movement ---
@export_subgroup("🏃 Movement")
@export_range(50, 200, 1, "suffix:px/s") var move_speed: float = 60.0
@export_range(100, 300, 1) var acceleration: float = 200.0
@export_range(100, 300, 1) var friction: float = 150.0
@export_range(0.5, 5.0, 0.1) var wait_time_min: float = 1.0
@export_range(0.5, 5.0, 0.1) var wait_time_max: float = 3.0
@export_range(1.0, 6.0, 0.1) var move_time_min: float = 1.5
@export_range(1.0, 6.0, 0.1) var move_time_max: float = 4.0

# --- Conversation ---
@export_subgroup("💬 Conversation")
@export_range(0.0, 1.0, 0.01) var conversation_chance: float = 0.4
@export_range(0.0, 1.0, 0.01) var continue_conversation_chance: float = 0.65
@export_range(0.1, 2.0, 0.1) var pause_between_turns_min: float = 0.3
@export_range(0.1, 2.0, 0.1) var pause_between_turns_max: float = 1.0

# --- Dialog ---
@export_subgroup("🗣️ Dialog")
@export_file("*.dtl") var dialog_timeline: String = ""

# --- Animation ---
@export_subgroup("🎬 Animation")
@export var move_threshold: float = 10.0

# --- Audio ---
@export_subgroup("🔊 Audio")
@export var step_sounds: Array[AudioStream] = []
@export var talk_stream: AudioStream
@export var step_volume_db: float = -6.0
@export var talk_volume_db: float = -4.0
@export var pitch_variation: float = 0.1
@export var positional_sound: bool = true


# ===============================
# 🔗 MODULE REFERENCES
# ===============================
@onready var movement: NPCMovement = $Movement
@onready var animation: NPCAnimation = $Animation
@onready var conversation: NPCConversation = $Conversation
@onready var audio: NPCAudio = $Audio


# ===============================
# ⚙️ INITIALIZATION
# ===============================
func _ready() -> void:
	randomize()

	# Randomize stats if not customized
	if not personalize:
		_apply_random_values()

	# Apply settings to submodules
	movement.speed = move_speed
	movement.acceleration = acceleration
	movement.friction = friction
	movement.wait_time_min = wait_time_min
	movement.wait_time_max = wait_time_max
	movement.move_time_min = move_time_min
	movement.move_time_max = move_time_max

	animation.move_threshold = move_threshold

	conversation.conversation_chance = conversation_chance
	conversation.continue_conversation_chance = continue_conversation_chance
	conversation.pause_between_turns_min = pause_between_turns_min
	conversation.pause_between_turns_max = pause_between_turns_max

	audio.step_sounds = step_sounds
	audio.talk_stream = talk_stream
	audio.step_volume_db = step_volume_db
	audio.talk_volume_db = talk_volume_db
	audio.pitch_variation = pitch_variation
	audio.positional = positional_sound

	conversation.conversation_started.connect(_on_conversation_started)
	conversation.conversation_ended.connect(_on_conversation_ended)


# ===============================
# 🔁 MAIN LOOP
# ===============================
func _physics_process(delta: float) -> void:
	movement.update_movement(delta)
	animation.update_animation(self)


# ===============================
# 💬 CONVERSATION EVENTS
# ===============================
func _on_conversation_started(_with):
	audio.play_talk()
	animation.play_talk()

func _on_conversation_ended(_with):
	audio.stop_talk()
	animation.stop_talk()


# ===============================
# 🎲 RANDOM STATS GENERATOR
# ===============================
func _apply_random_values() -> void:
	move_speed = randf_range(50.0, 200.0)
	acceleration = randf_range(150.0, 250.0)
	friction = randf_range(100.0, 250.0)
	wait_time_min = randf_range(0.5, 1.5)
	wait_time_max = randf_range(2.0, 4.0)
	move_time_min = randf_range(1.0, 3.0)
	move_time_max = randf_range(2.0, 5.0)

	conversation_chance = randf_range(0.2, 0.6)
	continue_conversation_chance = randf_range(0.5, 0.8)
	pause_between_turns_min = randf_range(0.3, 0.7)
	pause_between_turns_max = randf_range(0.7, 1.5)
