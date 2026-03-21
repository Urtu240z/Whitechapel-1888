extends Area2D

@export var target_outfit: String = "London"

func _ready():
	connect("body_entered", Callable(self, "_on_body_entered"))

func _on_body_entered(body: Node2D) -> void:

	if body.is_in_group("player"):
		if body.has_method("set_outfit"):
			body.set_outfit(target_outfit)
