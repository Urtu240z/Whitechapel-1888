extends CanvasLayer
class_name SleepScreen

# ================================================================
# SLEEP SCREEN — sleep_screen.gd
# Controla:
# - reloj
# - barra de progreso
# - botones
# - panel post-sleep
# - pausa / reanudación del AnimationPlayer de fondo
# ================================================================

signal cancelado
signal seguir_durmiendo
signal salir_a_la_calle
signal tramo_visual_terminado

@onready var lbl_hora: Label = $UI/LblHora
@onready var progress_bar: ProgressBar = $UI/ProgressBar
@onready var btn_cancelar: Button = $UI/BtnCancelar
@onready var post_panel: PanelContainer = $UI/PostSleepPanel
@onready var lbl_post: Label = $UI/PostSleepPanel/Margins/VBoxContainer/LblPost
@onready var btn_seguir: Button = $UI/PostSleepPanel/Margins/VBoxContainer/Botones/BtnSeguir
@onready var btn_salir: Button = $UI/PostSleepPanel/Margins/VBoxContainer/Botones/BtnSalir
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var _hora_inicio: float = 22.0
var _hora_fin: float = 8.0
var _progreso_inicio: float = 0.0
var _progreso_fin: float = 1.0

var _hora_actual: float = 22.0
var _progreso_actual: float = 0.0

var _tiempo_visual: float = 0.0
var _duracion_visual: float = 0.0

var _activo: bool = false
var _animando: bool = false
var _forzado: bool = false
var _sleep_preview: float = 0.0
var _ui_inicializada: bool = false
var _interaction_enabled: bool = true
var _closing: bool = false

var _sleep_anim_name: StringName = &"Sleep"
var _sleep_anim_base_speed: float = 1.0
var _paused_for_post_panel: bool = false

const HORAS_NOCHE_COMPLETA: float = 10.0     # 22:00 -> 08:00
const DURACION_NOCHE_COMPLETA: float = 20.0  # duración visual total buscada
const DURACION_MINIMA_TRAMO: float = 0.75
const HORA_INICIO_NOCHE: float = 22.0
const HORA_FIN_NOCHE: float = 8.0

# ================================================================
# INICIALIZACIÓN
# ================================================================

func _ready() -> void:
	btn_cancelar.pressed.connect(_on_cancelar_pressed)
	btn_seguir.pressed.connect(_on_seguir_pressed)
	btn_salir.pressed.connect(_on_salir_pressed)

	$UI.visible = true
	post_panel.visible = false

	_sleep_preview = PlayerStats.sueno
	_activo = true

	lbl_hora.modulate.a = 1.0
	progress_bar.modulate.a = 1.0
	btn_cancelar.modulate.a = 1.0
	post_panel.modulate.a = 1.0

	if animation_player:
		_sleep_anim_base_speed = animation_player.speed_scale
		if animation_player.has_animation(_sleep_anim_name):
			animation_player.stop()

	btn_cancelar.grab_focus()
	_actualizar_boton_despertar()

# ================================================================
# API PÚBLICA
# ================================================================

func set_forzado(value: bool) -> void:
	_forzado = value
	_actualizar_boton_despertar()

func set_sleep_preview(value: float) -> void:
	_sleep_preview = clampf(value, 0.0, 100.0)
	_actualizar_boton_despertar()

func set_interaction_enabled(value: bool) -> void:
	_interaction_enabled = value and not _closing
	_actualizar_boton_despertar()

	if btn_seguir:
		btn_seguir.disabled = not _interaction_enabled
	if btn_salir:
		btn_salir.disabled = not _interaction_enabled

func begin_closing() -> void:
	_closing = true
	set_interaction_enabled(false)
	_activo = false
	_animando = false
	_pausar_animacion_fondo()

func actualizar(hora: float, progreso: float, snap: bool = false) -> void:
	_hora_actual = fposmod(hora, 24.0)
	_progreso_actual = clampf(progreso, 0.0, 1.0)
	_ui_inicializada = true
	_actualizar_ui(_hora_actual, _progreso_actual)

	if snap:
		_animando = false

func iniciar_tramo_visual(hora_inicio: float, hora_fin: float, progreso_inicio: float, progreso_fin: float) -> void:
	_hora_inicio = fposmod(hora_inicio, 24.0)
	_hora_fin = fposmod(hora_fin, 24.0)
	_progreso_inicio = clampf(progreso_inicio, 0.0, 1.0)
	_progreso_fin = clampf(progreso_fin, 0.0, 1.0)

	_tiempo_visual = 0.0
	_duracion_visual = _calcular_duracion_visual(_hora_inicio, _hora_fin)

	_hora_actual = _hora_inicio
	_progreso_actual = _progreso_inicio
	_ui_inicializada = true

	# Actualización inmediata para que no “tarde en arrancar”
	_actualizar_ui(_hora_actual, _progreso_actual)

	post_panel.visible = false
	if _interaction_enabled:
		btn_cancelar.grab_focus()

	_activo = true
	_animando = true

	_sync_background_animation_for_segment(_hora_inicio)

func get_duracion_visual_actual() -> float:
	return _duracion_visual

func mostrar_panel_post(hora: float) -> void:
	_activo = false
	_animando = false
	_pausar_animacion_fondo()

	_hora_actual = fposmod(hora, 24.0)
	_actualizar_ui(_hora_actual, _progreso_actual)

	lbl_post.text = tr("SLEEP_POST_TEXTO") % _formato_hora(hora)
	post_panel.visible = true
	set_interaction_enabled(true)
	btn_seguir.grab_focus()

func fade_out() -> void:
	begin_closing()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl_hora, "modulate:a", 0.0, 0.8)
	tween.tween_property(progress_bar, "modulate:a", 0.0, 0.8)
	tween.tween_property(btn_cancelar, "modulate:a", 0.0, 0.8)
	tween.tween_property(post_panel, "modulate:a", 0.0, 0.8)
	await tween.finished

# ================================================================
# PROCESS
# ================================================================

func _process(delta: float) -> void:
	if not _activo:
		return

	if _forzado:
		_actualizar_boton_despertar()

	if not _animando:
		return

	_tiempo_visual = min(_tiempo_visual + delta, _duracion_visual)

	var t := 1.0
	if _duracion_visual > 0.0:
		t = clampf(_tiempo_visual / _duracion_visual, 0.0, 1.0)

	# Directo y exacto
	_hora_actual = _lerp_hora_forward(_hora_inicio, _hora_fin, t)
	_progreso_actual = lerpf(_progreso_inicio, _progreso_fin, t)

	_actualizar_ui(_hora_actual, _progreso_actual)

	if t >= 1.0:
		_animando = false

		# Snap final exacto
		_hora_actual = _hora_fin
		_progreso_actual = _progreso_fin
		_actualizar_ui(_hora_actual, _progreso_actual)

		# Dejar la animación exactamente en el punto final del tramo
		_sync_animation_position_to_hour(_hora_fin, true)

		tramo_visual_terminado.emit()

# ================================================================
# UI
# ================================================================

func _actualizar_ui(hora: float, progreso: float) -> void:
	lbl_hora.text = _formato_hora(hora)
	progress_bar.value = clampf(progreso, 0.0, 1.0)

func _actualizar_boton_despertar() -> void:
	if btn_cancelar == null:
		return

	if not _interaction_enabled or _closing:
		btn_cancelar.disabled = true
		if btn_cancelar.text == "":
			btn_cancelar.text = tr("SLEEP_DESPERTAR")
		return

	if _forzado:
		var puede := _sleep_preview >= 40.0
		btn_cancelar.disabled = not puede
		if not puede:
			btn_cancelar.text = "Necesitas descansar más..."
		else:
			btn_cancelar.text = tr("SLEEP_DESPERTAR")
	else:
		btn_cancelar.disabled = false
		btn_cancelar.text = tr("SLEEP_DESPERTAR")

# ================================================================
# ANIMACIÓN DE FONDO
# ================================================================

func _sync_background_animation_for_segment(hora_inicio_segmento: float) -> void:
	if animation_player == null:
		return
	if not animation_player.has_animation(_sleep_anim_name):
		return

	if _paused_for_post_panel:
		# Si venimos del panel post-sleep, reanudar exactamente donde estaba
		_paused_for_post_panel = false
		_reanudar_animacion_fondo()
		return

	_sync_animation_position_to_hour(hora_inicio_segmento, false)
	_reanudar_animacion_fondo()

func _sync_animation_position_to_hour(hora: float, keep_paused: bool) -> void:
	if animation_player == null:
		return
	if not animation_player.has_animation(_sleep_anim_name):
		return

	var anim: Animation = animation_player.get_animation(_sleep_anim_name)
	if anim == null:
		return

	var progress := _get_night_progress_from_hour(hora)
	var target_time := progress * anim.length

	animation_player.play(_sleep_anim_name)
	animation_player.speed_scale = _sleep_anim_base_speed
	animation_player.seek(target_time, true)

	if keep_paused:
		animation_player.pause()

func _pausar_animacion_fondo() -> void:
	if animation_player == null:
		return
	if not animation_player.is_playing():
		return

	animation_player.pause()
	_paused_for_post_panel = true

func _reanudar_animacion_fondo() -> void:
	if animation_player == null:
		return

	animation_player.speed_scale = _sleep_anim_base_speed
	animation_player.play()

# ================================================================
# CÁLCULOS
# ================================================================

func _calcular_duracion_visual(hora_inicio: float, hora_fin: float) -> float:
	var horas_a_dormir := _distancia_horas_forward(hora_inicio, hora_fin)
	var duracion := (horas_a_dormir / HORAS_NOCHE_COMPLETA) * DURACION_NOCHE_COMPLETA
	return max(duracion, DURACION_MINIMA_TRAMO)

func _distancia_horas_forward(inicio: float, fin: float) -> float:
	return fposmod(fin - inicio + 24.0, 24.0)

func _lerp_hora_forward(inicio: float, fin: float, t: float) -> float:
	var delta := _distancia_horas_forward(inicio, fin)
	return fposmod(inicio + delta * t, 24.0)

func _get_night_progress_from_hour(hora: float) -> float:
	var progress := _distancia_horas_forward(HORA_INICIO_NOCHE, hora) / HORAS_NOCHE_COMPLETA
	return clampf(progress, 0.0, 1.0)

func _formato_hora(hora: float) -> String:
	var total_minutes := int(round(fposmod(hora, 24.0) * 60.0)) % (24 * 60)
	var h := total_minutes / 60.0
	var m := total_minutes % 60
	return "%02d:%02d" % [h, m]

# ================================================================
# BOTONES
# ================================================================

func _on_cancelar_pressed() -> void:
	if not _interaction_enabled or _closing:
		return
	if _forzado and _sleep_preview < 40.0:
		return
	begin_closing()
	cancelado.emit()

func _on_seguir_pressed() -> void:
	if not _interaction_enabled or _closing:
		return

	set_interaction_enabled(false)
	post_panel.visible = false
	_activo = true

	# Reanudar visualmente ya; SleepManager arrancará el siguiente tramo real
	_reanudar_animacion_fondo()

	seguir_durmiendo.emit()

func _on_salir_pressed() -> void:
	if not _interaction_enabled or _closing:
		return
	begin_closing()
	salir_a_la_calle.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not _interaction_enabled or _closing:
		return
	if event.is_action_pressed("interact"):
		if btn_cancelar.has_focus() and not btn_cancelar.disabled:
			_on_cancelar_pressed()
		elif btn_seguir.has_focus():
			_on_seguir_pressed()
		elif btn_salir.has_focus():
			_on_salir_pressed()
