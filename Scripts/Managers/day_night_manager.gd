extends Node

# ================================================================
# DAY NIGHT MANAGER — day_night_manager.gd
# Autoload: DayNightManager
# ================================================================

const CONFIG = preload("res://Data/Game/game_config.tres")
const HORA_INICIO_RELOJ: float = 8.0

@export var horas_por_dia: int = 24

var hora_actual: float = HORA_INICIO_RELOJ
var tiempo_acumulado: float = 0.0
var pausado: bool = false

signal hora_cambiada(hora_actual: float)

# ================================================================
# LUCES EXTERIORES
# ================================================================

var sun: DirectionalLight2D = null
var moon: DirectionalLight2D = null
var ambient_light: DirectionalLight2D = null

const SUN_COLOR_ROJIZO  := Color(1.0, 0.28, 0.08)
const SUN_COLOR_NARANJA := Color(1.0, 0.529, 0.341)
const SUN_COLOR_ROSADO  := Color(1.0, 0.38, 0.52)

const MOON_COLOR_AZULADO := Color(0.55, 0.68, 1.0)

const AMBIENT_DAY_COLOR   := Color("5995b0")
const AMBIENT_NIGHT_COLOR := Color(0.0, 0.0, 0.0, 1.0)

const ROTATION_START_DEG := -65.0
const ROTATION_MID_DEG   := 0.0
const ROTATION_END_DEG   := 65.0

# ================================================================
# ENERGÍAS AJUSTABLES
# ================================================================

const SUN_MAX_ENERGY           := 2.0
const MOON_MAX_ENERGY          := 1.0
const AMBIENT_DAY_MAX_ENERGY   := 1.0
const AMBIENT_NIGHT_MAX_ENERGY := 0.7

# ================================================================
# HORARIOS
# ================================================================

# SOL
const SUN_START_HOUR      := 8.0
const SUN_PEAK_START_HOUR := 12.0
const SUN_PEAK_END_HOUR   := 17.0
const SUN_END_HOUR        := 19.0

# LUNA
const MOON_START_HOUR      := 20.0
const MOON_PEAK_START_HOUR := 22.0
const MOON_PEAK_END_HOUR   := 4.0
const MOON_END_HOUR        := 6.0


func registrar_luces(
	p_sun: DirectionalLight2D,
	p_moon: DirectionalLight2D,
	p_ambient: DirectionalLight2D
) -> void:
	sun = p_sun
	moon = p_moon
	ambient_light = p_ambient
	_actualizar_luces_exteriores()


# ================================================================
# CICLO PRINCIPAL
# ================================================================

func _ready() -> void:
	_sincronizar_reloj()


func _process(delta: float) -> void:
	if pausado:
		return

	advance_seconds(delta)
	_actualizar_luces_exteriores()


# ================================================================
# API PÚBLICA
# ================================================================

func advance_seconds(segundos: float) -> void:
	if segundos <= 0.0:
		return

	var hora_total_anterior: int = _get_hora_total_desde_tiempo(tiempo_acumulado)

	tiempo_acumulado += segundos
	hora_actual = _calcular_hora_desde_tiempo(tiempo_acumulado)

	var hora_total_nueva: int = _get_hora_total_desde_tiempo(tiempo_acumulado)
	_emitir_horas_cruzadas(hora_total_anterior, hora_total_nueva)


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

	tiempo_acumulado = maxf(nuevo_tiempo, 0.0)
	hora_actual = _calcular_hora_desde_tiempo(tiempo_acumulado)

	if emitir_eventos and tiempo_acumulado >= tiempo_anterior:
		var hora_total_anterior: int = _get_hora_total_desde_tiempo(tiempo_anterior)
		var hora_total_nueva: int = _get_hora_total_desde_tiempo(tiempo_acumulado)
		_emitir_horas_cruzadas(hora_total_anterior, hora_total_nueva)
	else:
		_sincronizar_reloj()

	_actualizar_luces_exteriores()


func pausar() -> void:
	pausado = true


func reanudar() -> void:
	pausado = false


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


func sincronizar_reloj() -> void:
	_sincronizar_reloj()
	_actualizar_luces_exteriores()


func get_ambient_night_factor() -> float:
	if not is_instance_valid(ambient_light):
		return 0.0

	if ambient_light.blend_mode != Light2D.BLEND_MODE_MIX:
		return 0.0

	return clampf(
		ambient_light.energy / maxf(AMBIENT_NIGHT_MAX_ENERGY, 0.001),
		0.0,
		1.0
	)


# ================================================================
# RELOJ INTERNO
# ================================================================

func _sincronizar_reloj() -> void:
	hora_actual = _calcular_hora_desde_tiempo(tiempo_acumulado)


func _calcular_hora_desde_tiempo(tiempo_total: float) -> float:
	var horas_pasadas: float = tiempo_total / get_segundos_por_hora()
	return fposmod(HORA_INICIO_RELOJ + horas_pasadas, float(horas_por_dia))


func _hora_a_segundos_en_ciclo(hora: float) -> float:
	var hora_normalizada: float = fposmod(hora, float(horas_por_dia))
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
		hora_cambiada.emit(hora_emitida)


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
		rot_deg = lerpf(ROTATION_START_DEG, ROTATION_MID_DEG, t_rot_1)
	else:
		var t_rot_2: float = inverse_lerp(SUN_PEAK_START_HOUR, SUN_END_HOUR, hora_actual)
		rot_deg = lerpf(ROTATION_MID_DEG, ROTATION_END_DEG, t_rot_2)

	sun.rotation_degrees = rot_deg

	var energy: float
	if hora_actual < SUN_PEAK_START_HOUR:
		var t_in: float = inverse_lerp(SUN_START_HOUR, SUN_PEAK_START_HOUR, hora_actual)
		energy = lerpf(0.0, SUN_MAX_ENERGY, t_in)
	elif hora_actual < SUN_PEAK_END_HOUR:
		energy = SUN_MAX_ENERGY
	else:
		var t_out: float = inverse_lerp(SUN_PEAK_END_HOUR, SUN_END_HOUR, hora_actual)
		energy = lerpf(SUN_MAX_ENERGY, 0.0, t_out)

	sun.energy = energy

	var color: Color
	if hora_actual < SUN_PEAK_START_HOUR:
		var t_color_1: float = inverse_lerp(SUN_START_HOUR, SUN_PEAK_START_HOUR, hora_actual)
		color = SUN_COLOR_ROJIZO.lerp(SUN_COLOR_NARANJA, t_color_1)
	elif hora_actual < SUN_PEAK_END_HOUR:
		color = SUN_COLOR_NARANJA
	else:
		var t_color_2: float = inverse_lerp(SUN_PEAK_END_HOUR, SUN_END_HOUR, hora_actual)
		color = SUN_COLOR_NARANJA.lerp(SUN_COLOR_ROSADO, t_color_2)

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
		rot_deg = lerpf(ROTATION_START_DEG, ROTATION_MID_DEG, t_rot_1)
	else:
		var t_rot_2: float = (horas_desde_inicio - mitad_rotacion) / maxf(mitad_rotacion, 0.001)
		rot_deg = lerpf(ROTATION_MID_DEG, ROTATION_END_DEG, t_rot_2)

	moon.rotation_degrees = rot_deg

	var energy: float
	if horas_desde_inicio < tramo_subida:
		var t_in: float = horas_desde_inicio / maxf(tramo_subida, 0.001)
		energy = lerpf(0.0, MOON_MAX_ENERGY, t_in)
	elif horas_desde_inicio < tramo_subida + tramo_meseta:
		energy = MOON_MAX_ENERGY
	else:
		var horas_en_bajada: float = horas_desde_inicio - tramo_subida - tramo_meseta
		var t_out: float = horas_en_bajada / maxf(tramo_bajada, 0.001)
		energy = lerpf(MOON_MAX_ENERGY, 0.0, t_out)

	moon.energy = energy
	moon.color = MOON_COLOR_AZULADO


func _actualizar_ambient_light() -> void:
	if not is_instance_valid(ambient_light):
		return

	ambient_light.visible = true

	# 6 -> 8
	# Aquí energy = 0 y dejamos el blend listo para el día
	if hora_actual >= MOON_END_HOUR and hora_actual < SUN_START_HOUR:
		ambient_light.energy = 0.0
		ambient_light.color = AMBIENT_DAY_COLOR
		ambient_light.blend_mode = Light2D.BLEND_MODE_ADD
		return

	# 19 -> 20
	# Aquí energy = 0 y dejamos el blend listo para la noche
	if hora_actual >= SUN_END_HOUR and hora_actual < MOON_START_HOUR:
		ambient_light.energy = 0.0
		ambient_light.color = AMBIENT_NIGHT_COLOR
		ambient_light.blend_mode = Light2D.BLEND_MODE_MIX
		return

	# Día
	if _is_hour_in_range(hora_actual, SUN_START_HOUR, SUN_END_HOUR):
		ambient_light.blend_mode = Light2D.BLEND_MODE_ADD

		var energy_day: float
		if hora_actual < SUN_PEAK_START_HOUR:
			var t_in_day: float = inverse_lerp(SUN_START_HOUR, SUN_PEAK_START_HOUR, hora_actual)
			energy_day = lerpf(0.0, AMBIENT_DAY_MAX_ENERGY, t_in_day)
		elif hora_actual < SUN_PEAK_END_HOUR:
			energy_day = AMBIENT_DAY_MAX_ENERGY
		else:
			var t_out_day: float = inverse_lerp(SUN_PEAK_END_HOUR, SUN_END_HOUR, hora_actual)
			energy_day = lerpf(AMBIENT_DAY_MAX_ENERGY, 0.0, t_out_day)

		var color_day: Color
		if hora_actual < SUN_PEAK_START_HOUR:
			var t_color_day_in: float = inverse_lerp(SUN_START_HOUR, SUN_PEAK_START_HOUR, hora_actual)
			color_day = AMBIENT_NIGHT_COLOR.lerp(AMBIENT_DAY_COLOR, t_color_day_in)
		elif hora_actual < SUN_PEAK_END_HOUR:
			color_day = AMBIENT_DAY_COLOR
		else:
			var t_color_day_out: float = inverse_lerp(SUN_PEAK_END_HOUR, SUN_END_HOUR, hora_actual)
			color_day = AMBIENT_DAY_COLOR.lerp(AMBIENT_NIGHT_COLOR, t_color_day_out)

		ambient_light.energy = energy_day
		ambient_light.color = color_day
		return

	# Noche
	if _is_hour_in_range(hora_actual, MOON_START_HOUR, MOON_END_HOUR):
		ambient_light.blend_mode = Light2D.BLEND_MODE_MIX
		ambient_light.color = AMBIENT_NIGHT_COLOR

		var horas_desde_inicio: float = _get_night_hours_since_start(hora_actual, MOON_START_HOUR)
		var tramo_subida: float = _wrapped_hour_distance(MOON_START_HOUR, MOON_PEAK_START_HOUR)
		var tramo_meseta: float = _wrapped_hour_distance(MOON_PEAK_START_HOUR, MOON_PEAK_END_HOUR)
		var tramo_bajada: float = _wrapped_hour_distance(MOON_PEAK_END_HOUR, MOON_END_HOUR)

		var energy_night: float
		if horas_desde_inicio < tramo_subida:
			var t_in_night: float = horas_desde_inicio / maxf(tramo_subida, 0.001)
			energy_night = lerpf(0.0, AMBIENT_NIGHT_MAX_ENERGY, t_in_night)
		elif horas_desde_inicio < tramo_subida + tramo_meseta:
			energy_night = AMBIENT_NIGHT_MAX_ENERGY
		else:
			var horas_en_bajada: float = horas_desde_inicio - tramo_subida - tramo_meseta
			var t_out_night: float = horas_en_bajada / maxf(tramo_bajada, 0.001)
			energy_night = lerpf(AMBIENT_NIGHT_MAX_ENERGY, 0.0, t_out_night)

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


func reset() -> void:
	tiempo_acumulado = 0.0
	hora_actual = HORA_INICIO_RELOJ
	pausado = false
	_actualizar_luces_exteriores()


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
