extends Area2D
class_name NPCInteractionArea

# ================================================================
# NPC INTERACTION AREA
# ================================================================
# Componente común para:
# - NPCClientConversation
# - NPCCompanionConversation
# - NPCServiceConversation
#
# Responsabilidad:
# - detectar InteractionArea del player
# - registrar/desregistrar el NPC en InteractionManager
# - emitir señales de entrada/salida
#
# Sin fallback legacy:
# - el owner NPC DEBE tener start_dialog()
# - el player DEBE resolverse por PlayerManager.get_player_node2d()
# ================================================================

signal player_entered_range(player: Node2D)
signal player_exited_range(player: Node2D)

@export var interaction_enabled: bool = true
@export var interaction_label: String = "Hablar"
@export var interaction_action: String = "interact"
@export var interaction_priority: int = 5

@onready var shape: CollisionShape2D = get_node_or_null("CollisionShape2D")

var _owner_npc: CharacterBody2D = null
var _player_in_range: bool = false
var _player: Node2D = null
var _initialized: bool = false


# ================================================================
# INIT
# ================================================================
func initialize(owner_npc: CharacterBody2D) -> void:
	if owner_npc == null:
		push_error("%s.initialize(): owner_npc es null." % name)
		return

	if not owner_npc.has_method("start_dialog"):
		push_error("%s.initialize(): el NPC '%s' no tiene start_dialog()." % [
			name,
			owner_npc.name
		])
		return

	_owner_npc = owner_npc
	_initialized = true

	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

	if not area_exited.is_connected(_on_area_exited):
		area_exited.connect(_on_area_exited)

	set_interaction_enabled(interaction_enabled)


func _exit_tree() -> void:
	_force_unregister_player()


# ================================================================
# API
# ================================================================
func set_interaction_enabled(value: bool) -> void:
	interaction_enabled = value

	monitoring = value
	monitorable = value

	if shape:
		shape.set_deferred("disabled", not value)

	if not value:
		_force_unregister_player()


func is_player_in_range() -> bool:
	return _player_in_range and is_instance_valid(_player)


func get_player_in_range() -> Node2D:
	if is_instance_valid(_player):
		return _player

	return null


# ================================================================
# SIGNALS
# ================================================================
func _on_area_entered(area: Area2D) -> void:
	if not _initialized:
		push_error("%s: no está inicializado. Falta conversation.initialize(self) en el NPC." % name)
		return

	if not interaction_enabled:
		return

	if area.name != "InteractionArea":
		return

	var player := PlayerManager.get_player_node2d()
	if player == null:
		push_error("%s: PlayerManager.get_player_node2d() devolvió null." % name)
		return

	_player = player
	_player_in_range = true

	_register_interaction()

	player_entered_range.emit(player)


func _on_area_exited(area: Area2D) -> void:
	if area.name != "InteractionArea":
		return

	var player := PlayerManager.get_player_node2d()
	if player == null:
		push_error("%s: PlayerManager.get_player_node2d() devolvió null al salir." % name)
		return

	_unregister_interaction()

	_player_in_range = false
	_player = null

	player_exited_range.emit(player)


# ================================================================
# INTERACTION MANAGER
# ================================================================
func _register_interaction() -> void:
	if _owner_npc == null or not is_instance_valid(_owner_npc):
		push_error("%s: owner NPC inválido al registrar interacción." % name)
		return

	InteractionManager.register(
		_owner_npc,
		interaction_priority,
		Callable(_owner_npc, "start_dialog"),
		interaction_label,
		interaction_action
	)


func _unregister_interaction() -> void:
	if _owner_npc == null:
		return

	InteractionManager.unregister(_owner_npc)


func _force_unregister_player() -> void:
	_unregister_interaction()

	_player_in_range = false
	_player = null
