extends CanvasLayer
class_name SleepSelection

# ================================================================
# SLEEP SELECTION — sleep_selection.gd
# Panel de selección de horas de sueño.
# SleepManager lo instancia, lo configura y escucha sus señales.
# ================================================================

@onready var lbl_desde_val: Label = $Panel/Margins/VBox/InfoGrid/LblDesdeVal
@onready var lbl_hasta_val: Label = $Panel/Margins/VBox/InfoGrid/LblHastaVal
@onready var lbl_sueno_val: Label = $Panel/Margins/VBox/InfoGrid/LblSuenoVal
@onready var slider: HSlider = $Panel/Margins/VBox/SliderHoras
@onready var lbl_horas: Label = $Panel/Margins/VBox/LblHoras
@onready var titulo: Label = $Panel/Margins/VBox/Titulo
@onready var btn_descansar: Button = $Panel/Margins/VBox/Botones/BtnDescansar
@onready var btn_cancelar: Button = $Panel/Margins/VBox/Botones/BtnCancelar

signal confirmado(horas: float)
signal cancelado

# ================================================================
# ESTADO INTERNO
# ================================================================

var _hora_inicio: float = 0.0
var _sueno_actual: float = 0.0
var _recuperacion_por_hora: float = 0.0


# ================================================================
# INICIALIZACIÓN
# ================================================================

func _ready() -> void:
	slider.value_changed.connect(_on_slider_changed)
	btn_descansar.pressed.connect(_on_descansar_pressed)
	btn_cancelar.pressed.connect(_on_cancelar_pressed)
	
	# Foco inicial en el slider para control con teclado
	# Izquierda/Derecha mueven el slider, Tab cambia entre nodos
	slider.grab_focus()
	
	# F confirma desde cualquier nodo del panel
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		# F sobre el slider → confirmar
		if slider.has_focus():
			_on_descansar_pressed()
		# F sobre cancelar → cancelar
		elif btn_cancelar.has_focus():
			_on_cancelar_pressed()


# ================================================================
# API PÚBLICA — llamado por SleepManager antes de mostrar el panel
# ================================================================

func configurar(lugar: String, hora_inicio: float, horas_max: float, sueno_actual: float, recuperacion_por_hora: float) -> void:
	# Título traducible según lugar
	match lugar:
		"hostal":
			titulo.text = tr("SLEEP_TITLE_HOSTAL")
		"callejon":
			titulo.text = tr("SLEEP_TITLE_CALLEJON")
		_:
			titulo.text = tr("SLEEP_TITLE_CALLE")

	# Configurar slider con el máximo calculado por SleepManager
	slider.min_value = 1.0
	slider.max_value = horas_max
	slider.step = 1.0
	slider.value = horas_max  # Por defecto al máximo

	# Guardar datos para los cálculos de la UI
	_hora_inicio = hora_inicio
	_sueno_actual = sueno_actual
	_recuperacion_por_hora = recuperacion_por_hora

	# Actualizar la info con los valores iniciales
	_actualizar_info(horas_max)


# ================================================================
# LÓGICA DE UI
# ================================================================

func _on_slider_changed(valor: float) -> void:
	_actualizar_info(valor)


func _actualizar_info(horas: float) -> void:
	var hora_fin = fmod(_hora_inicio + horas, 24.0)
	var sueno_estimado = minf(_sueno_actual + horas * _recuperacion_por_hora, 100.0)

	lbl_desde_val.text = _formato_hora(_hora_inicio)
	lbl_hasta_val.text = _formato_hora(hora_fin)
	lbl_sueno_val.text = "%d → %d" % [int(_sueno_actual), int(sueno_estimado)]

	# Plural traducible: "1 hora" / "6 horas"
	var sufijo = tr("SLEEP_HORAS") if horas > 1 else tr("SLEEP_HORA")
	lbl_horas.text = "%d %s" % [int(horas), sufijo]


# ================================================================
# BOTONES
# ================================================================

func _on_descansar_pressed() -> void:
	confirmado.emit(slider.value)
	queue_free()


func _on_cancelar_pressed() -> void:
	cancelado.emit()
	queue_free()


# ================================================================
# HELPERS
# ================================================================

func _formato_hora(hora: float) -> String:
	var h = int(hora)
	var m = int(fmod(hora, 1.0) * 60.0)
	return "%02d:%02d" % [h, m]

func mostrar_aviso_cerrado() -> void:
	titulo.text = tr("SLEEP_HOSTAL_CERRADO")
	$Panel/Margins/VBox/InfoGrid.visible = false
	slider.visible = false
	lbl_horas.visible = false
	$Panel/Margins/VBox/HSeparator.visible = false
	btn_descansar.visible = false
	btn_cancelar.grab_focus()
