# res://scripts/scene_changer.gd
extends Area2D

@export_file("*.tscn") var next_scene_path: String
@export var use_fade: bool = true
@export var fade_time: float = 0.5
@export var one_shot: bool = true

var _used := false

func _ready() -> void:
	# Conecta la señal si no está conectada
	if not self.body_entered.is_connected(_on_body_entered):
		self.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _used:
		return
	if not body.is_in_group("player"):
		return

	_used = true
	if one_shot:
		set_deferred("monitoring", false)

	if use_fade and is_instance_valid(SceneManager):
		SceneManager.change_scene(next_scene_path, fade_time)
	else:
		get_tree().change_scene_to_file(next_scene_path)
