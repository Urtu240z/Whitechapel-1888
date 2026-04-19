extends Node

# ================================================================
# PORTAL MANAGER
# Guarda el portal destino entre cambios de escena.
# Autoload: PortalManager
# ================================================================

var _pending_target_portal_id: String = ""
var _has_pending_spawn: bool = false


func travel_to_scene(
	scene_path: String,
	target_portal_id: String,
	use_fade: bool = true,
	fade_time: float = 0.5
) -> void:
	_pending_target_portal_id = target_portal_id
	_has_pending_spawn = true

	if use_fade and is_instance_valid(SceneManager):
		SceneManager.change_scene(scene_path, fade_time)
	else:
		get_tree().change_scene_to_file(scene_path)


func has_pending_spawn() -> bool:
	return _has_pending_spawn


func get_pending_target_portal_id() -> String:
	return _pending_target_portal_id if _has_pending_spawn else ""


func clear_pending_spawn() -> void:
	_pending_target_portal_id = ""
	_has_pending_spawn = false
