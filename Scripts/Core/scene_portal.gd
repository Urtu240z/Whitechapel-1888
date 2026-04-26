extends Area2D

# ================================================================
# SCENE PORTAL
# Portal entre escenas usando SceneManager.
#
# portal_id          = ID de este portal en esta escena.
# target_scene_path  = escena destino.
# target_portal_id   = portal donde aparecerá Nell en la escena destino.
# require_interact   = si true, se registra en InteractionManager y requiere F.
# ================================================================

@export_group("Portal IDs")
@export var portal_id: String = ""
@export_file("*.tscn") var target_scene_path: String = ""
@export var target_portal_id: String = ""

@export_group("Activation")
@export var require_interact: bool = false
@export var interact_action: StringName = &"interact"
@export var one_shot: bool = true

@export_group("Interaction UI")
@export var interaction_label: String = ""
@export var interaction_priority: int = 8

@export_group("Transition")
@export var use_fade: bool = true
@export var fade_time: float = 0.5
@export var transition_title: String = ""

var _used: bool = false
var _player_inside: bool = false
var _player_ref: Node = null


func _ready() -> void:
	add_to_group("scene_portal")

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

	if not tree_exiting.is_connected(_on_tree_exiting):
		tree_exiting.connect(_on_tree_exiting)

	# El input lo lee PlayerInteraction -> InteractionManager.try_interact().
	# El portal solo se registra/desregistra como interactuable.
	set_process_unhandled_input(false)


func _on_body_entered(body: Node) -> void:
	if _used:
		return

	if not body.is_in_group("player"):
		return

	_player_inside = true
	_player_ref = body

	if require_interact:
		_register_interaction()
		return

	_trigger_portal()


func _on_body_exited(body: Node) -> void:
	if body != _player_ref:
		return

	_unregister_interaction()
	_player_inside = false
	_player_ref = null


func _on_tree_exiting() -> void:
	_unregister_interaction()


# ================================================================
# INTERACTION MANAGER
# ================================================================
func _register_interaction() -> void:
	if _used:
		return

	if not _player_inside:
		return

	InteractionManager.register(
		self,
		interaction_priority,
		Callable(self, "_trigger_portal"),
		get_interaction_label(),
		str(interact_action)
	)


func _unregister_interaction() -> void:
	InteractionManager.unregister(self)


func get_interaction_label() -> String:
	var clean_label: String = interaction_label.strip_edges()
	if not clean_label.is_empty():
		return clean_label

	var clean_title: String = transition_title.strip_edges()
	if not clean_title.is_empty():
		return "Ir a %s" % clean_title

	return "Cambiar zona"


# ================================================================
# TRAVEL
# ================================================================
func _trigger_portal() -> void:
	if _used:
		return

	if require_interact and not _player_inside:
		return

	if SceneManager.is_transitioning():
		return

	if require_interact and get_node_or_null("/root/StateManager") != null and not StateManager.can_interact():
		return

	if not _is_config_valid():
		return

	_used = true
	_unregister_interaction()

	if one_shot:
		set_deferred("monitoring", false)
		_player_inside = false
		_player_ref = null

	if transition_title.strip_edges() != "":
		SceneManager.show_transition_title(transition_title, fade_time * 2.0)

	SceneManager.travel_to_scene(
		target_scene_path,
		target_portal_id,
		use_fade,
		fade_time,
		_get_final_state_after_travel(),
		"scene_portal_%s" % portal_id
	)


func _get_final_state_after_travel() -> int:
	if get_node_or_null("/root/StateManager") == null:
		return SceneManager.TARGET_STATE_NONE

	return StateManager.State.GAMEPLAY


func _is_config_valid() -> bool:
	if target_scene_path.strip_edges() == "":
		push_warning("ScenePortal: target_scene_path vacío en portal '%s'." % portal_id)
		return false

	if target_portal_id.strip_edges() == "":
		push_warning("ScenePortal: target_portal_id vacío en portal '%s'." % portal_id)
		return false

	return true


func get_portal_id() -> String:
	return portal_id


func get_spawn_global_position() -> Vector2:
	var spawn_point: Node2D = get_node_or_null("SpawnPoint") as Node2D
	return spawn_point.global_position if is_instance_valid(spawn_point) else global_position
