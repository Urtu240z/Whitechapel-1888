extends Node

# ================================================================
# DAY NIGHT MANAGER — day_night_manager.gd
# Autoload: DayNightManager
# Gestiona el ciclo día/noche y la iluminación ambiental.
# SleepManager puede pausar el ciclo y saltar horas via set_hora().
# CONFIG (game_config.tres) controla la duración de cada hora.
# ================================================================

const CONFIG = preload("res://Data/Game/game_config.tres")
const HORA_INICIO_DIA: float = 8.0

@export var horas_por_dia: int = 24

var hora_actual: float = HORA_INICIO_DIA
var tiempo_acumulado: float = 0.0
var canvas_modulate: CanvasModulate = null
var tween: Tween = null
var _ultimo_color_objetivo: Color = Color(-1.0, -1.0, -1.0, -1.0)
var hora_anterior: int = int(HORA_INICIO_DIA)
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

	var hora_total_anterior := _get_hora_total_desde_tiempo(tiempo_acumulado)
	tiempo_acumulado += segundos
	hora_actual = _calcular_hora_desde_tiempo(tiempo_acumulado)

	var hora_total_nueva := _get_hora_total_desde_tiempo(tiempo_acumulado)
	_emitir_horas_cruzadas(hora_total_anterior, hora_total_nueva)
	_actualizar_estado_visual()


# Avanza el reloj una cantidad de horas de juego.
func advance_hours(horas: float) -> void:
	if horas <= 0.0:
		return
	advance_seconds(horas * get_segundos_por_hora())


# Salta directamente a una hora específica.
# Conserva el día actual (o el siguiente si la hora objetivo ya pasó).
func set_hora(nueva_hora: float) -> void:
	var segundos_por_dia := get_segundos_por_dia()
	var dia_actual := int(floor(tiempo_acumulado / segundos_por_dia))
	var tiempo_objetivo := dia_actual * segundos_por_dia + _hora_a_segundos_en_dia(nueva_hora)

	# Si esa hora ya pasó dentro del día actual, saltamos al siguiente día.
	if tiempo_objetivo < tiempo_acumulado - 0.001:
		tiempo_objetivo += segundos_por_dia

	set_total_time(tiempo_objetivo, true)


# Fija el tiempo absoluto del juego.
# SaveManager debe usar esto al cargar una partida.
func set_total_time(nuevo_tiempo: float, emitir_eventos: bool = false) -> void:
	var tiempo_anterior := tiempo_acumulado
	tiempo_acumulado = maxf(nuevo_tiempo, 0.0)
	hora_actual = _calcular_hora_desde_tiempo(tiempo_acumulado)

	if emitir_eventos and tiempo_acumulado >= tiempo_anterior:
		var hora_total_anterior := _get_hora_total_desde_tiempo(tiempo_anterior)
		var hora_total_nueva := _get_hora_total_desde_tiempo(tiempo_acumulado)
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


func get_current_day() -> int:
	return int(floor(tiempo_acumulado / get_segundos_por_dia())) + 1


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
	var horas_pasadas := tiempo_total / get_segundos_por_hora()
	return fposmod(HORA_INICIO_DIA + horas_pasadas, float(horas_por_dia))


func _hora_a_segundos_en_dia(hora: float) -> float:
	var hora_normalizada := fposmod(hora, float(horas_por_dia))
	var horas_desde_inicio := fposmod(hora_normalizada - HORA_INICIO_DIA + float(horas_por_dia), float(horas_por_dia))
	return horas_desde_inicio * get_segundos_por_hora()


func _get_hora_total_desde_tiempo(tiempo_total: float) -> int:
	return int(floor(tiempo_total / get_segundos_por_hora()))


func _emitir_horas_cruzadas(hora_total_anterior: int, hora_total_nueva: int) -> void:
	if hora_total_nueva <= hora_total_anterior:
		_ultima_hora_total_emitida = hora_total_nueva
		hora_anterior = int(floor(hora_actual))
		return

	for hora_total in range(hora_total_anterior + 1, hora_total_nueva + 1):
		var hora_emitida := fposmod(HORA_INICIO_DIA + float(hora_total), float(horas_por_dia))
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
		target_color = Color(1.0, 1.0, 1.0)          # Día — blanco neutro
	elif hora_actual >= 18 and hora_actual < 20:
		target_color = Color(0.815, 0.336, 0.427)    # Atardecer — rojizo
	else:
		target_color = Color(0.25, 0.25, 0.4)        # Noche — azul oscuro

	if _ultimo_color_objetivo.is_equal_approx(target_color):
		return

	_ultimo_color_objetivo = target_color

	if tween and tween.is_running():
		tween.kill()

	tween = create_tween()
	tween.tween_property(canvas_modulate, "color", target_color, 0.35) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN_OUT)
