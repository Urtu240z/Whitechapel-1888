extends CanvasLayer

# ================================================================
# DEBUG MENU — debug_menu.gd
# Adjuntar al root de: res://Scenes/UI/Debug_Menu.tscn
# La escena puede estar vacía: este script crea toda la UI.
# Solo aparece en debug build.
# Toggle: acción InputMap "debug_toggle_menu" (en tu caso tecla I)
# ================================================================

var is_open: bool = false
var _mouse_mode_before_open: Input.MouseMode = Input.MOUSE_MODE_VISIBLE

var _root_control: Control
var _panel: PanelContainer
var _info_label: Label
var _hour_spin: SpinBox

var _btn_plus_1: Button
var _btn_plus_6: Button
var _btn_plus_12: Button
var _btn_plus_24: Button
var _btn_set_hour: Button
var _btn_save_1: Button
var _btn_load_1: Button
var _btn_close: Button
var _money_spin: SpinBox
var _btn_add_money: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 200

	if not OS.is_debug_build():
		queue_free()
		return

	_build_ui()
	visible = false

	if get_viewport():
		get_viewport().size_changed.connect(_recenter_panel)

	if DayNightManager.has_signal("hora_cambiada"):
		DayNightManager.hora_cambiada.connect(_on_hora_cambiada)

	if PlayerStats.has_signal("stats_updated"):
		PlayerStats.stats_updated.connect(_refresh_info)

	_refresh_info()
	_recenter_panel()


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return

	if event.is_action_pressed("debug_toggle_menu"):
		if not _can_toggle_menu():
			return

		_toggle_menu()
		get_viewport().set_input_as_handled()


func _can_toggle_menu() -> bool:
	return StateManager.current() == StateManager.State.GAMEPLAY


func _toggle_menu() -> void:
	is_open = not is_open
	visible = is_open

	if is_open:
		_mouse_mode_before_open = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh_info()
		_recenter_panel()
	else:
		Input.mouse_mode = _mouse_mode_before_open

# ================================================================
# UI
# ================================================================

func _build_ui() -> void:
	_root_control = Control.new()
	_root_control.name = "RootControl"
	_root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_control)

	_panel = PanelContainer.new()
	_panel.name = "DebugPanel"
	_panel.custom_minimum_size = Vector2(640, 420)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root_control.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "DEBUG MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	_info_label = Label.new()
	_info_label.text = "Cargando..."
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_info_label)

	var sep1 := HSeparator.new()
	vbox.add_child(sep1)

	# ------------------------------------------------------------
	# FILA HORAS
	# ------------------------------------------------------------
	var row_hours := HBoxContainer.new()
	row_hours.add_theme_constant_override("separation", 8)
	vbox.add_child(row_hours)

	_btn_plus_1 = Button.new()
	_btn_plus_1.text = "+1h"
	_btn_plus_1.custom_minimum_size = Vector2(110, 42)
	row_hours.add_child(_btn_plus_1)

	_btn_plus_6 = Button.new()
	_btn_plus_6.text = "+6h"
	_btn_plus_6.custom_minimum_size = Vector2(110, 42)
	row_hours.add_child(_btn_plus_6)

	_btn_plus_12 = Button.new()
	_btn_plus_12.text = "+12h"
	_btn_plus_12.custom_minimum_size = Vector2(110, 42)
	row_hours.add_child(_btn_plus_12)

	_btn_plus_24 = Button.new()
	_btn_plus_24.text = "+24h"
	_btn_plus_24.custom_minimum_size = Vector2(110, 42)
	row_hours.add_child(_btn_plus_24)

	# ------------------------------------------------------------
	# FILA SET HORA
	# ------------------------------------------------------------
	var row_set_hour := HBoxContainer.new()
	row_set_hour.add_theme_constant_override("separation", 8)
	vbox.add_child(row_set_hour)

	var set_hour_label := Label.new()
	set_hour_label.text = "Ir a hora:"
	set_hour_label.add_theme_font_size_override("font_size", 16)
	row_set_hour.add_child(set_hour_label)

	_hour_spin = SpinBox.new()
	_hour_spin.min_value = 0
	_hour_spin.max_value = 23
	_hour_spin.step = 1
	_hour_spin.rounded = true
	_hour_spin.custom_minimum_size = Vector2(140, 42)
	row_set_hour.add_child(_hour_spin)

	_btn_set_hour = Button.new()
	_btn_set_hour.text = "Set hora"
	_btn_set_hour.custom_minimum_size = Vector2(140, 42)
	row_set_hour.add_child(_btn_set_hour)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# ------------------------------------------------------------
	# FILA DINERO
	# ------------------------------------------------------------
	var row_money := HBoxContainer.new()
	row_money.add_theme_constant_override("separation", 8)
	vbox.add_child(row_money)

	var money_label := Label.new()
	money_label.text = "Añadir dinero:"
	money_label.add_theme_font_size_override("font_size", 16)
	row_money.add_child(money_label)

	_money_spin = SpinBox.new()
	_money_spin.min_value = 1
	_money_spin.max_value = 9999
	_money_spin.step = 1
	_money_spin.value = 10
	_money_spin.rounded = true
	_money_spin.custom_minimum_size = Vector2(140, 42)
	row_money.add_child(_money_spin)

	_btn_add_money = Button.new()
	_btn_add_money.text = "Añadir"
	_btn_add_money.custom_minimum_size = Vector2(110, 42)
	row_money.add_child(_btn_add_money)

	var sep3 := HSeparator.new()
	vbox.add_child(sep3)

	# ------------------------------------------------------------
	# FILA SAVE / LOAD
	# ------------------------------------------------------------
	var row_save := HBoxContainer.new()
	row_save.add_theme_constant_override("separation", 8)
	vbox.add_child(row_save)

	_btn_save_1 = Button.new()
	_btn_save_1.text = "Guardar S1"
	_btn_save_1.custom_minimum_size = Vector2(160, 42)
	row_save.add_child(_btn_save_1)

	_btn_load_1 = Button.new()
	_btn_load_1.text = "Cargar S1"
	_btn_load_1.custom_minimum_size = Vector2(160, 42)
	row_save.add_child(_btn_load_1)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_save.add_child(spacer)

	_btn_close = Button.new()
	_btn_close.text = "Cerrar"
	_btn_close.custom_minimum_size = Vector2(140, 42)
	row_save.add_child(_btn_close)

	# ------------------------------------------------------------
	# CONEXIONES
	# ------------------------------------------------------------
	_btn_plus_1.pressed.connect(_on_plus_1_pressed)
	_btn_plus_6.pressed.connect(_on_plus_6_pressed)
	_btn_plus_12.pressed.connect(_on_plus_12_pressed)
	_btn_plus_24.pressed.connect(_on_plus_24_pressed)
	_btn_set_hour.pressed.connect(_on_set_hour_pressed)
	_btn_save_1.pressed.connect(_on_save_1_pressed)
	_btn_load_1.pressed.connect(_on_load_1_pressed)
	_btn_close.pressed.connect(_on_close_pressed)
	_btn_add_money.pressed.connect(_on_add_money_pressed)


func _recenter_panel() -> void:
	if not is_instance_valid(_panel):
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_size: Vector2 = _panel.custom_minimum_size

	_panel.position = (viewport_size - panel_size) * 0.5


# ================================================================
# ACCIONES
# ================================================================

func _on_plus_1_pressed() -> void:
	DayNightManager.advance_hours(1.0)
	_refresh_info()


func _on_plus_6_pressed() -> void:
	DayNightManager.advance_hours(6.0)
	_refresh_info()


func _on_plus_12_pressed() -> void:
	DayNightManager.advance_hours(12.0)
	_refresh_info()


func _on_plus_24_pressed() -> void:
	DayNightManager.advance_hours(24.0)
	_refresh_info()


func _on_set_hour_pressed() -> void:
	var target_hour: float = float(int(_hour_spin.value))
	DayNightManager.set_hora(target_hour)
	_refresh_info()


func _on_save_1_pressed() -> void:
	if SaveManager:
		SaveManager.save_game(1)
	_refresh_info()


func _on_load_1_pressed() -> void:
	if SaveManager:
		SaveManager.load_game(1)
	_refresh_info()


func _on_add_money_pressed() -> void:
	PlayerStats.añadir_dinero(float(_money_spin.value))
	_refresh_info()


func _on_close_pressed() -> void:
	is_open = false
	visible = false
	Input.mouse_mode = _mouse_mode_before_open


func _on_hora_cambiada(_hora: float) -> void:
	if visible:
		_refresh_info()


# ================================================================
# INFO
# ================================================================

func _refresh_info() -> void:
	if not is_instance_valid(_info_label):
		return

	var dia: int = 1
	var hora: float = 8.0

	if DayNightManager and DayNightManager.has_method("get_current_day"):
		dia = DayNightManager.get_current_day()

	if DayNightManager and DayNightManager.has_method("get_hour_float"):
		hora = DayNightManager.get_hour_float()

	_hour_spin.value = int(floor(hora))

	var medicina_text := "No"
	if PlayerStats.medicina_activa:
		medicina_text = "Sí"

	_info_label.text = \
		"Día: %02d | Hora: %02d:00\n" % [dia, int(floor(hora))] + \
		"Dinero: %.2f\n" % PlayerStats.dinero + \
		"Hambre: %.1f | Sueño: %.1f | Higiene: %.1f\n" % [PlayerStats.hambre, PlayerStats.sueno, PlayerStats.higiene] + \
		"Salud: %.1f | Estrés: %.1f | Miedo: %.1f\n" % [PlayerStats.salud, PlayerStats.estres, PlayerStats.miedo] + \
		"Medicina activa: %s" % medicina_text
