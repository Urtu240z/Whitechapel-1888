extends Node2D

@onready var label_title       = $LabelTitle
@onready var label_hour        = $LabelHour
@onready var label_attr_text   = $LabelAttrText
@onready var label_attr_value  = $LabelAttrValue
@onready var label_money_title = $LabelMoneyTitle
@onready var label_money_value = $LabelMoneyValue
@onready var label_days_title  = $LabelDaysTitle
@onready var label_days_value  = $LabelDaysValue
@onready var attr_bar_container = $AttrBarContainer

var font_title = preload("res://Assets/Fonts/Cinzel.ttf")
var font_body  = preload("res://Assets/Fonts/IMFellEnglish.ttf")

var color_title  = Color("#8a5a2e")
var color_ink    = Color("#3a2510")
var color_muted  = Color("#7a5a30")
var color_bar_bg   = Color("#8a6a3a99")
var color_bar_fill = Color("#5c7a3088")

const BAR_WIDTH  = 140
const BAR_HEIGHT = 10
const CONFIG = preload("res://Data/Game/game_config.tres")

func _ready() -> void:
	label_title.text       = tr("JOURNAL_TITLE")
	label_attr_text.text   = tr("JOURNAL_ATTR_LABEL")
	label_money_title.text = tr("JOURNAL_MONEY_LABEL")
	label_days_title.text  = tr("JOURNAL_DAY_LABEL")
	_apply_styles()
	_update()
	if not PlayerStats.stats_updated.is_connected(_update):
		PlayerStats.stats_updated.connect(_update)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_L:
		_toggle_language()


func _toggle_language() -> void:
	var current = TranslationServer.get_locale()
	if current == "es":
		TranslationServer.set_locale("en")
	else:
		TranslationServer.set_locale("es")
	label_title.text       = tr("JOURNAL_TITLE")
	label_attr_text.text   = tr("JOURNAL_ATTR_LABEL")
	label_money_title.text = tr("JOURNAL_MONEY_LABEL")
	label_days_title.text  = tr("JOURNAL_DAY_LABEL")
	_update()


func _update() -> void:
	label_hour.text        = _format_hour(DayNightManager.hora_actual)
	label_attr_value.text  = str(int(PlayerStats.sex_appeal))
	label_money_value.text = str(int(PlayerStats.dinero)) + " s."
	label_days_value.text  = str(_calcular_dia())
	_update_attr_bar()


func _apply_styles() -> void:
	_style_label(label_title, font_body, 72, color_title)
	label_title.add_theme_constant_override("outline_size", 2)
	label_title.add_theme_color_override("font_outline_color", Color("#3a1a08"))

	_style_label(label_hour, font_body, 28, color_muted)

	for lbl in [label_attr_text, label_money_title]:
		_style_label(lbl, font_title, 22, color_muted)
		lbl.add_theme_constant_override("outline_size", 1)
		lbl.add_theme_color_override("font_outline_color", color_muted)

	_style_label(label_days_title, font_body, 72, Color("#8a5a2e"))
	label_days_title.add_theme_constant_override("outline_size", 2)
	label_days_title.add_theme_color_override("font_outline_color", Color("#3a1a08"))

	_style_label(label_attr_value,  font_body, 32, color_ink)
	_style_label(label_money_value, font_body, 28, color_ink)
	label_money_value.add_theme_constant_override("outline_size", 1)
	label_money_value.add_theme_color_override("font_outline_color", color_ink)

	_style_label(label_days_value, font_body, 72, color_ink)
	label_days_value.add_theme_constant_override("outline_size", 2)
	label_days_value.add_theme_color_override("font_outline_color", color_ink)


func _update_attr_bar() -> void:
	if not attr_bar_container: return
	for child in attr_bar_container.get_children():
		child.queue_free()

	attr_bar_container.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)

	var bg = ColorRect.new()
	bg.size  = Vector2(BAR_WIDTH, BAR_HEIGHT)
	bg.color = color_bar_bg

	var fill = ColorRect.new()
	var ratio = clamp(PlayerStats.sex_appeal / 100.0, 0.0, 1.0)
	fill.size  = Vector2(BAR_WIDTH * ratio, BAR_HEIGHT)
	fill.color = color_bar_fill

	attr_bar_container.add_child(bg)
	attr_bar_container.add_child(fill)


func _style_label(label: Label, font: FontFile, size: int, color: Color) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)


func _format_hour(h: float) -> String:
	var hh = int(h)
	var mm = int((h - hh) * 60)
	var period = tr("JOURNAL_HOUR_NIGHT")
	if hh >= 5 and hh < 12:    period = tr("JOURNAL_HOUR_MORNING")
	elif hh >= 12 and hh < 20: period = tr("JOURNAL_HOUR_AFTERNOON")
	return "%02d:%02d · %s" % [hh, mm, period]


func _calcular_dia() -> int:
	var segundos_por_dia = CONFIG.duracion_hora_segundos * 24.0
	return int(floor(DayNightManager.tiempo_acumulado / segundos_por_dia)) + 1
