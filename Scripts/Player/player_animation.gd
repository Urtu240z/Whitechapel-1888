extends Node
# ==========================
# ANIMATION MODULE
# ==========================

# ==========================
# REFERENCES
# ==========================
var player: MainPlayer = null
var movement_module: Node = null

@onready var anim_tree: AnimationTree = null
@onready var anim_player: AnimationPlayer = null
@onready var sprite_container: Node2D = null
var shadow: Node2D = null

# ==========================
# STATE
# ==========================
var state_machine: AnimationNodeStateMachinePlayback = null
var last_state: String = ""

# ==========================
# SHADOW SETTINGS
# ==========================
@export var shadow_max_height: float = 200.0  # altura máxima antes de desaparecer
@export var shadow_base_offset: float = 96.0  # distancia origen→suelo en reposo (medir en editor)

# ==========================
# INIT
# ==========================
func initialize(p: MainPlayer) -> void:
	player = p
	_get_references()
	if anim_tree:
		state_machine = anim_tree["parameters/playback"]
		state_machine.travel("Idle")
		last_state = "Idle"

func _get_references() -> void:
	if player.has_node("AnimationTree"):
		anim_tree = player.get_node("AnimationTree")
	if player.has_node("AnimationPlayer"):
		anim_player = player.get_node("AnimationPlayer")
	if player.has_node("CharacterContainer"):
		sprite_container = player.get_node("CharacterContainer")
	if player.has_node("Shadow"):
		shadow = player.get_node("Shadow")  # hijo directo del Player, fuera del CharacterContainer
	if player.has_node("Movement"):
		movement_module = player.get_node("Movement")

# ==========================
# ANIMATION UPDATE
# ==========================
func update_animation() -> void:
	if not movement_module or not state_machine:
		return

	var desired_state: String = _determine_animation_state()
	if desired_state != last_state:
		state_machine.travel(desired_state)
		last_state = desired_state

	_update_sprite_flip()
	_update_shadow()

func _determine_animation_state() -> String:
	var is_moving: bool = movement_module.is_moving()
	var is_running: bool = movement_module.is_running()
	var is_crouching: bool = movement_module.is_player_crouching()
	var speed: float = movement_module.get_movement_speed()

	if is_crouching:
		return "Crouch_Walk" if is_moving else "Crouch_Idle"

	if not is_moving:
		return "Idle"
	elif is_running and speed > (player.move_speed + player.run_speed) / 2:
		return "Run"
	else:
		return "Walk"

func _update_sprite_flip() -> void:
	if not sprite_container or not movement_module:
		return
	sprite_container.scale.x = 1 if movement_module.get_facing_direction() else -1

# ==========================
# SHADOW SYSTEM
# La sombra se queda en el suelo mientras el player sube.
# Requiere que Shadow sea hijo directo del Player (no de CharacterContainer).
# El ShadowRAY sigue en CharacterContainer/Shadow/ShadowRAY.
# ==========================
func _update_shadow() -> void:
	if not shadow:
		return

	var shadow_ray: RayCast2D = player.get_node_or_null("CharacterContainer/Shadow/ShadowRAY")
	if not shadow_ray or not shadow_ray.is_colliding():
		shadow.modulate.a = 0.0
		return

	# Anclar la sombra al suelo real
	var ground_y: float = shadow_ray.get_collision_point().y
	shadow.global_position.y = ground_y

	# Calcular cuánto aire hay bajo el player
	# shadow_base_offset = distancia origen→suelo cuando está en reposo
	var base_height: float = ground_y - player.global_position.y
	var air_height: float = 0.0
	if not player.is_on_floor():
		air_height = base_height - shadow_base_offset

	var ratio: float = clamp(1.0 - air_height / shadow_max_height, 0.0, 1.0)
	shadow.scale = Vector2(lerp(0.2, 0.4, ratio), lerp(0.2, 0.4, ratio))
	shadow.modulate.a = lerp(0.2, 1.0, ratio)

# ==========================
# ANIMATION TRANSITIONS
# ==========================
func play_crouch_down() -> void:
	if state_machine:
		state_machine.travel("Crouch_Down")
		await anim_tree.animation_finished
		state_machine.travel("Crouch_Idle")

func play_crouch_up() -> void:
	if state_machine:
		state_machine.travel("Crouch_Up")
		await anim_tree.animation_finished
		state_machine.travel("Idle")

# ==========================
# FORCE IDLE ANIMATION
# ==========================

func force_idle() -> void:
	if state_machine:
		state_machine.travel("Idle")
		last_state = "Idle"
