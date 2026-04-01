extends CharacterBody2D
class_name NPCService

# ============================================================================
# NPC SERVICE
# NPC fijo de servicio: hostelero, doctor, vendedor, etc.
# No reutiliza la lógica de npc_charger.
# ============================================================================
#
# RESPONSABILIDADES:
# - Activar la skin correcta
# - Inicializar módulos
# - Desactivar interacción si el NPC no es visible en árbol
# - Pasar al módulo de animación si el player está en rango
# ============================================================================

# ============================================================================
# DATOS DEL NPC
# ============================================================================
@export_group("NPC Service")
@export var npc_display_name: String = "Service NPC"
@export_file("*.dtl") var dialog_timeline: String = ""
@export var service_id: String = ""
@export var skin_name: String = "NPC_HostalKeeper"

# ============================================================================
# REFERENCIAS
# ============================================================================
@onready var skin: NPCServiceSkin = $CharacterContainer
@onready var movement: NPCServiceMovement = $Movement
@onready var animation: NPCServiceAnimation = $Animation
@onready var conversation: NPCServiceConversation = $Conversation
@onready var audio: NPCServiceAudio = $Audio

# ============================================================================
# ESTADO
# ============================================================================
var _service_enabled: bool = true

# ============================================================================
# READY
# ============================================================================
func _ready() -> void:
	add_to_group("npc_service")

	velocity = Vector2.ZERO

	if skin:
		skin.set_skin(skin_name)

	if movement:
		movement.initialize(self)

	if animation:
		animation.initialize(self)

	if conversation:
		conversation.initialize(self)

	if audio:
		audio.initialize(self)

	# Si el NPC está dentro de un interior oculto, debe quedar desactivado.
	visibility_changed.connect(_on_visibility_changed)
	set_service_enabled(is_visible_in_tree())

# ============================================================================
# LOOP
# ============================================================================
func _physics_process(delta: float) -> void:
	if not _service_enabled:
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
func set_skin(new_skin: String) -> void:
	skin_name = new_skin
	if skin:
		skin.set_skin(new_skin)

func get_display_name() -> String:
	if not npc_display_name.is_empty():
		return npc_display_name
	return name

func set_service_enabled(value: bool) -> void:
	_service_enabled = value
	set_physics_process(value)

	if conversation:
		conversation.set_interaction_enabled(value)

	# Al desactivar, lo devolvemos al estado base del mostrador.
	if not value and animation:
		animation.force_idle_counter()

# ============================================================================
# SEÑALES
# ============================================================================
func _on_visibility_changed() -> void:
	set_service_enabled(is_visible_in_tree())

# ============================================================================
# HELPERS
# ============================================================================
func _get_player() -> Node2D:
	if PlayerManager and PlayerManager.player_instance:
		return PlayerManager.player_instance as Node2D

	return get_tree().get_first_node_in_group("player") as Node2D

func prepare_dialogic_variables() -> void:
	if service_id != "lodge_reception":
		return

	PlayerStats._sync_dialogic_variables()
	Dialogic.VAR.set_variable("hostel.hostel_open", true)
	Dialogic.VAR.set_variable("hostel.player_money", PlayerStats.dinero)
	Dialogic.VAR.set_variable("hostel.hostel_price", PlayerStats.COSTE_HOSTAL_DIA)
	Dialogic.VAR.set_variable("hostel.hostel_result", "")

func resolve_dialogic_result() -> void:
	if service_id != "lodge_reception":
		return

	var result = str(Dialogic.VAR.get_variable("hostel.hostel_result"))

	# Limpiamos para la próxima vez
	Dialogic.VAR.set_variable("hostel.hostel_result", "")

	if result != "rent_room":
		return

	# Gasta el dinero real del jugador
	var ok := await PlayerStats.gastar_dinero(PlayerStats.COSTE_HOSTAL_DIA)
	if not ok:
		return

	PlayerStats.dias_sin_pagar_hostal = 0

	# Usa el sistema de sueño que ya tienes
	SleepManager.start_sleep("hostal")
