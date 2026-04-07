@tool
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
@export var initial_facing_right: bool = true

# Propiedad dinámica para dropdown
var skin_name: String = "NPC_ClientPoor"

# ============================================================================
# REFERENCIAS
# ============================================================================
@onready var skin: NPCClientSkin = $CharacterContainer
@onready var movement: NPCClientMovement = $Movement
@onready var animation: NPCClientAnimation = $Animation
@onready var conversation: NPCClientConversation = $Conversation
@onready var audio: NPCClientAudio = $Audio

# ============================================================================
# ESTADO
# ============================================================================
var _enabled: bool = true
var _editor_preview_queued: bool = false
var _last_preview_skin_name: String = ""
var _last_preview_facing_right: bool = true

# ============================================================================
# CICLO DE VIDA
# ============================================================================
func _enter_tree() -> void:
	if Engine.is_editor_hint():
		call_deferred("notify_property_list_changed")

func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		_queue_editor_preview()
		return

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
# EDITOR
# ============================================================================
func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return

	if skin_name != _last_preview_skin_name or initial_facing_right != _last_preview_facing_right:
		_queue_editor_preview()

func _queue_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	if _editor_preview_queued:
		return

	_editor_preview_queued = true
	call_deferred("_apply_editor_preview")

func _apply_editor_preview() -> void:
	_editor_preview_queued = false

	if not Engine.is_editor_hint():
		return

	_apply_selected_skin_preview()
	_apply_facing_preview()

	_last_preview_skin_name = skin_name
	_last_preview_facing_right = initial_facing_right

func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []

	var skins := _get_available_skin_names()
	properties.append({
		"name": "skin_name",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _build_enum_hint(skins),
		"usage": PROPERTY_USAGE_DEFAULT
	})

	return properties

func _get(property: StringName) -> Variant:
	if property == &"skin_name":
		return skin_name
	return null

func _set(property: StringName, value: Variant) -> bool:
	if property == &"skin_name":
		var new_value := str(value)
		if skin_name != new_value:
			skin_name = new_value
			_queue_editor_preview()
		return true
	return false

func _get_available_skin_names() -> PackedStringArray:
	var result: PackedStringArray = []
	var skins_root := get_node_or_null("CharacterContainer/Skins")

	if skins_root == null:
		result.append("NPC_ClientPoor")
		return result

	for child in skins_root.get_children():
		if child is Node2D:
			result.append(child.name)

	if result.is_empty():
		result.append("NPC_ClientPoor")

	return result

func _build_enum_hint(values: PackedStringArray) -> String:
	var text := ""
	for i in range(values.size()):
		if i > 0:
			text += ","
		text += values[i]
	return text

func _apply_selected_skin_preview() -> void:
	var skin_node := get_node_or_null("CharacterContainer") as NPCClientSkin
	if skin_node == null:
		return

	skin_node.preview_skin(skin_name)

func _apply_facing_preview() -> void:
	var character_container := get_node_or_null("CharacterContainer") as Node2D
	if character_container == null:
		return

	var base_scale := character_container.scale
	base_scale.x = abs(base_scale.x)
	base_scale.y = abs(base_scale.y)

	if is_zero_approx(base_scale.x):
		base_scale.x = 1.0
	if is_zero_approx(base_scale.y):
		base_scale.y = 1.0

	character_container.scale.x = base_scale.x if initial_facing_right else -base_scale.x
	character_container.scale.y = base_scale.y

# ============================================================================
# LOOP
# ============================================================================
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

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
	if Engine.is_editor_hint():
		return

	if not get_tree().root.has_node("Dialogic"):
		return

	PlayerStats._sync_dialogic_variables()
	Dialogic.VAR.set_variable("client.result", "")

	var precios = _get_precios()
	Dialogic.VAR.set_variable("client.precio_mano", precios.mano)
	Dialogic.VAR.set_variable("client.precio_oral", precios.oral)
	Dialogic.VAR.set_variable("client.precio_completo", precios.completo)

# ============================================================================
# DIALOGIC — RESOLVER RESULTADO
# ============================================================================
const CLIENT_TRANSITION_SCENE = preload("res://Scenes/Client_Transition/Client_Transition.tscn")

func resolve_dialogic_result() -> void:
	if Engine.is_editor_hint():
		return

	if not get_tree().root.has_node("Dialogic"):
		return

	var result: String = str(Dialogic.VAR.get_variable("client.result"))
	Dialogic.VAR.set_variable("client.result", "")

	if result.is_empty():
		return

	var tipo: String = _get_tipo_string()
	var data: Dictionary = await ClientServiceManager.start_service(result, tipo, skin_name)
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
		ClientType.POOR:
			return "poor"
		ClientType.MEDIUM:
			return "medium"
		ClientType.RICH:
			return "rich"
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
