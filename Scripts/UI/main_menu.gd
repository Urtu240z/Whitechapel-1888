extends Control
# =========================================================
# 🎬 MainMenu
# =========================================================

var font_title = preload("res://Assets/Fonts/Cinzel.ttf")
var font_body  = preload("res://Assets/Fonts/IMFellEnglish.ttf")

var color_title  = Color("#8a5a2e")
var color_button = Color("#3a2510")
var color_hover  = Color("#c8a45a")

const GAME_SCENE := "res://Scenes/Story/Intro_Game.tscn"

var _main_panel: VBoxContainer
var _load_panel: VBoxContainer
var _options_panel: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	StateManager.enter(StateManager.State.MENU)
	_build_ui()


func _input(event: InputEvent) -> void:
	var focused = get_viewport().gui_get_focus_owner()

	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		if focused is Button:
			focused.emit_signal("pressed")
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("move_left") or event.is_action_pressed("ui_left"):
		if focused:
			var neighbor = focused.get_focus_neighbor(SIDE_LEFT)
			if neighbor:
				neighbor.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
		if focused:
			var neighbor = focused.get_focus_neighbor(SIDE_RIGHT)
			if neighbor:
				neighbor.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("hide") or event.is_action_pressed("ui_up"):
		if focused:
			var prev = focused.find_prev_valid_focus()
			if prev: prev.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("crouch") or event.is_action_pressed("ui_down"):
		if focused:
			var next = focused.find_next_valid_focus()
			if next: next.grab_focus()
		get_viewport().set_input_as_handled()


# =========================================================
# 🏗️ UI
# =========================================================
func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.03, 0.01, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center = VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 16)
	center.custom_minimum_size = Vector2(400, 0)
	center.position = Vector2(-200, -250)
	add_child(center)

	var title = Label.new()
	title.text = "Whitechapel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", font_title)
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", color_title)
	title.add_theme_constant_override("outline_size", 2)
	title.add_theme_color_override("font_outline_color", Color("#1a0a00"))
	center.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "1888"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override("font", font_body)
	subtitle.add_theme_font_size_override("font_size", 36)
	subtitle.add_theme_color_override("font_color", color_hover)
	center.add_child(subtitle)

	var sep = HSeparator.new()
	sep.custom_minimum_size = Vector2(400, 20)
	center.add_child(sep)

	_main_panel = VBoxContainer.new()
	_main_panel.add_theme_constant_override("separation", 12)
	center.add_child(_main_panel)

	_load_panel = VBoxContainer.new()
	_load_panel.add_theme_constant_override("separation", 12)
	_load_panel.visible = false
	center.add_child(_load_panel)

	_options_panel = VBoxContainer.new()
	_options_panel.add_theme_constant_override("separation", 12)
	_options_panel.visible = false
	center.add_child(_options_panel)

	_build_main_panel()
	_build_load_panel()
	_build_options_panel()


func _build_main_panel() -> void:
	var has_save = SaveManager.slot_exists(0) or SaveManager.slot_exists(1) or SaveManager.slot_exists(2)

	if has_save:
		_add_button(_main_panel, tr("MENU_CONTINUE"), _on_continue_pressed)

	_add_button(_main_panel, tr("MENU_NEW_GAME"), _on_new_game_pressed)

	if has_save:
		_add_button(_main_panel, tr("MENU_LOAD"), _on_load_pressed)

	_add_button(_main_panel, tr("MENU_OPTIONS"), _on_options_pressed)
	_add_button(_main_panel, tr("MENU_QUIT"), _on_quit_pressed)

	_focus_first(_main_panel)


func _build_load_panel() -> void:
	var title = Label.new()
	title.text = tr("MENU_LOAD")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", font_title)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", color_title)
	_load_panel.add_child(title)

	for i in range(3):
		var info = SaveManager.get_slot_info(i)
		var label = ""
		if info.is_empty():
			label = tr("MENU_SLOT_EMPTY") % (i + 1)
		else:
			label = tr("MENU_SAVE_SLOT") % [
				i + 1,
				info.get("dia", 1),
				int(info.get("hora", 0)),
				int(fmod(info.get("hora", 0) * 60, 60)),
				info.get("dinero", 0)
			]

		var btn = _make_button(label)
		if not info.is_empty():
			btn.pressed.connect(_on_slot_load_pressed.bind(i))
		else:
			btn.disabled = true
		_load_panel.add_child(btn)

	_add_button(_load_panel, tr("MENU_BACK"), _on_back_pressed)


func _build_options_panel() -> void:
	var title = Label.new()
	title.text = tr("MENU_OPTIONS")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", font_title)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", color_title)
	_options_panel.add_child(title)

	var lang_label = Label.new()
	lang_label.text = tr("MENU_LANGUAGE")
	lang_label.add_theme_font_override("font", font_body)
	lang_label.add_theme_font_size_override("font_size", 20)
	lang_label.add_theme_color_override("font_color", color_button)
	lang_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_options_panel.add_child(lang_label)

	var lang_hbox = HBoxContainer.new()
	lang_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	lang_hbox.add_theme_constant_override("separation", 16)
	_options_panel.add_child(lang_hbox)

	var btn_es = _make_button("Español")
	btn_es.pressed.connect(func():
		TranslationServer.set_locale("es")
		get_tree().root.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	)
	lang_hbox.add_child(btn_es)

	var btn_en = _make_button("English")
	btn_en.pressed.connect(func():
		TranslationServer.set_locale("en")
		get_tree().root.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	)
	lang_hbox.add_child(btn_en)

	_add_button(_options_panel, tr("MENU_BACK"), _on_back_pressed)


# =========================================================
# 🎛️ HELPERS
# =========================================================
func _add_button(parent: Node, text: String, callback: Callable) -> Button:
	var btn = _make_button(text)
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn


func _make_button(text: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(400, 50)
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_theme_font_override("font", font_body)
	btn.add_theme_font_size_override("font_size", 24)
	btn.add_theme_color_override("font_color", color_button)
	btn.add_theme_color_override("font_hover_color", color_hover)
	btn.add_theme_color_override("font_focus_color", color_hover)
	btn.flat = true

	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.15, 0.08, 0.02, 0.6)
	normal.set_border_width_all(1)
	normal.border_color = Color("#5a3a1a66")
	normal.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", normal)

	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(0.25, 0.15, 0.05, 0.8)
	hover.set_border_width_all(1)
	hover.border_color = Color("#c8a45a99")
	hover.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("focus", hover)

	return btn


func _focus_first(panel: VBoxContainer) -> void:
	for child in panel.get_children():
		if child is Button and not child.disabled:
			child.grab_focus()
			return


# =========================================================
# 🔘 CALLBACKS
# =========================================================
func _on_continue_pressed() -> void:
	StateManager.exit(StateManager.State.MENU)
	for i in range(3):
		if SaveManager.slot_exists(i):
			SaveManager.load_game(i)
			return


func _on_new_game_pressed() -> void:
	StateManager.exit(StateManager.State.MENU)
	SceneManager.change_scene(GAME_SCENE)


func _on_load_pressed() -> void:
	_main_panel.visible = false
	_load_panel.visible = true
	_focus_first(_load_panel)


func _on_options_pressed() -> void:
	_main_panel.visible = false
	_options_panel.visible = true
	_focus_first(_options_panel)


func _on_back_pressed() -> void:
	_load_panel.visible = false
	_options_panel.visible = false
	_main_panel.visible = true
	_focus_first(_main_panel)


func _on_slot_load_pressed(slot: int) -> void:
	StateManager.exit(StateManager.State.MENU)
	SaveManager.load_game(slot)


func _on_quit_pressed() -> void:
	get_tree().quit()
