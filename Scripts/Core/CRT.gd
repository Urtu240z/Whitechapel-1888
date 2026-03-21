extends ColorRect

func _process(_delta):
	var mat := material as ShaderMaterial
	if mat:
		var viewport_size = get_viewport_rect().size
		mat.set_shader_parameter("screen_size", viewport_size)
		mat.set_shader_parameter("viewport_size", viewport_size)
