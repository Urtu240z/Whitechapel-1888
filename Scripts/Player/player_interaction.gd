extends Node
# ==========================
# INTERACTION MODULE
# ==========================
# Gestiona las interacciones del jugador con el mundo:
# - Delegar la tecla "interact" al InteractionManager.
#
# Los pickups NO se gestionan aquí.
# El nodo Pickup.tscn se auto-aplica via body_entered en su propio script.
#
# Los edificios, portales y NPCs modernos se registran en InteractionManager.
# ==========================

var player: MainPlayer = null

const PLAYER_LOCK_LEGACY_DIALOG: String = "legacy_npc_dialog"


func initialize(p: MainPlayer) -> void:
	player = p


func process_interactions() -> void:
	if not player:
		return

	if not StateManager.can_interact():
		return

	if Input.is_action_just_pressed("interact"):
		if InteractionManager.try_interact():
			get_viewport().set_input_as_handled()


func register_npc(npc) -> void:
	InteractionManager.register(
		npc,
		InteractionManager.Priority.NPC,
		func(): _start_dialog(npc),
		"Hablar",
		"interact"
	)


func unregister_npc(npc) -> void:
	InteractionManager.unregister(npc)


func _start_dialog(npc) -> void:
	# Clientes/compañeras/servicios modernos gestionan su propio flujo.
	if npc.has_method("start_dialog"):
		npc.start_dialog()
		return

	# NPCs normales — flujo estándar legacy.
	var timeline: String = npc.dialog_timeline
	if timeline.is_empty():
		push_warning("NPC '%s' no tiene dialog_timeline asignado." % npc.name)
		return

	var player_is_right: bool = player.global_position.x > npc.global_position.x
	npc.animation.lock_facing(player_is_right)
	player.movement.facing_right = not player_is_right
	player.animation.update_animation()

	PlayerManager.lock_player(PLAYER_LOCK_LEGACY_DIALOG)
	npc.movement.freeze()

	if npc.has_method("prepare_dialogic_variables"):
		npc.prepare_dialogic_variables()

	await get_tree().process_frame
	StateManager.change_to(StateManager.State.DIALOG, "start_dialog")
	Dialogic.start(timeline)
	Dialogic.timeline_ended.connect(func():
		StateManager.return_to_gameplay("end_dialog")
		PlayerManager.unlock_player(PLAYER_LOCK_LEGACY_DIALOG)
		npc.movement.unfreeze()
		npc.animation.unlock_facing()
		if npc.has_method("resolve_dialogic_result"):
			await npc.resolve_dialogic_result()
	, CONNECT_ONE_SHOT)
