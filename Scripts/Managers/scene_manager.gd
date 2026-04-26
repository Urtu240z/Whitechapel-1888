extends Node

# ================================================================
# SCENE MANAGER — Autoload
# ================================================================
# Autoridad única para:
# - fades globales
# - bloqueo visual/input durante transición
# - cambios de escena
# - spawn pendiente por portal entre escenas
# ================================================================

signal transition_started(reason: String)
signal transition_finished(reason: String)
signal fade_started(fade_out: bool, duration: float)
signal fade_finished(fade_out: bool)
signal scene_change_started(target_path: String)
signal scene_change_finished(target_path: String)
signal pending_portal_spawn_set(portal_id: String)
signal pending_portal_spawn_cleared()

const DEBUG_LOGS: bool = true
const DEFAULT_LAYER: int = 1000
const TARGET_STATE_NONE: int = -1
const TRANSITION_TITLE_LAYER: int = 1100
const TRANSITION_TITLE_FONT_PATH: String = "res://Assets/Fonts/IMFellEnglish.ttf"

var _title_layer: CanvasLayer = null
var _layer: CanvasLayer
var _fade: ColorRect
var _blocking: Control

var _is_transitioning: bool = false
var _active_reason: String = ""

var _pending_portal_id: String = ""
var _has_pending_portal_spawn: bool = false


# ================================================================
# READY
# ================================================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_canvas_layer()


func _setup_canvas_layer() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "SceneManagerLayer"
	_layer.layer = DEFAULT_LAYER
	add_child(_layer)

	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_fade)

	_blocking = Control.new()
	_blocking.name = "InputBlocker"
	_blocking.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocking.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocking.focus_mode = Control.FOCUS_ALL
	_blocking.visible = false
	_layer.add_child(_blocking)


# ================================================================
# ESTADO
# ================================================================
func is_transitioning() -> bool:
	return _is_transitioning


func is_screen_black() -> bool:
	return _fade.color.a >= 0.99


func is_input_blocked() -> bool:
	return _blocking.visible


func get_active_reason() -> String:
	return _active_reason


# ================================================================
# CAMBIO DE ESCENA SIMPLE
# ================================================================
# target_state:
# - TARGET_STATE_NONE: no fuerza estado final.
# - StateManager.State.GAMEPLAY / MENU / etc: intenta dejar ese estado al acabar.
#
# Ejemplos:
#   SceneManager.change_scene(path)
#   SceneManager.change_scene(path, 0.5, StateManager.State.MENU)
# ================================================================
func change_scene(
	target_path: String,
	fade_time: float = 0.5,
	target_state = TARGET_STATE_NONE,
	reason: String = "scene_change"
) -> void:
	if not _can_start_transition(reason):
		return

	if not _is_valid_scene_path(target_path):
		return

	_begin_transition(reason)
	_enter_transition_state(reason)

	scene_change_started.emit(target_path)

	await fade_out(fade_time, false)

	var err: Error = get_tree().change_scene_to_file(target_path)
	if err != OK:
		push_error("SceneManager: no se pudo cambiar a escena '%s'. Error: %s" % [target_path, str(err)])
		await fade_in(fade_time, false)
		_finish_transition(reason, target_state)
		return

	await get_tree().process_frame
	await fade_in(fade_time, false)

	scene_change_finished.emit(target_path)
	_finish_transition(reason, target_state)


# ================================================================
# CAMBIO DE ESCENA CON PORTAL
# ================================================================
func travel_to_scene(
	target_scene_path: String,
	target_portal_id: String,
	use_fade: bool = true,
	fade_time: float = 0.5,
	target_state = TARGET_STATE_NONE,
	reason: String = "portal_travel"
) -> void:
	if not _can_start_transition(reason):
		return

	if not _is_valid_scene_path(target_scene_path):
		return

	var clean_portal_id: String = target_portal_id.strip_edges()
	if clean_portal_id == "":
		push_warning("SceneManager.travel_to_scene(): target_portal_id vacío.")
		return

	_set_pending_portal_spawn(clean_portal_id)

	if use_fade:
		await change_scene(target_scene_path, fade_time, target_state, reason)
	else:
		_begin_transition(reason)

		var err: Error = get_tree().change_scene_to_file(target_scene_path)
		if err != OK:
			push_error("SceneManager: no se pudo cambiar a escena '%s'. Error: %s" % [target_scene_path, str(err)])
			clear_pending_portal_spawn()
			_finish_transition(reason, target_state)
			return

		await get_tree().process_frame
		_finish_transition(reason, target_state)


# ================================================================
# PORTAL PENDIENTE
# ================================================================
func has_pending_portal_spawn() -> bool:
	return _has_pending_portal_spawn


func get_pending_portal_id() -> String:
	return _pending_portal_id if _has_pending_portal_spawn else ""


func consume_pending_portal_id() -> String:
	var result: String = get_pending_portal_id()
	clear_pending_portal_spawn()
	return result


func clear_pending_portal_spawn() -> void:
	_pending_portal_id = ""
	_has_pending_portal_spawn = false
	pending_portal_spawn_cleared.emit()


func _set_pending_portal_spawn(portal_id: String) -> void:
	_pending_portal_id = portal_id
	_has_pending_portal_spawn = true
	pending_portal_spawn_set.emit(portal_id)

	if OS.is_debug_build() and DEBUG_LOGS:
		print("🚪 Portal pendiente: %s" % portal_id)


# ================================================================
# FADES PÚBLICOS
# ================================================================
# manage_transition=true se usa cuando quieres que fade_out/fade_in
# funcionen como transición por sí solos.
# En change_scene usamos false porque la transición ya la gestiona change_scene.
# ================================================================
func fade_out(duration: float = 0.5, manage_transition: bool = true, reason: String = "fade_out") -> void:
	if manage_transition:
		if not _can_start_transition(reason):
			return
		_begin_transition(reason)

	_blocking.visible = true
	fade_started.emit(true, duration)

	var tw: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_fade, "color:a", 1.0, maxf(duration, 0.0))
	await tw.finished

	fade_finished.emit(true)


func fade_in(duration: float = 0.5, manage_transition: bool = true, reason: String = "fade_in") -> void:
	fade_started.emit(false, duration)

	var tw: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_fade, "color:a", 0.0, maxf(duration, 0.0))
	await tw.finished

	_blocking.visible = false
	fade_finished.emit(false)

	if manage_transition:
		_finish_transition(reason, TARGET_STATE_NONE)

func show_transition_title(title: String, total_duration: float = 1.0) -> void:
	var clean_title := title.strip_edges()
	if clean_title == "":
		return

	_clear_transition_title()

	_title_layer = CanvasLayer.new()
	_title_layer.name = "TransitionTitleLayer"
	_title_layer.layer = TRANSITION_TITLE_LAYER
	get_tree().root.add_child(_title_layer)

	var lbl := Label.new()
	lbl.text = clean_title
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)

	var font := load(TRANSITION_TITLE_FONT_PATH) as FontFile
	if font:
		lbl.add_theme_font_override("font", font)

	lbl.add_theme_font_size_override("font_size", 36)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
	lbl.modulate.a = 0.0

	_title_layer.add_child(lbl)

	var title_duration: float = total_duration * (2.0 / 3.0)
	var title_delay: float = (total_duration - title_duration) * 0.5
	var fade_title: float = title_duration * 0.2
	var visible_time: float = max(title_duration - fade_title * 2.0, 0.0)

	var tween := _title_layer.create_tween()
	tween.tween_interval(title_delay)
	tween.tween_property(lbl, "modulate:a", 1.0, fade_title)
	tween.tween_interval(visible_time)
	tween.tween_property(lbl, "modulate:a", 0.0, fade_title)
	tween.tween_callback(_clear_transition_title)


func _clear_transition_title() -> void:
	if _title_layer and is_instance_valid(_title_layer):
		_title_layer.queue_free()

	_title_layer = null


func snap_black(reason: String = "snap_black") -> void:
	if not _is_transitioning:
		_begin_transition(reason)

	_blocking.visible = true
	_fade.color.a = 1.0


func snap_clear(reason: String = "snap_clear") -> void:
	_fade.color.a = 0.0
	_blocking.visible = false

	if _is_transitioning:
		_finish_transition(reason, TARGET_STATE_NONE)


# ================================================================
# BLOQUEO INPUT MANUAL
# ================================================================
func set_input_blocked(blocked: bool) -> void:
	_blocking.visible = blocked


# ================================================================
# INTERNO — TRANSICIÓN
# ================================================================
func _can_start_transition(reason: String) -> bool:
	if _is_transitioning:
		push_warning("SceneManager: transición ya en curso, ignorando '%s'." % reason)
		return false
	return true


func _begin_transition(reason: String) -> void:
	_is_transitioning = true
	_active_reason = reason
	transition_started.emit(reason)

	if OS.is_debug_build() and DEBUG_LOGS:
		print("🎬 SceneManager inicia transición: %s" % reason)


func _finish_transition(reason: String, target_state) -> void:
	_is_transitioning = false
	_active_reason = ""
	transition_finished.emit(reason)
	_apply_final_state(target_state, reason)

	if OS.is_debug_build() and DEBUG_LOGS:
		print("🎬 SceneManager termina transición: %s" % reason)


func _enter_transition_state(reason: String) -> void:
	if not _has_state_manager():
		return

	if StateManager.is_transitioning():
		return

	if StateManager.can_change_to(StateManager.State.TRANSITIONING):
		StateManager.change_to(StateManager.State.TRANSITIONING, reason)


func _apply_final_state(target_state, reason: String) -> void:
	if target_state == TARGET_STATE_NONE:
		return

	if not _has_state_manager():
		return

	if StateManager.current() == target_state:
		return

	if StateManager.can_change_to(target_state):
		StateManager.change_to(target_state, "%s_finished" % reason)
	else:
		StateManager.force_state(target_state, "%s_finished_forced" % reason)


func _has_state_manager() -> bool:
	return get_node_or_null("/root/StateManager") != null


func _is_valid_scene_path(path: String) -> bool:
	var clean_path: String = path.strip_edges()
	if clean_path == "":
		push_warning("SceneManager: target_path vacío.")
		return false

	if not ResourceLoader.exists(clean_path):
		push_warning("SceneManager: no existe la escena: %s" % clean_path)
		return false

	return true
