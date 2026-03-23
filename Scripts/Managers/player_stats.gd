extends Node

# ============================================================
# 🔧 SETTINGS
# ============================================================
@export var debug_mode: bool = false

# ============================================================
# 🧍 BASIC ATTRIBUTES (0–100)
# ============================================================
@export var miedo: float = 10.0
@export var estres: float = 30.0
@export var felicidad: float = 50.0
@export var nervios: float = 20.0
@export var hambre: float = 50.0
@export var higiene: float = 70.0
@export var sueno: float = 80.0
@export var alcohol: float = 0.0
@export var laudano: float = 0.0
@export var salud: float = 100.0
@export var stamina: float = 100.0

# ============================================================
# 🦠 ENFERMEDAD (0–100)
# 0 = sana, 100 = muerte inminente
# Solo sube con clientes o con el tiempo si ya está infectada
# Solo baja con tratamiento
# ============================================================
@export var enfermedad: float = 0.0

# Estado de enfermedad activa
var enferma: bool = false

# ⏱️ Medicina activa — impide que suba durante 2 días de juego
var medicina_activa: bool = false
var medicina_timer: float = 0.0
const MEDICINA_DURACION_DIAS: float = 2.0

# ============================================================
# 💰 ECONOMY
# ============================================================
@export var dinero: float = 5.0
@export var dias_sin_pagar_hostal: int = 0

# ============================================================
# 💋 DERIVED ATTRIBUTES
# ============================================================
var sex_appeal: float = 50.0

# ============================================================
# 💸 COST CONSTANTS
# ============================================================
const COSTE_HOSTAL_DIA: float = 2.0
const COSTE_COMIDA: float = 0.5
const COSTE_BANO: float = 0.3
const COSTE_ALCOHOL: float = 0.2
const COSTE_LAUDANO: float = 1.0
const COSTE_MEDICINA: float = 3.0
const COSTE_MEDICO: float = 15.0

# ============================================================
# 🦠 PROBABILIDADES DE INFECCIÓN POR TIPO DE CLIENTE
# ============================================================
const PROB_INFECCION_POOR: float = 0.15    # 15%
const PROB_INFECCION_MEDIUM: float = 0.05  # 5%
const PROB_INFECCION_RICH: float = 0.01    # 1%

# ============================================================
# ⏱️ DEGRADACIÓN CON EL TIEMPO
# Valores por minuto de juego real
# ============================================================
const HAMBRE_POR_MINUTO: float = 0.5
const HIGIENE_POR_MINUTO: float = -0.3
const SUENO_POR_MINUTO: float = -0.2
const ALCOHOL_POR_MINUTO: float = -1.0
const LAUDANO_POR_MINUTO: float = -0.5
const ENFERMEDAD_POR_MINUTO: float = 0.3  # sube lentamente si está infectada

var _degradacion_timer: float = 0.0
const DEGRADACION_INTERVALO: float = 60.0
var _sueno_anterior: float = 80.0  # Rastrea el sueno del frame anterior para detectar llegada a 0
var _colapso_activo: bool = false  # Evita disparar sueno_agotado múltiples veces

# ============================================================
# 🎯 GOAL
# ============================================================
const DINERO_PARA_ESCAPAR: float = 200.0

# ============================================================
# 📢 SIGNALS
# ============================================================
signal sex_appeal_changed(new_value)
signal dinero_changed(new_value)
signal stamina_changed(new_value)
signal atributo_critico(cual)
signal durmiendo_en_calle()
signal objetivo_completado()
signal stats_updated
signal enfermedad_cambiada(estado: bool)
signal jugador_muerto()
signal sueno_agotado()  # Emitida cuando sueno llega a 0 — colapso involuntario

# ============================================================
# ⚙️ READY
# ============================================================
func _ready() -> void:
	calcular_sex_appeal()
	stats_updated.connect(_sync_dialogic_variables)

# ============================================================
# ⏱️ PROCESS — degradación con el tiempo
# ============================================================
func _process(delta: float) -> void:
	_degradacion_timer += delta
	if _degradacion_timer >= DEGRADACION_INTERVALO:
		_degradacion_timer = 0.0
		await _aplicar_degradacion()

	# Medicina activa — cuenta el tiempo
	if medicina_activa:
		medicina_timer += delta
		var dias_jugados = medicina_timer / DEGRADACION_INTERVALO
		if dias_jugados >= MEDICINA_DURACION_DIAS:
			medicina_activa = false
			medicina_timer = 0.0

func _aplicar_degradacion() -> void:
	hambre  = clamp(hambre  + HAMBRE_POR_MINUTO,  0, 100)
	higiene = clamp(higiene + HIGIENE_POR_MINUTO, 0, 100)
	sueno   = clamp(sueno   + SUENO_POR_MINUTO,   0, 100)
	alcohol = clamp(alcohol + ALCOHOL_POR_MINUTO, 0, 100)
	laudano = clamp(laudano + LAUDANO_POR_MINUTO, 0, 100)

	# Enfermedad sube sola solo si está infectada y sin medicina
	if enferma and not medicina_activa:
		enfermedad = clamp(enfermedad + ENFERMEDAD_POR_MINUTO, 0, 100)
		_check_enfermedad_efectos()

	await actualizar_stats(1.0)

# ============================================================
# 🦠 ENFERMEDAD — efectos progresivos
# ============================================================
func _check_enfermedad_efectos() -> void:
	# Enfermedad grave (>70%) → salud cae lentamente
	if enfermedad >= 70 and not enferma:
		enferma = true
		enfermedad_cambiada.emit(true)

	# Enfermedad crítica (100%) → salud cae rápido
	if enfermedad >= 100:
		salud = max(0, salud - 5.0)  # -5 salud por minuto
		if salud <= 0:
			morir()
	elif enfermedad >= 70:
		salud = max(0, salud - 1.0)  # -1 salud por minuto

func infectar(probabilidad: float) -> bool:
	"""Intenta infectar al jugador con la probabilidad dada. Devuelve true si se infecta."""
	if randf() < probabilidad:
		if enfermedad == 0:
			enfermedad = 20.0  # empieza en 20
		enferma = true
		enfermedad_cambiada.emit(true)
		await actualizar_stats()
		return true
	return false

# ============================================================
# ❤️ SEX APPEAL
# ============================================================
func calcular_sex_appeal() -> float:
	var appeal: float = 50.0

	appeal += (higiene - 50) * 0.5
	appeal += (felicidad - 50) * 0.3
	appeal += (100 - hambre) * 0.2
	appeal += (sueno - 50) * 0.2
	appeal += alcohol * 0.15

	appeal -= miedo * 0.25
	appeal -= estres * 0.4
	appeal -= nervios * 0.3
	appeal -= (hambre - 50) * 0.3
	appeal -= max(0, alcohol - 50) * 0.5
	appeal -= laudano * 0.6

	# Enfermedad penaliza fuertemente el sex appeal
	appeal -= enfermedad * 0.5

	sex_appeal = clamp(appeal, 0.0, 100.0)
	sex_appeal_changed.emit(sex_appeal)

	if higiene < 20:
		atributo_critico.emit("higiene")
	if hambre > 80:
		atributo_critico.emit("hambre")
	if sueno < 20:
		atributo_critico.emit("sueno")
	if enfermedad >= 70:
		atributo_critico.emit("enfermedad")

	return sex_appeal

# ============================================================
# 🩺 SALUD
# ============================================================
func actualizar_salud(delta: float = 1.0) -> void:
	var daño := 0.0
	var curacion := 0.0

	daño += hambre * 0.02 * delta
	daño += estres * 0.015 * delta
	daño += miedo * 0.01 * delta
	daño += nervios * 0.015 * delta
	daño += max(0, alcohol - 50) * 0.04 * delta
	daño += laudano * 0.06 * delta
	daño += max(0, 30 - higiene) * 0.05 * delta

	curacion += max(0, felicidad - 50) * 0.02 * delta
	curacion += max(0, sueno - 60) * 0.03 * delta

	salud = clamp(salud - daño + curacion, 0, 100)

	if salud <= 0:
		morir()

# ============================================================
# 🍞 BASIC ACTIONS
# ============================================================
func comer() -> bool:
	if dinero >= COSTE_COMIDA:
		await gastar_dinero(COSTE_COMIDA)
		hambre    = max(0, hambre - 40)
		felicidad = min(100, felicidad + 5)
		await actualizar_stats()
		return true
	return false

func banarse() -> bool:
	if dinero >= COSTE_BANO:
		await gastar_dinero(COSTE_BANO)
		higiene   = 100.0
		felicidad = min(100, felicidad + 10)
		estres    = max(0, estres - 5)
		await actualizar_stats()
		return true
	return false

func beber_alcohol() -> bool:
	if dinero >= COSTE_ALCOHOL:
		await gastar_dinero(COSTE_ALCOHOL)
		alcohol   = min(100, alcohol + 30)
		nervios   = max(0, nervios - 20)
		estres    = max(0, estres - 15)
		felicidad = min(100, felicidad + 10)
		await actualizar_stats()
		return true
	return false

func tomar_laudano() -> bool:
	if dinero >= COSTE_LAUDANO:
		await gastar_dinero(COSTE_LAUDANO)
		laudano   = min(100, laudano + 40)
		estres    = max(0, estres - 40)
		nervios   = max(0, nervios - 30)
		felicidad = min(100, felicidad + 20)
		await actualizar_stats()
		return true
	return false

# ============================================================
# 💊 TRATAMIENTOS DE ENFERMEDAD
# ============================================================
func comprar_medicina() -> bool:
	"""Impide que la enfermedad suba durante 2 días. No cura."""
	if dinero >= COSTE_MEDICINA:
		await gastar_dinero(COSTE_MEDICINA)
		medicina_activa = true
		medicina_timer = 0.0
		await actualizar_stats()
		return true
	return false

func ir_al_medico() -> bool:
	"""Cura completamente la enfermedad."""
	if dinero >= COSTE_MEDICO:
		await gastar_dinero(COSTE_MEDICO)
		enfermedad = 0.0
		enferma = false
		medicina_activa = false
		enfermedad_cambiada.emit(false)
		await actualizar_stats()
		return true
	return false

func descansar_hostal() -> bool:
	"""3 días en el hostal — 40% de curar la enfermedad."""
	if dinero >= COSTE_HOSTAL_DIA * 3:
		await gastar_dinero(COSTE_HOSTAL_DIA * 3)
		sueno   = 100.0
		stamina = 100.0
		estres  = max(0, estres - 30)
		dias_sin_pagar_hostal = 0
		# 40% de curar
		if randf() < 0.4:
			enfermedad = 0.0
			enferma = false
			enfermedad_cambiada.emit(false)
		await actualizar_stats()
		return true
	return false

func descansar_calle() -> void:
	"""3 días en la calle — 15% curar, 15% empeorar (+10), 70% sin cambio."""
	sueno    = 60.0
	stamina  = min(100, stamina + 40)
	estres   = min(100, estres + 30)
	higiene  = max(0, higiene - 30)
	felicidad = max(0, felicidad - 20)
	nervios  = min(100, nervios + 20)
	durmiendo_en_calle.emit()

	var tirada := randf()
	if tirada < 0.15:
		enfermedad = 0.0
		enferma = false
		enfermedad_cambiada.emit(false)
	elif tirada < 0.30:
		enfermedad = min(100, enfermedad + 10)
		_check_enfermedad_efectos()

	await actualizar_stats()

# ============================================================
# 💋 ACCIÓN — Sexo con cliente
# ============================================================
func tener_sexo_poor() -> void:
	await añadir_dinero(1.0)
	higiene  = max(0, higiene - 25)
	sueno    = max(0, sueno - 15)
	estres   = min(100, estres + 20)
	nervios  = min(100, nervios + 10)
	hambre   = min(100, hambre + 10)
	await infectar(PROB_INFECCION_POOR)
	await actualizar_stats()

func tener_sexo_medium() -> void:
	await añadir_dinero(3.0)
	higiene  = max(0, higiene - 20)
	sueno    = max(0, sueno - 12)
	estres   = min(100, estres + 15)
	nervios  = min(100, nervios + 8)
	hambre   = min(100, hambre + 8)
	await infectar(PROB_INFECCION_MEDIUM)
	await actualizar_stats()

func tener_sexo_rich() -> void:
	await añadir_dinero(8.0)
	higiene  = max(0, higiene - 10)
	sueno    = max(0, sueno - 8)
	estres   = min(100, estres + 5)
	nervios  = min(100, nervios + 3)
	hambre   = min(100, hambre + 5)
	await infectar(PROB_INFECCION_RICH)
	await actualizar_stats()

# ============================================================
# 💤 SLEEP
# ============================================================
func dormir_hostal() -> bool:
	if dinero >= COSTE_HOSTAL_DIA:
		await gastar_dinero(COSTE_HOSTAL_DIA)
		sueno   = 100.0
		stamina = 100.0
		estres  = max(0, estres - 20)
		dias_sin_pagar_hostal = 0
		await actualizar_stats()
		return true
	else:
		dias_sin_pagar_hostal += 1
		await dormir_calle()
		return false

func dormir_calle() -> void:
	sueno    = 60.0
	stamina  = min(100, stamina + 40)
	estres   = min(100, estres + 30)
	higiene  = max(0, higiene - 30)
	felicidad = max(0, felicidad - 20)
	nervios  = min(100, nervios + 20)
	durmiendo_en_calle.emit()
	await actualizar_stats()

# ============================================================
# 💸 ECONOMY
# ============================================================
func añadir_dinero(cantidad: float) -> void:
	dinero += cantidad
	dinero_changed.emit(dinero)
	if dinero >= DINERO_PARA_ESCAPAR:
		objetivo_completado.emit()
	await actualizar_stats()

func gastar_dinero(cantidad: float) -> bool:
	if dinero >= cantidad:
		dinero -= cantidad
		dinero_changed.emit(dinero)
		await actualizar_stats()
		return true
	return false

func puede_escapar() -> bool:
	return dinero >= DINERO_PARA_ESCAPAR

# ============================================================
# 🧠 STATE MANAGEMENT
# ============================================================
func clamp_all() -> void:
	for prop in ["miedo", "estres", "felicidad", "nervios", "hambre",
				 "higiene", "sueno", "alcohol", "laudano", "salud",
				 "stamina", "enfermedad"]:
		self.set(prop, clamp(self.get(prop), 0, 100))

# ============================================================
# 🔄 UPDATE & SIGNAL EMIT
# ============================================================
func actualizar_stats(delta: float = 1.0) -> void:
	clamp_all()
	calcular_sex_appeal()
	actualizar_salud(delta)
	stamina_changed.emit(stamina)
	# Detectar llegada a 0 desde cualquier fuente (pickups, degradación, etc.)
	if sueno > 0 and _colapso_activo:
		_colapso_activo = false
	if sueno <= 0 and _sueno_anterior > 0 and not _colapso_activo:
		_colapso_activo = true
		sueno_agotado.emit()
	_sueno_anterior = sueno
	await get_tree().process_frame
	stats_updated.emit()
	if debug_mode:
		print("📣 stats — hambre:", hambre, " higiene:", higiene,
			  " salud:", salud, " enfermedad:", enfermedad,
			  " sex_appeal:", sex_appeal)

# ============================================================
# 🔁 SYNC CON DIALOGIC
# ============================================================
func _sync_dialogic_variables() -> void:
	if not Engine.has_singleton("Dialogic"):
		return
	Dialogic.VAR.set_variable("sex_appeal", sex_appeal)
	Dialogic.VAR.set_variable("hora", DayNightManager.hora_actual)
	Dialogic.VAR.set_variable("dinero", dinero)
	Dialogic.VAR.set_variable("higiene", higiene)
	Dialogic.VAR.set_variable("enfermedad", enfermedad)

# ============================================================
# 🎨 UTILS
# ============================================================
func obtener_color_atributo(valor: float) -> Color:
	if valor >= 70:
		return Color.GREEN
	elif valor >= 40:
		return Color.YELLOW
	else:
		return Color.RED

func obtener_estado_general() -> String:
	if enfermedad >= 70:
		return "😷 Estás gravemente enferma..."
	elif enfermedad >= 20:
		return "🤒 Te encuentras mal..."
	elif sex_appeal >= 80:
		return "Estás en tu mejor momento"
	elif sex_appeal >= 60:
		return "Te sientes atractiva"
	elif sex_appeal >= 40:
		return "Podrías estar mejor"
	elif sex_appeal >= 20:
		return "Necesitas cuidarte urgentemente"
	else:
		return "Estás al límite..."

func has(stat_name: String) -> bool:
	for prop in get_property_list():
		if prop.name == stat_name:
			return true
	return false

func morir() -> void:
	jugador_muerto.emit()
	if debug_mode:
		print("☠️ El jugador ha muerto.")

func reset_stats() -> void:
	miedo     = 10.0
	estres    = 30.0
	felicidad = 50.0
	nervios   = 20.0
	hambre    = 50.0
	higiene   = 70.0
	sueno     = 80.0
	alcohol   = 0.0
	laudano   = 0.0
	salud     = 100.0
	stamina   = 100.0
	enfermedad = 0.0
	enferma   = false
	medicina_activa = false
	dinero    = 5.0
	enfermedad_cambiada.emit(false)
	await actualizar_stats()
