extends PanelContainer

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("stats"):
		visible = !visible
