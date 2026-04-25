extends Node

# ================================================================
# DAY NIGHT MANAGER — Autoload
# ================================================================
# Autoridad del tiempo global y de la iluminación exterior.
#
# Mantiene compatibilidad con el proyecto actual:
# - hora_actual
# - tiempo_acumulado
# - pausado
# - hora_cambiada(hora_actual)
# - registrar_luces(...)
# - advance_seconds / advance_hours / set_hora / set_total_time
#
# Añade API limpia para diseño y guardado:
# - hour_tick(hour, day, absolute_hour)
# - day_changed(day)
# - period_changed(period_id)
# - is_night(), is_day(), is_between()
# - get_save_data(), apply_save_data()
# ================================================================

const CONFIG = preload("res://Data/Game/game_config.tres")
const HORA_INICIO_RELOJ: float = 8.0

@export var horas_por_dia: int = 24

var hora_actual: float = HORA_INICIO_RELOJ
var tiempo_acumulado: float = 0.0
var pausado: bool = false

# Señal legacy: muchos scripts ya la usan.
signal hora_cambiada(hora_actual: float)

# Señales nuevas.
signal hour_tick(hour: float, day: int, absolute_hour: int)
signal day_changed(day: int)
signal period_changed(period_id: String)
signal time_paused_changed(is_paused: bool)
signal time_synced(hour: float, day: int, total_time: float)

# ================================================================
# LUCES EXTERIORES
# ================================================================
var sun: DirectionalLight2D = null
var moon: DirectionalLight2D = null
var ambient_light: DirectionalLight2D = null
var _profile: LightingProfile2D = null

# ================================================================
# DEFAULTS (si no hay perfil asignado)
# ================================================================
const DEFAULT_SUN_COLOR_ROJIZO := Color(1.0, 0.28, 0.08)
const DEFAULT_SUN_COLOR_NARANJA := Color(1.0, 0.529, 0.341)
const DEFAULT_SUN_COLOR_ROSADO := Color(1.0, 0.38, 0.52)

const DEFAULT_MOON_COLOR_AZULADO := Color(0.55, 0.68, 1.0)

const DEFAULT_AMBIENT_DAY_COLOR := Color("5995b0")
const DEFAULT_AMBIENT_NIGHT_COLOR := Color(0.0, 0.0, 0.0, 1.0)

const DEFAULT_ROTATION_START_DEG := -65.0
const DEFAULT_ROTATION_MID_DEG := 0.0
const DEFAULT_ROTATION_END_DEG := 65.0

const DEFAULT_SUN_MAX_ENERGY := 1.0
const DEFAULT_MOON_MAX_ENERGY := 0.1
const DEFAULT_AMBIENT_DAY_MAX_ENERGY := 1.0
const DEFAULT_AMBIENT_NIGHT_MAX_ENERGY := 0.7

# ================================================================
# HORARIOS
# ================================================================
# SOL
const SUN_START_HOUR := 8.0
const SUN_PEAK_START_HOUR := 12.0
const SUN_PEAK_END_HOUR := 17.0
const SUN_END_HOUR := 19.0

# LUNA
const MOON_START_HOUR := 20.0
const MOON_PEAK_START_HOUR := 22.0
const MOON_PEAK_END_HOUR := 4.0
const MOON_END_HOUR := 6.0

# PERIODOS DE DISEÑO
const PERIOD_DAWN := "dawn"      # 06:00 - 08:00
const PERIOD_DAY := "day"        # 08:00 - 19:00
const PERIOD_DUSK := "dusk"      # 19:00 - 20:00
const PERIOD_NIGHT := "night"    # 20:00 - 06:00

var _last_day: int = 1
var _current_period: String = PERIOD_DAY


# ================================================================
# READY / PROCESS
# ================================================================
func _ready() -> void:
	_sincronizar_reloj()
	_last_day = get_current_day()
	_current_period = get_period_id()
	_actualizar_luces_exteriores()


func _process(delta: float) -> void:
	if pausado:
		return

	advance_seconds(delta)
	_actualizar_luces_exteriores()


# ================================================================
# REGISTRO DE LUCES
# ================================================================
func registrar_luces(
	p_sun: DirectionalLight2D,
	p_moon: DirectionalLight2D,
	p_ambient: DirectionalLight2D,
	p_profile: LightingProfile2D = null
) -> void:
	sun = p_sun
	moon = p_moon
	ambient_light = p_ambient
	_profile = p_profile
	_actualizar_luces_exteriores()


func clear_lights() -> void:
	sun = null
	moon = null
	ambient_light = null
	_profile = null


# ================================================================
# API PÚBLICA — AVANCE DE TIEMPO
# ================================================================
func advance_seconds(segundos: float) -> void:
	if segundos <= 0.0:
		return

	var tiempo_anterior: float = tiempo_acumulado
	var hora_total_anterior: int = _get_hora_total_desde_tiempo(tiempo_acumulado)
	var dia_anterior: int = get_current_day()
	var periodo_anterior: String = get_period_id()

	tiempo_acumulado += segundos
	_sincronizar_reloj()

	var hora_total_nueva: int = _get_hora_total_desde_tiempo(tiempo_acumulado)
	_emitir_horas_cruzadas(hora_total_anterior, hora_total_nueva)
	_emitir_cambios_de_dia_y_periodo(dia_anterior, periodo_anterior)

	# La variable existe solo para facilitar depuración si hace falta.
	# Evita warnings por no usar tiempo_anterior en builds con warnings estrictos.
	if tiempo_anterior < 0.0:
		return


func advance_hours(horas: float) -> void:
	if horas <= 0.0:
		return

	advance_seconds(horas * get_segundos_por_hora())


func set_hora(nueva_hora: float) -> void:
	var segundos_por_dia: float = get_segundos_por_dia()
	var ciclo_actual: int = int(floor(tiempo_acumulado / segundos_por_dia))
	var tiempo_objetivo: float = ciclo_actual * segundos_por_dia + _hora_a_segundos_en_ciclo(nueva_hora)

	if tiempo_objetivo < tiempo_acumulado - 0.001:
		tiempo_objetivo += segundos_por_dia

	set_total_time(tiempo_objetivo, true)


func set_total_time(nuevo_tiempo: float, emitir_eventos: bool = false) -> void:
	var tiempo_anterior: float = tiempo_acumulado
	var hora_total_anterior: int = _get_hora_total_desde_tiempo(tiempo_acumulado)
	var dia_anterior: int = get_current_day()
	var periodo_anterior: String = get_period_id()

	tiempo_acumulado = maxf(nuevo_tiempo, 0.0)
	_sincronizar_reloj()

	if emitir_eventos and tiempo_acumulado >= tiempo_anterior:
		var hora_total_nueva: int = _get_hora_total_desde_tiempo(tiempo_acumulado)
		_emitir_horas_cruzadas(hora_total_anterior, hora_total_nueva)
		_emitir_cambios_de_dia_y_periodo(dia_anterior, periodo_anterior)
	else:
		_last_day = get_current_day()
		_current_period = get_period_id()
		time_synced.emit(hora_actual, _last_day, tiempo_acumulado)

	_actualizar_luces_exteriores()


func reset() -> void:
	tiempo_acumulado = 0.0
	hora_actual = HORA_INICIO_RELOJ
	pausado = false
	_last_day = get_current_day()
	_current_period = get_period_id()
	_actualizar_luces_exteriores()
	time_synced.emit(hora_actual, _last_day, tiempo_acumulado)
	time_paused_changed.emit(false)


# ================================================================
# API PÚBLICA — PAUSA
# ================================================================
func pausar() -> void:
	set_paused(true)


func reanudar() -> void:
	set_paused(false)


func set_paused(value: bool) -> void:
	if pausado == value:
		return

	pausado = value
	time_paused_changed.emit(pausado)


func is_paused() -> bool:
	return pausado


# ================================================================
# API PÚBLICA — CONSULTAS DE TIEMPO
# ================================================================
func get_segundos_por_hora() -> float:
	return maxf(CONFIG.duracion_hora_segundos, 0.001)


func get_segundos_por_dia() -> float:
	return get_segundos_por_hora() * float(horas_por_dia)


func get_total_hours_elapsed() -> float:
	return tiempo_acumulado / get_segundos_por_hora()


func get_absolute_clock_hours() -> float:
	return HORA_INICIO_RELOJ + get_total_hours_elapsed()


func get_current_day() -> int:
	return int(floor(get_absolute_clock_hours() / 24.0)) + 1


func get_hour_float() -> float:
	return hora_actual


func get_current_hour() -> float:
	return hora_actual


func get_current_hour_int() -> int:
	return int(floor(hora_actual))


func get_current_minute() -> int:
	var decimal: float = hora_actual - floor(hora_actual)
	return int(floor(decimal * 60.0))


func get_time_string() -> String:
	var h: int = get_current_hour_int()
	var m: int = get_current_minute()
	return "%02d:%02d" % [h, m]


func get_day_time_string() -> String:
	return "Día %d — %s" % [get_current_day(), get_time_string()]


func is_between(start_hour: float, end_hour: float, hour: float = -1.0) -> bool:
	var h: float = hora_actual if hour < 0.0 else fposmod(hour, float(horas_por_dia))
	return _is_hour_in_range(h, start_hour, end_hour)


func is_night(hour: float = -1.0) -> bool:
	var h: float = hora_actual if hour < 0.0 else fposmod(hour, float(horas_por_dia))
	return _is_hour_in_range(h, MOON_START_HOUR, MOON_END_HOUR)


func is_day(hour: float = -1.0) -> bool:
	var h: float = hora_actual if hour < 0.0 else fposmod(hour, float(horas_por_dia))
	return _is_hour_in_range(h, SUN_START_HOUR, SUN_END_HOUR)


func is_dawn(hour: float = -1.0) -> bool:
	var h: float = hora_actual if hour < 0.0 else fposmod(hour, float(horas_por_dia))
	return _is_hour_in_range(h, MOON_END_HOUR, SUN_START_HOUR)


func is_dusk(hour: float = -1.0) -> bool:
	var h: float = hora_actual if hour < 0.0 else fposmod(hour, float(horas_por_dia))
	return _is_hour_in_range(h, SUN_END_HOUR, MOON_START_HOUR)


func get_period_id(hour: float = -1.0) -> String:
	var h: float = hora_actual if hour < 0.0 else fposmod(hour, float(horas_por_dia))

	if _is_hour_in_range(h, MOON_END_HOUR, SUN_START_HOUR):
		return PERIOD_DAWN
	if _is_hour_in_range(h, SUN_START_HOUR, SUN_END_HOUR):
		return PERIOD_DAY
	if _is_hour_in_range(h, SUN_END_HOUR, MOON_START_HOUR):
		return PERIOD_DUSK
	return PERIOD_NIGHT


func get_hours_until(target_hour: float) -> float:
	return _wrapped_hour_distance(hora_actual, target_hour)


func sincronizar_reloj() -> void:
	_sincronizar_reloj()
	_actualizar_luces_exteriores()
	time_synced.emit(hora_actual, get_current_day(), tiempo_acumulado)


# ================================================================
# API PÚBLICA — ILUMINACIÓN / FAROLAS
# ================================================================
func get_ambient_night_factor() -> float:
	if not is_instance_valid(ambient_light):
		return 0.0

	if ambient_light.blend_mode != Light2D.BLEND_MODE_MIX:
		return 0.0

	return clampf(
		ambient_light.energy / maxf(_ambient_night_max_energy(), 0.001),
		0.0,
		1.0
	)


func force_update_lighting() -> void:
	_actualizar_luces_exteriores()


# ================================================================
# API PÚBLICA — SAVE / LOAD
# ================================================================
func get_save_data() -> Dictionary:
	return {
		"hora": hora_actual,
		"tiempo_acumulado": tiempo_acumulado,
		"dia": get_current_day(),
		"pausado": pausado,
		"periodo": get_period_id(),
	}


func apply_save_data(data: Dictionary) -> void:
	var total_time: float = float(data.get("tiempo_acumulado", tiempo_acumulado))
	set_total_time(total_time, false)
	set_paused(bool(data.get("pausado", false)))
	_actualizar_luces_exteriores()
	time_synced.emit(hora_actual, get_current_day(), tiempo_acumulado)


# ================================================================
# RELOJ INTERNO
# ================================================================
func _sincronizar_reloj() -> void:
	hora_actual = _calcular_hora_desde_tiempo(tiempo_acumulado)


func _calcular_hora_desde_tiempo(tiempo_total: float) -> float:
	var horas_pasadas: float = tiempo_total / get_segundos_por_hora()
	return fposmod(HORA_INICIO_RELOJ + horas_pasadas, float(horas_por_dia))


func _hora_a_segundos_en_ciclo(hour: float) -> float:
	var hora_normalizada: float = fposmod(hour, float(horas_por_dia))
	var horas_desde_inicio: float = fposmod(
		hora_normalizada - HORA_INICIO_RELOJ + float(horas_por_dia),
		float(horas_por_dia)
	)
	return horas_desde_inicio * get_segundos_por_hora()


func _get_hora_total_desde_tiempo(tiempo_total: float) -> int:
	return int(floor(tiempo_total / get_segundos_por_hora()))


func _emitir_horas_cruzadas(hora_total_anterior: int, hora_total_nueva: int) -> void:
	if hora_total_nueva <= hora_total_anterior:
		return

	for hora_total in range(hora_total_anterior + 1, hora_total_nueva + 1):
		var hora_emitida: float = fposmod(
			HORA_INICIO_RELOJ + float(hora_total),
			float(horas_por_dia)
		)
		var absolute_hour: int = int(floor(HORA_INICIO_RELOJ + float(hora_total)))
		var day: int = int(floor(float(absolute_hour) / 24.0)) + 1

		hora_cambiada.emit(hora_emitida)
		hour_tick.emit(hora_emitida, day, absolute_hour)


func _emitir_cambios_de_dia_y_periodo(dia_anterior: int, periodo_anterior: String) -> void:
	var dia_nuevo: int = get_current_day()
	var periodo_nuevo: String = get_period_id()

	if dia_nuevo != dia_anterior:
		_last_day = dia_nuevo
		day_changed.emit(dia_nuevo)

	if periodo_nuevo != periodo_anterior:
		_current_period = periodo_nuevo
		period_changed.emit(periodo_nuevo)


# ================================================================
# ILUMINACIÓN — actualización continua cada frame
# ================================================================
func _actualizar_luces_exteriores() -> void:
	if _is_hour_in_range(hora_actual, SUN_START_HOUR, SUN_END_HOUR):
		_actualizar_sol()
	else:
		_ocultar_sol()

	if _is_hour_in_range(hora_actual, MOON_START_HOUR, MOON_END_HOUR):
		_actualizar_luna()
	else:
		_ocultar_luna()

	_actualizar_ambient_light()


func _actualizar_sol() -> void:
	if not is_instance_valid(sun):
		return

	sun.visible = true

	var rot_deg: float
	if hora_actual < SUN_PEAK_START_HOUR:
		var t_rot_1: float = inverse_lerp(SUN_START_HOUR, SUN_PEAK_START_HOUR, hora_actual)
		rot_deg = lerpf(_rotation_start_deg(), _rotation_mid_deg(), t_rot_1)
	else:
		var t_rot_2: float = inverse_lerp(SUN_PEAK_START_HOUR, SUN_END_HOUR, hora_actual)
		rot_deg = lerpf(_rotation_mid_deg(), _rotation_end_deg(), t_rot_2)

	sun.rotation_degrees = rot_deg

	var energy: float
	if hora_actual < SUN_PEAK_START_HOUR:
		var t_in: float = inverse_lerp(SUN_START_HOUR, SUN_PEAK_START_HOUR, hora_actual)
		energy = lerpf(0.0, _sun_max_energy(), t_in)
	elif hora_actual < SUN_PEAK_END_HOUR:
		energy = _sun_max_energy()
	else:
		var t_out: float = inverse_lerp(SUN_PEAK_END_HOUR, SUN_END_HOUR, hora_actual)
		energy = lerpf(_sun_max_energy(), 0.0, t_out)

	sun.energy = energy

	var color: Color
	if hora_actual < SUN_PEAK_START_HOUR:
		var t_color_1: float = inverse_lerp(SUN_START_HOUR, SUN_PEAK_START_HOUR, hora_actual)
		color = _sun_color_rojizo().lerp(_sun_color_naranja(), t_color_1)
	elif hora_actual < SUN_PEAK_END_HOUR:
		color = _sun_color_naranja()
	else:
		var t_color_2: float = inverse_lerp(SUN_PEAK_END_HOUR, SUN_END_HOUR, hora_actual)
		color = _sun_color_naranja().lerp(_sun_color_rosado(), t_color_2)

	sun.color = color


func _actualizar_luna() -> void:
	if not is_instance_valid(moon):
		return

	moon.visible = true

	var horas_desde_inicio: float = _get_night_hours_since_start(hora_actual, MOON_START_HOUR)

	var tramo_subida: float = _wrapped_hour_distance(MOON_START_HOUR, MOON_PEAK_START_HOUR)
	var tramo_meseta: float = _wrapped_hour_distance(MOON_PEAK_START_HOUR, MOON_PEAK_END_HOUR)
	var tramo_bajada: float = _wrapped_hour_distance(MOON_PEAK_END_HOUR, MOON_END_HOUR)
	var duracion_total: float = _wrapped_hour_distance(MOON_START_HOUR, MOON_END_HOUR)

	var mitad_rotacion: float = duracion_total * 0.5
	var rot_deg: float

	if horas_desde_inicio < mitad_rotacion:
		var t_rot_1: float = horas_desde_inicio / maxf(mitad_rotacion, 0.001)
		rot_deg = lerpf(_rotation_start_deg(), _rotation_mid_deg(), t_rot_1)
	else:
		var t_rot_2: float = (horas_desde_inicio - mitad_rotacion) / maxf(mitad_rotacion, 0.001)
		rot_deg = lerpf(_rotation_mid_deg(), _rotation_end_deg(), t_rot_2)

	moon.rotation_degrees = rot_deg

	var energy: float
	if horas_desde_inicio < tramo_subida:
		var t_in: float = horas_desde_inicio / maxf(tramo_subida, 0.001)
		energy = lerpf(0.0, _moon_max_energy(), t_in)
	elif horas_desde_inicio < tramo_subida + tramo_meseta:
		energy = _moon_max_energy()
	else:
		var horas_en_bajada: float = horas_desde_inicio - tramo_subida - tramo_meseta
		var t_out: float = horas_en_bajada / maxf(tramo_bajada, 0.001)
		energy = lerpf(_moon_max_energy(), 0.0, t_out)

	moon.energy = energy
	moon.color = _moon_color_azulado()


func _actualizar_ambient_light() -> void:
	if not is_instance_valid(ambient_light):
		return

	ambient_light.visible = true

	# 6 -> 8
	# Aquí energy = 0 y dejamos el blend listo para el día.
	if hora_actual >= MOON_END_HOUR and hora_actual < SUN_START_HOUR:
		ambient_light.energy = 0.0
		ambient_light.color = _ambient_day_color()
		ambient_light.blend_mode = Light2D.BLEND_MODE_ADD
		return

	# 19 -> 20
	# Aquí energy = 0 y dejamos el blend listo para la noche.
	if hora_actual >= SUN_END_HOUR and hora_actual < MOON_START_HOUR:
		ambient_light.energy = 0.0
		ambient_light.color = _ambient_night_color()
		ambient_light.blend_mode = Light2D.BLEND_MODE_MIX
		return

	# Día
	if _is_hour_in_range(hora_actual, SUN_START_HOUR, SUN_END_HOUR):
		ambient_light.blend_mode = Light2D.BLEND_MODE_ADD

		var energy_day: float
		if hora_actual < SUN_PEAK_START_HOUR:
			var t_in_day: float = inverse_lerp(SUN_START_HOUR, SUN_PEAK_START_HOUR, hora_actual)
			energy_day = lerpf(0.0, _ambient_day_max_energy(), t_in_day)
		elif hora_actual < SUN_PEAK_END_HOUR:
			energy_day = _ambient_day_max_energy()
		else:
			var t_out_day: float = inverse_lerp(SUN_PEAK_END_HOUR, SUN_END_HOUR, hora_actual)
			energy_day = lerpf(_ambient_day_max_energy(), 0.0, t_out_day)

		var color_day: Color
		if hora_actual < SUN_PEAK_START_HOUR:
			var t_color_day_in: float = inverse_lerp(SUN_START_HOUR, SUN_PEAK_START_HOUR, hora_actual)
			color_day = _ambient_night_color().lerp(_ambient_day_color(), t_color_day_in)
		elif hora_actual < SUN_PEAK_END_HOUR:
			color_day = _ambient_day_color()
		else:
			var t_color_day_out: float = inverse_lerp(SUN_PEAK_END_HOUR, SUN_END_HOUR, hora_actual)
			color_day = _ambient_day_color().lerp(_ambient_night_color(), t_color_day_out)

		ambient_light.energy = energy_day
		ambient_light.color = color_day
		return

	# Noche
	if _is_hour_in_range(hora_actual, MOON_START_HOUR, MOON_END_HOUR):
		ambient_light.blend_mode = Light2D.BLEND_MODE_MIX
		ambient_light.color = _ambient_night_color()

		var horas_desde_inicio: float = _get_night_hours_since_start(hora_actual, MOON_START_HOUR)
		var tramo_subida: float = _wrapped_hour_distance(MOON_START_HOUR, MOON_PEAK_START_HOUR)
		var tramo_meseta: float = _wrapped_hour_distance(MOON_PEAK_START_HOUR, MOON_PEAK_END_HOUR)
		var tramo_bajada: float = _wrapped_hour_distance(MOON_PEAK_END_HOUR, MOON_END_HOUR)

		var energy_night: float
		if horas_desde_inicio < tramo_subida:
			var t_in_night: float = horas_desde_inicio / maxf(tramo_subida, 0.001)
			energy_night = lerpf(0.0, _ambient_night_max_energy(), t_in_night)
		elif horas_desde_inicio < tramo_subida + tramo_meseta:
			energy_night = _ambient_night_max_energy()
		else:
			var horas_en_bajada: float = horas_desde_inicio - tramo_subida - tramo_meseta
			var t_out_night: float = horas_en_bajada / maxf(tramo_bajada, 0.001)
			energy_night = lerpf(_ambient_night_max_energy(), 0.0, t_out_night)

		ambient_light.energy = energy_night
		return


func _ocultar_sol() -> void:
	if is_instance_valid(sun):
		sun.visible = false
		sun.energy = 0.0


func _ocultar_luna() -> void:
	if is_instance_valid(moon):
		moon.visible = false
		moon.energy = 0.0


# ================================================================
# HELPERS HORA
# ================================================================
func _is_hour_in_range(hour: float, start_hour: float, end_hour: float) -> bool:
	if start_hour <= end_hour:
		return hour >= start_hour and hour < end_hour
	return hour >= start_hour or hour < end_hour


func _get_night_hours_since_start(hour: float, start_hour: float) -> float:
	if hour >= start_hour:
		return hour - start_hour
	return hour + (24.0 - start_hour)


func _wrapped_hour_distance(from_hour: float, to_hour: float) -> float:
	return fposmod(to_hour - from_hour + 24.0, 24.0)


# ================================================================
# HELPERS PERFIL / DEFAULT
# ================================================================
func _sun_max_energy() -> float:
	return _profile.sun_max_energy if is_instance_valid(_profile) else DEFAULT_SUN_MAX_ENERGY


func _moon_max_energy() -> float:
	return _profile.moon_max_energy if is_instance_valid(_profile) else DEFAULT_MOON_MAX_ENERGY


func _ambient_day_max_energy() -> float:
	return _profile.ambient_day_max_energy if is_instance_valid(_profile) else DEFAULT_AMBIENT_DAY_MAX_ENERGY


func _ambient_night_max_energy() -> float:
	return _profile.ambient_night_max_energy if is_instance_valid(_profile) else DEFAULT_AMBIENT_NIGHT_MAX_ENERGY


func _ambient_day_color() -> Color:
	return _profile.ambient_day_color if is_instance_valid(_profile) else DEFAULT_AMBIENT_DAY_COLOR


func _ambient_night_color() -> Color:
	return _profile.ambient_night_color if is_instance_valid(_profile) else DEFAULT_AMBIENT_NIGHT_COLOR


func _rotation_start_deg() -> float:
	return _profile.rotation_start_deg if is_instance_valid(_profile) else DEFAULT_ROTATION_START_DEG


func _rotation_mid_deg() -> float:
	return _profile.rotation_mid_deg if is_instance_valid(_profile) else DEFAULT_ROTATION_MID_DEG


func _rotation_end_deg() -> float:
	return _profile.rotation_end_deg if is_instance_valid(_profile) else DEFAULT_ROTATION_END_DEG


func _sun_color_rojizo() -> Color:
	return _profile.sun_color_rojizo if is_instance_valid(_profile) else DEFAULT_SUN_COLOR_ROJIZO


func _sun_color_naranja() -> Color:
	return _profile.sun_color_naranja if is_instance_valid(_profile) else DEFAULT_SUN_COLOR_NARANJA


func _sun_color_rosado() -> Color:
	return _profile.sun_color_rosado if is_instance_valid(_profile) else DEFAULT_SUN_COLOR_ROSADO


func _moon_color_azulado() -> Color:
	return _profile.moon_color_azulado if is_instance_valid(_profile) else DEFAULT_MOON_COLOR_AZULADO
