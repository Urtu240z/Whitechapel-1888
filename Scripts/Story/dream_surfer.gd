extends CanvasLayer

@export_category("🌊 Dream Surfer Control")

@export var texture1_visible: bool = true:
	set(value):
		texture1_visible = value
		if has_node("TextureRect"):
			$TextureRect.visible = value

@export var texture2_visible: bool = true:
	set(value):
		texture2_visible = value
		if has_node("TextureRect2"):
			$TextureRect2.visible = value


func _ready():
	# Aplica visibilidad inicial al cargar la escena
	if has_node("TextureRect"):
		$TextureRect.visible = texture1_visible

	if has_node("TextureRect2"):
		$TextureRect2.visible = texture2_visible
