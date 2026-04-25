extends Node

const CONFIG = preload("res://Data/Game/game_config.tres")

# ============================================================
# PLAYER STATS — Autoload
# ============================================================
# Autoridad de los stats vivos de Nell.
#
# Reglas:
# - Otros sistemas pueden leer PlayerStats.hambre, salud, etc.
# - Para modificar stats, usar preferentemente la API pública:
#     apply_stat_delta()
#     apply_stat_deltas()
#     set_stat_value()
#     apply_damage()
#     apply_healing()
#     apply_item_effect()
#     apply_sleep_result()
#     apply_client_result()
# - Se mantienen funciones antiguas compatibles:
#     damage_health()
#     heal_health()
#     tener_acto()
#     gastar_dinero()
#     añadir_dinero()
# ============================================================

# ============================================================
# 🔧 SETTINGS
# ============================================================
@export var debug_mode: bool = false

# ============================================================
# 🧍 BASIC ATTRIBUTES (0–100)
# IMPORTANTE:
# - hambre alto = peor, más hambre.
# - higiene bajo = peor.
# - sueno bajo = peor.
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
var medicina_timer: float = 0.0
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
var sex_appeal_bonus: float = 0.0

# ============================================================
# 🦠 PROBABILIDADES DE INFECCIÓN
# ============================================================
const PROB_INFECCION_POOR: float = 0.15
const PROB_INFECCION_MEDIUM: float = 0.05
const PROB_INFECCION_RICH: float = 0.01

# ============================================================
# ⏱️ DEGRADACIÓN HORARIA
# ============================================================
const HAMBRE_POR_HORA: float = 0.5
const HIGIENE_POR_HORA: float = -0.3
const SUENO_POR_HORA: float = -0.2
const ALCOHOL_POR_HORA: float = -1.0
const LAUDANO_POR_HORA: float = -0.5
const ENFERMEDAD_POR_HORA: float = 0.3

# ============================================================
# STATS SOPORTADOS
# ============================================================
const STAT_NAMES: PackedStringArray = [
	"miedo",
	"estres",
	"felicidad",
	"nervios",
	"hambre",
	"higiene",
	"sueno",
	"alcohol",
	"laudano",
	"salud",
	"stamina",
	"enfermedad",
]

const SAVE_STAT_NAMES: PackedStringArray = [
	"miedo",
	"estres",
	"felicidad",
	"nervios",
	"hambre",
	"higiene",
	"sueno",
	"alcohol",
	"laudano",
	"salud",
	"stamina",
	"enfermedad",
	"dinero",
	"sex_appeal_bonus",
]

var _ultima_hora_procesada: int = -1
var _sueno_anterior: float = 80.0
var _colapso_activo: bool = false
var _stats_refresh_queued: bool = false
var _updating_stats: bool = false

# ============================================================
# 📢 SIGNALS
# ============================================================
signal sex_appeal_changed(new_value: float)
signal dinero_changed(new_value: float)
signal stamina_changed(new_value: float)
signal stat_changed(stat_name: String, old_value: float, new_value: float, reason: String)
signal stats_delta_applied(deltas: Dictionary, reason: String)
signal atributo_critico(cual: String)
signal durmiendo_en_calle()
signal objetivo_completado()
signal stats_updated
signal enfermedad_cambiada(estado: bool)
signal jugador_muerto()
signal sueno_agotado()
signal damage_applied(amount: float, source: String)
signal healing_applied(amount: float, source: String)
signal condition_applied(condition_id: String)

# ============================================================
# ⚙️ READY
# ============================================================
func _ready() -> void:
	calcular_sex_appeal()

	if not stats_updated.is_connected(_sync_dialogic_variables):
		stats_updated.connect(_sync_dialogic_variables)

	if DayNightManager and not DayNightManager.hora_cambiada.is_connected(_on_hora_cambiada):
		DayNightManager.hora_cambiada.connect(_on_hora_cambiada)

	sincronizar_reloj()
	call_deferred("_post_ready_init")

# ============================================================
# ⏱️ RELOJ DEL JUEGO
# ============================================================
func sincronizar_reloj() -> void:
	if not DayNightManager:
		_ultima_hora_procesada = -1
		return

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
			condition_applied.emit("medicine_expired")


func _aplicar_degradacion() -> void:
	apply_stat_deltas({
		"hambre": HAMBRE_POR_HORA,
		"higiene": HIGIENE_POR_HORA,
		"sueno": SUENO_POR_HORA,
		"alcohol": ALCOHOL_POR_HORA,
		"laudano": LAUDANO_POR_HORA,
	}, "hourly_degradation", false)

	if enferma and not medicina_activa:
		apply_stat_delta("enfermedad", ENFERMEDAD_POR_HORA, "hourly_disease", false)
		_check_enfermedad_efectos()

	# La salud se actualiza SOLO por tiempo aquí.
	actualizar_salud()
	actualizar_stats()

# ============================================================
# API PÚBLICA — STATS
# ============================================================
func is_valid_stat(stat_name: String) -> bool:
	return STAT_NAMES.has(stat_name)


func has(stat_name: String) -> bool:
	# Compatibilidad con código actual.
	return is_valid_stat(stat_name) or SAVE_STAT_NAMES.has(stat_name)


func get_stat_value(stat_name: String, fallback: float = 0.0) -> float:
	if not has(stat_name):
		return fallback

	var value = get(stat_name)
	if value == null:
		return fallback

	return float(value)


func set_stat_value(stat_name: String, value: float, reason: String = "manual", emit_update: bool = true) -> bool:
	if not has(stat_name):
		push_warning("PlayerStats.set_stat_value(): stat inválido '%s'." % stat_name)
		return false

	var old_value: float = get_stat_value(stat_name)
	var new_value: float = _clamp_named_stat(stat_name, value)

	if is_equal_approx(old_value, new_value):
		return true

	set(stat_name, new_value)
	stat_changed.emit(stat_name, old_value, new_value, reason)

	if stat_name == "dinero":
		dinero_changed.emit(dinero)
		_check_money_goal()

	if stat_name == "enfermedad":
		_update_enferma_from_enfermedad()

	if emit_update:
		actualizar_stats()

	return true


func apply_stat_delta(stat_name: String, delta: float, reason: String = "delta", emit_update: bool = true) -> bool:
	if not has(stat_name):
		push_warning("PlayerStats.apply_stat_delta(): stat inválido '%s'." % stat_name)
		return false

	var old_value: float = get_stat_value(stat_name)
	var new_value: float = _clamp_named_stat(stat_name, old_value + delta)

	if is_equal_approx(old_value, new_value):
		return true

	set(stat_name, new_value)
	stat_changed.emit(stat_name, old_value, new_value, reason)

	if stat_name == "dinero":
		dinero_changed.emit(dinero)
		_check_money_goal()

	if stat_name == "enfermedad":
		_update_enferma_from_enfermedad()

	if emit_update:
		actualizar_stats()

	return true


func apply_stat_deltas(deltas: Dictionary, reason: String = "deltas", emit_update: bool = true) -> bool:
	var applied := false
	var applied_deltas: Dictionary = {}

	for raw_key in deltas.keys():
		var stat_name := str(raw_key)
		var delta := float(deltas[raw_key])

		if not has(stat_name):
			push_warning("PlayerStats.apply_stat_deltas(): stat inválido '%s'." % stat_name)
			continue

		var old_value: float = get_stat_value(stat_name)
		var new_value: float = _clamp_named_stat(stat_name, old_value + delta)

		if is_equal_approx(old_value, new_value):
			continue

		set(stat_name, new_value)
		stat_changed.emit(stat_name, old_value, new_value, reason)
		applied_deltas[stat_name] = new_value - old_value
		applied = true

		if stat_name == "dinero":
			dinero_changed.emit(dinero)
			_check_money_goal()

		if stat_name == "enfermedad":
			_update_enferma_from_enfermedad()

	if applied:
		stats_delta_applied.emit(applied_deltas, reason)
		if emit_update:
			actualizar_stats()

	return applied


func apply_absolute_stats(values: Dictionary, reason: String = "absolute", emit_update: bool = true) -> bool:
	var changed := false

	for raw_key in values.keys():
		var stat_name := str(raw_key)
		if set_stat_value(stat_name, float(values[raw_key]), reason, false):
			changed = true

	if changed and emit_update:
		actualizar_stats()

	return changed


func _clamp_named_stat(stat_name: String, value: float) -> float:
	if STAT_NAMES.has(stat_name) or stat_name == "sex_appeal_bonus":
		return clampf(value, 0.0, 100.0)

	if stat_name == "dinero":
		return maxf(0.0, value)

	return value

# ============================================================
# API PÚBLICA — DAÑO / CURA / CONDICIONES
# ============================================================
func apply_damage(amount: float, source: String = "generic") -> void:
	if amount <= 0.0:
		return

	apply_stat_delta("salud", -absf(amount), "damage_%s" % source, false)
	damage_applied.emit(absf(amount), source)
	actualizar_stats()

	if salud <= 0.0:
		morir()


func apply_healing(amount: float, source: String = "generic") -> void:
	if amount <= 0.0:
		return

	apply_stat_delta("salud", absf(amount), "healing_%s" % source, false)
	healing_applied.emit(absf(amount), source)
	actualizar_stats()


func apply_condition(condition_id: String, data: Dictionary = {}) -> void:
	match condition_id:
		"infectar", "infection":
			var probabilidad: float = float(data.get("probabilidad", 1.0))
			infectar(probabilidad)

		"medicine":
			medicina_activa = true
			medicina_timer = 0.0
			condition_applied.emit("medicine")
			actualizar_stats()

		"cure_disease":
			curar_enfermedad()

		"clear_substances":
			apply_absolute_stats({"alcohol": 0.0, "laudano": 0.0}, "clear_substances")
			condition_applied.emit("clear_substances")

		_:
			push_warning("PlayerStats.apply_condition(): condition_id desconocido '%s'." % condition_id)
			return

	condition_applied.emit(condition_id)


func damage_health(amount: float) -> void:
	# Compatibilidad con DamageManager antiguo.
	apply_damage(amount, "legacy_damage_health")


func heal_health(amount: float) -> void:
	# Compatibilidad con llamadas antiguas.
	apply_healing(amount, "legacy_heal_health")

# ============================================================
# API PÚBLICA — ITEMS / INVENTARIO
# ============================================================
func apply_item_effect(item, reason: String = "item") -> void:
	if item == null:
		return

	var deltas: Dictionary = _extract_item_deltas(item)
	if not deltas.is_empty():
		apply_stat_deltas(deltas, reason)
	else:
		actualizar_stats()


func remove_item_effect(item, reason: String = "remove_item") -> void:
	if item == null:
		return

	var deltas: Dictionary = _extract_item_deltas(item)
	var inverse: Dictionary = {}

	for key in deltas.keys():
		inverse[key] = -float(deltas[key])

	if not inverse.is_empty():
		apply_stat_deltas(inverse, reason)
	else:
		actualizar_stats()


func apply_equipment_bonus(item, reason: String = "equip") -> void:
	if item == null:
		return

	var deltas: Dictionary = {}

	if _object_has_property(item, "sex_appeal_bonus"):
		deltas["sex_appeal_bonus"] = float(item.sex_appeal_bonus)
	if _object_has_property(item, "higiene_bonus"):
		deltas["higiene"] = float(item.higiene_bonus)
	if _object_has_property(item, "nervios_bonus"):
		deltas["nervios"] = float(item.nervios_bonus)

	apply_stat_deltas(deltas, reason)


func remove_equipment_bonus(item, reason: String = "unequip") -> void:
	if item == null:
		return

	var deltas: Dictionary = {}

	if _object_has_property(item, "sex_appeal_bonus"):
		deltas["sex_appeal_bonus"] = -float(item.sex_appeal_bonus)
	if _object_has_property(item, "higiene_bonus"):
		deltas["higiene"] = -float(item.higiene_bonus)
	if _object_has_property(item, "nervios_bonus"):
		deltas["nervios"] = -float(item.nervios_bonus)

	apply_stat_deltas(deltas, reason)


func _extract_item_deltas(item) -> Dictionary:
	var deltas: Dictionary = {}

	# Soporta tanto Resources con campos directos como Dictionary.
	if item is Dictionary:
		if item.has("stats") and item["stats"] is Dictionary:
			return item["stats"]

		for key in item.keys():
			var stat_name := str(key)
			if has(stat_name):
				deltas[stat_name] = float(item[key])
		return deltas

	for stat_name in STAT_NAMES:
		if _object_has_property(item, stat_name):
			var value: float = float(item.get(stat_name))
			if not is_zero_approx(value):
				deltas[stat_name] = value

	return deltas

# ============================================================
# 🍞 BASIC ACTIONS
# ============================================================
func comer() -> bool:
	if gastar_dinero(CONFIG.coste_comida):
		apply_stat_deltas({
			"hambre": -40.0,
			"felicidad": 5.0,
		}, "eat")
		return true

	return false

# ============================================================
# 💊 TRATAMIENTOS
# ============================================================
func comprar_medicina() -> bool:
	if gastar_dinero(CONFIG.coste_medicina):
		medicina_activa = true
		medicina_timer = 0.0
		condition_applied.emit("medicine_bought")
		actualizar_stats()
		return true

	return false


func ir_al_medico() -> bool:
	if gastar_dinero(CONFIG.coste_medico):
		curar_enfermedad()
		condition_applied.emit("doctor")
		return true

	return false


func curar_enfermedad() -> void:
	enfermedad = 0.0
	enferma = false
	medicina_activa = false
	medicina_timer = 0.0
	enfermedad_cambiada.emit(false)
	actualizar_stats()

# ============================================================
# 💋 ACTO CON CLIENTE
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
	apply_client_result({
		"acto": acto,
		"tipo": tipo,
		"satisfaction": satisfaction,
	})


func apply_client_result(result: Dictionary) -> void:
	var acto: String = str(result.get("acto", ""))
	var tipo: String = str(result.get("tipo", ""))
	var satisfaction: float = float(result.get("satisfaction", 1.0))

	if not _ACTOS.has(acto) or not _ACTOS[acto].has(tipo):
		push_warning("PlayerStats.apply_client_result(): combinación inválida '%s'/'%s'." % [acto, tipo])
		return

	var d: Dictionary = _ACTOS[acto][tipo]

	apply_stat_deltas({
		"higiene": float(d["higiene"]),
		"nervios": float(d["nervios"]),
		"sueno": float(d["sueno"]),
		"estres": float(d["estres"]),
		"hambre": 5.0,
	}, "client_%s_%s" % [acto, tipo], false)

	infectar(float(d["infeccion"]))

	var pago_final: float = float(d["pago"]) * satisfaction
	añadir_dinero(pago_final)

	actualizar_stats()

# ============================================================
# 💤 SLEEP
# ============================================================
func dormir_hostal() -> bool:
	if gastar_dinero(CONFIG.coste_hostal):
		apply_sleep_result({
			"lugar": "hostal",
			"sueno": 100.0,
			"stamina": 100.0,
			"estres_delta": -20.0,
			"dias_sin_pagar_hostal": 0,
		})
		return true

	dias_sin_pagar_hostal += 1
	dormir_calle()
	return false


func dormir_calle() -> void:
	apply_sleep_result({
		"lugar": "calle",
		"sueno": 60.0,
		"stamina_delta": 40.0,
		"estres_delta": 30.0,
		"higiene_delta": -30.0,
		"felicidad_delta": -20.0,
		"nervios_delta": 20.0,
	})
	durmiendo_en_calle.emit()


func apply_sleep_result(result: Dictionary) -> void:
	var deltas: Dictionary = {}
	var absolutes: Dictionary = {}

	for raw_key in result.keys():
		var key := str(raw_key)
		if key.ends_with("_delta"):
			var stat_name := key.trim_suffix("_delta")
			deltas[stat_name] = float(result[raw_key])
		elif has(key):
			absolutes[key] = float(result[raw_key])

	if result.has("dias_sin_pagar_hostal"):
		dias_sin_pagar_hostal = int(result["dias_sin_pagar_hostal"])

	if not absolutes.is_empty():
		apply_absolute_stats(absolutes, "sleep_result", false)

	if not deltas.is_empty():
		apply_stat_deltas(deltas, "sleep_result", false)

	actualizar_stats()

# ============================================================
# 💸 ECONOMY
# ============================================================
func añadir_dinero(cantidad: float) -> void:
	if cantidad <= 0.0:
		return

	dinero = maxf(0.0, dinero + cantidad)
	dinero_changed.emit(dinero)
	_check_money_goal()
	actualizar_stats()


func gastar_dinero(cantidad: float) -> bool:
	if cantidad <= 0.0:
		return true

	if dinero >= cantidad:
		dinero = maxf(0.0, dinero - cantidad)
		dinero_changed.emit(dinero)
		actualizar_stats()
		return true

	return false


func can_afford(cantidad: float) -> bool:
	return dinero >= cantidad


func puede_escapar() -> bool:
	return dinero >= CONFIG.objetivo_dinero


func _check_money_goal() -> void:
	if dinero >= CONFIG.objetivo_dinero:
		objetivo_completado.emit()

# ============================================================
# 🦠 ENFERMEDAD
# ============================================================
func _check_enfermedad_efectos() -> void:
	if enfermedad >= CONFIG.salud_umbral_enfermedad_terminal:
		apply_damage(CONFIG.salud_dano_enfermedad_terminal, "terminal_disease")
	elif enfermedad >= CONFIG.salud_umbral_enfermedad_critica:
		apply_damage(CONFIG.salud_dano_enfermedad_critica, "critical_disease")


func infectar(probabilidad: float) -> bool:
	if probabilidad <= 0.0:
		return false

	if randf() < probabilidad:
		if enfermedad == 0.0:
			enfermedad = 20.0
		enferma = true
		enfermedad_cambiada.emit(true)
		condition_applied.emit("infection")
		actualizar_stats()
		return true

	return false


func _update_enferma_from_enfermedad() -> void:
	var should_be_sick := enfermedad > 0.0
	if enferma == should_be_sick:
		return

	enferma = should_be_sick
	enfermedad_cambiada.emit(enferma)

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

	appeal += sex_appeal_bonus

	var old_appeal := sex_appeal
	sex_appeal = clampf(appeal, 0.0, 100.0)

	if not is_equal_approx(old_appeal, sex_appeal):
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

	if hambre >= CONFIG.salud_umbral_hambre_3:
		delta_salud -= CONFIG.salud_dano_hambre_3
	elif hambre >= CONFIG.salud_umbral_hambre_2:
		delta_salud -= CONFIG.salud_dano_hambre_2
	elif hambre >= CONFIG.salud_umbral_hambre_1:
		delta_salud -= CONFIG.salud_dano_hambre_1

	if higiene <= CONFIG.salud_umbral_higiene_3:
		delta_salud -= CONFIG.salud_dano_higiene_3
	elif higiene <= CONFIG.salud_umbral_higiene_2:
		delta_salud -= CONFIG.salud_dano_higiene_2
	elif higiene <= CONFIG.salud_umbral_higiene_1:
		delta_salud -= CONFIG.salud_dano_higiene_1

	if enfermedad >= CONFIG.salud_umbral_enfermedad_3:
		delta_salud -= CONFIG.salud_dano_enfermedad_3
	elif enfermedad >= CONFIG.salud_umbral_enfermedad_2:
		delta_salud -= CONFIG.salud_dano_enfermedad_2
	elif enfermedad >= CONFIG.salud_umbral_enfermedad_1:
		delta_salud -= CONFIG.salud_dano_enfermedad_1

	if sueno >= CONFIG.salud_umbral_sueno_2:
		delta_salud += CONFIG.salud_recuperacion_sueno_2
	elif sueno >= CONFIG.salud_umbral_sueno_1:
		delta_salud += CONFIG.salud_recuperacion_sueno_1

	if felicidad >= CONFIG.salud_umbral_felicidad_2:
		delta_salud += CONFIG.salud_recuperacion_felicidad_2
	elif felicidad >= CONFIG.salud_umbral_felicidad_1:
		delta_salud += CONFIG.salud_recuperacion_felicidad_1

	if not is_zero_approx(delta_salud):
		apply_stat_delta("salud", delta_salud, "hourly_health", false)

	if salud <= 0.0:
		morir()

# ============================================================
# 🧠 STATE MANAGEMENT
# ============================================================
func clamp_all() -> void:
	for prop_name in STAT_NAMES:
		set(prop_name, _clamp_named_stat(prop_name, float(get(prop_name))))

	sex_appeal_bonus = clampf(sex_appeal_bonus, 0.0, 100.0)
	dinero = maxf(0.0, dinero)

# ============================================================
# 🔄 UPDATE & SIGNAL EMIT
# IMPORTANTE:
# - Ya NO recalcula salud aquí.
# - actualizar_salud() va en el tick horario.
# ============================================================
func actualizar_stats(_delta: float = 1.0) -> void:
	if _updating_stats:
		return

	_updating_stats = true
	clamp_all()
	calcular_sex_appeal()
	stamina_changed.emit(stamina)
	_detectar_colapso()
	stats_updated.emit()
	_updating_stats = false


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
# SAVE API — para limpiar SaveManager más adelante
# ============================================================
func get_save_data() -> Dictionary:
	return {
		"miedo": miedo,
		"estres": estres,
		"felicidad": felicidad,
		"nervios": nervios,
		"hambre": hambre,
		"higiene": higiene,
		"sueno": sueno,
		"alcohol": alcohol,
		"laudano": laudano,
		"salud": salud,
		"stamina": stamina,
		"enfermedad": enfermedad,
		"dinero": dinero,
		"sex_appeal_bonus": sex_appeal_bonus,
		"enferma": enferma,
		"medicina_activa": medicina_activa,
		"medicina_timer": medicina_timer,
		"dias_sin_pagar_hostal": dias_sin_pagar_hostal,
	}


func apply_save_data(data: Dictionary) -> void:
	miedo = float(data.get("miedo", 10.0))
	estres = float(data.get("estres", 30.0))
	felicidad = float(data.get("felicidad", 50.0))
	nervios = float(data.get("nervios", 20.0))
	hambre = float(data.get("hambre", 50.0))
	higiene = float(data.get("higiene", 70.0))
	sueno = float(data.get("sueno", 80.0))
	alcohol = float(data.get("alcohol", 0.0))
	laudano = float(data.get("laudano", 0.0))
	salud = float(data.get("salud", 100.0))
	stamina = float(data.get("stamina", 100.0))
	enfermedad = float(data.get("enfermedad", 0.0))
	dinero = float(data.get("dinero", 5.0))
	sex_appeal_bonus = float(data.get("sex_appeal_bonus", 0.0))

	enferma = bool(data.get("enferma", false))
	medicina_activa = bool(data.get("medicina_activa", false))
	medicina_timer = float(data.get("medicina_timer", 0.0))
	dias_sin_pagar_hostal = int(data.get("dias_sin_pagar_hostal", 0))

	enfermedad_cambiada.emit(enferma)
	dinero_changed.emit(dinero)
	sincronizar_reloj()
	actualizar_stats()

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

	if DayNightManager:
		dialogic_var.set_variable("hora", DayNightManager.get_hour_float())
	else:
		dialogic_var.set_variable("hora", 0.0)

	dialogic_var.set_variable("dinero", dinero)
	dialogic_var.set_variable("higiene", higiene)
	dialogic_var.set_variable("enfermedad", enfermedad)

	if SleepManager and DayNightManager:
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
	dias_sin_pagar_hostal = 0
	sex_appeal_bonus = 0.0

	enfermedad_cambiada.emit(false)
	dinero_changed.emit(dinero)
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

	var old_value: float = _alcohol
	_alcohol = clamped
	stat_changed.emit("alcohol", old_value, clamped, "direct_set")
	_queue_stats_refresh()


func _set_laudano(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 100.0)
	if is_equal_approx(_laudano, clamped):
		return

	var old_value: float = _laudano
	_laudano = clamped
	stat_changed.emit("laudano", old_value, clamped, "direct_set")
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


func _object_has_property(obj, property_name: String) -> bool:
	if obj == null:
		return false

	for prop in obj.get_property_list():
		if str(prop.name) == property_name:
			return true

	return false
