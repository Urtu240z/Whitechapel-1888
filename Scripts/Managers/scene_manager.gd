extends Node
# =========================================================
# 🎬 SceneManager
# Responsabilidades:
# - Fade negro entre escenas
# - Bloqueo de input durante la transición
# - Guard contra reentradas
#
# Uso simple (sin player):
#   SceneManager.change_scene("res://Scenes/Menu.tscn")
#
# Uso con player (desde PlayerManager):
#   await SceneManager._fade_out()
#   ... cambiar escena ...
#   await SceneManager._fade_in()
# =========================================================
var _layer: CanvasLayer
var _fade: ColorRect
var _blocking: Control
var _is_transitioning: bool = false


func _ready() -> void:
	# CanvasLayer persistente entre escenas
	_layer = CanvasLayer.new()
	add_child(_layer)

	# Rectángulo negro a pantalla completa
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_fade)

	# Bloqueador de input durante el fade
	_blocking = Control.new()
	_blocking.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocking.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocking.focus_mode = Control.FOCUS_ALL
	_blocking.visible = false
	_layer.add_child(_blocking)


# =========================================================
# 🔁 Cambio de escena simple (sin player, sin sonidos)
# =========================================================
func change_scene(target_path: String, fade_time: float = 0.5) -> void:
	if _is_transitioning:
		push_warning("SceneManager: transición ya en curso, ignorando.")
		return
	_do_change_scene(target_path, fade_time)


func _do_change_scene(target_path: String, fade_time: float) -> void:
	_is_transitioning = true
	await _fade_out(fade_time)
	get_tree().change_scene_to_file(target_path)
	await get_tree().process_frame
	await _fade_in(fade_time)
	_is_transitioning = false


# =========================================================
# 🔍 Estado de transición
# =========================================================
func is_transitioning() -> bool:
	return _is_transitioning


# =========================================================
# 🌑 Fade out / Fade in — públicos para uso desde PlayerManager
# =========================================================
func _fade_out(duration: float = 0.5) -> void:
	_blocking.visible = true
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_fade, "color:a", 1.0, duration)
	await tw.finished


func _fade_in(duration: float = 0.5) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_fade, "color:a", 0.0, duration)
	await tw.finished
	_blocking.visible = false
