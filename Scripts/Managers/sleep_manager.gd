extends Node

# ================================================================
# SLEEP MANAGER — sleep_manager.gd
# Autoload: SleepManager
# ================================================================
# FLUJO COMPLETO:
# 1. start_sleep(lugar) → bloquea movimiento
# 2. Muestra Sleep_Selection → jugador elige horas
# 3. Confirma → fade negro → Sleep_Screen aparece → fade entra
# 4. Timer avanza horas → recuperación progresiva de stats
# 5. Al terminar → fade negro → Sleep_Screen desaparece → fade sale
# 6. Si hostal antes 10:00 → panel post-sueño (seguir/salir)
# ================================================================
# HOOKS PARA EL FUTURO:
# - interrupt_sleep("policia") → policía despierta al jugador
# - interrupt_sleep("jack") → Jack the Ripper ataca
# ================================================================

const CONFIG = preload("res://Data/Game/game_config.tres")

# ================================================================
# CONSTANTES
# ================================================================

const HORA_APERTURA_HOSTAL: float = 22.0
const HORA_CIERRE_HOSTAL: float = 10.0

# Recuperación extra por hora en hostal
const SALUD_HOSTAL_POR_HORA: float = 0.5
const ESTRES_HOSTAL_POR_HORA: float = 1.0

# Penalizaciones al despertar en la calle
const ALCOHOL_PERDIDO_CALLE: float = 10.0
const LAUDANO_PERDIDO_CALLE: float = 5.0

# Probabilidades de enfermedad al dormir en la calle
const PROB_CURAR_CALLE: float = 0.15
const PROB_EMPEORAR_CALLE: float = 0.15
const EMPEORAMIENTO_CALLE: float = 10.0

# Segundos reales por hora de juego durante la animación de sueño
const SEGUNDOS_POR_HORA: float = 0.4

# Paths de las escenas UI
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

# Instancias de UI activas — Node para evitar problemas de cast con CanvasLayer
var _selection: Node = null
var _screen: Node = null
var _tick_timer: Timer = null


# ================================================================
# SEÑALES
# ================================================================

# Emitida si el sueño es interrumpido (policía, Jack, ruido)
# Conectar desde los sistemas correspondientes cuando existan
signal sleep_interrupted(motivo: String)

# Emitida al terminar el sueño (cancelado o completado)
signal sleep_ended(horas_dormidas: float, completado: bool)


# ================================================================
# API PÚBLICA
# ================================================================

# Punto de entrada único desde diálogos, pickups o triggers
# lugar_str: "hostal" | "calle" | "callejon"
func start_sleep(lugar_str: String) -> void:
	# Bloquea apertura múltiple
	if _durmiendo or _selection != null or _screen != null:
		return

	_lugar = _parsear_lugar(lugar_str)
	_hora_inicio = DayNightManager.hora_actual

	# Hostal: comprobar si está abierto (22:00 → 10:00)
	if _lugar == Lugar.HOSTAL and not _hostal_abierto(_hora_inicio):
		_mostrar_aviso_hostal_cerrado()
		return

	if _lugar == Lugar.HOSTAL:
		var horas_restantes = _horas_entre(_hora_inicio, HORA_CIERRE_HOSTAL)
		if horas_restantes < 1.0:
			_mostrar_aviso_poco_tiempo()
			return

	_mostrar_selection()


# Igual que start_sleep pero forzado (sueno=0, sin Selection panel)
# Muestra un mensaje de colapso antes del fade
func start_sleep_forced(lugar_str: String, mensaje: String = "") -> void:
	if _durmiendo or _screen != null:
		return

	_lugar = _parsear_lugar(lugar_str)
	_hora_inicio = DayNightManager.hora_actual
	_horas_totales = _calcular_horas_para_recuperar()
	_hora_fin = fmod(_hora_inicio + _horas_totales, 24.0)
	_horas_dormidas = 0.0
	_cancelado = false
	_durmiendo = true

	# Mostramos el mensaje de colapso durante el fade
	_mostrar_mensaje_colapso(mensaje)
	await SceneManager._fade_out(2.0)
	_limpiar_mensaje_colapso()
	await _iniciar_sueno_directo()


# ── Mensaje flotante de colapso ──────────────────────────────────
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

# Versión de _iniciar_sueno sin el fade_out inicial (ya se hizo)
func _iniciar_sueno_directo() -> void:
	DayNightManager.pausar()
	_screen = SCENE_SCREEN.instantiate()
	get_tree().root.add_child(_screen)
	_screen.connect("cancelado", _on_screen_cancelado)
	_screen.connect("seguir_durmiendo", _on_seguir_durmiendo)
	_screen.connect("salir_a_la_calle", _on_salir_a_la_calle)
	_screen.call("actualizar", DayNightManager.hora_actual, 0.0)
	await SceneManager._fade_in(1.5)
	_tick_timer = Timer.new()
	_tick_timer.wait_time = SEGUNDOS_POR_HORA
	_tick_timer.one_shot = false
	_tick_timer.timeout.connect(_tick_hora)
	add_child(_tick_timer)
	_tick_timer.start()
# Llamar cuando esos sistemas estén implementados
func interrupt_sleep(motivo: String) -> void:
	if not _durmiendo:
		return
	_cancelado = true
	sleep_interrupted.emit(motivo)
	_finalizar_sueno()


# Hostal abierto entre 22:00 y 10:00 (cruza medianoche)
func _hostal_abierto(hora: float) -> bool:
	return hora >= HORA_APERTURA_HOSTAL or hora < HORA_CIERRE_HOSTAL


# ================================================================
# PANEL DE SELECCIÓN
# ================================================================

func _mostrar_selection() -> void:
	# Bloqueamos movimiento al abrir el panel
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
	# Reutilizamos Sleep_Selection solo con el aviso de cerrado
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
	# No desbloqueamos — el sueño continúa con movimiento bloqueado
	_horas_totales = horas
	_hora_fin = fmod(_hora_inicio + horas, 24.0)
	_horas_dormidas = 0.0
	_cancelado = false
	_durmiendo = true
	_selection = null  # Ya hizo queue_free() solo en sleep_selection.gd
	_iniciar_sueno()


func _on_selection_cancelado() -> void:
	# Canceló — devolvemos el control al jugador
	var player = PlayerManager.player_instance
	if player:
		player.enable_movement()
	_selection = null


# ================================================================
# PANTALLA DE SUEÑO
# ================================================================

func _iniciar_sueno() -> void:
	# Pausamos el ciclo natural del tiempo
	DayNightManager.pausar()

	# Fade a negro antes de mostrar Sleep_Screen
	await SceneManager._fade_out(1.5)

	# Instanciamos mientras todo está negro
	_screen = SCENE_SCREEN.instantiate()
	get_tree().root.add_child(_screen)

	_screen.connect("cancelado", _on_screen_cancelado)
	_screen.connect("seguir_durmiendo", _on_seguir_durmiendo)
	_screen.connect("salir_a_la_calle", _on_salir_a_la_calle)

	# Actualizamos con la hora inicial antes del fade in
	_screen.call("actualizar", DayNightManager.hora_actual, 0.0)

	# Fade de negro a Sleep_Screen
	await SceneManager._fade_in(1.5)

	# El timer empieza SOLO después del fade — no antes
	_tick_timer = Timer.new()
	_tick_timer.wait_time = SEGUNDOS_POR_HORA
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

	# Avanzamos el tiempo en DayNightManager
	DayNightManager.set_hora(nueva_hora)

	# Recuperación progresiva — un poco por cada hora
	_aplicar_recuperacion_parcial()

	var progreso = _horas_dormidas / _horas_totales if _horas_totales > 0 else 0.0
	if _screen:
		_screen.call("actualizar", nueva_hora, progreso)

	# Comprobamos si hemos llegado a la hora de fin
	if _horas_dormidas >= _horas_totales:
		_limpiar_timer()
		_al_terminar_sueno()


func _al_terminar_sueno() -> void:
	# Hostal: si terminó antes de las 10:00 → mostrar opciones
	if _lugar == Lugar.HOSTAL:
		var hora_actual = DayNightManager.hora_actual
		var antes_cierre = hora_actual < HORA_CIERRE_HOSTAL or hora_actual >= HORA_APERTURA_HOSTAL
		if antes_cierre and _screen:
			_screen.call("mostrar_panel_post", hora_actual)
			return

	# Calle o hostal que llegó exactamente a las 10:00 → finalizar
	_finalizar_sueno()


func _on_screen_cancelado() -> void:
	_cancelado = true
	_limpiar_timer()
	_finalizar_sueno()


func _on_seguir_durmiendo() -> void:
	# Calcula horas restantes hasta las 10:00 y reinicia el timer
	var hora_actual = DayNightManager.hora_actual
	var horas_restantes = _horas_entre(hora_actual, HORA_CIERRE_HOSTAL)

	if horas_restantes <= 0.0:
		_finalizar_sueno()
		return

	_hora_inicio = hora_actual
	_horas_totales = horas_restantes
	_horas_dormidas = 0.0

	_tick_timer = Timer.new()
	_tick_timer.wait_time = SEGUNDOS_POR_HORA
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
	# Se aplica una fracción por cada hora
	# Si cancelas a mitad has recuperado la mitad
	match _lugar:
		Lugar.HOSTAL:
			PlayerStats.sueno = minf(PlayerStats.sueno + CONFIG.recuperacion_hostal_por_hora, 100.0)
			PlayerStats.salud = minf(PlayerStats.salud + SALUD_HOSTAL_POR_HORA, 100.0)
			PlayerStats.estres = maxf(PlayerStats.estres - ESTRES_HOSTAL_POR_HORA, 0.0)
		_:
			PlayerStats.sueno = minf(PlayerStats.sueno + CONFIG.recuperacion_calle_por_hora, 100.0)

	PlayerStats.stats_updated.emit()


# ================================================================
# FINALIZACIÓN
# ================================================================

func _finalizar_sueno() -> void:
	_durmiendo = false
	_limpiar_timer()

	# Aplicamos efectos de despertar según el lugar
	_aplicar_efectos_al_despertar()

	# Fade a negro antes de ocultar Sleep_Screen
	await SceneManager._fade_out(1.5)

	# Limpiamos la pantalla mientras todo está negro
	if _screen:
		_screen.queue_free()
		_screen = null

	# Reanudamos el tiempo real
	DayNightManager.reanudar()

	# Devolvemos el control al jugador — primero animación de levantarse
	var player = PlayerManager.player_instance
	if player:
		# Fade de negro a juego
		await SceneManager._fade_in(1.5)
		player.animation.play_rise()
		await player.animation.anim_tree.animation_finished
		player.enable_movement()
	else:
		# Fade de negro a juego
		await SceneManager._fade_in(1.5)

	sleep_ended.emit(_horas_dormidas, not _cancelado)


func _aplicar_efectos_al_despertar() -> void:
	match _lugar:
		Lugar.HOSTAL:
			pass  # Todo se aplica progresivamente — nada extra al despertar

		Lugar.CALLE, Lugar.CALLEJON:
			# Penalizaciones de sustancias al despertar en la calle
			PlayerStats.alcohol = maxf(PlayerStats.alcohol - ALCOHOL_PERDIDO_CALLE, 0.0)
			PlayerStats.laudano = maxf(PlayerStats.laudano - LAUDANO_PERDIDO_CALLE, 0.0)

			# Enfermedad: 15% curar, 15% empeorar, 70% sin cambio
			var roll = randf()
			if roll < PROB_CURAR_CALLE:
				PlayerStats.enfermedad = maxf(PlayerStats.enfermedad - 20.0, 0.0)
			elif roll < PROB_CURAR_CALLE + PROB_EMPEORAR_CALLE:
				PlayerStats.enfermedad = minf(
					PlayerStats.enfermedad + EMPEORAMIENTO_CALLE, 100.0
				)

	PlayerStats.stats_updated.emit()


# ================================================================
# CÁLCULOS
# ================================================================

# Horas necesarias para llevar sueno a 100 según el lugar
func _calcular_horas_para_recuperar() -> float:
	var sueno_faltante = 100.0 - PlayerStats.sueno
	if sueno_faltante <= 0.0:
		return 1.0  # Mínimo 1 hora aunque esté al 100%

	var recuperacion = CONFIG.recuperacion_hostal_por_hora \
		if _lugar == Lugar.HOSTAL \
		else CONFIG.recuperacion_calle_por_hora

	return ceilf(sueno_faltante / recuperacion)


# Horas máximas disponibles según lugar y hora actual
func _calcular_horas_maximas() -> float:
	var horas_para_recuperar = _calcular_horas_para_recuperar()

	match _lugar:
		Lugar.HOSTAL:
			# Máximo: horas hasta las 10:00 desde la hora actual
			var horas_hasta_cierre = _horas_entre(_hora_inicio, HORA_CIERRE_HOSTAL)
			return minf(horas_para_recuperar, horas_hasta_cierre)
		_:
			return minf(horas_para_recuperar, CONFIG.horas_max_calle)


# Calcula horas entre dos horas del día (maneja medianoche)
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
