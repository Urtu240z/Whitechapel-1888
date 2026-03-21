extends Label

func _process(delta):
	# Obtenemos los FPS actuales del motor de Godot
	var fps = Engine.get_frames_per_second()
	
	# Actualizamos el texto del Label
	# Lo redondeamos para que sea un número entero
	text = "FPS: " + str(int(fps))
