extends CanvasLayer
# ================================================================
# JOURNAL — journal.gd
# 3 spreads (doble página):
#   Spread 0: Stats (izq) + Sex appeal/clientes (der)
#   Spread 1: Inventario bolsillo (izq) + Silueta equipamiento (der)
#   Spread 2: Mapa (izq) + Objetivos (der)
# Navegación: flechas ArrowLeft / ArrowRight + A/D
# Tecla: "stats" (Q)
# ================================================================

# ================================================================
# NODOS
# ================================================================

@onready var color_rect        = $Control/ColorRect
@onready var journal_container = $Control/JournalContainer
@onready var page_left         = $Control/JournalContainer/JournalBg/PageLeft
@onready var page_right        = $Control/JournalContainer/JournalBg/PageRight
@onready var page_turn_r       = $Control/JournalContainer/JournalBg/PageTurnR
@onready var page_turn_l       = $Control/JournalContainer/JournalBg/PageTurnL
@onready var arrow_left        = $Control/JournalContainer/ArrowLeft
@onready var arrow_right       = $Control/JournalContainer/ArrowRight

@onready var label_title        = $Control/JournalContainer/JournalBg/PageLeft/SpreadL0/LabelTitle
@onready var label_hour         = $Control/JournalContainer/JournalBg/PageLeft/SpreadL0/LabelHour
@onready var label_attr_text    = $Control/JournalContainer/JournalBg/PageLeft/SpreadL0/LabelAttrText
@onready var label_attr_value   = $Control/JournalContainer/JournalBg/PageLeft/SpreadL0/LabelAttrValue
@onready var label_money_title  = $Control/JournalContainer/JournalBg/PageLeft/SpreadL0/LabelMoneyTitle
@onready var label_money_value  = $Control/JournalContainer/JournalBg/PageLeft/SpreadL0/LabelMoneyValue
@onready var label_days_title   = $Control/JournalContainer/JournalBg/PageLeft/SpreadL0/LabelDaysTitle
@onready var label_days_value   = $Control/JournalContainer/JournalBg/PageLeft/SpreadL0/LabelDaysValue

@onready var grid_physical      = $Control/JournalContainer/JournalBg/PageRight/SpreadR0/GridContainerPhysical
@onready var grid_mental        = $Control/JournalContainer/JournalBg/PageRight/SpreadR0/GridContainerMental
@onready var badges_container   = $Control/JournalContainer/JournalBg/PageRight/SpreadR0/HBoxContainerBadges
@onready var label_physical     = $Control/JournalContainer/JournalBg/PageRight/SpreadR0/LabelPhysical
@onready var label_mental       = $Control/JournalContainer/JournalBg/PageRight/SpreadR0/LabelMental

# ================================================================
# FUENTES Y COLORES
# ================================================================

var font_title  = preload("res://Assets/Fonts/Cinzel.ttf")
var font_body   = preload("res://Assets/Fonts/IMFellEnglish.ttf")
var color_ink   = Color("#2a1a05")
var color_muted = Color("#7a5a30")

# ================================================================
# ESTADO
# ================================================================

var is_open: bool = false
var _current_spread: int = 0
const MAX_SPREAD: int = 2
var _transitioning: bool = false

const THRESHOLDS = [
	{"label": "Vagabundos",   "min": 10},
	{"label": "Trabajadores", "min": 35},
	{"label": "Burgueses",    "min": 65},
	{"label": "Nobles",       "min": 80}
]

# ================================================================
# READY
# ================================================================

func _ready() -> void:
	label_title.text       = "Mi Diario"
	label_attr_text.text   = "Atractivo"
	label_physical.text    = "ESTADO FÍSICO"
	label_mental.text      = "ESTADO MENTAL"
	label_money_title.text = "DINERO"
	label_days_title.text  = "DÍA"
	color_rect.color = Color(0, 0, 0, 0.7)
	_apply_styles()
	visible = false

	page_turn_r.visible = false
	page_turn_l.visible = false

	# Pivot en el borde de encuadernación
	page_turn_r.pivot_offset = Vector2(0.0, page_turn_r.size.y / 2.0)
	page_turn_l.pivot_offset = Vector2(page_turn_l.size.x, page_turn_l.size.y / 2.0)

	arrow_left.pressed.connect(_on_arrow_left)
	arrow_right.pressed.connect(_on_arrow_right)

	PlayerStats.stats_updated.connect(_on_stats_updated)

# ================================================================
# INPUT
# ================================================================

func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("stats"):
		if is_open:
			_close()
		else:
			_open()
		return

	if not is_open:
		return

	if Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("move_right"):
		_on_arrow_right()
	elif Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("move_left"):
		_on_arrow_left()

# ================================================================
# ABRIR / CERRAR
# ================================================================

func _open() -> void:
	is_open = true
	visible = true
	_current_spread = 0
	_update_spread()
	_update_arrows()
	journal_container.scale = Vector2(0.5, 0.5)
	journal_container.pivot_offset = journal_container.size / 2.0
	journal_container.modulate.a = 0.0
	color_rect.modulate.a = 0.0
	var tw = create_tween().set_parallel(true)
	tw.tween_property(journal_container, "scale", Vector2(1.0, 1.0), 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(journal_container, "modulate:a", 1.0, 0.25)
	tw.tween_property(color_rect, "modulate:a", 1.0, 0.25)
	PlayerManager.player_instance.disable_movement()

func _close() -> void:
	var tw = create_tween().set_parallel(true)
	tw.tween_property(journal_container, "scale", Vector2(0.5, 0.5), 0.2).set_ease(Tween.EASE_IN)
	tw.tween_property(journal_container, "modulate:a", 0.0, 0.2)
	tw.tween_property(color_rect, "modulate:a", 0.0, 0.2)
	await tw.finished
	is_open = false
	visible = false
	PlayerManager.player_instance.enable_movement()

# ================================================================
# NAVEGACIÓN
# ================================================================

func _on_arrow_right() -> void:
	if _transitioning or _current_spread >= MAX_SPREAD:
		return
	_page_turn(1)

func _on_arrow_left() -> void:
	if _transitioning or _current_spread <= 0:
		return
	_page_turn(-1)

func _page_turn(direction: int) -> void:
	_transitioning = true
	var turn_node  = page_turn_r if direction > 0 else page_turn_l
	var unfold_node = page_turn_l if direction > 0 else page_turn_r
	var mat        = turn_node.get_node("TextureRect").material as ShaderMaterial
	var unfold_mat = unfold_node.get_node("TextureRect").material as ShaderMaterial

	# Preparar nodo que se dobla
	turn_node.visible = true
	unfold_node.visible = false
	mat.set_shader_parameter("fold_progress", 0.0)
	mat.set_shader_parameter("fold_from_right", direction > 0)

	var tw = create_tween()

	# Primera mitad — doblar hasta desaparecer
	tw.tween_method(
		func(v: float): mat.set_shader_parameter("fold_progress", v),
		0.0, 1.0, 0.6
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

	# Punto medio — swap contenido, ocultar doblada, preparar la que se despliega
	tw.tween_callback(func():
		_current_spread += direction
		_update_spread()
		_update_arrows()
		turn_node.visible = false
		unfold_mat.set_shader_parameter("fold_progress", 1.0)
		unfold_mat.set_shader_parameter("fold_from_right", direction < 0)
		unfold_node.visible = true
	)

	# Segunda mitad — desdoblar desde plegada hasta plana
	tw.tween_method(
		func(v: float): unfold_mat.set_shader_parameter("fold_progress", v),
		1.0, 0.0, 0.3
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	tw.tween_callback(func():
		unfold_node.visible = false
		_transitioning = false
	)

func _update_arrows() -> void:
	arrow_left.visible  = _current_spread > 0
	arrow_right.visible = _current_spread < MAX_SPREAD

# ================================================================
# SPREADS
# ================================================================

func _update_spread() -> void:
	match _current_spread:
		0: _show_spread_stats()
		1: _show_spread_inventory()
		2: _show_spread_map_objectives()

func _show_spread_stats() -> void:
	_update_stats()

func _show_spread_inventory() -> void:
	pass

func _show_spread_map_objectives() -> void:
	pass

# ================================================================
# STATS (spread 0)
# ================================================================

func _on_stats_updated() -> void:
	if is_open and _current_spread == 0:
		_update_stats()

func _update_stats() -> void:
	label_hour.text        = _format_hour(DayNightManager.hora_actual)
	label_attr_value.text  = str(int(PlayerStats.sex_appeal))
	label_money_value.text = str(int(PlayerStats.dinero)) + "s"
	label_days_value.text  = str(_calcular_dia())
	_update_badges()
	_update_grid(grid_physical, [
		{"label": "Higiene",    "value": int(PlayerStats.higiene)},
		{"label": "Salud",      "value": int(PlayerStats.salud)},
		{"label": "Stamina",    "value": int(PlayerStats.stamina)},
		{"label": "Hambre",     "value": int(100 - PlayerStats.hambre)},
		{"label": "Alcohol",    "value": int(PlayerStats.alcohol)},
		{"label": "Laudano",    "value": int(PlayerStats.laudano)},
		{"label": "Enfermedad", "value": int(PlayerStats.enfermedad)},
		{"label": "Sueño",      "value": int(PlayerStats.sueno)}
	])
	_update_grid(grid_mental, [
		{"label": "Felicidad", "value": int(PlayerStats.felicidad)},
		{"label": "Calma",     "value": int(100 - PlayerStats.miedo)},
		{"label": "Estres",    "value": int(PlayerStats.estres)},
		{"label": "Nervios",   "value": int(PlayerStats.nervios)}
	])

func _update_badges() -> void:
	for child in badges_container.get_children():
		child.queue_free()
	for t in THRESHOLDS:
		var label = Label.new()
		var ok = PlayerStats.sex_appeal >= t.min
		label.text = t.label + (" ✓" if ok else " ✗")
		_style_label(label, font_body, 12, color_ink)
		badges_container.add_child(label)

func _update_grid(grid: GridContainer, stats: Array) -> void:
	for child in grid.get_children():
		child.queue_free()
	grid.columns = 2
	for stat in stats:
		var label = Label.new()
		label.text = stat.label + ": " + str(stat.value) + "/100"
		_style_label(label, font_body, 12, color_ink)
		grid.add_child(label)

# ================================================================
# ESTILOS
# ================================================================

func _apply_styles() -> void:
	_style_label(label_title,       font_title, 22, color_ink)
	_style_label(label_hour,        font_body,  13, color_muted)
	_style_label(label_attr_text,   font_body,  14, color_ink)
	_style_label(label_attr_value,  font_title, 28, color_ink)
	_style_label(label_physical,    font_title, 11, color_muted)
	_style_label(label_mental,      font_title, 11, color_muted)
	_style_label(label_money_title, font_title, 10, color_muted)
	_style_label(label_money_value, font_body,  18, color_ink)
	_style_label(label_days_title,  font_title, 10, color_muted)
	_style_label(label_days_value,  font_body,  18, color_ink)

func _style_label(label: Label, font: FontFile, size: int, color: Color) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)

# ================================================================
# HELPERS
# ================================================================

func _format_hour(h: float) -> String:
	var hh = int(h)
	var mm = int((h - hh) * 60)
	var period = "Noche"
	if hh >= 5 and hh < 12:   period = "Mañana"
	elif hh >= 12 and hh < 20: period = "Tarde"
	return "%02d:%02d · %s" % [hh, mm, period]

func _calcular_dia() -> int:
	var segundos_por_dia = 24.0 * 60.0
	return int(DayNightManager.tiempo_acumulado / segundos_por_dia) + 1
