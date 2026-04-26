extends Node
# ================================================================
# INTERACTION MANAGER — Autoload
# ================================================================
# Autoridad única para interacciones con F.
#
# Responsabilidades:
# - Registrar/desregistrar interactuables.
# - Elegir el interactuable activo por prioridad y distancia.
# - Ejecutar la interacción activa.
# - Emitir señal para que HUD/KeyPrompt pueda mostrar texto/contexto.
#
# No debe:
# - Leer input directamente. Eso lo hace PlayerInteraction.
# - Abrir diálogos/puertas por sí mismo. Solo llama al callback registrado.
# ================================================================

enum Priority {
	PICKUP = 1,
	NPC = 5,
	PORTAL = 8,
	BUILDING = 10,
}

signal active_interactable_changed(node: Node, label: String, action: String)
signal interaction_performed(node: Node, label: String)
signal interactions_cleared()

var _enabled: bool = true
var _interactables: Array[Dictionary] = []

var _active_node: Node = null
var _active_label: String = ""
var _active_action: String = "interact"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if StateManager and not StateManager.state_changed.is_connected(_on_state_changed):
		StateManager.state_changed.connect(_on_state_changed)


func _process(_delta: float) -> void:
	_refresh_active_interactable()


# ================================================================
# CONTROL GLOBAL
# ================================================================
func set_enabled(value: bool) -> void:
	if _enabled == value:
		return

	_enabled = value

	if not _enabled:
		_set_active_interactable(null)
	else:
		_refresh_active_interactable()


func is_enabled() -> bool:
	return _enabled


func clear_all() -> void:
	_interactables.clear()
	_set_active_interactable(null)
	interactions_cleared.emit()


# ================================================================
# REGISTRO / DESREGISTRO
# ================================================================
func register(
	node: Node,
	priority: int,
	callback: Callable,
	label: String = "",
	action: String = "interact"
) -> void:
	if node == null or not is_instance_valid(node):
		return

	if callback.is_null():
		push_warning("InteractionManager.register(): callback nulo para %s" % node.name)
		return

	var clean_label: String = label.strip_edges()
	if clean_label.is_empty():
		clean_label = _guess_label(node, priority)

	var clean_action: String = action.strip_edges()
	if clean_action.is_empty():
		clean_action = "interact"

	for i in range(_interactables.size()):
		var entry: Dictionary = _interactables[i]
		var entry_node: Node = entry.get("node", null) as Node
		if entry_node == node:
			entry["priority"] = priority
			entry["callback"] = callback
			entry["label"] = clean_label
			entry["action"] = clean_action
			_interactables[i] = entry
			_refresh_active_interactable()
			return

	_interactables.append({
		"node": node,
		"priority": priority,
		"callback": callback,
		"label": clean_label,
		"action": clean_action,
	})

	_refresh_active_interactable()


func unregister(node: Node) -> void:
	if node == null:
		return

	var removed_active: bool = node == _active_node
	var filtered: Array[Dictionary] = []

	for entry: Dictionary in _interactables:
		var entry_node: Node = entry.get("node", null) as Node
		if entry_node != node:
			filtered.append(entry)

	_interactables = filtered

	if removed_active:
		_set_active_interactable(null)

	_refresh_active_interactable()


func unregister_by_owner(interaction_owner: Node) -> void:
	unregister(interaction_owner)


# ================================================================
# INTERACCIÓN
# ================================================================
func try_interact() -> bool:
	if not _can_use_interactions():
		return false

	_refresh_active_interactable()

	if _active_node == null or not is_instance_valid(_active_node):
		return false

	var active_entry: Dictionary = _get_entry_for_node(_active_node)
	if active_entry.is_empty():
		return false

	var callback: Callable = active_entry.get("callback", Callable())
	if callback.is_null():
		return false

	var label: String = str(active_entry.get("label", "Interactuar"))
	var node: Node = active_entry.get("node", null) as Node

	callback.call()
	interaction_performed.emit(node, label)
	return true


# ================================================================
# GETTERS PARA UI / DEBUG
# ================================================================
func has_active_interactable() -> bool:
	return _active_node != null and is_instance_valid(_active_node)


func get_active_interactable() -> Node:
	if has_active_interactable():
		return _active_node
	return null


func get_active_label() -> String:
	return _active_label


func get_active_action() -> String:
	return _active_action


func get_interactable_count() -> int:
	_cleanup_invalid_interactables()
	return _interactables.size()


# ================================================================
# ACTIVO
# ================================================================
func _refresh_active_interactable() -> void:
	if not _can_use_interactions():
		_set_active_interactable(null)
		return

	_cleanup_invalid_interactables()

	if _interactables.is_empty():
		_set_active_interactable(null)
		return

	_sort_interactables()
	_set_active_interactable(_interactables[0])


func _set_active_interactable(entry) -> void:
	var new_node: Node = null
	var new_label: String = ""
	var new_action: String = "interact"

	if entry is Dictionary and not (entry as Dictionary).is_empty():
		var dict: Dictionary = entry as Dictionary
		new_node = dict.get("node", null) as Node
		new_label = str(dict.get("label", "Interactuar"))
		new_action = str(dict.get("action", "interact"))

	if new_node == _active_node and new_label == _active_label and new_action == _active_action:
		return

	_active_node = new_node
	_active_label = new_label
	_active_action = new_action
	active_interactable_changed.emit(_active_node, _active_label, _active_action)


func _get_entry_for_node(node: Node) -> Dictionary:
	if node == null:
		return {}

	for entry: Dictionary in _interactables:
		var entry_node: Node = entry.get("node", null) as Node
		if entry_node == node:
			return entry

	return {}


# ================================================================
# ORDEN / DISTANCIA
# ================================================================
func _sort_interactables() -> void:
	var player: Node2D = PlayerManager.get_player_node2d()

	_interactables.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var priority_a: int = int(a.get("priority", 0))
		var priority_b: int = int(b.get("priority", 0))

		if priority_a != priority_b:
			return priority_a > priority_b

		if player != null:
			var dist_a: float = _distance_to_player(a, player)
			var dist_b: float = _distance_to_player(b, player)
			return dist_a < dist_b

		return false
	)


func _distance_to_player(entry: Dictionary, player: Node2D) -> float:
	var node: Node = entry.get("node", null) as Node
	if node == null or not is_instance_valid(node):
		return INF

	if node is Node2D:
		return player.global_position.distance_to((node as Node2D).global_position)

	return INF


# ================================================================
# LIMPIEZA / VALIDACIÓN
# ================================================================
func _cleanup_invalid_interactables() -> void:
	var filtered: Array[Dictionary] = []
	var active_still_valid: bool = false

	for entry: Dictionary in _interactables:
		var node: Node = entry.get("node", null) as Node
		var callback: Callable = entry.get("callback", Callable())

		if node == null or not is_instance_valid(node):
			continue

		if callback.is_null():
			continue

		if node == _active_node:
			active_still_valid = true

		filtered.append(entry)

	_interactables = filtered

	if _active_node != null and not active_still_valid:
		_set_active_interactable(null)


func _can_use_interactions() -> bool:
	if not _enabled:
		return false

	if not StateManager:
		return true

	return StateManager.can_interact()


func _on_state_changed(_from_state, _to_state) -> void:
	_refresh_active_interactable()


func _guess_label(node: Node, priority: int) -> String:
	if node.has_method("get_interaction_label"):
		var method_label: String = str(node.call("get_interaction_label")).strip_edges()
		if not method_label.is_empty():
			return method_label

	if node.has_meta("interaction_label"):
		var meta_label: String = str(node.get_meta("interaction_label", "")).strip_edges()
		if not meta_label.is_empty():
			return meta_label

	match priority:
		Priority.NPC:
			return "Hablar"
		Priority.BUILDING:
			return "Interactuar"
		Priority.PORTAL:
			return "Cambiar zona"
		Priority.PICKUP:
			return "Recoger"

	return "Interactuar"
