extends Area2D

@export var linked_word: NodePath
@export var flash_index: int = -1  # Qué imagen de flash usar (0 = primera)

func _on_body_entered(body):
	if body.name != "Fairy":
		return

	# Activa palabra asociada (si existe)
	if linked_word != NodePath("") and has_node(linked_word):
		var word_node = get_node(linked_word)
		if word_node and word_node.has_method("animate_word"):
			word_node.animate_word()

	# Notifica al script padre que dispare flash y cámara
	var flashback_parent = get_parent().get_parent()  # sube hasta el Node2D principal
	if flashback_parent and flashback_parent.has_method("trigger_flash_effect"):
		flashback_parent.trigger_flash_effect(flash_index)

	queue_free()  # Se destruye tras activarse
