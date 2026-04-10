@tool
extends Node2D
class_name NPCCompanionSkin

# ============================================================================
# NPC COMPANION SKIN
# Activa una única skin y oculta las demás.
# Idéntico a NPCClientSkin.
# ============================================================================

@export var current_skin: String = "Mary"

@onready var skins_root: Node = $Skins

func _ready() -> void:
	if Engine.is_editor_hint():
		call_deferred("_apply_export_skin_preview")
		return
	set_skin(current_skin)

func set_skin(skin_name: String) -> String:
	current_skin = skin_name
	return _apply_skin_visibility(skin_name)

func preview_skin(skin_name: String) -> String:
	return _apply_skin_visibility(skin_name)

func get_current_skin() -> Node:
	var root := get_node_or_null("Skins")
	if not root:
		return null
	return root.get_node_or_null(current_skin)

func _apply_export_skin_preview() -> void:
	preview_skin(current_skin)

func _apply_skin_visibility(skin_name: String) -> String:
	var root := get_node_or_null("Skins")
	if not root:
		return ""

	var target: Node = root.get_node_or_null(skin_name)

	if target == null and root.get_child_count() > 0:
		target = root.get_child(0)
		skin_name = target.name

	if target == null:
		push_warning("NPCCompanionSkin: no hay skins disponibles.")
		return ""

	for child in root.get_children():
		if child is CanvasItem:
			child.visible = (child == target)

	return skin_name
