extends Timer

func _on_timeout() -> void:
	$Intro_Light.play("Light_Move")
