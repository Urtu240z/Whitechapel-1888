extends Node2D

@onready var label_physical   = $LabelPhysical
@onready var label_mental     = $LabelMental
@onready var grid_physical    = $GridContainerPhysical
@onready var grid_mental      = $GridContainerMental
@onready var badges_container = $HBoxContainerBadges

var font_title = preload("res://Assets/Fonts/Cinzel.ttf")
var font_body  = preload("res://Assets/Fonts/IMFellEnglish.ttf")

var color_ink      = Color("#2a1a05")
var color_muted    = Color("#7a5a30")
var color_bar_bg   = Color("#8a6a3a99")
var color_bar_good = Color("#4a7a3088")
var color_bar_bad  = Color("#7a303088")

const BAR_WIDTH  = 100
const BAR_HEIGHT = 10

const THRESHOLDS = [
	{"key": "JOURNAL_BADGE_VAGABONDS", "min": 10},
	{"key": "JOURNAL_BADGE_WORKERS",   "min": 35},
	{"key": "JOURNAL_BADGE_BOURGEOIS", "min": 65},
	{"key": "JOURNAL_BADGE_NOBLES",    "min": 80}
]

const NEGATIVE_STATS = [
	"JOURNAL_STAT_ALCOHOL",
	"JOURNAL_STAT_LAUDANUM",
	"JOURNAL_STAT_DISEASE",
	"JOURNAL_STAT_STRESS",
	"JOURNAL_STAT_NERVES"
]


func _ready() -> void:
	label_physical.text = tr("JOURNAL_PHYSICAL_STATE")
	label_mental.text   = tr("JOURNAL_MENTAL_STATE")
	_apply_styles()
	_update()
	if not PlayerStats.stats_updated.is_connected(_update):
		PlayerStats.stats_updated.connect(_update)


func _update() -> void:
	_update_grid(grid_physical, [
		{"key": "JOURNAL_STAT_HYGIENE",  "value": int(PlayerStats.higiene)},
		{"key": "JOURNAL_STAT_HEALTH",   "value": int(PlayerStats.salud)},
		{"key": "JOURNAL_STAT_STAMINA",  "value": int(PlayerStats.stamina)},
		{"key": "JOURNAL_STAT_HUNGER",   "value": int(100 - PlayerStats.hambre)},
		{"key": "JOURNAL_STAT_ALCOHOL",  "value": int(PlayerStats.alcohol)},
		{"key": "JOURNAL_STAT_LAUDANUM", "value": int(PlayerStats.laudano)},
		{"key": "JOURNAL_STAT_DISEASE",  "value": int(PlayerStats.enfermedad)},
		{"key": "JOURNAL_STAT_SLEEP",    "value": int(PlayerStats.sueno)}
	])
	_update_grid(grid_mental, [
		{"key": "JOURNAL_STAT_HAPPINESS", "value": int(PlayerStats.felicidad)},
		{"key": "JOURNAL_STAT_CALM",      "value": int(100 - PlayerStats.miedo)},
		{"key": "JOURNAL_STAT_STRESS",    "value": int(PlayerStats.estres)},
		{"key": "JOURNAL_STAT_NERVES",    "value": int(PlayerStats.nervios)}
	])
	_update_badges()


func _update_grid(grid: GridContainer, stats: Array) -> void:
	for child in grid.get_children():
		child.queue_free()
	grid.columns = 2

	for stat in stats:
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 2)

		var lbl = Label.new()
		lbl.text = tr(stat.key)
		_style_label(lbl, font_body, 17, color_ink)
		lbl.add_theme_constant_override("outline_size", 1)
		lbl.add_theme_color_override("font_outline_color", color_ink)
		vbox.add_child(lbl)

		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 6)

		var bar_container = Control.new()
		bar_container.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)

		var bg = ColorRect.new()
		bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
		bg.color = color_bar_bg

		var fill = ColorRect.new()
		var ratio = clamp(stat.value / 100.0, 0.0, 1.0)
		fill.size = Vector2(BAR_WIDTH * ratio, BAR_HEIGHT)
		fill.color = color_bar_bad if stat.key in NEGATIVE_STATS else color_bar_good

		bar_container.add_child(bg)
		bar_container.add_child(fill)

		var num_lbl = Label.new()
		num_lbl.text = str(stat.value)
		_style_label(num_lbl, font_body, 15, color_muted)

		hbox.add_child(bar_container)
		hbox.add_child(num_lbl)
		vbox.add_child(hbox)
		grid.add_child(vbox)


func _update_badges() -> void:
	for child in badges_container.get_children():
		child.queue_free()

	for t in THRESHOLDS:
		var label = Label.new()
		var ok = PlayerStats.sex_appeal >= t.min
		label.text = tr(t.key) + (" ✓" if ok else " ✗")
		var col = Color("#4a7a30") if ok else Color("#7a3030")
		_style_label(label, font_body, 17, col)
		label.add_theme_constant_override("outline_size", 1)
		label.add_theme_color_override("font_outline_color", col)
		badges_container.add_child(label)


func _apply_styles() -> void:
	for lbl in [label_physical, label_mental]:
		_style_label(lbl, font_body, 32, Color("#8a5a2e"))
		lbl.add_theme_constant_override("outline_size", 2)
		lbl.add_theme_color_override("font_outline_color", Color("#3a1a08"))


func _style_label(label: Label, font: FontFile, size: int, color: Color) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
