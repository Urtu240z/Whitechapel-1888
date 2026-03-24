extends Node2D

@onready var label_title       = $LabelTitle
@onready var label_hour        = $LabelHour
@onready var label_attr_text   = $LabelAttrText
@onready var label_attr_value  = $LabelAttrValue
@onready var label_money_title = $LabelMoneyTitle
@onready var label_money_value = $LabelMoneyValue
@onready var label_days_title  = $LabelDaysTitle
@onready var label_days_value  = $LabelDaysValue

var font_title = preload("res://Assets/Fonts/Cinzel.ttf")
var font_body  = preload("res://Assets/Fonts/IMFellEnglish.ttf")
var color_ink   = Color("#2a1a05")
var color_muted = Color("#7a5a30")

func _ready() -> void:
	label_title.text       = "Mi Diario"
	label_attr_text.text   = "Atractivo"
	label_money_title.text = "DINERO"
	label_days_title.text  = "DÍA"
	_apply_styles()
	_update()
	PlayerStats.stats_updated.connect(_update)

func _update() -> void:
	label_hour.text        = _format_hour(DayNightManager.hora_actual)
	label_attr_value.text  = str(int(PlayerStats.sex_appeal))
	label_money_value.text = str(int(PlayerStats.dinero)) + "s"
	label_days_value.text  = str(_calcular_dia())

func _apply_styles() -> void:
	_style_label(label_title,       font_title, 64, color_ink)
	_style_label(label_hour,        font_body,  42, color_muted)
	_style_label(label_attr_text,   font_body,  28, color_ink)
	_style_label(label_attr_value,  font_title, 36, color_ink)
	_style_label(label_money_title, font_title, 26, color_ink)
	_style_label(label_money_value, font_body,  24, color_ink)
	_style_label(label_days_title,  font_title, 26, color_ink)
	_style_label(label_days_value,  font_body,  24, color_ink)

func _style_label(label: Label, font: FontFile, size: int, color: Color) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)

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
