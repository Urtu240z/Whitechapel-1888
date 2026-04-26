@tool
extends Node2D
class_name NPCSkinComponent

# ============================================================================
# NPC SKIN COMPONENT
# ============================================================================
# Debe ir en:
#
# CharacterContainer
#   Skins
#     SkinA
#     SkinB
#
# No debe ir en el nodo raíz del NPC salvo que cambies skins_root_path.
# ============================================================================

@export var skins_root_path: NodePath = NodePath("Skins")

var _current_skin: String = ""
var _skins_root: Node = null
var _preview_queued: bool = false


# ============================================================================
# PROPERTY LIST DINÁMICO
# ============================================================================
func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	var skins := get_available_skin_names()

	properties.append({
		"name": "current_skin",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _build_enum_hint(skins),
		"usage": PROPERTY_USAGE_DEFAULT
	})

	return properties


func _get(property: StringName) -> Variant:
	if property == &"current_skin":
		return _current_skin

	return null


func _set(property: StringName, value: Variant) -> bool:
	if property == &"current_skin":
		set_skin(str(value))
		return true

	return false


func _build_enum_hint(values: PackedStringArray) -> String:
	var text := ""

	for i in range(values.size()):
		if i > 0:
			text += ","
		text += values[i]

	return text


# ============================================================================
# READY / EDITOR
# ============================================================================
func _enter_tree() -> void:
	if Engine.is_editor_hint():
		call_deferred("_refresh_editor")


func _ready() -> void:
	_cache_skins_root()

	if Engine.is_editor_hint():
		call_deferred("_refresh_editor")
	else:
		if not _current_skin.strip_edges().is_empty():
			set_skin(_current_skin)


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return

	if what == NOTIFICATION_CHILD_ORDER_CHANGED:
		call_deferred("_refresh_editor")


func _refresh_editor() -> void:
	if not Engine.is_editor_hint():
		return

	_cache_skins_root()
	notify_property_list_changed()
	_queue_editor_preview()


# ============================================================================
# API
# ============================================================================
func set_skin(skin_name: String) -> String:
	var clean_skin := skin_name.strip_edges()

	_current_skin = clean_skin

	if clean_skin.is_empty():
		return ""

	_cache_skins_root()

	if _skins_root == null:
		if is_inside_tree():
			push_error("NPCSkinComponent '%s': falta nodo 'Skins'. Ruta buscada: %s" % [
				name,
				str(skins_root_path)
			])
		return ""

	var target := _skins_root.get_node_or_null(clean_skin)
	if target == null:
		push_error("NPCSkinComponent '%s': no existe la skin '%s'." % [
			name,
			clean_skin
		])
		return ""

	_show_only_skin(target)

	if Engine.is_editor_hint():
		_queue_editor_preview()

	return _current_skin


func preview_skin(skin_name: String) -> String:
	return set_skin(skin_name)


func get_current_skin_name() -> String:
	return _current_skin


func get_current_skin() -> Node:
	_cache_skins_root()

	if _skins_root == null:
		return null

	if _current_skin.strip_edges().is_empty():
		return null

	return _skins_root.get_node_or_null(_current_skin)


func has_skin(skin_name: String) -> bool:
	_cache_skins_root()

	if _skins_root == null:
		return false

	return _skins_root.has_node(skin_name)


func get_available_skin_names() -> PackedStringArray:
	var result := PackedStringArray()

	_cache_skins_root()

	if _skins_root == null:
		return result

	for child in _skins_root.get_children():
		if child is CanvasItem:
			result.append(child.name)

	return result


func get_first_skin_name() -> String:
	var skins := get_available_skin_names()

	if skins.is_empty():
		return ""

	return skins[0]


# ============================================================================
# INTERNOS
# ============================================================================
func _cache_skins_root() -> void:
	if not is_inside_tree():
		_skins_root = null
		return

	_skins_root = get_node_or_null(skins_root_path)


func _show_only_skin(target: Node) -> void:
	if _skins_root == null:
		return

	for child in _skins_root.get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = child == target


func _queue_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return

	if _preview_queued:
		return

	_preview_queued = true
	call_deferred("_apply_editor_preview")


func _apply_editor_preview() -> void:
	_preview_queued = false

	if not Engine.is_editor_hint():
		return

	if _current_skin.strip_edges().is_empty():
		return

	_cache_skins_root()

	if _skins_root == null:
		return

	var target := _skins_root.get_node_or_null(_current_skin)
	if target == null:
		return

	_show_only_skin(target)
