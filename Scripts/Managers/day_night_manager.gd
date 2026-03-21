extends Node

# ================================================================
# DAY NIGHT MANAGER — day_night_manager.gd
# Autoload: DayNightManager
# Gestiona el ciclo día/noche y la iluminación ambiental.
# SleepManager puede pausar el ciclo y saltar horas via set_hora().
# CONFIG (game_config.tres) controla la duración de cada hora.
# ================================================================

const CONFIG = preload("res://Data/Game/game_config.tres")

@export var horas_por_dia: int = 24

var hora_actual: float = 8.0
var tiempo_acumulado: float = 0.0
var canvas_modulate: CanvasModulate = null
var tween: Tween = null
var hora_anterior: int = -1

# Controlado por SleepManager durante el sueño
var pausado: bool = false

signal hora_cambiada(hora_actual: float)


# ================================================================
# CICLO PRINCIPAL
# ================================================================

func _ready() -> void:
	_buscar_canvas_modulate()


func _process(delta: float) -> void:
	# SleepManager pausa el ciclo mientras controla el tiempo manualmente
	if pausado:
		return

	tiempo_acumulado += delta

	var segundos_por_dia = CONFIG.duracion_hora_segundos * horas_por_dia
	var horas_pasadas = (tiempo_acumulado / segundos_por_dia) * horas_por_dia
	hora_actual = fmod(8.0 + horas_pasadas, horas_por_dia)

	# Emitir señal una vez por hora entera
	if int(hora_actual) != hora_anterior:
		hora_anterior = int(hora_actual)
		hora_cambiada.emit(hora_actual)

	# Asegurar referencia al CanvasModulate en la escena activa
	if canvas_modulate == null:
		_buscar_canvas_modulate()

	if canvas_modulate:
		_actualizar_iluminacion()


# ================================================================
# API PÚBLICA — usada por SleepManager
# ================================================================

# Salta directamente a una hora específica.
# Ajusta tiempo_acumulado para que _process sea consistente.
# Emite hora_cambiada para que NPCs e iluminación reaccionen.
func set_hora(nueva_hora: float) -> void:
	var horas_desde_inicio = fmod(nueva_hora - 8.0 + horas_por_dia, horas_por_dia)
	var segundos_por_dia = CONFIG.duracion_hora_segundos * horas_por_dia
	tiempo_acumulado = (horas_desde_inicio / horas_por_dia) * segundos_por_dia

	hora_actual = nueva_hora
	hora_anterior = int(nueva_hora) - 1

	# Emitimos la señal inmediatamente — no esperamos al siguiente frame
	hora_cambiada.emit(hora_actual)

	# Actualizamos la iluminación al instante, sin esperar a _process
	if canvas_modulate:
		_actualizar_iluminacion()


# Pausa el avance del tiempo. Llamado por SleepManager al iniciar el sueño.
func pausar() -> void:
	pausado = true


# Reanuda el avance del tiempo. Llamado por SleepManager al despertar.
func reanudar() -> void:
	pausado = false


# ================================================================
# ILUMINACIÓN
# ================================================================

func _buscar_canvas_modulate() -> void:
	var scene_root = get_tree().current_scene
	if scene_root:
		canvas_modulate = scene_root.get_node_or_null("IluminacionAmbiental")


func _actualizar_iluminacion() -> void:
	if canvas_modulate == null:
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

	# Solo lanzamos un nuevo tween si el anterior ya terminó
	# Evita spam de tweens que compiten entre sí
	if not tween or not tween.is_running():
		tween = create_tween()
		tween.tween_property(canvas_modulate, "color", target_color, 2.0) \
			.set_trans(Tween.TRANS_SINE) \
			.set_ease(Tween.EASE_IN_OUT)
