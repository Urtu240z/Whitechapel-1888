extends Node

const CONFIG = preload("res://Data/Game/game_config.tres")

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
# ============================================================
@export var enfermedad: float = 0.0

var enferma: bool = false

var medicina_activa: bool = false
var medicina_timer: float = 0.0  # horas de juego transcurridas desde que se tomó
const MEDICINA_DURACION_HORAS: float = 48.0

# ============================================================
# 💰 ECONOMY
# ============================================================
@export var dinero: float = 5.0
@export var dias_sin_pagar_hostal: int = 0

# ============================================================
# 💋 DERIVED ATTRIBUTES
# ============================================================
var sex_appeal: float = 50.0
var sex_appeal_bonus: float = 0.0  # bonus temporal de perfumes

# ============================================================
# 💸 COST CONSTANTS
# ============================================================
const COSTE_COMIDA: float = 0.5
const COSTE_BANO: float = 0.3
const COSTE_ALCOHOL: float = 0.2
const COSTE_LAUDANO: float = 1.0

# ============================================================
# 🦠 PROBABILIDADES DE INFECCIÓN
# ============================================================
const PROB_INFECCION_POOR: float = 0.15
const PROB_INFECCION_MEDIUM: float = 0.05
const PROB_INFECCION_RICH: float = 0.01

# ============================================================
# ⏱️ DEGRADACIÓN
# ============================================================
const HAMBRE_POR_HORA: float = 0.5
const HIGIENE_POR_HORA: float = -0.3
const SUENO_POR_HORA: float = -0.2
const ALCOHOL_POR_HORA: float = -1.0
const LAUDANO_POR_HORA: float = -0.5
const ENFERMEDAD_POR_HORA: float = 0.3

var _ultima_hora_procesada: int = -1
var _sueno_anterior: float = 80.0
var _colapso_activo: bool = false

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
signal sueno_agotado()

# ============================================================
# ⚙️ READY
# ============================================================
func _ready() -> void:
	calcular_sex_appeal()
	stats_updated.connect(_sync_dialogic_variables)
	if not DayNightManager.hora_cambiada.is_connected(_on_hora_cambiada):
		DayNightManager.hora_cambiada.connect(_on_hora_cambiada)
	sincronizar_reloj()

# ============================================================
# ⏱️ RELOJ DEL JUEGO
# ============================================================
func sincronizar_reloj() -> void:
	_ultima_hora_procesada = int(floor(DayNightManager.hora_actual))

func _on_hora_cambiada(hora: float) -> void:
	var hora_int := int(floor(hora))
	if hora_int == _ultima_hora_procesada:
		return

	_ultima_hora_procesada = hora_int
	_aplicar_degradacion()

	if medicina_activa:
		medicina_timer += 1.0
		if medicina_timer >= MEDICINA_DURACION_HORAS:
			medicina_activa = false
			medicina_timer = 0.0

func _aplicar_degradacion() -> void:
	hambre  = clamp(hambre  + HAMBRE_POR_HORA,  0, 100)
	higiene = clamp(higiene + HIGIENE_POR_HORA, 0, 100)
	sueno   = clamp(sueno   + SUENO_POR_HORA,   0, 100)
	alcohol = clamp(alcohol + ALCOHOL_POR_HORA, 0, 100)
	laudano = clamp(laudano + LAUDANO_POR_HORA, 0, 100)

	if enferma and not medicina_activa:
		enfermedad = clamp(enfermedad + ENFERMEDAD_POR_HORA, 0, 100)
		_check_enfermedad_efectos()

	actualizar_stats(1.0)

# ============================================================
# 🦠 ENFERMEDAD
# ============================================================
func _check_enfermedad_efectos() -> void:
	if enfermedad >= 100:
		salud = max(0, salud - 5.0)
		if salud <= 0:
			morir()
	elif enfermedad >= 70:
		salud = max(0, salud - 1.0)

func infectar(probabilidad: float) -> bool:
	if randf() < probabilidad:
		if enfermedad == 0:
			enfermedad = 20.0
		enferma = true
		enfermedad_cambiada.emit(true)
		actualizar_stats()
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
	appeal -= enfermedad * 0.5

	# Bonus temporal de perfumes
	appeal += sex_appeal_bonus

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
		gastar_dinero(COSTE_COMIDA)
		hambre    = max(0, hambre - 40)
		felicidad = min(100, felicidad + 5)
		actualizar_stats()
		return true
	return false

func banarse() -> bool:
	if dinero >= COSTE_BANO:
		gastar_dinero(COSTE_BANO)
		higiene   = 100.0
		felicidad = min(100, felicidad + 10)
		estres    = max(0, estres - 5)
		actualizar_stats()
		return true
	return false

func beber_alcohol() -> bool:
	if dinero >= COSTE_ALCOHOL:
		gastar_dinero(COSTE_ALCOHOL)
		alcohol   = min(100, alcohol + 30)
		nervios   = max(0, nervios - 20)
		estres    = max(0, estres - 15)
		felicidad = min(100, felicidad + 10)
		actualizar_stats()
		return true
	return false

func tomar_laudano() -> bool:
	if dinero >= COSTE_LAUDANO:
		gastar_dinero(COSTE_LAUDANO)
		laudano   = min(100, laudano + 40)
		estres    = max(0, estres - 40)
		nervios   = max(0, nervios - 30)
		felicidad = min(100, felicidad + 20)
		actualizar_stats()
		return true
	return false

# ============================================================
# 💊 TRATAMIENTOS
# ============================================================
func comprar_medicina() -> bool:
	if dinero >= CONFIG.coste_medicina:
		gastar_dinero(CONFIG.coste_medicina)
		medicina_activa = true
		medicina_timer = 0.0
		actualizar_stats()
		return true
	return false

func ir_al_medico() -> bool:
	if dinero >= CONFIG.coste_medico:
		gastar_dinero(CONFIG.coste_medico)
		enfermedad = 0.0
		enferma = false
		medicina_activa = false
		enfermedad_cambiada.emit(false)
		actualizar_stats()
		return true
	return false

func descansar_hostal() -> bool:
	if dinero >= CONFIG.coste_hostal * 3:
		gastar_dinero(CONFIG.coste_hostal * 3)
		sueno   = 100.0
		stamina = 100.0
		estres  = max(0, estres - 30)
		dias_sin_pagar_hostal = 0
		if randf() < 0.4:
			enfermedad = 0.0
			enferma = false
			enfermedad_cambiada.emit(false)
		actualizar_stats()
		return true
	return false

func descansar_calle() -> void:
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

	actualizar_stats()

# ============================================================
# 💋 ACTO CON CLIENTE — reemplaza tener_sexo_poor/medium/rich
# acto:  "mano" | "oral" | "completo"
# tipo:  "poor" | "medium" | "rich"
# ============================================================

# Tabla de datos por acto y tipo de cliente
const _ACTOS: Dictionary = {
	"mano": {
		"poor":   { "pago": 0.5, "higiene": -5,  "nervios": 5,  "sueno": -3,  "estres": 5,  "infeccion": 0.00 },
		"medium": { "pago": 1.0, "higiene": -4,  "nervios": 4,  "sueno": -2,  "estres": 4,  "infeccion": 0.00 },
		"rich":   { "pago": 2.0, "higiene": -2,  "nervios": 2,  "sueno": -1,  "estres": 2,  "infeccion": 0.00 },
	},
	"oral": {
		"poor":   { "pago": 1.0, "higiene": -12, "nervios": 10, "sueno": -5,  "estres": 10, "infeccion": 0.05 },
		"medium": { "pago": 2.0, "higiene": -8,  "nervios": 7,  "sueno": -4,  "estres": 7,  "infeccion": 0.02 },
		"rich":   { "pago": 4.0, "higiene": -4,  "nervios": 4,  "sueno": -2,  "estres": 4,  "infeccion": 0.01 },
	},
	"completo": {
		"poor":   { "pago": 2.0, "higiene": -25, "nervios": 20, "sueno": -10, "estres": 20, "infeccion": PROB_INFECCION_POOR   },
		"medium": { "pago": 4.0, "higiene": -18, "nervios": 14, "sueno": -8,  "estres": 14, "infeccion": PROB_INFECCION_MEDIUM },
		"rich":   { "pago": 8.0, "higiene": -8,  "nervios": 6,  "sueno": -4,  "estres": 6,  "infeccion": PROB_INFECCION_RICH   },
	},
}

# ============================================================
# Reemplaza tener_acto() en player_stats.gd
# satisfaction: 0.25 a 1.0 según ronda del minijuego
# ============================================================
 
func tener_acto(acto: String, tipo: String, satisfaction: float = 1.0) -> void:
	if not _ACTOS.has(acto) or not _ACTOS[acto].has(tipo):
		push_warning("PlayerStats.tener_acto: combinación inválida '%s'/'%s'" % [acto, tipo])
		return
 
	var d: Dictionary = _ACTOS[acto][tipo]
 
	higiene = clamp(higiene  + d["higiene"],  0, 100)
	nervios = clamp(nervios  + d["nervios"],  0, 100)
	sueno   = clamp(sueno    + d["sueno"],    0, 100)
	estres  = clamp(estres   + d["estres"],   0, 100)
	hambre  = clamp(hambre   + 5.0,           0, 100)
 
	infectar(d["infeccion"])
 
	# El pago se escala con la satisfacción del minijuego
	var pago_final: float = d["pago"] * satisfaction
	añadir_dinero(pago_final)
 
	actualizar_stats()

# ============================================================
# 💤 SLEEP
# ============================================================
func dormir_hostal() -> bool:
	if dinero >= CONFIG.coste_hostal:
		gastar_dinero(CONFIG.coste_hostal)
		sueno   = 100.0
		stamina = 100.0
		estres  = max(0, estres - 20)
		dias_sin_pagar_hostal = 0
		actualizar_stats()
		return true
	else:
		dias_sin_pagar_hostal += 1
		dormir_calle()
		return false

func dormir_calle() -> void:
	sueno    = 60.0
	stamina  = min(100, stamina + 40)
	estres   = min(100, estres + 30)
	higiene  = max(0, higiene - 30)
	felicidad = max(0, felicidad - 20)
	nervios  = min(100, nervios + 20)
	durmiendo_en_calle.emit()
	actualizar_stats()

# ============================================================
# 💸 ECONOMY
# ============================================================
func añadir_dinero(cantidad: float) -> void:
	dinero += cantidad
	dinero_changed.emit(dinero)
	if dinero >= DINERO_PARA_ESCAPAR:
		objetivo_completado.emit()
	actualizar_stats()

func gastar_dinero(cantidad: float) -> bool:
	if dinero >= cantidad:
		dinero -= cantidad
		dinero_changed.emit(dinero)
		actualizar_stats()
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
	_detectar_colapso()
	stats_updated.emit()
	if debug_mode:
		print("📣 stats — hambre:", hambre, " higiene:", higiene,
			  " salud:", salud, " enfermedad:", enfermedad,
			  " sex_appeal:", sex_appeal)

func _detectar_colapso() -> void:
	if sueno > 0 and _colapso_activo:
		_colapso_activo = false
	if sueno <= 0 and _sueno_anterior > 0 and not _colapso_activo:
		_colapso_activo = true
		sueno_agotado.emit()
	_sueno_anterior = sueno

func actualizar_stats_diferido(delta: float = 1.0) -> void:
	actualizar_stats(delta)
	await get_tree().process_frame

# ============================================================
# 🔁 SYNC CON DIALOGIC
# ============================================================
func _sync_dialogic_variables() -> void:
	if not get_tree().root.has_node("Dialogic"):
		return

	Dialogic.VAR.set_variable("sex_appeal", sex_appeal)
	Dialogic.VAR.set_variable("hora", DayNightManager.hora_actual)
	Dialogic.VAR.set_variable("dinero", dinero)
	Dialogic.VAR.set_variable("higiene", higiene)
	Dialogic.VAR.set_variable("enfermedad", enfermedad)

	var hora_actual := DayNightManager.hora_actual
	var hostel_open := hora_actual >= SleepManager.HORA_APERTURA_HOSTAL or hora_actual < SleepManager.HORA_CIERRE_HOSTAL

	Dialogic.VAR.set_variable("hostel.hostel_open", hostel_open)
	Dialogic.VAR.set_variable("hostel.player_money", dinero)
	Dialogic.VAR.set_variable("hostel.hostel_price", CONFIG.coste_hostal)

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
	medicina_timer = 0.0
	dinero    = 5.0
	sex_appeal_bonus = 0.0
	enfermedad_cambiada.emit(false)
	sincronizar_reloj()
	actualizar_stats()
