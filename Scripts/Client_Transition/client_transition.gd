extends Node2D

signal finished(data: Dictionary)

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var minigame: Control = $CanvasLayer/Minigame
@onready var client_skins_root: Node2D = $Characters/NpcClient/Skins
@onready var transition_pcam: PhantomCamera2D = $TransitionPhantomCamera2D
@onready var transition_target: Node2D = $TransitionCameraTarget
@onready var local_camera: Camera2D = $Camera2D

var _acto: String = ""
var _tipo: String = ""
var _client_skin_name: String = "NPC_ClientPoor"
var _previous_camera: Camera2D = null
var _can_skip_animation: bool = false
var _animation_phase_done: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	minigame.visible = false

	if is_instance_valid(transition_pcam):
		transition_pcam.follow_mode = 2 # SIMPLE
		transition_pcam.set_follow_target(transition_target)
		transition_pcam.set_priority(0)

	minigame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	animation_player.animation_finished.connect(_on_animation_finished)
	minigame.completed.connect(_on_minigame_completed)
	visible = false
func _unhandled_input(event: InputEvent) -> void:
	if not _can_skip_animation:
		return

	if event.is_action_pressed("interact"):
		_skip_animation_to_minigame()
		get_viewport().set_input_as_handled()

func begin(acto: String, tipo: String, client_skin_name: String = "NPC_ClientPoor") -> void:
	_acto = acto
	_tipo = tipo
	_client_skin_name = client_skin_name
	_can_skip_animation = true
	_animation_phase_done = false

	_previous_camera = get_viewport().get_camera_2d()

	if is_instance_valid(local_camera):
		local_camera.make_current()

	if is_instance_valid(transition_pcam):
		transition_pcam.follow_mode = 2 # SIMPLE
		transition_pcam.set_follow_target(transition_target)
		transition_pcam.set_priority(90)

	_apply_client_skin(_client_skin_name)

	await get_tree().process_frame

	visible = true
	animation_player.play("ClientTransition1")

func _apply_client_skin(skin_name: String) -> void:
	if client_skins_root == null:
		return

	var target := client_skins_root.get_node_or_null(skin_name)

	if target == null and client_skins_root.get_child_count() > 0:
		target = client_skins_root.get_child(0)

	for child in client_skins_root.get_children():
		if child is CanvasItem:
			child.visible = (child == target)

		if child is Node2D:
			child.scale = _get_client_skin_scale(child.name)

func _get_client_skin_scale(skin_name: String) -> Vector2:
	match skin_name:
		"NPC_ClientPoor5", "NPC_ClientPoor6":
			return Vector2(1.3, 1.3)
		_:
			return Vector2.ONE

func _enter_minigame_phase() -> void:
	if _animation_phase_done:
		return

	_animation_phase_done = true
	_can_skip_animation = false

	minigame.z_index = 20
	minigame.visible = true
	minigame.start()

func _skip_animation_to_minigame() -> void:
	if _animation_phase_done:
		return

	if animation_player.current_animation == "ClientTransition1":
		var anim_length := animation_player.current_animation_length
		animation_player.seek(anim_length, true)

	_enter_minigame_phase()

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name != "ClientTransition1":
		return

	_enter_minigame_phase()

func _on_minigame_completed(satisfaction: float) -> void:
	minigame.visible = false

	if is_instance_valid(transition_pcam):
		transition_pcam.set_priority(0)

	if is_instance_valid(_previous_camera):
		_previous_camera.make_current()

	finished.emit({
		"acto": _acto,
		"tipo": _tipo,
		"satisfaction": satisfaction,
		"client_skin_name": _client_skin_name,
	})

	queue_free()
