extends Node2D
class_name NPCSkin

# Nombre del skin activo (hijo de "Skins")
@export var current_skin: String = "NPC_1"

func _ready() -> void:
	set_skin(current_skin)


func set_skin(skin_name: String) -> void:
	var skins_root := $Skins
	if not skins_root or not skins_root.has_node(skin_name):
		return

	# Ocultar todos los skins
	for s in skins_root.get_children():
		s.visible = false

	# Activar solo el seleccionado
	var skin: Node = skins_root.get_node(skin_name)
	skin.visible = true

	# Obtener el Skeleton2D (ubicado fuera de Skins)
	var skeleton := $Bones/Skeleton2D
	if not skeleton:
		return

	# Vincular cada RemoteTransform2D a su sprite homónimo
	for remote in _get_all_remotes(skeleton):
		var sprite_name: String = remote.name
		var sprite_node = skin.get_node_or_null(NodePath(sprite_name))
		if sprite_node:
			remote.remote_path = sprite_node.get_path()


func _get_all_remotes(root: Node) -> Array:
	var remotes: Array = []
	for child in root.get_children():
		if child is RemoteTransform2D:
			remotes.append(child)
		if child.get_child_count() > 0:
			remotes.append_array(_get_all_remotes(child))
	return remotes
