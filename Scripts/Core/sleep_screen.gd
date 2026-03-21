extends CanvasLayer
class_name SleepScreen

# ================================================================
# SLEEP SCREEN — sleep_screen.gd
# ================================================================

@onready var celestial_body: Node2D = $CelestialBody
@onready var lbl_hora: Label = $UI/LblHora
@onready var progress_bar: ProgressBar = $UI/ProgressBar
@onready var btn_cancelar: Button = $UI/BtnCancelar
@onready var post_panel: PanelContainer = $UI/PostSleepPanel
@onready var lbl_post: Label = $UI/PostSleepPanel/Margins/VBoxContainer/LblPost
@onready var btn_seguir: Button = $UI/PostSleepPanel/Margins/VBoxContainer/Botones/BtnSeguir
@onready var btn_salir: Button = $UI/PostSleepPanel/Margins/VBoxContainer/Botones/BtnSalir
@onready var background: ColorRect = $Background

signal cancelado
signal seguir_durmiendo
signal salir_a_la_calle

# Estado interno para interpolación continua
var _hora_actual: float = 0.0
var _hora_objetivo: float = 0.0
var _progreso_actual: float = 0.0
var _progreso_objetivo: float = 0.0
var _activo: bool = false

# Velocidad de interpolación — cuanto más alto más suave pero más lento visualmente
const VELOCIDAD_HORA: float = 2.0
const VELOCIDAD_PROGRESO: float = 2.0


# ================================================================
# INICIALIZACIÓN
# ================================================================

func _ready() -> void:
	btn_cancelar.pressed.connect(_on_cancelar_pressed)
	btn_seguir.pressed.connect(_on_seguir_pressed)
	btn_salir.pressed.connect(_on_salir_pressed)
	post_panel.visible = false
	btn_cancelar.grab_focus()
	_activo = true


func _process(delta: float) -> void:
	if not _activo:
		return

	# Interpolamos hora y progreso continuamente
	_hora_actual = _interpolar_hora(_hora_actual, _hora_objetivo, delta * VELOCIDAD_HORA)
	_progreso_actual = lerpf(_progreso_actual, _progreso_objetivo, delta * VELOCIDAD_PROGRESO)

	# Actualizamos la UI cada frame
	_actualizar_ui(_hora_actual, _progreso_actual)


# ================================================================
# API PÚBLICA — llamada por SleepManager
# ================================================================

func actualizar(hora: float, progreso: float) -> void:
	_hora_objetivo = hora
	_progreso_objetivo = progreso


func mostrar_panel_post(hora: float) -> void:
	_activo = false
	lbl_post.text = tr("SLEEP_POST_TEXTO") % _formato_hora(hora)
	post_panel.visible = true
	btn_seguir.grab_focus()


# Fade out — llamado por SleepManager antes de queue_free
func fade_out() -> void:
	_activo = false
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(background, "modulate:a", 0.0, 3.0)
	tween.tween_property(celestial_body, "modulate:a", 0.0, 3.0)
	tween.tween_property(lbl_hora, "modulate:a", 0.0, 3.0)
	tween.tween_property(progress_bar, "modulate:a", 0.0, 3.0)
	tween.tween_property(btn_cancelar, "modulate:a", 0.0, 3.0)
	await tween.finished


# ================================================================
# ACTUALIZACIÓN UI
# ================================================================

func _actualizar_ui(hora: float, progreso: float) -> void:
	# Hora con minutos interpolados
	var horas_int = int(hora)
	var minutos = int(fmod(hora, 1.0) * 60.0)
	lbl_hora.text = "%02d:%02d" % [horas_int, minutos]

	progress_bar.value = progreso
	_actualizar_cuerpo_celeste(hora)


func _actualizar_cuerpo_celeste(hora: float) -> void:
	var es_noche = hora >= 20.0 or hora < 6.0

	if es_noche:
		celestial_body.modulate = Color(0.85, 0.9, 1.0, celestial_body.modulate.a)
	else:
		celestial_body.modulate = Color(1.0, 0.85, 0.2, celestial_body.modulate.a)

	var t: float
	if es_noche:
		t = fmod(hora - 20.0 + 24.0, 24.0) / 10.0
	else:
		t = (hora - 6.0) / 14.0
	t = clampf(t, 0.0, 1.0)

	var vp = get_viewport().get_visible_rect().size
	var x = lerp(120.0, vp.x - 120.0, t)
	var y = vp.y * 0.4 - sin(t * PI) * vp.y * 0.25
	celestial_body.position = Vector2(x, y)


# ================================================================
# INTERPOLACIÓN DE HORA (maneja medianoche)
# ================================================================

func _interpolar_hora(actual: float, objetivo: float, t: float) -> float:
	# Maneja el cruce de medianoche correctamente
	var diff = objetivo - actual

	# Si la diferencia es mayor de 12h en cualquier dirección,
	# estamos cruzando medianoche
	if diff > 12.0:
		diff -= 24.0
	elif diff < -12.0:
		diff += 24.0

	var nueva = actual + diff * t
	return fmod(nueva + 24.0, 24.0)


# ================================================================
# BOTONES
# ================================================================

func _on_cancelar_pressed() -> void:
	cancelado.emit()

func _on_seguir_pressed() -> void:
	post_panel.visible = false
	_activo = true
	seguir_durmiendo.emit()

func _on_salir_pressed() -> void:
	salir_a_la_calle.emit()


# ================================================================
# INPUT — F para confirmar
# ================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if btn_cancelar.has_focus():
			_on_cancelar_pressed()
		elif btn_seguir.has_focus():
			_on_seguir_pressed()
		elif btn_salir.has_focus():
			_on_salir_pressed()


# ================================================================
# HELPERS
# ================================================================

func _formato_hora(hora: float) -> String:
	var h = int(hora)
	var m = int(fmod(hora, 1.0) * 60.0)
	return "%02d:%02d" % [h, m]
