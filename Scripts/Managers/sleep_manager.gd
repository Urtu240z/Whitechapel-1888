extends Node

# ================================================================
# SLEEP MANAGER — sleep_manager.gd
# Autoload: SleepManager
# ================================================================

const CONFIG = preload("res://Data/Game/game_config.tres")

# ================================================================
# CONSTANTES
# ================================================================

const SALUD_HOSTAL_POR_HORA: float = 0.5
const ESTRES_HOSTAL_POR_HORA: float = 1.0

const ALCOHOL_PERDIDO_CALLE: float = 10.0
const LAUDANO_PERDIDO_CALLE: float = 5.0

const PROB_CURAR_CALLE: float = 0.15
const PROB_EMPEORAR_CALLE: float = 0.15
const EMPEORAMIENTO_CALLE: float = 10.0

# ── COLAPSO ──────────────────────────────────────────────────────
const RECUPERACION_COLAPSO_POR_HORA: float = 10.0
const SUENO_MINIMO_DESPERTAR: float = 40.0

const SCENE_SELECTION = preload("res://Scenes/Core/Sleep_Selection.tscn")
const SCENE_SCREEN = preload("res://Scenes/Core/Sleep_Screen.tscn")

const LOCK_REASON: String = "sleep"

# ================================================================
# ESTADO INTERNO
# ================================================================

enum Lugar { HOSTAL, CALLE, CALLEJON }

var _lugar: Lugar = Lugar.CALLE
var _hora_inicio: float = 0.0
var _hora_fin: float = 0.0
var _horas_totales: float = 0.0
var _horas_dormidas: float = 0.0
var _durmiendo: bool = false
var _cancelado: bool = false
var _forzado: bool = false
var _hostel_payment_required: bool = false
var _pending_hostel_payment: float = 0.0

var _selection: Node = null
var _screen: Node = null

# Tramo visual actual
var _segment_started_at_sec: float = 0.0
var _segment_visual_duration: float = 0.0
var _segment_hours_total: float = 0.0
var _segment_sleep_start: float = 0.0

# ================================================================
# SEÑALES
# ================================================================

signal sleep_interrupted(motivo: String)
signal sleep_ended(horas_dormidas: float, completado: bool)

# ================================================================
# READY / PROCESS
# ================================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)

func _process(_delta: float) -> void:
	if not _durmiendo:
		return
	if not _forzado:
		return
	if _screen == null:
		return
	if _segment_visual_duration <= 0.0:
		return

	if _screen.has_method("set_sleep_preview"):
		var t := _get_segment_progress_01()
		var recuperacion_total := RECUPERACION_COLAPSO_POR_HORA * _segment_hours_total
		var sueno_preview := minf(_segment_sleep_start + recuperacion_total * t, 100.0)
		_screen.call("set_sleep_preview", sueno_preview)

# ================================================================
# API PÚBLICA
# ================================================================

func start_sleep(lugar_str: String) -> void:
	if _durmiendo or _selection != null or _screen != null:
		return

	if not StateManager.can_start_sleep():
		push_warning("SleepManager.start_sleep(): estado inválido: %s" % StateManager.current_name())
		return

	_lugar = _parsear_lugar(lugar_str)
	_hora_inicio = DayNightManager.get_hour_float()

	if _lugar == Lugar.HOSTAL and not is_hostel_open(_hora_inicio):
		_mostrar_aviso_hostal_cerrado()
		return

	if _lugar == Lugar.HOSTAL:
		var horas_restantes: float = get_hostel_hours_until_close(_hora_inicio)
		if horas_restantes < 1.0:
			_mostrar_aviso_poco_tiempo()
			return

	_mostrar_selection()


func start_sleep_forced(lugar_str: String, mensaje: String = "") -> void:
	if _durmiendo or _screen != null:
		return

	if not _enter_sleep_mode("forced_sleep"):
		return

	_lugar = _parsear_lugar(lugar_str)
	_hora_inicio = DayNightManager.get_hour_float()
	_horas_totales = _calcular_horas_para_recuperar_forzado()
	_hora_fin = fmod(_hora_inicio + _horas_totales, 24.0)
	_horas_dormidas = 0.0
	_cancelado = false
	_durmiendo = true
	_forzado = true

	_mostrar_mensaje_colapso(mensaje)
	await SceneManager.fade_out(2.0, true, "forced_sleep_fade_out")
	_limpiar_mensaje_colapso()
	await _iniciar_sueno_directo()


func interrupt_sleep(motivo: String) -> void:
	if not _durmiendo:
		return

	_cancelado = true
	sleep_interrupted.emit(motivo)
	_on_screen_cancelado()


func is_hostel_open(hora: float = -1.0) -> bool:
	var h: float = hora
	if h < 0.0:
		h = DayNightManager.get_hour_float()

	return h >= CONFIG.hora_apertura_hostal or h < CONFIG.hora_cierre_hostal


func get_hostel_hours_until_close(hora: float = -1.0) -> float:
	var h: float = hora
	if h < 0.0:
		h = DayNightManager.get_hour_float()

	return _horas_entre(h, CONFIG.hora_cierre_hostal)


func can_rent_hostel_room(hora: float = -1.0) -> bool:
	return bool(get_hostel_rent_status(hora).get("can_rent", false))


func get_hostel_rent_status(hora: float = -1.0) -> Dictionary:
	var h: float = hora
	if h < 0.0:
		h = DayNightManager.get_hour_float()

	if not is_hostel_open(h):
		return {
			"can_rent": false,
			"reason": "closed",
			"hours_left": 0.0
		}

	var horas_restantes: float = get_hostel_hours_until_close(h)
	if horas_restantes < 1.0:
		return {
			"can_rent": false,
			"reason": "not_enough_time",
			"hours_left": horas_restantes
		}

	return {
		"can_rent": true,
		"reason": "ok",
		"hours_left": horas_restantes
	}


func start_hostel_rental_flow(coste: float) -> Dictionary:
	if _durmiendo or _selection != null or _screen != null:
		return {
			"success": false,
			"reason": "busy"
		}

	if not StateManager.can_start_sleep():
		return {
			"success": false,
			"reason": "invalid_state"
		}

	_lugar = Lugar.HOSTAL
	_hora_inicio = DayNightManager.get_hour_float()

	var rent_status: Dictionary = get_hostel_rent_status(_hora_inicio)
	if not bool(rent_status.get("can_rent", false)):
		match str(rent_status.get("reason", "")):
			"closed":
				_mostrar_aviso_hostal_cerrado()
			"not_enough_time":
				_mostrar_aviso_poco_tiempo()
			_:
				_mostrar_aviso_poco_tiempo()

		return {
			"success": false,
			"reason": rent_status.get("reason", "invalid")
		}

	_hostel_payment_required = true
	_pending_hostel_payment = maxf(coste, 0.0)
	_mostrar_selection()

	return {
		"success": true,
		"reason": "ok"
	}

# ================================================================
# ESTADO / BLOQUEO GLOBAL
# ================================================================
func _enter_sleep_mode(reason: String) -> bool:
	if StateManager.is_sleeping():
		PlayerManager.lock_player(LOCK_REASON, true)
		DayNightManager.pausar()
		return true

	if not StateManager.can_start_sleep():
		push_warning("SleepManager: no se puede iniciar sueño desde %s" % StateManager.current_name())
		return false

	if not StateManager.change_to(StateManager.State.SLEEPING, reason):
		return false

	PlayerManager.lock_player(LOCK_REASON, true)
	PlayerManager.force_stop()
	DayNightManager.pausar()
	return true


func _exit_sleep_mode(reason: String) -> void:
	DayNightManager.reanudar()

	if StateManager.is_sleeping():
		StateManager.return_to_gameplay(reason)
	elif StateManager.is_hard_lock_state():
		StateManager.force_state(StateManager.State.GAMEPLAY, reason)

	PlayerManager.unlock_player(LOCK_REASON)
	PlayerManager.force_stop()


func _play_player_rise_animation(player: Node) -> void:
	if not is_instance_valid(player):
		return

	var animation = player.get("animation")
	if animation == null:
		return

	if animation.has_method("play_rise"):
		animation.play_rise()

	var anim_tree = animation.get("anim_tree")
	if anim_tree != null and anim_tree.has_signal("animation_finished"):
		await anim_tree.animation_finished

# ================================================================
# MENSAJE DE COLAPSO
# ================================================================

var _collapse_label: CanvasLayer = null

func _mostrar_mensaje_colapso(mensaje: String) -> void:
	if mensaje.is_empty():
		return

	_collapse_label = CanvasLayer.new()
	_collapse_label.layer = 1100

	var lbl := Label.new()
	lbl.text = mensaje
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)

	var font := load("res://Assets/Fonts/IMFellEnglish.ttf") as FontFile
	if font:
		lbl.add_theme_font_override("font", font)

	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))

	_collapse_label.add_child(lbl)
	get_tree().root.add_child(_collapse_label)

func _limpiar_mensaje_colapso() -> void:
	if _collapse_label != null and is_instance_valid(_collapse_label):
		_collapse_label.queue_free()
		_collapse_label = null

# ================================================================
# INICIO DE SUEÑO DIRECTO (sin Selection)
# ================================================================

func _iniciar_sueno_directo() -> void:
	DayNightManager.pausar()

	_screen = SCENE_SCREEN.instantiate()
	get_tree().root.add_child(_screen)
	_screen.connect("cancelado", _on_screen_cancelado)
	_screen.connect("seguir_durmiendo", _on_seguir_durmiendo)
	_screen.connect("salir_a_la_calle", _on_salir_a_la_calle)
	_screen.connect("tramo_visual_terminado", _on_tramo_visual_terminado)
	_screen.call("actualizar", DayNightManager.get_hour_float(), 0.0, true)

	if _forzado:
		_screen.call("set_forzado", true)
		if _screen.has_method("set_sleep_preview"):
			_screen.call("set_sleep_preview", PlayerStats.sueno)

	await SceneManager.fade_in(1.5, true, "sleep_fade_in")

	_arrancar_tramo_visual(_hora_inicio, _hora_fin, _horas_totales)

# ================================================================
# PANEL DE SELECCIÓN
# ================================================================

func _mostrar_selection() -> void:
	if not _enter_sleep_mode("sleep_selection"):
		return

	_selection = SCENE_SELECTION.instantiate()
	get_tree().root.add_child(_selection)

	var horas_max: float = _calcular_horas_maximas()
	var recuperacion: float = CONFIG.recuperacion_hostal_por_hora if _lugar == Lugar.HOSTAL else CONFIG.recuperacion_calle_por_hora

	_selection.call(
		"configurar",
		_lugar_a_string(_lugar),
		_hora_inicio,
		horas_max,
		PlayerStats.sueno,
		recuperacion
	)

	_selection.connect("confirmado", _on_selection_confirmado)
	_selection.connect("cancelado", _on_selection_cancelado)

func _mostrar_aviso_hostal_cerrado() -> void:
	if not _enter_sleep_mode("hostel_closed_notice"):
		return

	_selection = SCENE_SELECTION.instantiate()
	get_tree().root.add_child(_selection)
	_selection.call("mostrar_aviso_cerrado")
	_selection.connect("cancelado", _on_selection_cancelado)

func _mostrar_aviso_poco_tiempo() -> void:
	if not _enter_sleep_mode("hostel_not_enough_time_notice"):
		return

	_selection = SCENE_SELECTION.instantiate()
	get_tree().root.add_child(_selection)
	_selection.call("mostrar_aviso_poco_tiempo")
	_selection.connect("cancelado", _on_selection_cancelado)

func _on_selection_confirmado(horas: float) -> void:
	if _lugar == Lugar.HOSTAL and _hostel_payment_required:
		var ok: bool = PlayerStats.gastar_dinero(_pending_hostel_payment)
		if not ok:
			_limpiar_pago_hostal_pendiente()
			_on_selection_cancelado()
			return

		PlayerStats.apply_sleep_result({"dias_sin_pagar_hostal": 0})
		PlayerStats.sync_dialogic_variables_now()
		_limpiar_pago_hostal_pendiente()

	_horas_totales = horas
	_hora_fin = fmod(_hora_inicio + horas, 24.0)
	_horas_dormidas = 0.0
	_cancelado = false
	_durmiendo = true

	_cerrar_selection()
	_iniciar_sueno()

func _on_selection_cancelado() -> void:
	_limpiar_pago_hostal_pendiente()
	_exit_sleep_mode("cancel_sleep_selection")
	_cerrar_selection()

# ================================================================
# PANTALLA DE SUEÑO
# ================================================================

func _iniciar_sueno() -> void:
	DayNightManager.pausar()

	await SceneManager.fade_out(1.5, true, "sleep_fade_out")

	_screen = SCENE_SCREEN.instantiate()
	get_tree().root.add_child(_screen)
	_screen.connect("cancelado", _on_screen_cancelado)
	_screen.connect("seguir_durmiendo", _on_seguir_durmiendo)
	_screen.connect("salir_a_la_calle", _on_salir_a_la_calle)
	_screen.connect("tramo_visual_terminado", _on_tramo_visual_terminado)
	_screen.call("actualizar", DayNightManager.get_hour_float(), 0.0, true)

	if _forzado:
		_screen.call("set_forzado", true)
		if _screen.has_method("set_sleep_preview"):
			_screen.call("set_sleep_preview", PlayerStats.sueno)

	await SceneManager.fade_in(1.5, true, "sleep_fade_in")

	_arrancar_tramo_visual(_hora_inicio, _hora_fin, _horas_totales)

func _arrancar_tramo_visual(hora_inicio: float, hora_fin: float, horas_tramo: float) -> void:
	if _screen == null:
		return

	_segment_started_at_sec = Time.get_ticks_msec() / 1000.0
	_segment_hours_total = maxf(horas_tramo, 0.0)
	_segment_sleep_start = PlayerStats.sueno

	_screen.call("iniciar_tramo_visual", hora_inicio, hora_fin, 0.0, 1.0)

	if _screen.has_method("get_duracion_visual_actual"):
		_segment_visual_duration = float(_screen.call("get_duracion_visual_actual"))
	else:
		_segment_visual_duration = 20.0

func _on_tramo_visual_terminado() -> void:
	if _cancelado:
		return

	_aplicar_tramo_completo()

func _aplicar_tramo_completo() -> void:
	if _segment_hours_total <= 0.0:
		_al_terminar_tramo_real()
		return

	_horas_dormidas += _segment_hours_total
	DayNightManager.advance_hours(_segment_hours_total)
	_aplicar_recuperacion_por_horas(_segment_hours_total)

	_al_terminar_tramo_real()

func _aplicar_tramo_parcial() -> void:
	var t := _get_segment_progress_01()
	var horas_parciales := _segment_hours_total * t

	if horas_parciales <= 0.0:
		return

	_horas_dormidas += horas_parciales
	DayNightManager.advance_hours(horas_parciales)
	_aplicar_recuperacion_por_horas(horas_parciales)

func _al_terminar_tramo_real() -> void:
	_reset_segment_state()

	if _lugar == Lugar.HOSTAL and not _forzado:
		var hora_actual: float = DayNightManager.get_hour_float()
		if is_hostel_open(hora_actual) and _screen:
			_screen.call("mostrar_panel_post", hora_actual)
			return

	_finalizar_sueno()

func _on_screen_cancelado() -> void:
	_cancelado = true
	_aplicar_tramo_parcial()
	_finalizar_sueno()

func _on_seguir_durmiendo() -> void:
	var hora_actual: float = DayNightManager.get_hour_float()
	var horas_restantes: float = get_hostel_hours_until_close(hora_actual)

	if horas_restantes <= 0.0:
		_finalizar_sueno()
		return

	_hora_inicio = hora_actual
	_horas_totales = horas_restantes
	_hora_fin = fmod(_hora_inicio + _horas_totales, 24.0)

	if _screen:
		_screen.call("actualizar", hora_actual, 0.0, true)

	_arrancar_tramo_visual(_hora_inicio, _hora_fin, _horas_totales)

func _on_salir_a_la_calle() -> void:
	_finalizar_sueno()

func _get_segment_progress_01() -> float:
	if _segment_visual_duration <= 0.0:
		return 1.0

	var now_sec := Time.get_ticks_msec() / 1000.0
	var elapsed := maxf(0.0, now_sec - _segment_started_at_sec)
	return clampf(elapsed / _segment_visual_duration, 0.0, 1.0)

func _reset_segment_state() -> void:
	_segment_started_at_sec = 0.0
	_segment_visual_duration = 0.0
	_segment_hours_total = 0.0
	_segment_sleep_start = 0.0

# ================================================================
# RECUPERACIÓN PROGRESIVA
# ================================================================

func _aplicar_recuperacion_por_horas(horas: float) -> void:
	if horas <= 0.0:
		return

	var deltas: Dictionary = {}

	match _lugar:
		Lugar.HOSTAL:
			deltas = {
				"sueno": CONFIG.recuperacion_hostal_por_hora * horas,
				"salud": SALUD_HOSTAL_POR_HORA * horas,
				"estres": -ESTRES_HOSTAL_POR_HORA * horas,
			}
		_:
			var recuperacion: float = RECUPERACION_COLAPSO_POR_HORA if _forzado else CONFIG.recuperacion_calle_por_hora
			deltas = {
				"sueno": recuperacion * horas,
			}

	PlayerStats.apply_stat_deltas(deltas, "sleep_recovery")

# ================================================================
# FINALIZACIÓN
# ================================================================

func _finalizar_sueno() -> void:
	_durmiendo = false
	_forzado = false
	_reset_segment_state()
	_aplicar_efectos_al_despertar()

	await SceneManager.fade_out(1.5, true, "sleep_fade_out")

	if _screen:
		_screen.queue_free()
		_screen = null

	DayNightManager.reanudar()

	var player := PlayerManager.get_player()
	if player:
		await SceneManager.fade_in(1.5, true, "sleep_wake_fade_in")
		await _play_player_rise_animation(player)
		_exit_sleep_mode("end_sleep")
	else:
		await SceneManager.fade_in(1.5, true, "sleep_wake_fade_in")
		_exit_sleep_mode("end_sleep_no_player")

	sleep_ended.emit(_horas_dormidas, not _cancelado)

func _aplicar_efectos_al_despertar() -> void:
	match _lugar:
		Lugar.HOSTAL:
			return
		Lugar.CALLE, Lugar.CALLEJON:
			var deltas: Dictionary = {
				"alcohol": -ALCOHOL_PERDIDO_CALLE,
				"laudano": -LAUDANO_PERDIDO_CALLE,
			}

			var roll: float = randf()
			if roll < PROB_CURAR_CALLE:
				deltas["enfermedad"] = -20.0
			elif roll < PROB_CURAR_CALLE + PROB_EMPEORAR_CALLE:
				deltas["enfermedad"] = EMPEORAMIENTO_CALLE

			PlayerStats.apply_stat_deltas(deltas, "wake_up_street")

# ================================================================
# CÁLCULOS
# ================================================================

func _calcular_horas_para_recuperar() -> float:
	var sueno_faltante: float = 100.0 - PlayerStats.sueno
	if sueno_faltante <= 0.0:
		return 1.0

	var recuperacion: float = CONFIG.recuperacion_hostal_por_hora if _lugar == Lugar.HOSTAL else CONFIG.recuperacion_calle_por_hora
	return ceilf(sueno_faltante / recuperacion)

func _calcular_horas_para_recuperar_forzado() -> float:
	var sueno_faltante: float = 100.0 - PlayerStats.sueno
	if sueno_faltante <= 0.0:
		return 1.0

	return ceilf(sueno_faltante / RECUPERACION_COLAPSO_POR_HORA)

func _calcular_horas_maximas() -> float:
	var horas_para_recuperar: float = _calcular_horas_para_recuperar()

	match _lugar:
		Lugar.HOSTAL:
			var horas_hasta_cierre: float = get_hostel_hours_until_close(_hora_inicio)
			return minf(horas_para_recuperar, horas_hasta_cierre)
		_:
			return minf(horas_para_recuperar, CONFIG.horas_max_calle)

func _horas_entre(desde: float, hasta: float) -> float:
	if hasta > desde:
		return hasta - desde
	else:
		return (24.0 - desde) + hasta

# ================================================================
# LIMPIEZA
# ================================================================

func _limpiar_pago_hostal_pendiente() -> void:
	_hostel_payment_required = false
	_pending_hostel_payment = 0.0

func _cerrar_selection() -> void:
	if _selection != null and is_instance_valid(_selection):
		_selection.queue_free()
	_selection = null

# ================================================================
# HELPERS
# ================================================================

func _parsear_lugar(lugar_str: String) -> Lugar:
	match lugar_str.to_lower():
		"hostal":
			return Lugar.HOSTAL
		"callejon":
			return Lugar.CALLEJON
		_:
			return Lugar.CALLE

func _lugar_a_string(lugar: Lugar) -> String:
	match lugar:
		Lugar.HOSTAL:
			return "hostal"
		Lugar.CALLEJON:
			return "callejon"
		_:
			return "calle"

func is_sleeping_flow_active() -> bool:
	return _durmiendo or _selection != null or _screen != null


func get_save_data() -> Dictionary:
	# De momento no guardamos partida a mitad de sueño.
	# Este bloque deja preparada la API para SaveManager.
	return {
		"is_sleeping": is_sleeping_flow_active(),
		"lugar": _lugar_a_string(_lugar),
		"horas_dormidas": _horas_dormidas,
	}


func apply_save_data(_data: Dictionary) -> void:
	# Si una partida se carga mientras había sueño activo, restauramos a limpio.
	# Más adelante se puede implementar guardado real mid-sleep.
	reset()

func reset() -> void:
	# Limpia todo el estado de sueño para una nueva partida.
	_durmiendo = false
	_forzado = false
	_cancelado = false
	_hostel_payment_required = false
	_pending_hostel_payment = 0.0
	_horas_totales = 0.0
	_horas_dormidas = 0.0
	_reset_segment_state()
	if _selection != null and is_instance_valid(_selection):
		_selection.queue_free()
	_selection = null
	if _screen != null and is_instance_valid(_screen):
		_screen.queue_free()
	_screen = null
	_limpiar_mensaje_colapso()
	_limpiar_pago_hostal_pendiente()
