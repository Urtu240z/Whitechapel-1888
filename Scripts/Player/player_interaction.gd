extends Node
# ==========================
# INTERACTION MODULE
# ==========================
# Gestiona las interacciones del jugador con el mundo:
# - Entrar en edificios (BuildingEntrance) → tecla "interact"
# - Iniciar diálogos con NPCs via Dialogic  → tecla "interact"
#
# ℹ️ Los pickups NO se gestionan aquí.
# El nodo Pickup.tscn se auto-aplica via body_entered en su propio script.
#
# 📋 SETUP NPCs PARA DIALOGIC:
# - El NPC debe tener class_name NPC (ya lo tiene)
# - Añadir @export var dialog_timeline: String = "" en npc_main.gd
# - Asignar el path del timeline (.dtl) desde el Inspector del NPC
# - El InteractionArea del player (Interaction/InteractionArea) debe
#   solaparse con el Area2D Conversation del NPC (capa 5)
#
# 📋 INPUT MAP — teclas necesarias:
# - "interact"   → F  (abrir diálogo / entrar edificio)
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
		_check_for_building_entry()
		_check_for_dialog()

# ==========================
# BUILDING ENTRY
# ==========================
func _check_for_building_entry() -> void:
	var interaction_area = player.get_node_or_null("Interaction/InteractionArea")
	if not interaction_area:
		return

	for area in interaction_area.get_overlapping_areas():
		if area.is_in_group("BuildingEntrance"):
			area.call_deferred("enter_building", player)
			return

# ==========================
# DIALOG — DIALOGIC
# ==========================
func _check_for_dialog() -> void:
	var interaction_area = player.get_node_or_null("Interaction/InteractionArea")
	if not interaction_area:
		return

	for area in interaction_area.get_overlapping_areas():
		var parent = area.get_parent()
		if parent is NPC:
			var timeline: String = parent.dialog_timeline
			if timeline.is_empty():
				push_warning("NPC '%s' no tiene dialog_timeline asignado." % parent.name)
				return

			# Orientarse mutuamente
			var player_is_right: bool = player.global_position.x > parent.global_position.x
			parent.animation.lock_facing(player_is_right)
			player.movement.facing_right = not player_is_right
			player.animation.update_animation()

			# Parar ambos
			player.disable_movement()
			parent.movement.freeze()

			Dialogic.start(timeline)
			Dialogic.timeline_ended.connect(func():
				player.enable_movement()
				parent.movement.unfreeze()
				parent.animation.unlock_facing()
			, CONNECT_ONE_SHOT)
			return
