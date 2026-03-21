class_name NPCAnimation
extends Node

@export var move_threshold: float = 10.0

@onready var anim_tree: AnimationTree = $"../AnimationTree"
@onready var visual_node: Node2D = $"../CharacterContainer"

var state_machine
var right: bool = true
var last_state: String = "Idle"
var is_talking: bool = false
var on_talk_finished_callback: Callable = Callable()

# 🔒 Nuevo: control de bloqueo de dirección
var lock_direction: bool = false
var locked_right: bool = true


func _ready() -> void:
	if anim_tree:
		state_machine = anim_tree["parameters/playback"]
		state_machine.travel("Idle")


func update_animation(npc: CharacterBody2D) -> void:
	if not anim_tree:
		return
	if is_talking:
		return  # no cambiar anim mientras habla

	var speed_abs: float = abs(npc.velocity.x)
	var moving: bool = speed_abs > move_threshold

	# --- Dirección ---
	if not lock_direction:
		if npc.velocity.x > 0.0:
			right = true
		elif npc.velocity.x < 0.0:
			right = false
	else:
		right = locked_right

	# --- Flip visual ---
	if visual_node:
		visual_node.scale.x = 1.0 if right else -1.0

	# --- Estado ---
	var desired_state: String = "Walk" if moving else "Idle"
	if desired_state != last_state:
		state_machine.travel(desired_state)
		last_state = desired_state


func play_talk(callback: Callable = Callable()) -> void:
	is_talking = true
	on_talk_finished_callback = callback
	var talk_anim: String = "Talk_1" if randf() < 0.5 else "Talk_2"
	state_machine.travel(talk_anim)
	last_state = talk_anim

	# 🔊 Avisar al módulo de audio
	var npc = get_parent() as CharacterBody2D
	if npc and npc.has_node("Audio"):
		var audio = npc.get_node("Audio")
		if audio.has_method("set_talking"):
			audio.set_talking(true)

	# Esperar a que acabe la animación
	var player_path: NodePath = anim_tree.anim_player
	if player_path and anim_tree.has_node(player_path):
		var player: AnimationPlayer = anim_tree.get_node(player_path)
		if player.has_animation(talk_anim):
			var duration: float = player.get_animation(talk_anim).length
			await get_tree().create_timer(duration).timeout
			_on_talk_finished()


func stop_talk() -> void:
	is_talking = false
	state_machine.travel("Idle")
	last_state = "Idle"


func _on_talk_finished() -> void:
	is_talking = false
	var npc = get_parent() as CharacterBody2D
	if npc and npc.has_node("Audio"):
		var audio = npc.get_node("Audio")
		if audio.has_method("set_talking"):
			audio.set_talking(false)

	if on_talk_finished_callback.is_valid():
		on_talk_finished_callback.call()
	on_talk_finished_callback = Callable()


# --- 🔒 Control de orientación durante conversación ---
func lock_facing(facing_right: bool) -> void:
	lock_direction = true
	locked_right = facing_right
	if visual_node:
		visual_node.scale.x = 1.0 if facing_right else -1.0

func unlock_facing() -> void:
	lock_direction = false
