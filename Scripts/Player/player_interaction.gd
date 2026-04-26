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
# Este script conserva el flujo de diálogo para NPCs legacy.
# ==========================

var player: MainPlayer = null
var _legacy_dialog_active: bool = false

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
	if npc == null or not is_instance_valid(npc):
		return

	# Clientes/compañeras/servicios modernos gestionan su propio flujo.
	if npc.has_method("start_dialog"):
		npc.start_dialog()
		return

	_start_legacy_dialog(npc)


func _start_legacy_dialog(npc: Node) -> void:
	if _legacy_dialog_active:
		return

	if not StateManager.can_start_dialog():
		return

	if player == null or not is_instance_valid(player):
		push_warning("PlayerInteraction: no hay player válido para iniciar diálogo legacy.")
		return

	var timeline: String = str(npc.get("dialog_timeline")).strip_edges()
	if timeline.is_empty() or timeline == "<null>":
		push_warning("NPC '%s' no tiene dialog_timeline asignado." % npc.name)
		return

	_legacy_dialog_active = true

	var npc_movement: Node = npc.get("movement") as Node
	var npc_animation: Node = npc.get("animation") as Node
	var player_movement: Node = player.get("movement") as Node
	var player_animation: Node = player.get("animation") as Node

	var player_is_right: bool = false
	if npc is Node2D:
		player_is_right = player.global_position.x > (npc as Node2D).global_position.x

	if npc_animation and npc_animation.has_method("lock_facing"):
		npc_animation.lock_facing(player_is_right)

	if player_movement and player_movement.get("facing_right") != null:
		player_movement.set("facing_right", not player_is_right)

	if player_animation and player_animation.has_method("update_animation"):
		player_animation.update_animation()

	PlayerManager.lock_player(PLAYER_LOCK_LEGACY_DIALOG)

	if npc_movement and npc_movement.has_method("freeze"):
		npc_movement.freeze()

	if npc.has_method("prepare_dialogic_variables"):
		npc.prepare_dialogic_variables()

	await get_tree().process_frame

	if not StateManager.change_to(StateManager.State.DIALOG, "start_legacy_dialog"):
		_finish_legacy_dialog(npc, "start_legacy_dialog_failed")
		return

	# Importante: conectar antes de Dialogic.start(). Si el timeline es muy corto,
	# conectar después puede perder timeline_ended.
	Dialogic.timeline_ended.connect(func():
		if npc.has_method("resolve_dialogic_result"):
			await npc.resolve_dialogic_result()

		_finish_legacy_dialog(npc, "end_legacy_dialog")
	, CONNECT_ONE_SHOT)

	Dialogic.start(timeline)


func _finish_legacy_dialog(npc: Node, return_reason: String) -> void:
	_legacy_dialog_active = false

	if StateManager.is_dialog():
		StateManager.return_to_gameplay(return_reason)

	PlayerManager.unlock_player(PLAYER_LOCK_LEGACY_DIALOG)
	PlayerManager.force_stop()

	if npc != null and is_instance_valid(npc):
		var npc_movement: Node = npc.get("movement") as Node
		var npc_animation: Node = npc.get("animation") as Node

		if npc_movement and npc_movement.has_method("unfreeze"):
			npc_movement.unfreeze()

		if npc_animation and npc_animation.has_method("unlock_facing"):
			npc_animation.unlock_facing()

	PlayerManager.block_movement_input_until_release()
