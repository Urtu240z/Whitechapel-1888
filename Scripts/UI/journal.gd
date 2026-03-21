extends CanvasLayer

# ================================================================
# JOURNAL — journal.gd
# Diario del jugador. Adaptado de otro proyecto.
# Usa PlayerStats y DayNightManager en lugar de GameState.
# Tecla: "stats" (Q) — misma acción que el panel anterior.
# ================================================================

@onready var color_rect = $Control/ColorRect
@onready var texture_rect = $Control/TextureRect
@onready var label_title = $Control/TextureRect/LabelTitle
@onready var label_hour = $Control/TextureRect/LabelHour
@onready var label_attr_text = $Control/TextureRect/LabelAttrText
@onready var label_attr_value = $Control/TextureRect/LabelAttrValue
@onready var badges_container = $Control/TextureRect/HBoxContainerBadges
@onready var grid_physical = $Control/TextureRect/GridContainerPhysical
@onready var grid_mental = $Control/TextureRect/GridContainerMental
@onready var label_money_title = $Control/TextureRect/LabelMoneyTitle
@onready var label_money_value = $Control/TextureRect/LabelMoneyValue
@onready var label_days_title = $Control/TextureRect/LabelDaysTitle
@onready var label_days_value = $Control/TextureRect/LabelDaysValue
@onready var label_physical = $Control/TextureRect/LabelPhysical
@onready var label_mental = $Control/TextureRect/LabelMental

# Fuentes — ajusta las rutas si son diferentes en tu proyecto
var font_title = preload("res://Assets/Fonts/Cinzel.ttf")
var font_body = preload("res://Assets/Fonts/IMFellEnglish.ttf")
var color_ink = Color("#2a1a05")
var color_muted = Color("#7a5a30")

var is_open: bool = false

# Umbrales de sex_appeal para mostrar qué clientes te interesan
const THRESHOLDS = [
	{"label": "Vagabundos", "min": 10},
	{"label": "Trabajadores", "min": 35},
	{"label": "Burgueses", "min": 65},
	{"label": "Nobles", "min": 80}
]


# ================================================================
# INICIALIZACIÓN
# ================================================================

func _ready() -> void:
	label_title.text = "Mi Diario"
	label_attr_text.text = "Atractivo"
	label_physical.text = "ESTADO FÍSICO"
	label_mental.text = "ESTADO MENTAL"
	label_money_title.text = "DINERO"
	label_days_title.text = "DÍA"
	color_rect.color = Color(0, 0, 0, 0.7)
	_apply_styles()
	visible = false

	# Conectamos a stats_updated para que se refresque si está abierto
	PlayerStats.stats_updated.connect(_on_stats_updated)


# ================================================================
# INPUT
# ================================================================

func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("stats"):
		if is_open:
			_close()
		else:
			_open()


# ================================================================
# ABRIR / CERRAR
# ================================================================

func _open() -> void:
	is_open = true
	visible = true
	_update()
	texture_rect.scale = Vector2(0.5, 0.5)
	texture_rect.pivot_offset = texture_rect.size / 2.0
	texture_rect.modulate.a = 0.0
	color_rect.modulate.a = 0.0
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(texture_rect, "scale", Vector2(1.0, 1.0), 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(texture_rect, "modulate:a", 1.0, 0.25)
	tween.tween_property(color_rect, "modulate:a", 1.0, 0.25)


func _close() -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(texture_rect, "scale", Vector2(0.5, 0.5), 0.2).set_ease(Tween.EASE_IN)
	tween.tween_property(texture_rect, "modulate:a", 0.0, 0.2)
	tween.tween_property(color_rect, "modulate:a", 0.0, 0.2)
	await tween.finished
	is_open = false
	visible = false


# ================================================================
# ACTUALIZACIÓN DE DATOS
# ================================================================

func _on_stats_updated() -> void:
	if is_open:
		_update()


func _update() -> void:
	# Hora actual desde DayNightManager
	label_hour.text = _format_hour(DayNightManager.hora_actual)

	# Sex appeal como atractivo general
	label_attr_value.text = str(int(PlayerStats.sex_appeal))

	# Dinero y días
	label_money_value.text = str(int(PlayerStats.dinero)) + "s"
	label_days_value.text = str(_calcular_dia())

	_update_badges()

	# Estado físico
	_update_grid(grid_physical, [
		{"label": "Higiene",    "value": int(PlayerStats.higiene)},
		{"label": "Salud",      "value": int(PlayerStats.salud)},
		{"label": "Stamina",    "value": int(PlayerStats.stamina)},
		{"label": "Hambre",     "value": int(100 - PlayerStats.hambre)},  # invertido: 100=llena
		{"label": "Alcohol",    "value": int(PlayerStats.alcohol)},
		{"label": "Laudano",    "value": int(PlayerStats.laudano)},
		{"label": "Enfermedad", "value": int(PlayerStats.enfermedad)},
		{"label": "Sueño",      "value": int(PlayerStats.sueno)}
	])

	# Estado mental
	_update_grid(grid_mental, [
		{"label": "Felicidad", "value": int(PlayerStats.felicidad)},
		{"label": "Calma",     "value": int(100 - PlayerStats.miedo)},   # invertido
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
	_style_label(label_title, font_title, 22, color_ink)
	_style_label(label_hour, font_body, 13, color_muted)
	_style_label(label_attr_text, font_body, 14, color_ink)
	_style_label(label_attr_value, font_title, 28, color_ink)
	_style_label(label_physical, font_title, 11, color_muted)
	_style_label(label_mental, font_title, 11, color_muted)
	_style_label(label_money_title, font_title, 10, color_muted)
	_style_label(label_money_value, font_body, 18, color_ink)
	_style_label(label_days_title, font_title, 10, color_muted)
	_style_label(label_days_value, font_body, 18, color_ink)


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
	if hh >= 5 and hh < 12:
		period = "Mañana"
	elif hh >= 12 and hh < 20:
		period = "Tarde"
	return "%02d:%02d · %s" % [hh, mm, period]


func _calcular_dia() -> int:
	# Calcula el día basándose en el tiempo acumulado de DayNightManager
	# Empieza en día 1
	var segundos_por_dia = 24.0 * 60.0  # con duracion_hora_segundos = 60
	var dias = int(DayNightManager.tiempo_acumulado / segundos_por_dia) + 1
	return dias
