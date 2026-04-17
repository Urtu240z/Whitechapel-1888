extends Node

const CONFIG = preload("res://Data/Game/game_config.tres")

# ============================================================
# 🔧 SETTINGS
# ============================================================
@export var debug_mode: bool = false

# ============================================================
# 🧍 BASIC ATTRIBUTES (0–100)
# IMPORTANTE:
# - hambre alto = peor (más hambre)
# - higiene bajo = peor
# - sueno bajo = peor
# ============================================================
@export var miedo: float = 10.0
@export var estres: float = 30.0
@export var felicidad: float = 50.0
@export var nervios: float = 20.0
@export var hambre: float = 50.0
@export var higiene: float = 70.0
@export var sueno: float = 80.0

var _alcohol: float = 0.0
@export var alcohol: float:
	get:
		return _alcohol
	set(value):
		_set_alcohol(value)

var _laudano: float = 0.0
@export var laudano: float:
	get:
		return _laudano
	set(value):
		_set_laudano(value)

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
var _stats_refresh_queued: bool = false

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
	call_deferred("_post_ready_init")

# ============================================================
# ⏱️ RELOJ DEL JUEGO
# ============================================================
func sincronizar_reloj() -> void:
	_ultima_hora_procesada = int(floor(DayNightManager.get_hour_float()))

func _on_hora_cambiada(hora: float) -> void:
	var hora_int: int = int(floor(hora))
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
	hambre = clampf(hambre + HAMBRE_POR_HORA, 0.0, 100.0)
	higiene = clampf(higiene + HIGIENE_POR_HORA, 0.0, 100.0)
	sueno = clampf(sueno + SUENO_POR_HORA, 0.0, 100.0)
	alcohol = clampf(alcohol + ALCOHOL_POR_HORA, 0.0, 100.0)
	laudano = clampf(laudano + LAUDANO_POR_HORA, 0.0, 100.0)

	if enferma and not medicina_activa:
		enfermedad = clampf(enfermedad + ENFERMEDAD_POR_HORA, 0.0, 100.0)
		_check_enfermedad_efectos()

	# La salud se actualiza SOLO por tiempo aquí.
	actualizar_salud()
	actualizar_stats()

# ============================================================
# 🦠 ENFERMEDAD
# ============================================================
func _check_enfermedad_efectos() -> void:
	if enfermedad >= CONFIG.salud_umbral_enfermedad_terminal:
		damage_health(CONFIG.salud_dano_enfermedad_terminal)
	elif enfermedad >= CONFIG.salud_umbral_enfermedad_critica:
		damage_health(CONFIG.salud_dano_enfermedad_critica)

func infectar(probabilidad: float) -> bool:
	if randf() < probabilidad:
		if enfermedad == 0.0:
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

	appeal += (higiene - 50.0) * 0.5
	appeal += (felicidad - 50.0) * 0.3
	appeal += (100.0 - hambre) * 0.2
	appeal += (sueno - 50.0) * 0.2
	appeal += alcohol * 0.15

	appeal -= miedo * 0.25
	appeal -= estres * 0.4
	appeal -= nervios * 0.3
	appeal -= maxf(0.0, hambre - 50.0) * 0.3
	appeal -= maxf(0.0, alcohol - 50.0) * 0.5
	appeal -= laudano * 0.6
	appeal -= enfermedad * 0.5

	# Bonus temporal de perfumes
	appeal += sex_appeal_bonus

	sex_appeal = clampf(appeal, 0.0, 100.0)
	sex_appeal_changed.emit(sex_appeal)

	if higiene < 20.0:
		atributo_critico.emit("higiene")
	if hambre > 80.0:
		atributo_critico.emit("hambre")
	if sueno < 20.0:
		atributo_critico.emit("sueno")
	if enfermedad >= 70.0:
		atributo_critico.emit("enfermedad")

	return sex_appeal

# ============================================================
# 🩺 SALUD
# IMPORTANTE:
# - Esta función es para el desgaste suave por tiempo.
# - Se llama en el tick horario.
# - Se mantiene firma compatible con llamadas antiguas.
# ============================================================
func actualizar_salud(_delta: float = 1.0) -> void:
	var delta_salud: float = 0.0

	# Hambre alta = malo
	if hambre >= CONFIG.salud_umbral_hambre_3:
		delta_salud -= CONFIG.salud_dano_hambre_3
	elif hambre >= CONFIG.salud_umbral_hambre_2:
		delta_salud -= CONFIG.salud_dano_hambre_2
	elif hambre >= CONFIG.salud_umbral_hambre_1:
		delta_salud -= CONFIG.salud_dano_hambre_1

	# Higiene baja = malo
	if higiene <= CONFIG.salud_umbral_higiene_3:
		delta_salud -= CONFIG.salud_dano_higiene_3
	elif higiene <= CONFIG.salud_umbral_higiene_2:
		delta_salud -= CONFIG.salud_dano_higiene_2
	elif higiene <= CONFIG.salud_umbral_higiene_1:
		delta_salud -= CONFIG.salud_dano_higiene_1

	# Enfermedad sostenida = castigo moderado
	if enfermedad >= CONFIG.salud_umbral_enfermedad_3:
		delta_salud -= CONFIG.salud_dano_enfermedad_3
	elif enfermedad >= CONFIG.salud_umbral_enfermedad_2:
		delta_salud -= CONFIG.salud_dano_enfermedad_2
	elif enfermedad >= CONFIG.salud_umbral_enfermedad_1:
		delta_salud -= CONFIG.salud_dano_enfermedad_1

	# Recuperación suave
	if sueno >= CONFIG.salud_umbral_sueno_2:
		delta_salud += CONFIG.salud_recuperacion_sueno_2
	elif sueno >= CONFIG.salud_umbral_sueno_1:
		delta_salud += CONFIG.salud_recuperacion_sueno_1

	if felicidad >= CONFIG.salud_umbral_felicidad_2:
		delta_salud += CONFIG.salud_recuperacion_felicidad_2
	elif felicidad >= CONFIG.salud_umbral_felicidad_1:
		delta_salud += CONFIG.salud_recuperacion_felicidad_1

	salud = clampf(salud + delta_salud, 0.0, 100.0)

	if salud <= 0.0:
		morir()

# ============================================================
# 💥 DAÑO / CURA INSTANTÁNEA
# Para golpes, agresiones, eventos, medicina instantánea, etc.
# ============================================================
func damage_health(amount: float) -> void:
	if amount <= 0.0:
		return

	salud = clampf(salud - amount, 0.0, 100.0)
	actualizar_stats()

	if salud <= 0.0:
		morir()

func heal_health(amount: float) -> void:
	if amount <= 0.0:
		return

	salud = clampf(salud + amount, 0.0, 100.0)
	actualizar_stats()

# ============================================================
# 🍞 BASIC ACTIONS
# ============================================================
func comer() -> bool:
	if dinero >= CONFIG.coste_comida:
		gastar_dinero(CONFIG.coste_comida)
		hambre = maxf(0.0, hambre - 40.0)
		felicidad = minf(100.0, felicidad + 5.0)
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

# ============================================================
# 💋 ACTO CON CLIENTE — reemplaza tener_sexo_poor/medium/rich
# acto:  "mano" | "oral" | "completo"
# tipo:  "poor" | "medium" | "rich"
# ============================================================
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

func tener_acto(acto: String, tipo: String, satisfaction: float = 1.0) -> void:
	if not _ACTOS.has(acto) or not _ACTOS[acto].has(tipo):
		push_warning("PlayerStats.tener_acto: combinación inválida '%s'/'%s'" % [acto, tipo])
		return

	var d: Dictionary = _ACTOS[acto][tipo]

	higiene = clampf(higiene + float(d["higiene"]), 0.0, 100.0)
	nervios = clampf(nervios + float(d["nervios"]), 0.0, 100.0)
	sueno = clampf(sueno + float(d["sueno"]), 0.0, 100.0)
	estres = clampf(estres + float(d["estres"]), 0.0, 100.0)
	hambre = clampf(hambre + 5.0, 0.0, 100.0)

	infectar(float(d["infeccion"]))

	var pago_final: float = float(d["pago"]) * satisfaction
	añadir_dinero(pago_final)

	actualizar_stats()

# ============================================================
# 💤 SLEEP
# ============================================================
func dormir_hostal() -> bool:
	if dinero >= CONFIG.coste_hostal:
		gastar_dinero(CONFIG.coste_hostal)
		sueno = 100.0
		stamina = 100.0
		estres = maxf(0.0, estres - 20.0)
		dias_sin_pagar_hostal = 0
		actualizar_stats()
		return true
	else:
		dias_sin_pagar_hostal += 1
		dormir_calle()
		return false

func dormir_calle() -> void:
	sueno = 60.0
	stamina = minf(100.0, stamina + 40.0)
	estres = minf(100.0, estres + 30.0)
	higiene = maxf(0.0, higiene - 30.0)
	felicidad = maxf(0.0, felicidad - 20.0)
	nervios = minf(100.0, nervios + 20.0)
	durmiendo_en_calle.emit()
	actualizar_stats()

# ============================================================
# 💸 ECONOMY
# ============================================================
func añadir_dinero(cantidad: float) -> void:
	dinero += cantidad
	dinero_changed.emit(dinero)
	if dinero >= CONFIG.objetivo_dinero:
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
	return dinero >= CONFIG.objetivo_dinero

# ============================================================
# 🧠 STATE MANAGEMENT
# ============================================================
func clamp_all() -> void:
	for prop_name in [
		"miedo", "estres", "felicidad", "nervios", "hambre",
		"higiene", "sueno", "alcohol", "laudano", "salud",
		"stamina", "enfermedad"
	]:
		self.set(prop_name, clampf(float(self.get(prop_name)), 0.0, 100.0))

# ============================================================
# 🔄 UPDATE & SIGNAL EMIT
# IMPORTANTE:
# - Ya NO recalcula salud aquí.
# - actualizar_salud() va en el tick horario.
# ============================================================
func actualizar_stats(_delta: float = 1.0) -> void:
	clamp_all()
	calcular_sex_appeal()
	stamina_changed.emit(stamina)
	_detectar_colapso()
	stats_updated.emit()

func _detectar_colapso() -> void:
	if sueno > 0.0 and _colapso_activo:
		_colapso_activo = false

	if sueno <= 0.0 and _sueno_anterior > 0.0 and not _colapso_activo:
		_colapso_activo = true
		sueno_agotado.emit()

	_sueno_anterior = sueno

func actualizar_stats_diferido(_delta: float = 1.0) -> void:
	actualizar_stats()
	await get_tree().process_frame

# ============================================================
# 🔁 SYNC CON DIALOGIC
# ============================================================
func _sync_dialogic_variables() -> void:
	var dialogic_root := get_tree().root.get_node_or_null("Dialogic")
	if dialogic_root == null:
		return

	var dialogic_var = dialogic_root.get_node_or_null("VAR")
	if dialogic_var == null:
		return

	dialogic_var.set_variable("sex_appeal", sex_appeal)
	dialogic_var.set_variable("hora", DayNightManager.get_hour_float())
	dialogic_var.set_variable("dinero", dinero)
	dialogic_var.set_variable("higiene", higiene)
	dialogic_var.set_variable("enfermedad", enfermedad)

	var hora_actual: float = DayNightManager.get_hour_float()
	var hostel_open: bool = SleepManager.is_hostel_open(hora_actual)
	var hostel_can_rent: bool = hostel_open and SleepManager.get_hostel_hours_until_close(hora_actual) >= 1.0

	dialogic_var.set_variable("hostel.hostel_open", hostel_open)
	dialogic_var.set_variable("hostel.hostel_can_rent", hostel_can_rent)
	dialogic_var.set_variable("hostel.player_money", dinero)
	dialogic_var.set_variable("hostel.hostel_price", CONFIG.coste_hostal)

func sync_dialogic_variables_now() -> void:
	_sync_dialogic_variables()

# ============================================================
# 🎨 UTILS
# ============================================================
func obtener_color_atributo(valor: float) -> Color:
	if valor >= 70.0:
		return Color.GREEN
	elif valor >= 40.0:
		return Color.YELLOW
	else:
		return Color.RED

func obtener_estado_general() -> String:
	if enfermedad >= 70.0:
		return "😷 Estás gravemente enferma..."
	elif enfermedad >= 20.0:
		return "🤒 Te encuentras mal..."
	elif sex_appeal >= 80.0:
		return "Estás en tu mejor momento"
	elif sex_appeal >= 60.0:
		return "Te sientes atractiva"
	elif sex_appeal >= 40.0:
		return "Podrías estar mejor"
	elif sex_appeal >= 20.0:
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
	miedo = 10.0
	estres = 30.0
	felicidad = 50.0
	nervios = 20.0
	hambre = 50.0
	higiene = 70.0
	sueno = 80.0
	alcohol = 0.0
	laudano = 0.0
	salud = 100.0
	stamina = 100.0
	enfermedad = 0.0
	enferma = false
	medicina_activa = false
	medicina_timer = 0.0
	dinero = 5.0
	sex_appeal_bonus = 0.0

	enfermedad_cambiada.emit(false)
	sincronizar_reloj()
	actualizar_stats()

func _post_ready_init() -> void:
	actualizar_stats()
	_sync_dialogic_variables()

# ============================================================
# 🍷 CAMBIOS INMEDIATOS DE ALCOHOL / LAUDANO
# Para que los efectos visuales reaccionen al instante aunque
# otra parte del código cambie estas stats directamente.
# ============================================================
func _set_alcohol(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 100.0)
	if is_equal_approx(_alcohol, clamped):
		return
	_alcohol = clamped
	_queue_stats_refresh()

func _set_laudano(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 100.0)
	if is_equal_approx(_laudano, clamped):
		return
	_laudano = clamped
	_queue_stats_refresh()

func _queue_stats_refresh() -> void:
	if Engine.is_editor_hint():
		return
	if not is_node_ready():
		return
	if _stats_refresh_queued:
		return

	_stats_refresh_queued = true
	call_deferred("_apply_deferred_stats_refresh")

func _apply_deferred_stats_refresh() -> void:
	_stats_refresh_queued = false
	actualizar_stats()
