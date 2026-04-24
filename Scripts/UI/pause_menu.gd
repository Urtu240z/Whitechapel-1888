extends CanvasLayer

const MAIN_MENU_SCENE := "res://Scenes/UI/Main_Menu.tscn"

const PAUSE_LOCK_REASON := "pause_menu"

enum MenuMode {
	MAIN,
	SAVE,
	LOAD,
	SAVE_CONFIRM
}

var is_open: bool = false
var _mode: int = MenuMode.MAIN
var _pending_save_slot: int = -1

var _root: Control
var _panel: VBoxContainer
var _title: Label
var _subtitle: Label
var _buttons_box: VBoxContainer

var _btn_continue: Button
var _btn_save: Button
var _btn_load: Button
var _btn_main_menu: Button
var _btn_quit: Button

var font_title = preload("res://Assets/Fonts/Cinzel.ttf")
var font_body  = preload("res://Assets/Fonts/IMFellEnglish.ttf")

var color_title  = Color("#8a5a2e")
var color_button = Color("#3a2510")
var color_hover  = Color("#c8a45a")


func _ready() -> void:
	if not is_in_group("pause_menu"):
		add_to_group("pause_menu")

	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	_rebuild_menu(MenuMode.MAIN)


func _input(event: InputEvent) -> void:
	if not is_open:
		return

	if event.is_action_pressed("ui_cancel"):
		match _mode:
			MenuMode.MAIN:
				close()
			MenuMode.SAVE_CONFIRM:
				_pending_save_slot = -1
				_rebuild_menu(MenuMode.SAVE)
			_:
				_rebuild_menu(MenuMode.MAIN)

		get_viewport().set_input_as_handled()
		return

	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null:
		call_deferred("_focus_first")
		return

	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		if focused is Button:
			(focused as Button).pressed.emit()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("ui_up") or event.is_action_pressed("hide"):
		var prev: Control = focused.find_prev_valid_focus()
		if prev:
			prev.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("crouch"):
		var next: Control = focused.find_next_valid_focus()
		if next:
			next.grab_focus()
		get_viewport().set_input_as_handled()


func open() -> void:
	if is_open:
		return

	is_open = true
	_pending_save_slot = -1
	_rebuild_menu(MenuMode.MAIN)
	visible = true

	PlayerManager.lock_player(PAUSE_LOCK_REASON, true)
	get_tree().paused = true

	call_deferred("_focus_first")


func close() -> void:
	if not is_open:
		return

	is_open = false
	_pending_save_slot = -1
	visible = false

	get_tree().paused = false
	PlayerManager.unlock_player(PAUSE_LOCK_REASON)
	PlayerManager.force_stop()
	PlayerManager.block_movement_input_until_release()
	get_viewport().gui_release_focus()

	if StateManager.is_paused():
		StateManager.pop_state("resume")


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.95)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	_panel = VBoxContainer.new()
	_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.custom_minimum_size = Vector2(520, 0)
	_panel.add_theme_constant_override("separation", 12)
	center.add_child(_panel)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", font_title)
	_title.add_theme_font_size_override("font_size", 42)
	_title.add_theme_color_override("font_color", color_title)
	_panel.add_child(_title)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_override("font", font_body)
	_subtitle.add_theme_font_size_override("font_size", 22)
	_subtitle.add_theme_color_override("font_color", color_hover)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_subtitle)

	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(520, 16)
	_panel.add_child(sep)

	_buttons_box = VBoxContainer.new()
	_buttons_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons_box.add_theme_constant_override("separation", 10)
	_panel.add_child(_buttons_box)


func _rebuild_menu(new_mode: int) -> void:
	_mode = new_mode
	_clear_buttons()

	match _mode:
		MenuMode.MAIN:
			_title.text = "PAUSA"
			_subtitle.text = "Whitechapel 1888"
			_btn_continue = _add_button("Continuar", _on_continue_pressed)
			_btn_save = _add_button("Guardar", _on_save_pressed)
			_btn_load = _add_button("Cargar", _on_load_pressed)
			_btn_main_menu = _add_button("Menú principal", _on_main_menu_pressed)
			_btn_quit = _add_button("Salir del juego", _on_quit_pressed)

		MenuMode.SAVE:
			_title.text = "GUARDAR PARTIDA"
			_subtitle.text = "Elige un slot"
			for i in range(SaveManager.MAX_SLOTS):
				var slot_index: int = i
				_add_button(_get_save_slot_text(slot_index), func(): _on_save_slot_selected(slot_index))
			_add_button("Volver", _on_back_pressed)

		MenuMode.LOAD:
			_title.text = "CARGAR PARTIDA"
			_subtitle.text = "Elige un slot"
			for i in range(SaveManager.MAX_SLOTS):
				var slot_index: int = i
				var btn: Button = _add_button(_get_load_slot_text(slot_index), func(): await _load_from_slot(slot_index))
				btn.disabled = not SaveManager.slot_exists(slot_index)
			_add_button("Volver", _on_back_pressed)

		MenuMode.SAVE_CONFIRM:
			var slot_num: int = _pending_save_slot + 1
			_title.text = "SOBRESCRIBIR SLOT %d" % slot_num
			if SaveManager.slot_exists(_pending_save_slot):
				var info: Dictionary = SaveManager.get_slot_info(_pending_save_slot)
				_subtitle.text = "Ya existe una partida en este slot.\n%s" % _format_slot_info(info)
			else:
				_subtitle.text = "Este slot está vacío."
			_add_button("Sí, sobrescribir", _confirm_save_overwrite)
			_add_button("No, volver", _cancel_save_overwrite)

	call_deferred("_focus_first")


func _clear_buttons() -> void:
	for child: Node in _buttons_box.get_children():
		child.queue_free()

	_btn_continue = null
	_btn_save = null
	_btn_load = null
	_btn_main_menu = null
	_btn_quit = null


func _focus_first() -> void:
	for child: Node in _buttons_box.get_children():
		if child is Button and not (child as Button).disabled:
			(child as Button).grab_focus()
			return


func _add_button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(520, 52)
	btn.focus_mode = Control.FOCUS_ALL
	btn.flat = true
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.add_theme_font_override("font", font_body)
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", color_button)
	btn.add_theme_color_override("font_hover_color", color_hover)
	btn.add_theme_color_override("font_focus_color", color_hover)
	btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.55, 0.55, 0.8))

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.15, 0.08, 0.02, 0.6)
	normal.set_border_width_all(1)
	normal.border_color = Color("#5a3a1a66")
	normal.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.25, 0.15, 0.05, 0.8)
	hover.set_border_width_all(1)
	hover.border_color = Color("#c8a45a99")
	hover.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("focus", hover)

	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.08, 0.05, 0.02, 0.45)
	disabled.set_border_width_all(1)
	disabled.border_color = Color("#3a2a1a55")
	disabled.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("disabled", disabled)

	btn.pressed.connect(callback)
	_buttons_box.add_child(btn)
	return btn


func _get_save_slot_text(slot: int) -> String:
	if SaveManager.slot_exists(slot):
		var info: Dictionary = SaveManager.get_slot_info(slot)
		return "Guardar en Slot %d  —  %s" % [slot + 1, _format_slot_info(info)]

	return "Guardar en Slot %d  —  Vacío" % [slot + 1]


func _get_load_slot_text(slot: int) -> String:
	if SaveManager.slot_exists(slot):
		var info: Dictionary = SaveManager.get_slot_info(slot)
		return "Cargar Slot %d  —  %s" % [slot + 1, _format_slot_info(info)]

	return "Cargar Slot %d  —  Vacío" % [slot + 1]


func _format_slot_info(info: Dictionary) -> String:
	var dia: int = int(info.get("dia", 1))
	var hora: float = float(info.get("hora", 8.0))
	var dinero: float = float(info.get("dinero", 0.0))
	return "Día %d | %s | £%s" % [dia, _format_hour(hora), str(snapped(dinero, 0.01))]


func _format_hour(hora_float: float) -> String:
	var horas: int = int(floor(hora_float))
	var minutos: int = int(round((hora_float - float(horas)) * 60.0))
	if minutos >= 60:
		minutos = 0
		horas += 1
	horas = horas % 24
	return "%02d:%02d" % [horas, minutos]


func _on_continue_pressed() -> void:
	close()


func _on_save_pressed() -> void:
	_rebuild_menu(MenuMode.SAVE)


func _on_load_pressed() -> void:
	_rebuild_menu(MenuMode.LOAD)


func _on_back_pressed() -> void:
	_pending_save_slot = -1
	_rebuild_menu(MenuMode.MAIN)


func _on_save_slot_selected(slot: int) -> void:
	if SaveManager.slot_exists(slot):
		_pending_save_slot = slot
		_rebuild_menu(MenuMode.SAVE_CONFIRM)
		return

	SaveManager.save_game(slot)
	_rebuild_menu(MenuMode.SAVE)


func _confirm_save_overwrite() -> void:
	if _pending_save_slot < 0:
		_rebuild_menu(MenuMode.SAVE)
		return

	SaveManager.save_game(_pending_save_slot)
	_pending_save_slot = -1
	_rebuild_menu(MenuMode.SAVE)


func _cancel_save_overwrite() -> void:
	_pending_save_slot = -1
	_rebuild_menu(MenuMode.SAVE)


func _load_from_slot(slot: int) -> void:
	if not SaveManager.slot_exists(slot):
		return

	close()
	await SaveManager.load_game(slot)


func _on_main_menu_pressed() -> void:
	close()
	SceneManager.change_scene(MAIN_MENU_SCENE, 0.5, StateManager.State.MENU, "pause_to_main_menu")


func _on_quit_pressed() -> void:
	get_tree().paused = false
	PlayerManager.unlock_player(PAUSE_LOCK_REASON)
	get_tree().quit()
