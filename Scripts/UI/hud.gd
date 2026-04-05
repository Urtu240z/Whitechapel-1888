extends CanvasLayer
# ================================================================
# HUD
# Barra superior con hora, dinero y stats básicos.
# ================================================================

const CONFIG = preload("res://Data/Game/game_config.tres")

@export var update_interval: float = 0.15

@onready var top_bar: Control = $TopBar
@onready var sundial_clock: Control = $TopBar/Panel/HBoxContainer/SundialClock

@onready var time_label: Label = $TopBar/Panel/HBoxContainer/VBoxStats/TimeLabel
@onready var money_label: Label = $TopBar/Panel/HBoxContainer/VBoxStats/MoneyLabel

@onready var health_bar: Range = $TopBar/Panel/HBoxContainer/VBoxStats/HealthBar
@onready var hunger_bar: Range = $TopBar/Panel/HBoxContainer/VBoxStats/HungerBar
@onready var sleep_bar: Range = $TopBar/Panel/HBoxContainer/VBoxStats/SleepBar
@onready var hygiene_bar: Range = $TopBar/Panel/HBoxContainer/VBoxStats/HygieneBar

var _update_accum: float = 0.0

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS

	_configure_bar(health_bar)
	_configure_bar(hunger_bar)
	_configure_bar(sleep_bar)
	_configure_bar(hygiene_bar)

	if StateManager.state_changed.is_connected(_on_state_changed) == false:
		StateManager.state_changed.connect(_on_state_changed)

	_refresh_visibility()
	_update_all()

func _process(delta: float) -> void:
	_update_accum += delta
	if _update_accum < update_interval:
		return

	_update_accum = 0.0
	_update_all()

func _on_state_changed(_from: int, _to: int) -> void:
	_refresh_visibility()
	_update_all()

func _refresh_visibility() -> void:
	var state := StateManager.current()

	visible = (
		state == StateManager.State.GAMEPLAY
		or state == StateManager.State.DIALOG
	)

func _update_all() -> void:
	var time_info := _get_time_info()

	time_label.text = "Día %02d  %02d:%02d" % [
		time_info.day,
		time_info.hour,
		time_info.minute
	]

	var money := _get_player_stat(["money", "dinero"], 0.0)
	money_label.text = "£%d" % int(round(money))

	health_bar.value = clamp(_get_player_stat(["health", "salud", "vida"], 100.0), 0.0, 100.0)
	hunger_bar.value = clamp(_get_player_stat(["hunger", "hambre"], 100.0), 0.0, 100.0)
	sleep_bar.value = clamp(_get_player_stat(["sleep", "sueno", "sueño"], 100.0), 0.0, 100.0)
	hygiene_bar.value = clamp(_get_player_stat(["hygiene", "higiene"], 100.0), 0.0, 100.0)

	if sundial_clock.has_method("set_time"):
		sundial_clock.call("set_time", time_info.hour, time_info.minute)

func _configure_bar(bar: Range) -> void:
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.step = 1.0

	if bar is ProgressBar:
		bar.show_percentage = false

func _get_player_stat(candidates: Array[String], default_value: float) -> float:
	for key in candidates:
		var value = PlayerStats.get(key)
		if value != null:
			return float(value)

	return default_value

func _get_time_info() -> Dictionary:
	var h: float = DayNightManager.hora_actual
	var hh: int = int(floor(h))
	var mm: int = int(floor((h - float(hh)) * 60.0))

	# corregir posible 60 por redondeos raros
	if mm >= 60:
		mm = 0
		hh += 1

	hh = hh % 24

	var day := _get_current_day()

	return {
		"day": day,
		"hour": hh,
		"minute": mm
	}

func _get_current_day() -> int:
	var seconds_per_day: float = CONFIG.duracion_hora_segundos * 24.0
	if seconds_per_day <= 0.0:
		seconds_per_day = 24.0 * 60.0

	return int(floor(DayNightManager.tiempo_acumulado / seconds_per_day)) + 1
