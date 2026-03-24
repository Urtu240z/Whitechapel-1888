extends Area2D
class_name Pickup

# ⚙️ Esta línea se actualiza automáticamente por el plugin
@export_enum("client-medium", "client-poor", "client-rich", "cure-doctor", "cure-hostal", "cure-medicine", "cure-reset", "cure-street", "drink-absenta", "drink-cerveza", "drink-ginebra", "drink-ron", "drink-whisky", "drink-wine", "drug-eter", "drug-laudano", "food-arenque", "food-gachas", "food-pan", "food-patata", "food-sopa", "food-tocino", "health-ducha", "health-sleep-cama", "health-sleep-silla", "health-sleep-suelo", "liquid-agua", "liquid-cafe", "liquid-leche", "liquid-te", "scare-down", "scare-up", "sueño-down", "sueño-up") var pickup_type: String = "client-medium"
@export var disappear_on_pickup: bool = true

var data: ItemData

@export var info := "" : set = _set_info, get = _get_info

func _get_info() -> String:
	if pickup_type.begins_with("client-"):
		match pickup_type:
			"client-poor":   return "👤 Cliente Pobre\n💰 +1 chelín\n⚠️ 15% riesgo infección"
			"client-medium": return "👤 Cliente Medio\n💰 +3 chelines\n⚠️ 5% riesgo infección"
			"client-rich":   return "👤 Cliente Rico\n💰 +8 chelines\n⚠️ 1% riesgo infección"
	if pickup_type.begins_with("cure-"):
		match pickup_type:
			"cure-medicine": return "💊 Medicina\n Mantiene la enfermedad a raya 2 días"
			"cure-doctor":   return "🏥 Médico\n Cura completamente la enfermedad"
			"cure-hostal":   return "🛏️ Descanso Hostal\n 3 días — 40% de curar"
			"cure-street":   return "🌙 Descanso Calle\n 3 días — 15% de curar (gratis)"
			"cure-laudano":  return "🧪 Laudano\n Enmascara síntomas graves"
			"cure-reset": return "🔄 Reset\n Resetea todos los stats"
	if data == null:
		return "⚠️ Sin datos cargados"
	var text := "📜 " + data.display_name + "\n"
	text += "💰 Coste: %d peniques\n" % data.cost
	text += "🎯 Efectos:\n"
	for stat in data.effects.keys():
		text += "   %s: %.1f\n" % [stat, data.effects[stat]]
	return text.strip_edges()

func _set_info(_value: String) -> void:
	pass

func _ready() -> void:
	add_to_group("pickup")
	body_entered.connect(_on_body_entered)
	notify_property_list_changed()

	# Clientes y curas no necesitan resource
	if pickup_type.begins_with("client-") or pickup_type.begins_with("cure-"):
		return

	var pickup_path := "res://Data/Pickups/%s.tres" % pickup_type
	if ResourceLoader.exists(pickup_path):
		data = load(pickup_path)
	else:
		push_warning("⚠️ No se encontró el recurso: %s" % pickup_path)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	# =====================================================
	# 👤 CLIENTES
	# =====================================================
	if pickup_type.begins_with("client-"):
		match pickup_type:
			"client-poor":   PlayerStats.tener_sexo_poor()
			"client-medium": PlayerStats.tener_sexo_medium()
			"client-rich":   PlayerStats.tener_sexo_rich()
		if disappear_on_pickup:
			queue_free()
		return

	# =====================================================
	# 💊 CURAS
	# =====================================================
	if pickup_type.begins_with("cure-"):
		match pickup_type:
			"cure-medicine": PlayerStats.comprar_medicina()
			"cure-doctor":   PlayerStats.ir_al_medico()
			"cure-hostal":   PlayerStats.descansar_hostal()
			"cure-street":   PlayerStats.descansar_calle()
			"cure-laudano":  PlayerStats.tomar_laudano()
			"cure-reset":    PlayerStats.reset_stats() 
		if disappear_on_pickup:
			queue_free()
		return

	# =====================================================
	# 📦 PICKUPS NORMALES
	# =====================================================
	if data == null:
		push_warning("⚠️ No hay datos de pickup cargados: %s" % pickup_type)
		return

	var coste_chelines: float = data.cost / 12.0
	if PlayerStats.dinero < coste_chelines:
		print("💸 No tienes dinero suficiente (%.1f chelines requeridos)" % coste_chelines)
		return

	PlayerStats.gastar_dinero(coste_chelines)

	for stat_name in data.effects.keys():
		var valor = data.effects[stat_name]
		if not PlayerStats.has(stat_name):
			push_warning("⚠️ Stat '%s' no existe en PlayerStats." % stat_name)
			continue
		PlayerStats.set(stat_name, PlayerStats.get(stat_name) + valor)

	PlayerStats.actualizar_stats()

	if data.sound:
		var snd := AudioStreamPlayer2D.new()
		snd.stream = data.sound
		add_child(snd)
		snd.play()
		snd.finished.connect(snd.queue_free)

	if disappear_on_pickup:
		queue_free()
