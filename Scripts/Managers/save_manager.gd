extends Node
# =========================================================
# 💾 SaveManager
# Guardado desde menú de pausa (ESC)
# =========================================================

const SAVE_DIR  := "user://saves/"
const SAVE_EXT  := ".sav"
const MAX_SLOTS := 3


# =========================================================
# 💾 GUARDAR
# =========================================================
func save_game(slot: int = 0) -> bool:
	var lista_edificios = get_tree().get_nodes_in_group("buildings")
	print("🔍 DEBUG SAVE: Edificios encontrados en el grupo: ", lista_edificios)
	var data = _collect_data()
	var path = _slot_path(slot)

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("SaveManager: no se pudo abrir el archivo: %s" % path)
		return false

	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("💾 Partida guardada en slot %d" % slot)
	return true


# =========================================================
# 📂 CARGAR
# =========================================================
func load_game(slot: int = 0) -> bool:
	var path = _slot_path(slot)

	if not FileAccess.file_exists(path):
		push_warning("SaveManager: no existe: %s" % path)
		return false

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("SaveManager: no se pudo leer: %s" % path)
		return false

	var content = file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(content)
	if parsed == null:
		push_error("SaveManager: JSON inválido")
		return false

	await _apply_data(parsed)
	print("📂 Partida cargada desde slot %d" % slot)
	return true


# =========================================================
# 🗑️ BORRAR
# =========================================================
func delete_save(slot: int = 0) -> void:
	var path = _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		print("🗑️ Partida borrada en slot %d" % slot)


# =========================================================
# 🔍 INFO DE SLOT
# =========================================================
func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


func get_slot_info(slot: int) -> Dictionary:
	if not slot_exists(slot):
		return {}

	var file = FileAccess.open(_slot_path(slot), FileAccess.READ)
	if not file:
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()

	if parsed == null:
		return {}

	return {
		"dia":    parsed.get("dia", 1),
		"hora":   parsed.get("hora", 8.0),
		"dinero": parsed.get("dinero", 0.0),
		"escena": parsed.get("escena", ""),
		"timestamp": parsed.get("timestamp", ""),
	}


# =========================================================
# 📦 RECOPILAR DATOS
# =========================================================
func _collect_data() -> Dictionary:
	var player = PlayerManager.player_instance
	var pos = player.global_position if is_instance_valid(player) else Vector2.ZERO
	var escena = get_tree().current_scene.scene_file_path if get_tree().current_scene else ""
	var outfit = player.default_outfit if is_instance_valid(player) else "London"
	
	# DETECCIÓN DE INTERIOR
	var esta_dentro = false
	for b in get_tree().get_nodes_in_group("buildings"):
		var entrance = b.get_node_or_null("BuildingEntrance")
		if is_instance_valid(entrance):
			# CAMBIO CLAVE: Buscamos _inside, que es como se llama en tu script
			if entrance._inside == true: 
				esta_dentro = true
				break
	# Equipamiento: convertir enum keys a string
	var equipment_data: Dictionary = {}
	for slot_key in InventoryManager.get_equipped_all():
		var item: ItemData = InventoryManager.get_equipped_all()[slot_key]
		equipment_data[str(slot_key)] = item.name if item else ""

	return {
		# Metadata
		"version":   1,
		"timestamp": Time.get_datetime_string_from_system(),

		# Mundo
		"escena":   escena,
		"player_x": pos.x,
		"player_y": pos.y,
		"en_interior": esta_dentro,
		"outfit":   outfit,
		
		# Tiempo
		"hora":             DayNightManager.hora_actual,
		"tiempo_acumulado": DayNightManager.tiempo_acumulado,
		"dia":              int(DayNightManager.tiempo_acumulado / (24.0 * 60.0)) + 1,

		# Stats básicos
		"miedo":      PlayerStats.miedo,
		"estres":     PlayerStats.estres,
		"felicidad":  PlayerStats.felicidad,
		"nervios":    PlayerStats.nervios,
		"hambre":     PlayerStats.hambre,
		"higiene":    PlayerStats.higiene,
		"sueno":      PlayerStats.sueno,
		"alcohol":    PlayerStats.alcohol,
		"laudano":    PlayerStats.laudano,
		"salud":      PlayerStats.salud,
		"stamina":    PlayerStats.stamina,
		"enfermedad": PlayerStats.enfermedad,
		"dinero":     PlayerStats.dinero,

		# Estado enfermedad
		"enferma":          PlayerStats.enferma,
		"medicina_activa":  PlayerStats.medicina_activa,
		"medicina_timer":   PlayerStats.medicina_timer,

		# Economía
		"dias_sin_pagar_hostal": PlayerStats.dias_sin_pagar_hostal,

		# Inventario
		"pocket":    InventoryManager.get_pocket(),
		"equipment": equipment_data,
	}


# =========================================================
# 📥 APLICAR DATOS
# =========================================================
func _apply_data(data: Dictionary) -> void:
	# Tiempo
	DayNightManager.hora_actual      = data.get("hora", 8.0)
	DayNightManager.tiempo_acumulado = data.get("tiempo_acumulado", 0.0)
	DayNightManager.pausado          = false  # siempre reanudar al cargar

	# Stats básicos
	PlayerStats.miedo      = data.get("miedo",      10.0)
	PlayerStats.estres     = data.get("estres",      30.0)
	PlayerStats.felicidad  = data.get("felicidad",   50.0)
	PlayerStats.nervios    = data.get("nervios",     20.0)
	PlayerStats.hambre     = data.get("hambre",      50.0)
	PlayerStats.higiene    = data.get("higiene",     70.0)
	PlayerStats.sueno      = data.get("sueno",       80.0)
	PlayerStats.alcohol    = data.get("alcohol",     0.0)
	PlayerStats.laudano    = data.get("laudano",     0.0)
	PlayerStats.salud      = data.get("salud",       100.0)
	PlayerStats.stamina    = data.get("stamina",     100.0)
	PlayerStats.enfermedad = data.get("enfermedad",  0.0)
	PlayerStats.dinero     = data.get("dinero",      5.0)

	# Estado enfermedad
	PlayerStats.enferma         = data.get("enferma",         false)
	PlayerStats.medicina_activa = data.get("medicina_activa", false)
	PlayerStats.medicina_timer  = data.get("medicina_timer",  0.0)

	# Economía
	PlayerStats.dias_sin_pagar_hostal = data.get("dias_sin_pagar_hostal", 0)

	PlayerStats.actualizar_stats()

	# Inventario — limpiar antes de cargar
	# (evita duplicados si se carga sobre una partida en curso)
	for item_id in InventoryManager.get_pocket().keys():
		InventoryManager.remove_item(item_id, InventoryManager.get_pocket()[item_id])

	var pocket: Dictionary = data.get("pocket", {})
	for item_id in pocket:
		InventoryManager.add_item(item_id, pocket[item_id])

	var equipment: Dictionary = data.get("equipment", {})
	for slot_str in equipment:
		var item_id: String = equipment[slot_str]
		if item_id != "":
			InventoryManager.equip(item_id)

	# Escena y posición del player
	var escena: String = data.get("escena", "")
	var px: float = data.get("player_x", 0.0)
	var py: float = data.get("player_y", 0.0)
	var outfit: String = data.get("outfit", "London")
	var en_interior: bool = data.get("en_interior", false)

	if escena != "" and FileAccess.file_exists(escena):
		await SceneManager._fade_out(0.3)
		get_tree().change_scene_to_file(escena)
		
		# Damos 2 frames para que los edificios en el grupo "buildings" se registren
		await get_tree().process_frame
		await get_tree().process_frame

		var player = PlayerManager.player_instance
		if is_instance_valid(player):
			player.global_position = Vector2(px, py)
			player.set_outfit(outfit)
			if "velocity" in player: player.velocity = Vector2.ZERO

			if en_interior:
				var edificios = get_tree().get_nodes_in_group("buildings")
				print("📂 Cargando interior. Edificios en escena: ", edificios.size())
				
				for b in edificios:
					# Usamos una distancia amplia (800) porque a veces el origen del 
					# edificio está lejos de donde aparece el jugador dentro
					var distancia = b.global_position.distance_to(player.global_position)
					
					if distancia < 800:
						var entrance = b.get_node_or_null("BuildingEntrance")
						if is_instance_valid(entrance) and entrance.has_method("force_inside_state"):
							print("✅ Edificio detectado para carga: ", b.name)
							entrance.force_inside_state(true)
							break

		await SceneManager._fade_in(0.5)


# =========================================================
# 🔧 UTILS
# =========================================================
func _slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d" % slot + SAVE_EXT
