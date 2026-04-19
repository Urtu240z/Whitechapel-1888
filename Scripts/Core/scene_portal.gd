extends Area2D

# ================================================================
# SCENE PORTAL
# Portal entre escenas con portal_id y target_portal_id
# ================================================================

@export_group("Portal IDs")
@export var portal_id: String = ""
@export_file("*.tscn") var target_scene_path: String = ""
@export var target_portal_id: String = ""

@export_group("Activation")
@export var require_interact: bool = false
@export var interact_action: StringName = &"interact"
@export var one_shot: bool = true

@export_group("Transition")
@export var use_fade: bool = true
@export var fade_time: float = 0.5

var _used: bool = false
var _player_inside: bool = false
var _player_ref: Node = null


func _ready() -> void:
	add_to_group("scene_portal")

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

	set_process_unhandled_input(require_interact)


func _on_body_entered(body: Node) -> void:
	if _used:
		return
	if not body.is_in_group("player"):
		return

	if require_interact:
		_player_inside = true
		_player_ref = body
	else:
		_trigger_portal()


func _on_body_exited(body: Node) -> void:
	if body == _player_ref:
		_player_inside = false
		_player_ref = null


func _unhandled_input(event: InputEvent) -> void:
	if not require_interact:
		return
	if _used:
		return
	if not _player_inside:
		return

	if event.is_action_pressed(interact_action):
		_trigger_portal()


func _trigger_portal() -> void:
	if _used:
		return

	if target_scene_path.strip_edges() == "":
		push_warning("ScenePortal: target_scene_path vacío en portal '%s'." % portal_id)
		return

	if target_portal_id.strip_edges() == "":
		push_warning("ScenePortal: target_portal_id vacío en portal '%s'." % portal_id)
		return

	_used = true

	if one_shot:
		set_deferred("monitoring", false)
		_player_inside = false
		_player_ref = null

	PortalManager.travel_to_scene(
		target_scene_path,
		target_portal_id,
		use_fade,
		fade_time
	)


func get_portal_id() -> String:
	return portal_id


func get_spawn_global_position() -> Vector2:
	var spawn_point: Node2D = get_node_or_null("SpawnPoint") as Node2D
	return spawn_point.global_position if is_instance_valid(spawn_point) else global_position
