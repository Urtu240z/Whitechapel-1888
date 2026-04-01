extends Node2D
class_name NPCServiceSkin

# ============================================================================
# NPC SERVICE SKIN
# Activa una única skin y oculta las demás.
# Todas las skins deben compartir el mismo rig y la misma estructura.
# ============================================================================

# ============================================================================
# CONFIG
# ============================================================================
@export var current_skin: String = "NPC_HostalKeeper"

# ============================================================================
# REFERENCIAS
# ============================================================================
@onready var skins_root: Node = $Skins

# ============================================================================
# READY
# ============================================================================
func _ready() -> void:
	set_skin(current_skin)

# ============================================================================
# API
# ============================================================================
func set_skin(skin_name: String) -> void:
	if not skins_root:
		return

	var target: Node = skins_root.get_node_or_null(skin_name)

	# Fallback: primera skin disponible
	if target == null and skins_root.get_child_count() > 0:
		target = skins_root.get_child(0)
		skin_name = target.name

	if target == null:
		push_warning("NPCServiceSkin: no hay skins disponibles.")
		return

	for child in skins_root.get_children():
		if child is CanvasItem:
			child.visible = (child == target)

	current_skin = skin_name

func get_current_skin() -> Node:
	if not skins_root:
		return null
	return skins_root.get_node_or_null(current_skin)
