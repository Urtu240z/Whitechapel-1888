extends Node2D

signal finished(data: Dictionary)

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var minigame: Control = $CanvasLayer/Minigame
@onready var client_skins_root: Node2D = $Characters/NpcClient/Skins
@onready var transition_pcam: PhantomCamera2D = $TransitionPhantomCamera2D
@onready var transition_target: Node2D = $TransitionCameraTarget
@onready var local_camera: Camera2D = $Camera2D
@onready var audio_root: Node = $Audio

var _acto: String = ""
var _tipo: String = ""
var _client_skin_name: String = "NPC_ClientPoor"
var _previous_camera: Camera2D = null
var _can_skip_animation: bool = false
var _animation_phase_done: bool = false
var _transition_playing: bool = false

const TRANSITION_ANIMATION: StringName = &"ClientTransition1"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	minigame.visible = false

	if is_instance_valid(transition_pcam):
		transition_pcam.set_follow_target(transition_target)
		transition_pcam.set_priority(0)

	minigame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	animation_player.animation_finished.connect(_on_animation_finished)
	minigame.completed.connect(_on_minigame_completed)

func prepare(acto: String, tipo: String, client_skin_name: String = "NPC_ClientPoor") -> void:
	_acto = acto
	_tipo = tipo
	_client_skin_name = client_skin_name
	_can_skip_animation = false
	_animation_phase_done = false
	_transition_playing = false

	_previous_camera = get_viewport().get_camera_2d()

	if is_instance_valid(local_camera):
		local_camera.make_current()

	if is_instance_valid(transition_pcam):
		transition_pcam.set_follow_target(transition_target)
		transition_pcam.set_priority(90)

	_apply_client_skin(_client_skin_name)

	# Dejar la animación colocada en frame 0, pero sin reproducir aún.
	# Importante: no usamos play+stop aquí para no disparar pistas de audio.
	if animation_player.has_animation(TRANSITION_ANIMATION):
		animation_player.assigned_animation = TRANSITION_ANIMATION
		animation_player.seek(0.0, true)
		animation_player.stop()

	_stop_transition_audio()

func play_transition() -> void:
	if _transition_playing or _animation_phase_done:
		return

	visible = true
	_transition_playing = true
	_can_skip_animation = false
	_stop_transition_audio()
	animation_player.play(TRANSITION_ANIMATION)

func _unhandled_input(event: InputEvent) -> void:
	# Durante la animación principal, F no hace nada.
	# El input queda reservado para el minijuego cuando este se activa.
	if not _can_skip_animation:
		return

	if event.is_action_pressed("interact"):
		_skip_animation_to_minigame()
		get_viewport().set_input_as_handled()

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

	_transition_playing = false

	_animation_phase_done = true
	_can_skip_animation = false

	minigame.z_index = 20
	minigame.visible = true
	if minigame.has_method("start"):
		minigame.start()

func _skip_animation_to_minigame() -> void:
	# Desactivado por defecto: saltar con seek puede redisparar pistas de audio.
	return

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name != TRANSITION_ANIMATION:
		return

	_enter_minigame_phase()

func _on_minigame_completed(satisfaction: float) -> void:
	minigame.visible = false
	_stop_transition_audio()

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

func _stop_transition_audio() -> void:
	if audio_root == null:
		return

	for child: Node in audio_root.get_children():
		if child is AudioStreamPlayer:
			child.stop()
		elif child is AudioStreamPlayer2D:
			child.stop()
