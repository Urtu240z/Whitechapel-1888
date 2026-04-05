extends CharacterBody2D
class_name NPCClient

# ============================================================================
# NPC CLIENT
# NPC cliente: interacción con F, diálogo de Dialogic,
# resolución del acto elegido.
# ============================================================================

# ============================================================================
# TIPOS
# ============================================================================
enum ClientType { POOR, MEDIUM, RICH }

# ============================================================================
# DATOS DEL CLIENTE
# ============================================================================
@export_group("NPC Client")
@export var npc_display_name: String = "Client"
@export_file("*.dtl") var dialog_timeline: String = ""
@export var client_type: ClientType = ClientType.POOR
@export var skin_name: String = "NPC_Client_Poor"
@export var initial_facing_right: bool = true

# ============================================================================
# REFERENCIAS
# ============================================================================
@onready var skin: NPCClientSkin         = $CharacterContainer
@onready var movement: NPCClientMovement = $Movement
@onready var animation: NPCClientAnimation     = $Animation
@onready var conversation: NPCClientConversation = $Conversation
@onready var audio: NPCClientAudio       = $Audio

# ============================================================================
# ESTADO
# ============================================================================
var _enabled: bool = true

# ============================================================================
# READY
# ============================================================================
func _ready() -> void:
	add_to_group("npc_client")
	velocity = Vector2.ZERO

	if skin:
		skin.set_skin(skin_name)
	if movement:
		movement.initialize(self)
	if animation:
		animation.initialize(self, initial_facing_right)
	if conversation:
		conversation.initialize(self)
	if audio:
		audio.initialize(self)

	visibility_changed.connect(_on_visibility_changed)
	set_enabled(is_visible_in_tree())

# ============================================================================
# LOOP
# ============================================================================
func _physics_process(delta: float) -> void:
	if not _enabled:
		return

	velocity = Vector2.ZERO

	var player := _get_player()
	var player_in_range: bool = false

	if conversation:
		player_in_range = conversation.is_player_in_range()

	if animation:
		animation.update_service(delta, player, player_in_range)

# ============================================================================
# API
# ============================================================================
func get_display_name() -> String:
	if not npc_display_name.is_empty():
		return npc_display_name
	return name

func set_enabled(value: bool) -> void:
	_enabled = value
	set_physics_process(value)

	if conversation:
		conversation.set_interaction_enabled(value)

	if not value and animation:
		animation.force_idle_counter()

# ============================================================================
# DIALOGIC — PREPARAR VARIABLES
# ============================================================================
func prepare_dialogic_variables() -> void:
	if not get_tree().root.has_node("Dialogic"):
		return

	PlayerStats._sync_dialogic_variables()
	Dialogic.VAR.set_variable("client.result", "")

	# Precios visibles en el diálogo según tipo de cliente
	var precios = _get_precios()
	Dialogic.VAR.set_variable("client.precio_mano",     precios.mano)
	Dialogic.VAR.set_variable("client.precio_oral",     precios.oral)
	Dialogic.VAR.set_variable("client.precio_completo", precios.completo)

# ============================================================================
# DIALOGIC — RESOLVER RESULTADO
# ============================================================================

const CLIENT_TRANSITION_SCENE = preload("res://Scenes/Client_Transition/Client_Transition.tscn")

func resolve_dialogic_result() -> void:
	if not get_tree().root.has_node("Dialogic"):
		return

	var result: String = str(Dialogic.VAR.get_variable("client.result"))
	Dialogic.VAR.set_variable("client.result", "")

	if result.is_empty():
		return

	var tipo: String = _get_tipo_string()

	var data: Dictionary = await ClientServiceManager.start_service(result, tipo)
	if data.is_empty():
		return

	PlayerStats.tener_acto(data["acto"], data["tipo"], data["satisfaction"])

# ============================================================================
# HELPERS
# ============================================================================
func _get_player() -> Node2D:
	if PlayerManager and PlayerManager.player_instance:
		return PlayerManager.player_instance as Node2D
	return get_tree().get_first_node_in_group("player") as Node2D

func _get_tipo_string() -> String:
	match client_type:
		ClientType.POOR:   return "poor"
		ClientType.MEDIUM: return "medium"
		ClientType.RICH:   return "rich"
	return "poor"

func _get_precios() -> Dictionary:
	match client_type:
		ClientType.POOR:
			return { "mano": 0.5, "oral": 1.0, "completo": 2.0 }
		ClientType.MEDIUM:
			return { "mano": 1.0, "oral": 2.0, "completo": 4.0 }
		ClientType.RICH:
			return { "mano": 2.0, "oral": 4.0, "completo": 8.0 }
	return { "mano": 0.5, "oral": 1.0, "completo": 2.0 }

# ============================================================================
# SEÑALES
# ============================================================================
func _on_visibility_changed() -> void:
	set_enabled(is_visible_in_tree())
