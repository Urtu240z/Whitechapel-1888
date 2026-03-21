extends PointLight2D

func _ready() -> void:
	flicker()

func flicker() -> void:
	var new_energy = randf_range(1.0, 6.0)
	energy = lerp(energy, new_energy, 0.3) # transición más suave
	await get_tree().create_timer(0.09).timeout
	flicker()
