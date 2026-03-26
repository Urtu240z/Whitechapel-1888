extends Node

var thomas: ThomasController = null

@onready var character_container: Node2D = $"../CharacterContainer"
@onready var animation_tree: AnimationTree = $"../AnimationTree"

var playback: AnimationNodeStateMachinePlayback = null
var current_state: String = ""

func initialize(owner_node: ThomasController) -> void:
	thomas = owner_node

	if animation_tree:
		animation_tree.active = true
		playback = animation_tree.get("parameters/playback")

		if playback:
			current_state = "Idle"
			playback.travel(current_state)

	apply_facing()

func update_animation() -> void:
	if not thomas:
		return

	apply_facing()

	var next_state: String = "Idle"
	if thomas.is_walking():
		next_state = "Walk"

	if next_state != current_state and playback:
		current_state = next_state
		playback.travel(current_state)

func apply_facing() -> void:
	if not thomas or not character_container:
		return

	character_container.scale.x = 1.0 if thomas.facing_right else -1.0
