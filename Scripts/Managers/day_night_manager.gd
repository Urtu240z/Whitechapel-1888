extends Node

# ================================================================
# DAY NIGHT MANAGER — day_night_manager.gd
# Autoload: DayNightManager
# Gestiona el ciclo día/noche y la iluminación ambiental.
# SleepManager puede pausar el ciclo y avanzar horas de juego.
# CONFIG (game_config.tres) controla la duración de cada hora.
#
# IMPORTANTE:
# - El juego EMPIEZA a las 08:00
# - El día CAMBIA a las 00:00
# ================================================================

const CONFIG = preload("res://Data/Game/game_config.tres")
const HORA_INICIO_RELOJ: float = 8.0

@export var horas_por_dia: int = 24

var hora_actual: float = HORA_INICIO_RELOJ
var tiempo_acumulado: float = 0.0
var canvas_modulate: CanvasModulate = null
var tween: Tween = null
var _ultimo_color_objetivo: Color = Color(-1.0, -1.0, -1.0, -1.0)
var hora_anterior: int = int(HORA_INICIO_RELOJ)
var _ultima_hora_total_emitida: int = 0

# Controlado por SleepManager durante el sueño
var pausado: bool = false

signal hora_cambiada(hora_actual: float)


# ================================================================
# CICLO PRINCIPAL
# ================================================================

func _ready() -> void:
	_buscar_canvas_modulate()
	_sincronizar_reloj(false)
	_actualizar_estado_visual()


func _process(delta: float) -> void:
	# SleepManager pausa el ciclo mientras controla el tiempo manualmente
	if pausado:
		return

	advance_seconds(delta)


# ================================================================
# API PÚBLICA — usada por SleepManager / SaveManager / UI
# ================================================================

# Avanza el reloj una cantidad de segundos reales.
func advance_seconds(segundos: float) -> void:
	if segundos <= 0.0:
		_actualizar_estado_visual()
		return

	var hora_total_anterior: int = _get_hora_total_desde_tiempo(tiempo_acumulado)

	tiempo_acumulado += segundos
	hora_actual = _calcular_hora_desde_tiempo(tiempo_acumulado)

	var hora_total_nueva: int = _get_hora_total_desde_tiempo(tiempo_acumulado)
	_emitir_horas_cruzadas(hora_total_anterior, hora_total_nueva)
	_actualizar_estado_visual()


# Avanza el reloj una cantidad de horas de juego.
func advance_hours(horas: float) -> void:
	if horas <= 0.0:
		return
	advance_seconds(horas * get_segundos_por_hora())


# Salta directamente a una hora específica.
# Conserva el ciclo actual o avanza al siguiente si esa hora ya pasó.
func set_hora(nueva_hora: float) -> void:
	var segundos_por_dia: float = get_segundos_por_dia()
	var ciclo_actual: int = int(floor(tiempo_acumulado / segundos_por_dia))
	var tiempo_objetivo: float = ciclo_actual * segundos_por_dia + _hora_a_segundos_en_ciclo(nueva_hora)

	# Si esa hora ya pasó dentro del ciclo actual, saltamos al siguiente.
	if tiempo_objetivo < tiempo_acumulado - 0.001:
		tiempo_objetivo += segundos_por_dia

	set_total_time(tiempo_objetivo, true)


# Fija el tiempo absoluto del juego.
# SaveManager debe usar esto al cargar una partida.
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

	_actualizar_estado_visual()


# Pausa el avance del tiempo. Llamado por SleepManager al iniciar el sueño.
func pausar() -> void:
	pausado = true


# Reanuda el avance del tiempo. Llamado por SleepManager al despertar.
func reanudar() -> void:
	pausado = false


func get_segundos_por_hora() -> float:
	return maxf(CONFIG.duracion_hora_segundos, 0.001)


func get_segundos_por_dia() -> float:
	return get_segundos_por_hora() * float(horas_por_dia)


# Horas de juego transcurridas desde el inicio de partida.
func get_total_hours_elapsed() -> float:
	return tiempo_acumulado / get_segundos_por_hora()


# Hora absoluta desde el inicio del calendario del juego.
# Ejemplo:
# - inicio partida: 8.0
# - medianoche del primer día: 24.0
# - día 2 a las 07:00: 31.0
func get_absolute_clock_hours() -> float:
	return HORA_INICIO_RELOJ + get_total_hours_elapsed()


# Día visible para HUD / Journal / Save.
# CAMBIA a las 00:00, no a las 08:00.
func get_current_day() -> int:
	return int(floor(get_absolute_clock_hours() / 24.0)) + 1


func get_hour_float() -> float:
	return hora_actual


func sincronizar_reloj() -> void:
	_sincronizar_reloj(false)
	_actualizar_estado_visual()


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


# Convierte una hora visible del reloj (0-23) en segundos dentro del ciclo
# de 24h contado desde la hora inicial del juego.
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
# ILUMINACIÓN
# ================================================================

func _buscar_canvas_modulate() -> void:
	var scene_root = get_tree().current_scene
	if scene_root:
		canvas_modulate = scene_root.get_node_or_null("IluminacionAmbiental")


func _actualizar_estado_visual() -> void:
	if not is_instance_valid(canvas_modulate):
		canvas_modulate = null

	if canvas_modulate == null:
		_buscar_canvas_modulate()

	if is_instance_valid(canvas_modulate):
		_actualizar_iluminacion()


func _actualizar_iluminacion() -> void:
	if not is_instance_valid(canvas_modulate):
		return

	var target_color: Color

	if hora_actual >= 6 and hora_actual < 8:
		target_color = Color(0.8, 0.7, 0.6)         # Amanecer — cálido
	elif hora_actual >= 8 and hora_actual < 18:
		target_color = Color(1.0, 1.0, 1.0)         # Día — blanco neutro
	elif hora_actual >= 18 and hora_actual < 20:
		target_color = Color(0.815, 0.336, 0.427)   # Atardecer — rojizo
	else:
		target_color = Color(0.25, 0.25, 0.4)       # Noche — azul oscuro

	if _ultimo_color_objetivo.is_equal_approx(target_color):
		return

	_ultimo_color_objetivo = target_color

	if tween and tween.is_running():
		tween.kill()

	tween = create_tween()
	tween.tween_property(canvas_modulate, "color", target_color, 0.35) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)


func reset() -> void:
	# Vuelve al inicio del juego: día 1, 08:00.
	tiempo_acumulado = 0.0
	hora_actual = HORA_INICIO_RELOJ
	hora_anterior = int(HORA_INICIO_RELOJ)
	_ultima_hora_total_emitida = 0
	pausado = false
	_ultimo_color_objetivo = Color(-1.0, -1.0, -1.0, -1.0)
	if tween and tween.is_running():
		tween.kill()
	_actualizar_estado_visual()
