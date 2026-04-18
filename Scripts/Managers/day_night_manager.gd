extends Node

# ================================================================
# DAY NIGHT MANAGER — day_night_manager.gd
# Autoload: DayNightManager
# Ahora usa UN SOLO DirectionalLight2D para:
# - fase sol (6h -> 18h)
# - fase luna (18h -> 6h)
# ================================================================

const CONFIG = preload("res://Data/Game/game_config.tres")
const HORA_INICIO_RELOJ: float = 8.0

@export var horas_por_dia: int = 24

var hora_actual: float = HORA_INICIO_RELOJ
var tiempo_acumulado: float = 0.0
var hora_anterior: int = int(HORA_INICIO_RELOJ)
var _ultima_hora_total_emitida: int = 0
var pausado: bool = false

signal hora_cambiada(hora_actual: float)

# ================================================================
# LUZ DIRECCIONAL ÚNICA
# ================================================================

var ambient_light: DirectionalLight2D = null

const SUN_COLOR_ROJIZO  := Color(1.0, 0.28, 0.08)
const SUN_COLOR_NARANJA := Color(1.0, 0.529, 0.341)
const SUN_COLOR_ROSADO  := Color(1.0, 0.38, 0.52)

# Ajusta este azul si quieres clavar el tono actual exacto de tu luna
const MOON_COLOR_AZULADO := Color(0.55, 0.68, 1.0)

# Rotaciones:
# - amanecer  -> izquierda
# - mediodía  -> centro
# - atardecer -> derecha
#
# Si ves que la dirección de las sombras sale invertida,
# cambia los signos: -65 <-> 65
const ROTATION_START_DEG := -65.0
const ROTATION_MID_DEG   := 0.0
const ROTATION_END_DEG   := 65.0


func registrar_luz_ambiental(p_ambient: DirectionalLight2D) -> void:
	ambient_light = p_ambient
	_actualizar_luz_ambiental()


# ================================================================
# CICLO PRINCIPAL
# ================================================================

func _ready() -> void:
	_sincronizar_reloj(false)


func _process(delta: float) -> void:
	if pausado:
		return

	advance_seconds(delta)
	_actualizar_luz_ambiental()


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
		_sincronizar_reloj(false)

	_actualizar_luz_ambiental()


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
	_sincronizar_reloj(false)
	_actualizar_luz_ambiental()


# ================================================================
# RELOJ INTERNO
# ================================================================

func _sincronizar_reloj(_emitir_eventos: bool) -> void:
	hora_actual = _calcular_hora_desde_tiempo(tiempo_acumulado)
	hora_anterior = int(floor(hora_actual))
	_ultima_hora_total_emitida = _get_hora_total_desde_tiempo(tiempo_acumulado)


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
		_ultima_hora_total_emitida = hora_total_nueva
		hora_anterior = int(floor(hora_actual))
		return

	for hora_total in range(hora_total_anterior + 1, hora_total_nueva + 1):
		var hora_emitida: float = fposmod(
			HORA_INICIO_RELOJ + float(hora_total),
			float(horas_por_dia)
		)
		hora_anterior = int(floor(hora_emitida))
		_ultima_hora_total_emitida = hora_total
		hora_cambiada.emit(hora_emitida)


# ================================================================
# LUZ DIRECCIONAL — SOL / LUNA
# ================================================================

func _actualizar_luz_ambiental() -> void:
	if not is_instance_valid(ambient_light):
		return

	ambient_light.visible = true

	if hora_actual >= 6.0 and hora_actual < 18.0:
		_actualizar_fase_sol()
	else:
		_actualizar_fase_luna()


func _actualizar_fase_sol() -> void:
	# ------------------------------------------------------------
	# ROTACIÓN
	# 6h   -> inicio
	# 12h  -> centro
	# 18h  -> fin
	# ------------------------------------------------------------
	var rot_deg: float

	if hora_actual < 12.0:
		var t_rot_morning: float = (hora_actual - 6.0) / 6.0
		rot_deg = lerpf(ROTATION_START_DEG, ROTATION_MID_DEG, t_rot_morning)
	else:
		var t_rot_evening: float = (hora_actual - 12.0) / 6.0
		rot_deg = lerpf(ROTATION_MID_DEG, ROTATION_END_DEG, t_rot_evening)

	ambient_light.rotation_degrees = rot_deg

	# ------------------------------------------------------------
	# ENERGÍA
	# 6-8   -> 1
	# 8-12  -> 1 a 4
	# 12-17 -> 4 a 1
	# 17-18 -> 1
	# ------------------------------------------------------------
	var energy: float

	if hora_actual < 8.0:
		energy = 1.0
	elif hora_actual < 12.0:
		var t_energy_up: float = (hora_actual - 8.0) / 4.0
		energy = lerpf(1.0, 4.0, t_energy_up)
	elif hora_actual < 17.0:
		var t_energy_down: float = (hora_actual - 12.0) / 5.0
		energy = lerpf(4.0, 1.0, t_energy_down)
	else:
		energy = 1.0

	ambient_light.energy = energy

	# ------------------------------------------------------------
	# COLOR
	# 6-8   -> rojizo a naranja
	# 8-17  -> naranja
	# 17-18 -> naranja a rosado
	# ------------------------------------------------------------
	var color: Color

	if hora_actual < 8.0:
		var t_color_morning: float = (hora_actual - 6.0) / 2.0
		color = SUN_COLOR_ROJIZO.lerp(SUN_COLOR_NARANJA, t_color_morning)
	elif hora_actual < 17.0:
		color = SUN_COLOR_NARANJA
	else:
		var t_color_evening: float = (hora_actual - 17.0) / 1.0
		color = SUN_COLOR_NARANJA.lerp(SUN_COLOR_ROSADO, t_color_evening)

	ambient_light.color = color


func _actualizar_fase_luna() -> void:
	# ------------------------------------------------------------
	# 18h -> inicio
	# 00h -> centro
	# 06h -> fin
	# ------------------------------------------------------------
	var horas_desde_18: float

	if hora_actual >= 18.0:
		horas_desde_18 = hora_actual - 18.0
	else:
		horas_desde_18 = hora_actual + 6.0

	var rot_deg: float

	if horas_desde_18 < 6.0:
		var t_rot_first_half: float = horas_desde_18 / 6.0
		rot_deg = lerpf(ROTATION_START_DEG, ROTATION_MID_DEG, t_rot_first_half)
	else:
		var t_rot_second_half: float = (horas_desde_18 - 6.0) / 6.0
		rot_deg = lerpf(ROTATION_MID_DEG, ROTATION_END_DEG, t_rot_second_half)

	ambient_light.rotation_degrees = rot_deg

	# Luna siempre azulada y energía 1
	ambient_light.color = MOON_COLOR_AZULADO
	ambient_light.energy = 1.0


func reset() -> void:
	tiempo_acumulado = 0.0
	hora_actual = HORA_INICIO_RELOJ
	hora_anterior = int(HORA_INICIO_RELOJ)
	_ultima_hora_total_emitida = 0
	pausado = false
	_actualizar_luz_ambiental()
