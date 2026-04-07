@tool
extends EditorScript

func _run() -> void:
	var size := 256
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	
	var center := Vector2(size * 0.5, size * 0.5)
	var max_dist: float = size * 0.5
	
	for x in size:
		for y in size:
			var dist: float = Vector2(x, y).distance_to(center)
			var t: float = clamp(dist / max_dist, 0.0, 1.0)
			
			# Gaussian falloff — blanco puro, solo alpha varía
			var alpha: float = exp(-t * t * 3.0)
			
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	
	var path := "res://Assets/Sprites/Effects/Smoke_Soft.png"
	var err := image.save_png(path)
	if err == OK:
		print("✅ Guardado en: ", path)
	else:
		print("❌ Error — crea la carpeta primero")
