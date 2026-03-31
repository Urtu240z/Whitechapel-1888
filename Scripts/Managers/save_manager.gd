extends Node
# =========================================================
# 💾 SaveManager
# Guardado desde menú de pausa (ESC)
# Carga directa sin escena intermedia
# =========================================================

const SAVE_DIR   := "user://saves/"
const SAVE_EXT   := ".sav"
const MAX_SLOTS  := 3

var _pending_data: Dictionary = {}


# =========================================================
# 💾 GUARDAR
# =========================================================
func save_game(slot: int = 0) -> bool:
	var data = _collect_data()
	var path = _slot_path(slot)
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("SaveManager: no se pudo abrir: %s" % path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("💾 Partida guardada en slot %d" % slot)
	return true


# =========================================================
# 📂 CARGAR
# =========================================================
func load_game(slot: int = 0) -> void:
	var path = _slot_path(slot)
	if not FileAccess.file_exists(path):
		push_warning("SaveManager: no existe: %s" % path)
		return

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("SaveManager: no se pudo leer: %s" % path)
		return

	var content = file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(content)
	if parsed == null:
		push_error("SaveManager: JSON inválido")
		return

	_do_load(parsed)


func _do_load(data: Dictionary) -> void:
	var escena: String = data.get("escena", "")
	if escena == "" or not FileAccess.file_exists(escena):
		push_warning("SaveManager: escena no encontrada: %s" % escena)
		return

	# Aplicar stats antes del cambio de escena
	_apply_stats(data)

	# Fade out — cambio de escena — esperar tree_changed — fade in
	await SceneManager._fade_out(0.5)
	get_tree().change_scene_to_file(escena)
	await get_tree().tree_changed
	await get_tree().process_frame
	await get_tree().process_frame
	_apply_world(data)
	
	await get_tree().create_timer(1.0).timeout
	await SceneManager._fade_in(1.0)

	# Limpiar bloqueo del SceneManager por si acaso
	SceneManager._blocking.visible = false
	SceneManager._is_transitioning = false

	print("📂 Partida cargada")


# =========================================================
# 🗑️ BORRAR
# =========================================================
func delete_save(slot: int = 0) -> void:
	var path = _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


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
		"dia":       parsed.get("dia", 1),
		"hora":      parsed.get("hora", 8.0),
		"dinero":    parsed.get("dinero", 0.0),
		"escena":    parsed.get("escena", ""),
		"timestamp": parsed.get("timestamp", ""),
	}


# =========================================================
# 📦 RECOPILAR DATOS
# =========================================================
func _collect_data() -> Dictionary:
	var player = PlayerManager.player_instance
	var pos    = player.global_position if is_instance_valid(player) else Vector2.ZERO
	var escena = get_tree().current_scene.scene_file_path if get_tree().current_scene else ""
	var outfit = player.default_outfit if is_instance_valid(player) else "London"

	# Detectar interior — guardar path exacto del edificio y posición local
	var en_interior: bool         = false
	var inside_building_path: String = ""
	var inside_local_x: float     = 0.0
	var inside_local_y: float     = 0.0

	for b in get_tree().get_nodes_in_group("buildings"):
		var entrance = b.get_node_or_null("BuildingEntrance")
		if is_instance_valid(entrance) and entrance._inside:
			en_interior = true
			inside_building_path = str(b.get_path())
			var local_pos = b.to_local(pos)
			inside_local_x = local_pos.x
			inside_local_y = local_pos.y
			break

	var equipment_data: Dictionary = {}
	for slot_key in InventoryManager.get_equipped_all():
		var item: ItemData = InventoryManager.get_equipped_all()[slot_key]
		equipment_data[str(slot_key)] = item.name if item else ""

	return {
		"version":   1,
		"timestamp": Time.get_datetime_string_from_system(),
		"escena":    escena,
		"player_x":  pos.x,
		"player_y":  pos.y,
		"outfit":    outfit,
		"en_interior":          en_interior,
		"inside_building_path": inside_building_path,
		"inside_local_x":       inside_local_x,
		"inside_local_y":       inside_local_y,
		"hora":             DayNightManager.hora_actual,
		"tiempo_acumulado": DayNightManager.tiempo_acumulado,
		"dia":              int(DayNightManager.tiempo_acumulado / (24.0 * 60.0)) + 1,
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
		"enferma":               PlayerStats.enferma,
		"medicina_activa":       PlayerStats.medicina_activa,
		"medicina_timer":        PlayerStats.medicina_timer,
		"dias_sin_pagar_hostal": PlayerStats.dias_sin_pagar_hostal,
		"pocket":    InventoryManager.get_pocket(),
		"equipment": equipment_data,
	}


# =========================================================
# 📥 APLICAR STATS — no dependen de la escena
# =========================================================
func _apply_stats(data: Dictionary) -> void:
	DayNightManager.hora_actual      = data.get("hora", 8.0)
	DayNightManager.tiempo_acumulado = data.get("tiempo_acumulado", 0.0)
	DayNightManager.pausado          = false

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
	PlayerStats.enferma         = data.get("enferma",         false)
	PlayerStats.medicina_activa = data.get("medicina_activa", false)
	PlayerStats.medicina_timer  = data.get("medicina_timer",  0.0)
	PlayerStats.dias_sin_pagar_hostal = data.get("dias_sin_pagar_hostal", 0)
	PlayerStats.actualizar_stats()

	# Limpiar inventario antes de cargar
	for item_id in InventoryManager.get_pocket().keys().duplicate():
		InventoryManager.remove_item(item_id, 999)

	var pocket: Dictionary = data.get("pocket", {})
	for item_id in pocket:
		InventoryManager.add_item(item_id, pocket[item_id])

	var equipment: Dictionary = data.get("equipment", {})
	for slot_str in equipment:
		var item_id: String = equipment[slot_str]
		if item_id != "":
			InventoryManager.equip(item_id)


# =========================================================
# 📥 APLICAR MUNDO — necesita que el player esté en el árbol
# =========================================================
func _apply_world(data: Dictionary) -> void:
	var player = PlayerManager.player_instance
	if not is_instance_valid(player):
		push_warning("SaveManager: player no encontrado")
		return

	var px: float      = data.get("player_x", 0.0)
	var py: float      = data.get("player_y", 0.0)
	var outfit: String = data.get("outfit", "London")
	var en_interior: bool     = data.get("en_interior", false)
	var building_path: String = data.get("inside_building_path", "")
	var local_x: float        = data.get("inside_local_x", 0.0)
	var local_y: float        = data.get("inside_local_y", 0.0)

	player.global_position = Vector2(px, py)
	player.set_outfit(outfit)

	if player.has_node("Movement"):
		player.get_node("Movement").enabled = true
	if player.has_node("AnimationTree"):
		player.get_node("AnimationTree").active = true

	# Restaurar interior con path exacto
	if en_interior and building_path != "":
		var building = get_tree().current_scene.get_node_or_null(building_path)
		if not is_instance_valid(building):
			# Fallback: buscar por nombre
			building = get_tree().current_scene.find_child(
				NodePath(building_path).get_name(NodePath(building_path).get_name_count() - 1),
				true, false
			)

		if is_instance_valid(building):
			var entrance = building.get_node_or_null("BuildingEntrance")
			if is_instance_valid(entrance):
				entrance.force_inside_state(true)
				player.global_position = building.to_global(Vector2(local_x, local_y))
				print("✅ Interior restaurado: ", building.name)
		else:
			push_warning("SaveManager: edificio no encontrado: %s" % building_path)

	print("✅ Partida cargada — pos: ", player.global_position)


# =========================================================
# 🔧 UTILS
# =========================================================
func _slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d" % slot + SAVE_EXT
