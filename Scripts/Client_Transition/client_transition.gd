extends Node2D

signal finished(data: Dictionary)

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var minigame: Control = $CanvasLayer/Minigame

var _acto: String = ""
var _tipo: String = ""
var _previous_camera: Camera2D = null
var _can_skip_animation: bool = false
var _animation_phase_done: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	minigame.visible = false

	_previous_camera = get_viewport().get_camera_2d()
	$Camera2D.make_current()
	minigame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	animation_player.animation_finished.connect(_on_animation_finished)
	minigame.completed.connect(_on_minigame_completed)

func _unhandled_input(event: InputEvent) -> void:
	if not _can_skip_animation:
		return

	if event.is_action_pressed("interact"):
		_skip_animation_to_minigame()
		get_viewport().set_input_as_handled()

func begin(acto: String, tipo: String) -> void:
	_acto = acto
	_tipo = tipo
	_can_skip_animation = true
	_animation_phase_done = false
	animation_player.play("ClientTransition1")

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

	if is_instance_valid(_previous_camera):
		_previous_camera.make_current()

	finished.emit({
		"acto": _acto,
		"tipo": _tipo,
		"satisfaction": satisfaction,
	})

	queue_free()
