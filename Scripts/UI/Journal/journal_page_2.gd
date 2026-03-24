extends Node2D

@onready var label_physical    = $LabelPhysical
@onready var label_mental      = $LabelMental
@onready var grid_physical     = $GridContainerPhysical
@onready var grid_mental       = $GridContainerMental
@onready var badges_container  = $HBoxContainerBadges

var font_title = preload("res://Assets/Fonts/Cinzel.ttf")
var font_body  = preload("res://Assets/Fonts/IMFellEnglish.ttf")
var color_ink   = Color("#2a1a05")
var color_muted = Color("#7a5a30")

const THRESHOLDS = [
	{"label": "Vagabundos",   "min": 10},
	{"label": "Trabajadores", "min": 35},
	{"label": "Burgueses",    "min": 65},
	{"label": "Nobles",       "min": 80}
]

func _ready() -> void:
	label_physical.text = "ESTADO FÍSICO"
	label_mental.text   = "ESTADO MENTAL"
	_apply_styles()
	_update()
	PlayerStats.stats_updated.connect(_update)

func _update() -> void:
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
	_update_badges()

func _update_grid(grid: GridContainer, stats: Array) -> void:
	for child in grid.get_children():
		child.queue_free()
	grid.columns = 2
	for stat in stats:
		var label = Label.new()
		label.text = stat.label + ": " + str(stat.value) + "/100"
		_style_label(label, font_body, 18, color_ink)
		grid.add_child(label)

func _update_badges() -> void:
	for child in badges_container.get_children():
		child.queue_free()
	for t in THRESHOLDS:
		var label = Label.new()
		var ok = PlayerStats.sex_appeal >= t.min
		label.text = t.label + (" ✓" if ok else " ✗")
		_style_label(label, font_body, 18, color_ink)
		badges_container.add_child(label)

func _apply_styles() -> void:
	_style_label(label_physical, font_title, 26, color_muted)
	_style_label(label_mental,   font_title, 26, color_muted)

func _style_label(label: Label, font: FontFile, size: int, color: Color) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
