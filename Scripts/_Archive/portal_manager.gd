extends Node

# ================================================================
# PORTAL MANAGER — LEGACY WRAPPER
# ================================================================
# Este autoload queda jubilado.
# La autoridad real de portales pendientes ahora es SceneManager.
#
# Puedes quitar PortalManager de Project Settings > Autoload cuando no
# quede ninguna referencia directa a él.
# ================================================================

func travel_to_scene(
	scene_path: String,
	target_portal_id: String,
	use_fade: bool = true,
	fade_time: float = 0.5
) -> void:
	SceneManager.travel_to_scene(
		scene_path,
		target_portal_id,
		use_fade,
		fade_time,
		_get_final_state_after_travel(),
		"portal_manager_legacy"
	)


func has_pending_spawn() -> bool:
	return SceneManager.has_pending_portal_spawn()


func get_pending_target_portal_id() -> String:
	return SceneManager.get_pending_portal_id()


func clear_pending_spawn() -> void:
	SceneManager.clear_pending_portal_spawn()


func _get_final_state_after_travel() -> int:
	if get_node_or_null("/root/StateManager") == null:
		return SceneManager.TARGET_STATE_NONE

	return StateManager.State.GAMEPLAY
