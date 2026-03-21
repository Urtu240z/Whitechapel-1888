extends Area2D
class_name NPCConversation

signal conversation_started(with)
signal conversation_ended(with)

@export_range(0.0, 1.0) var conversation_chance: float = 0.4
@export_range(0.0, 1.0) var continue_conversation_chance: float = 0.65
@export var pause_between_turns_min: float = 0.3
@export var pause_between_turns_max: float = 1.0

@onready var movement: NPCMovement = $"../Movement"
@onready var animation: NPCAnimation = $"../Animation"

var active: bool = false
var partner: CharacterBody2D = null
var is_talking: bool = false
var is_listening: bool = false


func _ready() -> void:
	body_entered.connect(_on_area_body_entered)
	body_exited.connect(_on_area_body_exited)


func _on_area_body_entered(body: Node) -> void:
	if body == get_parent():
		return
	
	# Si es el player, lo guardamos como referencia pero no iniciamos conversación NPC
	if body is MainPlayer:
		return  # el player_interaction.gd se encarga de iniciar el diálogo
	
	if not (body is CharacterBody2D):
		return
	if not body.has_node("Conversation"):
		return
	# ... resto igual

	var other_convo: NPCConversation = body.get_node("Conversation")
	if not other_convo or other_convo.active or active:
		return
	if randf() > conversation_chance:
		return

	active = true
	other_convo.active = true
	partner = body
	other_convo.partner = get_parent()

	# Parar movimiento total
	movement.freeze()
	body.get_node("Movement").freeze()

	# --- Orientarse ---
	var facing_right: bool = body.global_position.x > get_parent().global_position.x
	var anim_a: NPCAnimation = animation
	var anim_b: NPCAnimation = body.get_node("Animation")

	anim_a.lock_facing(facing_right)
	anim_b.lock_facing(!facing_right)

	# --- Quién empieza ---
	if randf() < 0.5:
		_start_talking()
	else:
		other_convo._start_talking()


func _on_area_body_exited(body: Node) -> void:
	if body == partner:
		_end_conversation()


func _start_talking() -> void:
	if not partner or not partner.is_inside_tree():
		_end_conversation()
		return
	is_talking = true
	is_listening = false
	var other_convo: NPCConversation = partner.get_node("Conversation")
	other_convo.is_talking = false
	other_convo.is_listening = true

	emit_signal("conversation_started", partner)
	animation.play_talk(_on_talk_finished)


func _on_talk_finished() -> void:
	if not partner or not partner.is_inside_tree():
		_end_conversation()
		return
	is_talking = false
	is_listening = false
	animation.stop_talk()

	var other_convo: NPCConversation = partner.get_node("Conversation")
	if randf() < continue_conversation_chance:
		var pause: float = randf_range(pause_between_turns_min, pause_between_turns_max)
		await get_tree().create_timer(pause).timeout
		other_convo._start_talking()
	else:
		_end_conversation()


func _end_conversation() -> void:
	if not active:
		return
	active = false
	is_talking = false
	is_listening = false
	animation.stop_talk()
	movement.unfreeze()
	animation.unlock_facing()

	if partner and partner.is_inside_tree():
		var other_convo: NPCConversation = partner.get_node("Conversation")
		other_convo.active = false
		other_convo.is_talking = false
		other_convo.is_listening = false
		other_convo.movement.unfreeze()
		other_convo.animation.unlock_facing()
		other_convo.partner = null

	emit_signal("conversation_ended", partner)
	partner = null
