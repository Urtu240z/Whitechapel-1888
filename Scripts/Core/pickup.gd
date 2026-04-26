extends Area2D
class_name Pickup

# ================================================================
# PICKUP — legacy limpio y robusto
# ================================================================
# - Aplica efectos usando PlayerStats.apply_stat_deltas()
# - No modifica stats directamente.
# ================================================================

@export_enum("client-medium", "client-poor", "client-rich", "cure-doctor", "cure-hostal", "cure-medicine", "cure-reset", "cure-street", "drink-absenta", "drink-cerveza", "drink-ginebra", "drink-ron", "drink-whisky", "drink-wine", "drug-eter", "drug-laudano", "food-arenque", "food-gachas", "food-pan", "food-patata", "food-sopa", "food-tocino", "health-ducha", "health-sleep-cama", "health-sleep-silla", "health-sleep-suelo", "liquid-agua", "liquid-cafe", "liquid-leche", "liquid-te", "scare-down", "scare-up", "sueno-down", "sueno-up") var pickup_type: String = "client-medium"

@export var disappear_on_pickup: bool = true
@export var auto_trigger_on_touch: bool = true
@export var require_payment: bool = true

var data: Resource = null

@export var info := "" : set = _set_info, get = _get_info


# ================================================================
# EDITOR INFO
# ================================================================
func _get_info() -> String:
	if pickup_type.begins_with("client-"):
		match pickup_type:
			"client-poor":
				return "👤 Cliente Pobre\n💰 +1 chelín\n⚠️ 15% riesgo infección"
			"client-medium":
				return "👤 Cliente Medio\n💰 +3 chelines\n⚠️ 5% riesgo infección"
			"client-rich":
				return "👤 Cliente Rico\n💰 +8 chelines\n⚠️ 1% riesgo infección"

	if pickup_type.begins_with("cure-"):
		match pickup_type:
			"cure-medicine":
				return "💊 Medicina\nMantiene la enfermedad a raya 2 días"
			"cure-doctor":
				return "🏥 Médico\nCura completamente la enfermedad"
			"cure-reset":
				return "🔄 Reset\nResetea todos los stats"
			"cure-hostal":
				return "🛏️ Hostal\nLegacy / sin efecto directo"
			"cure-street":
				return "🌧️ Calle\nLegacy / sin efecto directo"

	if data == null:
		return "⚠️ Sin datos cargados"

	var display_name := _get_data_string("display_name", pickup_type)
	var cost := _get_data_float("cost", 0.0)
	var effects := _get_data_dictionary("effects")

	var text := "📜 " + display_name + "\n"
	text += "💰 Coste: %d\n" % int(cost)
	text += "🎯 Efectos:\n"

	for stat in effects.keys():
		text += "   %s: %.1f\n" % [str(stat), float(effects[stat])]

	return text.strip_edges()


func _set_info(_value: String) -> void:
	pass


# ================================================================
# READY
# ================================================================
func _ready() -> void:
	add_to_group("pickup")

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	_load_data()
	notify_property_list_changed()


func _load_data() -> void:
	data = null

	var pickup_path := "res://Data/Pickups/%s.tres" % pickup_type

	if ResourceLoader.exists(pickup_path):
		data = load(pickup_path)
	else:
		push_warning("Pickup: no se encontró el recurso: %s" % pickup_path)


# ================================================================
# TRIGGER
# ================================================================
func _on_body_entered(body: Node) -> void:
	if not auto_trigger_on_touch:
		return

	if not _is_player(body):
		return

	_try_consume_pickup()


func _is_player(body: Node) -> bool:
	if body == null:
		return false

	if body.is_in_group("player"):
		return true

	if PlayerManager and PlayerManager.has_method("get_player"):
		var player = PlayerManager.get_player()
		if is_instance_valid(player) and body == player:
			return true

	return false


func _try_consume_pickup() -> bool:
	if pickup_type.begins_with("client-"):
		return _handle_client_pickup()

	if pickup_type.begins_with("cure-"):
		return _handle_cure_pickup()

	return _handle_item_pickup()


# ================================================================
# CLIENTES LEGACY
# ================================================================
func _handle_client_pickup() -> bool:
	var client_type := ""

	match pickup_type:
		"client-poor":
			client_type = "poor"
		"client-medium":
			client_type = "medium"
		"client-rich":
			client_type = "rich"
		_:
			push_warning("Pickup: client pickup desconocido: %s" % pickup_type)
			return false

	if PlayerStats.has_method("apply_client_result"):
		PlayerStats.apply_client_result({
			"acto": "completo",
			"tipo": client_type,
			"satisfaction": 1.0,
		})
	else:
		push_warning("Pickup: PlayerStats no tiene apply_client_result().")
		return false

	_finish_pickup()
	return true


# ================================================================
# CURAS LEGACY
# ================================================================
func _handle_cure_pickup() -> bool:
	match pickup_type:
		"cure-medicine":
			if PlayerStats.has_method("comprar_medicina"):
				PlayerStats.comprar_medicina()
			else:
				push_warning("Pickup: PlayerStats no tiene comprar_medicina().")
				return false

		"cure-doctor":
			if PlayerStats.has_method("ir_al_medico"):
				PlayerStats.ir_al_medico()
			else:
				push_warning("Pickup: PlayerStats no tiene ir_al_medico().")
				return false

		"cure-reset":
			if PlayerStats.has_method("reset_stats"):
				PlayerStats.reset_stats()
			else:
				push_warning("Pickup: PlayerStats no tiene reset_stats().")
				return false

		"cure-hostal", "cure-street":
			push_warning("Pickup: '%s' es legacy y no tiene efecto directo." % pickup_type)

		_:
			push_warning("Pickup: cure pickup desconocido: %s" % pickup_type)
			return false

	_finish_pickup()
	return true


# ================================================================
# ITEMS NORMALES
# ================================================================
func _handle_item_pickup() -> bool:
	if data == null:
		push_warning("Pickup: no hay datos cargados para: %s" % pickup_type)
		return false

	var cost := _get_data_float("cost", 0.0)
	var effects := _get_data_dictionary("effects")

	if effects.is_empty():
		push_warning("Pickup: '%s' no tiene efectos." % pickup_type)
		return false

	if require_payment and cost > 0.0:
		if not _try_pay(cost):
			return false

	if PlayerStats.has_method("apply_stat_deltas"):
		PlayerStats.apply_stat_deltas(effects, "pickup_%s" % pickup_type)
	else:
		push_warning("Pickup: PlayerStats no tiene apply_stat_deltas().")
		return false

	_play_pickup_sound()
	_finish_pickup()
	return true


func _try_pay(cost: float) -> bool:
	# IMPORTANTE:
	# Mantengo el coste tal cual viene del .tres.
	# Si tus .tres guardan coste en peniques, PlayerStats debe usar peniques.
	# Si guardan chelines, PlayerStats debe usar chelines.
	#
	# No divido entre 12 aquí para evitar cambiar economía sin querer.
	if PlayerStats.has_method("gastar_dinero"):
		return PlayerStats.gastar_dinero(cost)

	if PlayerStats.dinero < cost:
		return false

	PlayerStats.dinero -= cost

	if PlayerStats.has_method("actualizar_stats"):
		PlayerStats.actualizar_stats()

	return true


func _play_pickup_sound() -> void:
	if data == null:
		return

	var sound = data.get("sound")
	if sound == null:
		return

	var snd := AudioStreamPlayer2D.new()
	snd.stream = sound
	add_child(snd)
	snd.play()
	snd.finished.connect(snd.queue_free)


func _finish_pickup() -> void:
	if disappear_on_pickup:
		queue_free()


# ================================================================
# DATA HELPERS
# ================================================================
func _get_data_float(property_name: String, fallback: float = 0.0) -> float:
	if data == null:
		return fallback

	var value = data.get(property_name)
	if value == null:
		return fallback

	return float(value)


func _get_data_string(property_name: String, fallback: String = "") -> String:
	if data == null:
		return fallback

	var value = data.get(property_name)
	if value == null:
		return fallback

	return str(value)


func _get_data_dictionary(property_name: String) -> Dictionary:
	if data == null:
		return {}

	var value = data.get(property_name)
	if value == null:
		return {}

	if value is Dictionary:
		return value

	return {}
