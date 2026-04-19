# res://scripts/scene_changer.gd
extends Area2D

@export_file("*.tscn") var next_scene_path: String
@export var use_fade: bool = true
@export var fade_time: float = 0.5
@export var one_shot: bool = true
@export var require_press_f: bool = false

var _used: bool = false
var _player_inside: bool = false
var _player_ref: Node = null

func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

	set_process_unhandled_input(require_press_f)


func _on_body_entered(body: Node) -> void:
	if _used:
		return

	if not body.is_in_group("player"):
		return

	if require_press_f:
		_player_inside = true
		_player_ref = body
	else:
		_trigger_scene_change()


func _on_body_exited(body: Node) -> void:
	if body == _player_ref:
		_player_inside = false
		_player_ref = null


func _unhandled_input(event: InputEvent) -> void:
	if not require_press_f:
		return

	if _used:
		return

	if not _player_inside:
		return

	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F:
			_trigger_scene_change()


func _trigger_scene_change() -> void:
	if _used:
		return

	_used = true

	if one_shot:
		set_deferred("monitoring", false)
		_player_inside = false
		_player_ref = null

	if use_fade and is_instance_valid(SceneManager):
		SceneManager.change_scene(next_scene_path, fade_time)
	else:
		get_tree().change_scene_to_file(next_scene_path)
