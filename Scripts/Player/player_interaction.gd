extends Node
# ==========================
# INTERACTION MODULE
# ==========================
# Gestiona las interacciones del jugador con el mundo:
# - Iniciar diálogos con NPCs via Dialogic → tecla "interact"
#
# ℹ️ Los pickups NO se gestionan aquí.
# El nodo Pickup.tscn se auto-aplica via body_entered en su propio script.
#
# ℹ️ Los edificios NO se gestionan aquí.
# enter_building.gd en BuildingEntrance gestiona su propia entrada/salida.
#
# 📋 SETUP NPCs PARA DIALOGIC:
# - El NPC debe tener class_name NPC (ya lo tiene)
# - Añadir @export var dialog_timeline: String = "" en npc_main.gd
# - Asignar el path del timeline (.dtl) desde el Inspector del NPC
# - El InteractionArea del player (Interaction/InteractionArea) debe
#   solaparse con el Area2D Conversation del NPC (capa 5)
#
# 📋 INPUT MAP — teclas necesarias:
# - "interact"   → F  (abrir diálogo)
# - ui_accept    → F  (avanzar texto y seleccionar opciones en Dialogic)
# - ui_cancel    → F  (cerrar diálogo al terminar)
# ==========================

var player: MainPlayer = null

# ==========================
# INIT
# ==========================

func initialize(p: MainPlayer) -> void:
	player = p

# ==========================
# PROCESS INTERACTIONS
# ==========================

func process_interactions() -> void:
	if not player or not player.can_move:
		return
	if Input.is_action_just_pressed("interact"):
		InteractionManager.try_interact()

# ==========================
# REGISTRO DE NPCs
# ==========================

func register_npc(npc) -> void:
	print("Registrando NPC: ", npc.name)
	# Route specialized NPCs to their own interaction method
	if npc.is_in_group("npc_hostelkeepers"):
		InteractionManager.register(npc, InteractionManager.Priority.NPC,
			func(): npc.start_hostel_interaction())
	else:
		InteractionManager.register(npc, InteractionManager.Priority.NPC,
			func(): _start_dialog(npc))

func unregister_npc(npc) -> void:
	InteractionManager.unregister(npc)

# ==========================
# DIALOG — DIALOGIC
# ==========================

func _start_dialog(npc) -> void:
	var timeline: String = npc.dialog_timeline
	if timeline.is_empty():
		push_warning("NPC '%s' no tiene dialog_timeline asignado." % npc.name)
		return
	# Orientarse mutuamente
	var player_is_right: bool = player.global_position.x > npc.global_position.x
	npc.animation.lock_facing(player_is_right)
	player.movement.facing_right = not player_is_right
	player.animation.update_animation()
	# Parar ambos
	player.disable_movement()
	npc.movement.freeze()
	if npc.has_method("prepare_dialogic_variables"):
		npc.prepare_dialogic_variables()
	Dialogic.start(timeline)
	Dialogic.timeline_ended.connect(func():
		player.enable_movement()
		npc.movement.unfreeze()
		npc.animation.unlock_facing()

		if npc.has_method("resolve_dialogic_result"):
			await npc.resolve_dialogic_result()
	, CONNECT_ONE_SHOT)
