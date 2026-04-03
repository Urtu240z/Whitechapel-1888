extends Node

# ================================================================
# SLEEP MANAGER — sleep_manager.gd
# Autoload: SleepManager
# ================================================================

const CONFIG = preload("res://Data/Game/game_config.tres")

# ================================================================
# CONSTANTES
# ================================================================

const HORA_APERTURA_HOSTAL: float = 22.0
const HORA_CIERRE_HOSTAL: float = 10.0

const SALUD_HOSTAL_POR_HORA: float = 0.5
const ESTRES_HOSTAL_POR_HORA: float = 1.0

const ALCOHOL_PERDIDO_CALLE: float = 10.0
const LAUDANO_PERDIDO_CALLE: float = 5.0

const PROB_CURAR_CALLE: float = 0.15
const PROB_EMPEORAR_CALLE: float = 0.15
const EMPEORAMIENTO_CALLE: float = 10.0


# ── COLAPSO ──────────────────────────────────────────────────────
const RECUPERACION_COLAPSO_POR_HORA: float = 10.0  # más rápido al caer desvanecida
const SUENO_MINIMO_DESPERTAR: float = 40.0          # mínimo para poder despertar

const SCENE_SELECTION = preload("res://Scenes/Core/Sleep_Selection.tscn")
const SCENE_SCREEN = preload("res://Scenes/Core/Sleep_Screen.tscn")

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
var _forzado: bool = false  # true cuando el sueño fue forzado por colapso

var _selection: Node = null
var _screen: Node = null
var _tick_timer: Timer = null

# ================================================================
# SEÑALES
# ================================================================

signal sleep_interrupted(motivo: String)
signal sleep_ended(horas_dormidas: float, completado: bool)

# ================================================================
# API PÚBLICA
# ================================================================

func start_sleep(lugar_str: String) -> void:
	if _durmiendo or _selection != null or _screen != null:
		return

	_lugar = _parsear_lugar(lugar_str)
	_hora_inicio = DayNightManager.hora_actual

	if _lugar == Lugar.HOSTAL and not _hostal_abierto(_hora_inicio):
		_mostrar_aviso_hostal_cerrado()
		return

	if _lugar == Lugar.HOSTAL:
		var horas_restantes = _horas_entre(_hora_inicio, HORA_CIERRE_HOSTAL)
		if horas_restantes < 1.0:
			_mostrar_aviso_poco_tiempo()
			return

	_mostrar_selection()


func start_sleep_forced(lugar_str: String, mensaje: String = "") -> void:
	if _durmiendo or _screen != null:
		return

	_lugar = _parsear_lugar(lugar_str)
	_hora_inicio = DayNightManager.hora_actual
	_horas_totales = _calcular_horas_para_recuperar_forzado()
	_hora_fin = fmod(_hora_inicio + _horas_totales, 24.0)
	_horas_dormidas = 0.0
	_cancelado = false
	_durmiendo = true
	_forzado = true

	_mostrar_mensaje_colapso(mensaje)
	await SceneManager.fade_out(2.0)
	_limpiar_mensaje_colapso()
	await _iniciar_sueno_directo()


func interrupt_sleep(motivo: String) -> void:
	if not _durmiendo:
		return
	_cancelado = true
	sleep_interrupted.emit(motivo)
	_finalizar_sueno()


# ================================================================
# MENSAJE DE COLAPSO
# ================================================================

var _collapse_label: CanvasLayer = null

func _mostrar_mensaje_colapso(mensaje: String) -> void:
	if mensaje.is_empty():
		return
	_collapse_label = CanvasLayer.new()
	_collapse_label.layer = 20
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
	if _collapse_label:
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
	_screen.call("actualizar", DayNightManager.hora_actual, 0.0)
	if _forzado:
		_screen.call("set_forzado", true)
	await SceneManager.fade_in(1.5)
	_tick_timer = Timer.new()
	_tick_timer.wait_time = CONFIG.duracion_hora_segundos
	_tick_timer.one_shot = false
	_tick_timer.timeout.connect(_tick_hora)
	add_child(_tick_timer)
	_tick_timer.start()

# ================================================================
# HOSTAL ABIERTO
# ================================================================

func _hostal_abierto(hora: float) -> bool:
	return hora >= HORA_APERTURA_HOSTAL or hora < HORA_CIERRE_HOSTAL

# ================================================================
# PANEL DE SELECCIÓN
# ================================================================

func _mostrar_selection() -> void:
	var player = PlayerManager.player_instance
	if player:
		player.disable_movement()

	_selection = SCENE_SELECTION.instantiate()
	get_tree().root.add_child(_selection)

	var horas_max = _calcular_horas_maximas()
	var recuperacion = CONFIG.recuperacion_hostal_por_hora \
		if _lugar == Lugar.HOSTAL \
		else CONFIG.recuperacion_calle_por_hora

	_selection.call("configurar",
		_lugar_a_string(_lugar),
		_hora_inicio,
		horas_max,
		PlayerStats.sueno,
		recuperacion
	)

	_selection.connect("confirmado", _on_selection_confirmado)
	_selection.connect("cancelado", _on_selection_cancelado)


func _mostrar_aviso_hostal_cerrado() -> void:
	var player = PlayerManager.player_instance
	if player:
		player.disable_movement()
	_selection = SCENE_SELECTION.instantiate()
	get_tree().root.add_child(_selection)
	_selection.call("mostrar_aviso_cerrado")
	_selection.connect("cancelado", _on_selection_cancelado)

func _mostrar_aviso_poco_tiempo() -> void:
	var player = PlayerManager.player_instance
	if player:
		player.disable_movement()
	_selection = SCENE_SELECTION.instantiate()
	get_tree().root.add_child(_selection)
	_selection.call("mostrar_aviso_poco_tiempo")
	_selection.connect("cancelado", _on_selection_cancelado)

func _on_selection_confirmado(horas: float) -> void:
	_horas_totales = horas
	_hora_fin = fmod(_hora_inicio + horas, 24.0)
	_horas_dormidas = 0.0
	_cancelado = false
	_durmiendo = true
	_selection = null
	_iniciar_sueno()

func _on_selection_cancelado() -> void:
	var player = PlayerManager.player_instance
	if player:
		player.enable_movement()
	_selection = null

# ================================================================
# PANTALLA DE SUEÑO
# ================================================================

func _iniciar_sueno() -> void:
	DayNightManager.pausar()
	await SceneManager.fade_out(1.5)
	_screen = SCENE_SCREEN.instantiate()
	get_tree().root.add_child(_screen)
	_screen.connect("cancelado", _on_screen_cancelado)
	_screen.connect("seguir_durmiendo", _on_seguir_durmiendo)
	_screen.connect("salir_a_la_calle", _on_salir_a_la_calle)
	_screen.call("actualizar", DayNightManager.hora_actual, 0.0)
	await SceneManager.fade_in(1.5)
	_tick_timer = Timer.new()
	_tick_timer.wait_time = CONFIG.duracion_hora_segundos
	_tick_timer.one_shot = false
	_tick_timer.timeout.connect(_tick_hora)
	add_child(_tick_timer)
	_tick_timer.start()


func _tick_hora() -> void:
	if _cancelado:
		_limpiar_timer()
		return

	_horas_dormidas += 1.0
	var nueva_hora = fmod(_hora_inicio + _horas_dormidas, 24.0)
	DayNightManager.set_hora(nueva_hora)
	_aplicar_recuperacion_parcial()

	var progreso = _horas_dormidas / _horas_totales if _horas_totales > 0 else 0.0
	if _screen:
		_screen.call("actualizar", nueva_hora, progreso)

	if _horas_dormidas >= _horas_totales:
		_limpiar_timer()
		_al_terminar_sueno()


func _al_terminar_sueno() -> void:
	if _lugar == Lugar.HOSTAL:
		var hora_actual = DayNightManager.hora_actual
		var antes_cierre = hora_actual < HORA_CIERRE_HOSTAL or hora_actual >= HORA_APERTURA_HOSTAL
		if antes_cierre and _screen:
			_screen.call("mostrar_panel_post", hora_actual)
			return
	_finalizar_sueno()


func _on_screen_cancelado() -> void:
	_cancelado = true
	_limpiar_timer()
	_finalizar_sueno()

func _on_seguir_durmiendo() -> void:
	var hora_actual = DayNightManager.hora_actual
	var horas_restantes = _horas_entre(hora_actual, HORA_CIERRE_HOSTAL)
	if horas_restantes <= 0.0:
		_finalizar_sueno()
		return
	_hora_inicio = hora_actual
	_horas_totales = horas_restantes
	_horas_dormidas = 0.0
	_tick_timer = Timer.new()
	_tick_timer.wait_time = CONFIG.duracion_hora_segundos
	_tick_timer.one_shot = false
	_tick_timer.timeout.connect(_tick_hora)
	add_child(_tick_timer)
	_tick_timer.start()

func _on_salir_a_la_calle() -> void:
	_finalizar_sueno()

# ================================================================
# RECUPERACIÓN PROGRESIVA
# ================================================================

func _aplicar_recuperacion_parcial() -> void:
	match _lugar:
		Lugar.HOSTAL:
			PlayerStats.sueno = minf(PlayerStats.sueno + CONFIG.recuperacion_hostal_por_hora, 100.0)
			PlayerStats.salud = minf(PlayerStats.salud + SALUD_HOSTAL_POR_HORA, 100.0)
			PlayerStats.estres = maxf(PlayerStats.estres - ESTRES_HOSTAL_POR_HORA, 0.0)
		_:
			var recuperacion = RECUPERACION_COLAPSO_POR_HORA if _forzado \
				else CONFIG.recuperacion_calle_por_hora
			PlayerStats.sueno = minf(PlayerStats.sueno + recuperacion, 100.0)

	PlayerStats.actualizar_stats()

# ================================================================
# FINALIZACIÓN
# ================================================================

func _finalizar_sueno() -> void:
	_durmiendo = false
	_forzado = false
	_limpiar_timer()
	_aplicar_efectos_al_despertar()
	await SceneManager.fade_out(1.5)
	if _screen:
		_screen.queue_free()
		_screen = null
	DayNightManager.reanudar()
	var player = PlayerManager.player_instance
	if player:
		await SceneManager.fade_in(1.5)
		player.animation.play_rise()
		await player.animation.anim_tree.animation_finished
		player.enable_movement()
	else:
		await SceneManager.fade_in(1.5)
	sleep_ended.emit(_horas_dormidas, not _cancelado)


func _aplicar_efectos_al_despertar() -> void:
	match _lugar:
		Lugar.HOSTAL:
			pass
		Lugar.CALLE, Lugar.CALLEJON:
			PlayerStats.alcohol = maxf(PlayerStats.alcohol - ALCOHOL_PERDIDO_CALLE, 0.0)
			PlayerStats.laudano = maxf(PlayerStats.laudano - LAUDANO_PERDIDO_CALLE, 0.0)
			var roll = randf()
			if roll < PROB_CURAR_CALLE:
				PlayerStats.enfermedad = maxf(PlayerStats.enfermedad - 20.0, 0.0)
			elif roll < PROB_CURAR_CALLE + PROB_EMPEORAR_CALLE:
				PlayerStats.enfermedad = minf(PlayerStats.enfermedad + EMPEORAMIENTO_CALLE, 100.0)
	PlayerStats.actualizar_stats()

# ================================================================
# CÁLCULOS
# ================================================================

func _calcular_horas_para_recuperar() -> float:
	var sueno_faltante = 100.0 - PlayerStats.sueno
	if sueno_faltante <= 0.0:
		return 1.0
	var recuperacion = CONFIG.recuperacion_hostal_por_hora \
		if _lugar == Lugar.HOSTAL \
		else CONFIG.recuperacion_calle_por_hora
	return ceilf(sueno_faltante / recuperacion)

func _calcular_horas_para_recuperar_forzado() -> float:
	# Usa la tasa de recuperación del colapso (10/hora)
	var sueno_faltante = 100.0 - PlayerStats.sueno
	if sueno_faltante <= 0.0:
		return 1.0
	return ceilf(sueno_faltante / RECUPERACION_COLAPSO_POR_HORA)

func _calcular_horas_maximas() -> float:
	var horas_para_recuperar = _calcular_horas_para_recuperar()
	match _lugar:
		Lugar.HOSTAL:
			var horas_hasta_cierre = _horas_entre(_hora_inicio, HORA_CIERRE_HOSTAL)
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

func _limpiar_timer() -> void:
	if _tick_timer:
		_tick_timer.queue_free()
		_tick_timer = null

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
