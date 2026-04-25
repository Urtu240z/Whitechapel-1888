extends CanvasLayer

# ================================================================
# DEBUG MENU
# ================================================================
# Toggle: acción "debug_toggle_menu" / tecla I.
#
# Requiere en StateManager:
# - State.DEBUG_MENU
# - is_debug_menu()
#
# Comportamiento:
# - No usa PAUSED.
# - Muestra ratón.
# - Permite ver efectos en tiempo real si EffectsManager permite DEBUG_MENU.
# - Bloquea movimiento por estado, no por pause global.
# ================================================================

@export var panel_path: NodePath
@export var info_label_path: NodePath
@export var close_button_path: NodePath

var is_open: bool = false

var _panel: Control = null
var _info_label: Label = null
var _close_button: Button = null


# ================================================================
# READY
# ================================================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 1200
	visible = false

	_cache_nodes()
	_connect_buttons()


func _cache_nodes() -> void:
	if panel_path != NodePath():
		_panel = get_node_or_null(panel_path) as Control

	if info_label_path != NodePath():
		_info_label = get_node_or_null(info_label_path) as Label

	if close_button_path != NodePath():
		_close_button = get_node_or_null(close_button_path) as Button

	# Fallbacks por nombre, por si no tienes paths exportados asignados.
	if _panel == null:
		_panel = find_child("Panel", true, false) as Control

	if _info_label == null:
		_info_label = find_child("InfoLabel", true, false) as Label

	if _close_button == null:
		_close_button = find_child("CloseButton", true, false) as Button


func _connect_buttons() -> void:
	if _close_button and not _close_button.pressed.is_connected(_on_close_pressed):
		_close_button.pressed.connect(_on_close_pressed)


# ================================================================
# INPUT
# ================================================================
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle_menu"):
		get_viewport().set_input_as_handled()

		if not _can_toggle_menu():
			return

		_toggle_menu()


func _can_toggle_menu() -> bool:
	return (
		StateManager.is_gameplay()
		or StateManager.is_hiding()
		or StateManager.is_debug_menu()
	)


# ================================================================
# OPEN / CLOSE
# ================================================================
func _toggle_menu() -> void:
	if is_open:
		_close_debug_menu()
	else:
		_open_debug_menu()


func _open_debug_menu() -> void:
	if is_open:
		return

	is_open = true
	visible = true

	if not StateManager.is_debug_menu():
		if not StateManager.push_state(StateManager.State.DEBUG_MENU, "open_debug_menu"):
			is_open = false
			visible = false
			return

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	PlayerManager.lock_player("debug_menu", true)
	PlayerManager.force_stop()

	_refresh_info()
	_recenter_panel()


func _close_debug_menu() -> void:
	if not is_open:
		return

	is_open = false
	visible = false

	PlayerManager.unlock_player("debug_menu")
	get_viewport().gui_release_focus()

	if StateManager.is_debug_menu():
		StateManager.pop_state("close_debug_menu")


func _on_close_pressed() -> void:
	_close_debug_menu()


# ================================================================
# PROCESS
# ================================================================
func _process(_delta: float) -> void:
	if not is_open:
		return

	# Por si algún sistema intenta ocultarlo.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_refresh_info()


# ================================================================
# INFO
# ================================================================
func _refresh_info() -> void:
	if _info_label == null:
		return

	var lines: Array[String] = []

	lines.append("DEBUG MENU")
	lines.append("--------------------")

	if StateManager:
		lines.append("State: %s" % StateManager.current_name())

	if DayNightManager:
		if DayNightManager.has_method("get_day_time_string"):
			lines.append("Time: %s" % DayNightManager.get_day_time_string())
		else:
			lines.append("Hour: %.2f" % DayNightManager.hora_actual)

	if PlayerStats:
		lines.append("Money: %s" % str(PlayerStats.get("dinero")))
		lines.append("Health: %s" % str(PlayerStats.get("salud")))
		lines.append("Stamina: %s" % str(PlayerStats.get("stamina")))
		lines.append("Sleep: %s" % str(PlayerStats.get("sueno")))
		lines.append("Hunger: %s" % str(PlayerStats.get("hambre")))
		lines.append("Hygiene: %s" % str(PlayerStats.get("higiene")))
		lines.append("Fear: %s" % str(PlayerStats.get("miedo")))
		lines.append("Stress: %s" % str(PlayerStats.get("estres")))
		lines.append("Alcohol: %s" % str(PlayerStats.get("alcohol")))
		lines.append("Laudano: %s" % str(PlayerStats.get("laudano")))
		lines.append("Disease: %s" % str(PlayerStats.get("enfermedad")))

	var player := PlayerManager.get_player() if PlayerManager.has_method("get_player") else null
	if is_instance_valid(player):
		lines.append("Player pos: %s" % str(player.global_position))

	_info_label.text = "\n".join(lines)


func _recenter_panel() -> void:
	if _panel == null:
		return

	await get_tree().process_frame

	var viewport_size := get_viewport().get_visible_rect().size
	_panel.position = (viewport_size - _panel.size) * 0.5


# ================================================================
# DEBUG BUTTONS — TIEMPO
# Puedes conectar botones a estos métodos si los tienes en escena.
# ================================================================
func _on_add_1_hour_pressed() -> void:
	if DayNightManager:
		DayNightManager.advance_hours(1.0)
	_refresh_info()


func _on_add_3_hours_pressed() -> void:
	if DayNightManager:
		DayNightManager.advance_hours(3.0)
	_refresh_info()


func _on_add_6_hours_pressed() -> void:
	if DayNightManager:
		DayNightManager.advance_hours(6.0)
	_refresh_info()


func _on_set_morning_pressed() -> void:
	if DayNightManager:
		DayNightManager.set_hora(8.0)
	_refresh_info()


func _on_set_noon_pressed() -> void:
	if DayNightManager:
		DayNightManager.set_hora(12.0)
	_refresh_info()


func _on_set_evening_pressed() -> void:
	if DayNightManager:
		DayNightManager.set_hora(18.0)
	_refresh_info()


func _on_set_night_pressed() -> void:
	if DayNightManager:
		DayNightManager.set_hora(22.0)
	_refresh_info()


# ================================================================
# DEBUG BUTTONS — PLAYER STATS
# Puedes conectar botones a estos métodos si los tienes en escena.
# ================================================================
func _on_heal_pressed() -> void:
	if PlayerStats and PlayerStats.has_method("apply_healing"):
		PlayerStats.apply_healing(10.0, "debug")
	_refresh_info()


func _on_damage_pressed() -> void:
	if PlayerStats and PlayerStats.has_method("apply_damage"):
		PlayerStats.apply_damage(10.0, "debug")
	_refresh_info()


func _on_add_money_pressed() -> void:
	if PlayerStats and PlayerStats.has_method("añadir_dinero"):
		PlayerStats.añadir_dinero(10.0)
	_refresh_info()


func _on_remove_money_pressed() -> void:
	if PlayerStats and PlayerStats.has_method("gastar_dinero"):
		PlayerStats.gastar_dinero(10.0)
	_refresh_info()


func _on_add_alcohol_pressed() -> void:
	if PlayerStats and PlayerStats.has_method("apply_stat_delta"):
		PlayerStats.apply_stat_delta("alcohol", 25.0, "debug")
	_refresh_info()


func _on_clear_alcohol_pressed() -> void:
	if PlayerStats:
		PlayerStats.set("alcohol", 0.0)
		if PlayerStats.has_signal("stats_updated"):
			PlayerStats.stats_updated.emit()
	_refresh_info()


func _on_add_laudano_pressed() -> void:
	if PlayerStats and PlayerStats.has_method("apply_stat_delta"):
		PlayerStats.apply_stat_delta("laudano", 25.0, "debug")
	_refresh_info()


func _on_clear_laudano_pressed() -> void:
	if PlayerStats:
		PlayerStats.set("laudano", 0.0)
		if PlayerStats.has_signal("stats_updated"):
			PlayerStats.stats_updated.emit()
	_refresh_info()


func _on_refresh_pressed() -> void:
	_refresh_info()
