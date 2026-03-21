extends Timer

func _on_timeout() -> void:
	print("⏰ Timer terminado, reproduciendo animación Light_Move")
	$Intro_Light.play("Light_Move")
