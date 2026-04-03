extends Area2D
class_name NPCServiceConversation

# ============================================================================
# NPC SERVICE CONVERSATION
# Este Area2D sirve para:
# - detectar si el player está en rango
# - registrar / desregistrar el NPC en el sistema de interacción del player
#
# IMPORTANTE:
# El tamaño de este Area2D también controla el cambio:
# Idle_Counter <-> Idle
# ============================================================================

# ============================================================================
# SEÑALES
# ============================================================================
signal player_entered_range(player)
signal player_exited_range(player)

# ============================================================================
# CONFIG
# ============================================================================
@export var interaction_enabled: bool = true

# ============================================================================
# REFERENCIAS
# ============================================================================
@onready var shape: CollisionShape2D = get_node_or_null("CollisionShape2D")

# ============================================================================
# ESTADO
# ============================================================================
var _player_in_range: bool = false
var _player: Node2D = null

# ============================================================================
# INIT
# ============================================================================
func initialize(_owner_npc: CharacterBody2D) -> void:
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

	if not area_exited.is_connected(_on_area_exited):
		area_exited.connect(_on_area_exited)

	set_interaction_enabled(interaction_enabled)

# ============================================================================
# API
# ============================================================================
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

# ============================================================================
# SIGNALS
# ============================================================================
func _on_area_entered(area: Area2D) -> void:
	if not interaction_enabled:
		return

	if area.name != "InteractionArea":
		return

	var player := _resolve_player_from_interaction_area(area)
	if player == null:
		return

	_player = player
	_player_in_range = true

	var interaction = player.get_node_or_null("Interaction")
	if interaction and interaction.has_method("register_npc"):
		interaction.register_npc(get_parent())

	emit_signal("player_entered_range", player)

func _on_area_exited(area: Area2D) -> void:
	if area.name != "InteractionArea":
		return

	var player := _resolve_player_from_interaction_area(area)
	if player == null:
		return

	var interaction = player.get_node_or_null("Interaction")
	if interaction and interaction.has_method("unregister_npc"):
		interaction.unregister_npc(get_parent())

	_player_in_range = false
	_player = null

	emit_signal("player_exited_range", player)

# ============================================================================
# HELPERS
# ============================================================================
func _force_unregister_player() -> void:
	if is_instance_valid(_player):
		var interaction = _player.get_node_or_null("Interaction")
		if interaction and interaction.has_method("unregister_npc"):
			interaction.unregister_npc(get_parent())

	_player_in_range = false
	_player = null

func _resolve_player_from_interaction_area(_area: Area2D) -> Node2D:
	if PlayerManager and PlayerManager.player_instance:
		return PlayerManager.player_instance as Node2D
	return null
