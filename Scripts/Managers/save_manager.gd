extends Node
# =========================================================
# 💾 SaveManager
# Guardado desde menú de pausa (ESC)
# Carga directa sin escena intermedia
# =========================================================

const SAVE_DIR   := "user://saves/"
const SAVE_EXT   := ".sav"
const MAX_SLOTS  := 3
const CONFIG = preload("res://Data/Game/game_config.tres")

var _busy: bool = false


# =========================================================
# 💾 GUARDAR
# =========================================================
func save_game(slot: int = 0) -> bool:
	if _busy:
		push_warning("SaveManager: operación ya en curso")
		return false

	_busy = true

	var data = _collect_data()
	var path = _slot_path(slot)

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		_busy = false
		push_error("SaveManager: no se pudo abrir: %s" % path)
		return false

	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	_busy = false
	print("💾 Partida guardada en slot %d" % slot)
	_log_stats("SAVE")
	return true


# =========================================================
# 📂 CARGAR
# =========================================================
func load_game(slot: int = 0) -> void:
	if _busy:
		push_warning("SaveManager: operación ya en curso")
		return

	_busy = true

	var path = _slot_path(slot)
	if not FileAccess.file_exists(path):
		_busy = false
		push_warning("SaveManager: no existe: %s" % path)
		return

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		_busy = false
		push_error("SaveManager: no se pudo leer: %s" % path)
		return

	var content = file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(content)
	if parsed == null:
		_busy = false
		push_error("SaveManager: JSON inválido")
		return

	await _do_load(parsed)
	_busy = false


func _do_load(data: Dictionary) -> void:
	var escena: String = data.get("escena", "")
	if escena == "" or not FileAccess.file_exists(escena):
		push_warning("SaveManager: escena no encontrada: %s" % escena)
		return

	_apply_stats(data)

	await SceneManager.fade_out(0.5)
	get_tree().change_scene_to_file(escena)
	await get_tree().tree_changed
	await get_tree().process_frame
	await get_tree().process_frame

	await _apply_world(data)

	await get_tree().create_timer(1.0).timeout
	await SceneManager.fade_in(1.0)

	print("📂 Partida cargada")


# =========================================================
# 🗑️ BORRAR
# =========================================================
func delete_save(slot: int = 0) -> void:
	if _busy:
		push_warning("SaveManager: no se puede borrar mientras hay una operación en curso")
		return

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

	var tiempo_guardado := float(parsed.get("tiempo_acumulado", 0.0))
	var dia_guardado: int = int(parsed.get("dia", 1))
	if parsed.has("tiempo_acumulado"):
		dia_guardado = int(floor(tiempo_guardado / (CONFIG.duracion_hora_segundos * 24.0))) + 1

	return {
		"dia":       dia_guardado,
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
	var current_scene = get_tree().current_scene

	var pos := Vector2.ZERO
	var escena := ""
	var outfit := "London"

	if is_instance_valid(player):
		pos = player.global_position

		if player.has_method("get_outfit_id"):
			outfit = player.get_outfit_id()
		else:
			outfit = player.default_outfit

	if current_scene:
		escena = current_scene.scene_file_path

	# Detectar interior
	var en_interior: bool = false
	var inside_building_path: String = ""
	var inside_local_x: float = 0.0
	var inside_local_y: float = 0.0

	for b in get_tree().get_nodes_in_group("buildings"):
		var entrance = b.get_node_or_null("BuildingEntrance")
		if is_instance_valid(entrance) and entrance._inside:
			en_interior = true

			if current_scene:
				inside_building_path = str(current_scene.get_path_to(b))
			else:
				inside_building_path = str(b.get_path())

			var local_pos = b.to_local(pos)
			inside_local_x = local_pos.x
			inside_local_y = local_pos.y
			break

	# Calcular stats base SIN bonuses de equipamiento
	var higiene_base := PlayerStats.higiene
	var nervios_base := PlayerStats.nervios
	var sex_appeal_bonus_base := PlayerStats.sex_appeal_bonus

	var equipment_data: Dictionary = {}
	var equipped_now: Dictionary = InventoryManager.get_equipped_all()
	for slot_key in equipped_now.keys():
		var item: ItemData = equipped_now[slot_key]
		if item:
			higiene_base -= item.higiene_bonus
			nervios_base -= item.nervios_bonus
			sex_appeal_bonus_base -= item.sex_appeal_bonus
			var horas: int = 0
			if item.duracion_horas > 0:
				horas = InventoryManager.get_equip_timer(slot_key)
			equipment_data[str(slot_key)] = {
				"id": item.name,
				"horas": horas
			}

	# Recopilar stock de todos los vendedores
	var shop_stocks: Dictionary = {}
	for npc in get_tree().get_nodes_in_group("npc_service"):
		if npc.shop_items.size() > 0 and not npc.service_id.is_empty():
			shop_stocks[npc.service_id] = npc.get_stock()

	return {
		"version":   2,
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
		"dia":              DayNightManager.get_current_day(),

		"miedo":            PlayerStats.miedo,
		"estres":           PlayerStats.estres,
		"felicidad":        PlayerStats.felicidad,
		"nervios":          nervios_base,
		"hambre":           PlayerStats.hambre,
		"higiene":          higiene_base,
		"sueno":            PlayerStats.sueno,
		"alcohol":          PlayerStats.alcohol,
		"laudano":          PlayerStats.laudano,
		"salud":            PlayerStats.salud,
		"stamina":          PlayerStats.stamina,
		"enfermedad":       PlayerStats.enfermedad,
		"dinero":           PlayerStats.dinero,
		"sex_appeal_bonus": sex_appeal_bonus_base,

		"enferma":               PlayerStats.enferma,
		"medicina_activa":       PlayerStats.medicina_activa,
		"medicina_timer":        PlayerStats.medicina_timer,
		"dias_sin_pagar_hostal": PlayerStats.dias_sin_pagar_hostal,

		"pocket":         InventoryManager.get_pocket_serializable(),
		"bolso_contents": InventoryManager.get_bolso_contents_serializable(),
		"equipment":      equipment_data,
		"shop_stocks":    shop_stocks,
	}


# =========================================================
# 📥 APLICAR STATS — no dependen de la escena
# =========================================================
func _apply_stats(data: Dictionary) -> void:
	DayNightManager.set_total_time(data.get("tiempo_acumulado", 0.0), false)
	DayNightManager.pausado = false

	PlayerStats.miedo            = data.get("miedo", 10.0)
	PlayerStats.estres           = data.get("estres", 30.0)
	PlayerStats.felicidad        = data.get("felicidad", 50.0)
	PlayerStats.nervios          = data.get("nervios", 20.0)
	PlayerStats.hambre           = data.get("hambre", 50.0)
	PlayerStats.higiene          = data.get("higiene", 70.0)
	PlayerStats.sueno            = data.get("sueno", 80.0)
	PlayerStats.alcohol          = data.get("alcohol", 0.0)
	PlayerStats.laudano          = data.get("laudano", 0.0)
	PlayerStats.salud            = data.get("salud", 100.0)
	PlayerStats.stamina          = data.get("stamina", 100.0)
	PlayerStats.enfermedad       = data.get("enfermedad", 0.0)
	PlayerStats.dinero           = data.get("dinero", 5.0)
	PlayerStats.sex_appeal_bonus = data.get("sex_appeal_bonus", 0.0)

	PlayerStats.enferma               = data.get("enferma", false)
	PlayerStats.medicina_activa       = data.get("medicina_activa", false)
	PlayerStats.medicina_timer        = _convert_medicina_timer_from_save(data)
	PlayerStats.dias_sin_pagar_hostal = data.get("dias_sin_pagar_hostal", 0)

	# 1) Limpiar equipamiento
	InventoryManager.clear_all_equipped()

	# 2) Limpiar inventario y bolso
	for i in range(InventoryManager.MAX_SLOTS):
		if InventoryManager.get_slot(i) != {}:
			InventoryManager.remove_item_from_slot(i, 999)

	# 3) Restaurar contenido del bolso desequipado
	var bolso_contents: Array = data.get("bolso_contents", [])
	InventoryManager.restore_bolso_contents_from_save(bolso_contents)

	# 4) Restaurar bolsillo
	var pocket: Array = data.get("pocket", [])
	InventoryManager.restore_pocket_from_serializable(pocket)

	# 5) Restaurar equipamiento — aplica bonuses encima de los valores base
	var equipment: Dictionary = data.get("equipment", {})
	for slot_str in equipment:
		var entry: Dictionary = equipment[slot_str]
		var item_id: String = entry.get("id", "")
		var horas: int = entry.get("horas", 0)
		if item_id != "":
			InventoryManager.restore_equipped_from_save(int(slot_str), item_id, horas)

	PlayerStats.sincronizar_reloj()
	PlayerStats.actualizar_stats()
	_log_stats("LOAD")


func _convert_medicina_timer_from_save(data: Dictionary) -> float:
	var timer := float(data.get("medicina_timer", 0.0))
	var version := int(data.get("version", 1))
	if version <= 1:
		timer = timer / CONFIG.duracion_hora_segundos
	return timer


# =========================================================
# 📥 APLICAR MUNDO — necesita que el player esté en el árbol
# =========================================================
func _apply_world(data: Dictionary) -> void:
	var player = PlayerManager.player_instance
	if not is_instance_valid(player):
		push_warning("SaveManager: player no encontrado")
		return

	var px: float = data.get("player_x", 0.0)
	var py: float = data.get("player_y", 0.0)
	var outfit: String = data.get("outfit", "London")

	var en_interior: bool = data.get("en_interior", false)
	var building_path: String = data.get("inside_building_path", "")
	var local_x: float = data.get("inside_local_x", 0.0)
	var local_y: float = data.get("inside_local_y", 0.0)

	player.global_position = Vector2(px, py)
	player.set_outfit(outfit)
	player.velocity = Vector2.ZERO

	if player.has_node("Movement"):
		player.get_node("Movement").enabled = true
	if player.has_node("AnimationTree"):
		player.get_node("AnimationTree").active = true

	# Restaurar interior
	if en_interior and building_path != "":
		var current_scene = get_tree().current_scene
		var building = null

		if current_scene:
			building = current_scene.get_node_or_null(NodePath(building_path))

		if not is_instance_valid(building):
			var last_name := building_path.get_file()
			for b in get_tree().get_nodes_in_group("buildings"):
				if b.name == last_name:
					building = b
					break

		if is_instance_valid(building):
			var entrance = building.get_node_or_null("BuildingEntrance")
			if is_instance_valid(entrance):
				entrance.force_inside_state(true)
				await get_tree().process_frame
				player.global_position = building.to_global(Vector2(local_x, local_y))
				print("✅ Interior restaurado: ", building.name)
			else:
				push_warning("SaveManager: BuildingEntrance no válido en %s" % building.name)
		else:
			push_warning("SaveManager: edificio no encontrado: %s" % building_path)

	# Restaurar stock de vendedores
	var shop_stocks: Dictionary = data.get("shop_stocks", {})
	for npc in get_tree().get_nodes_in_group("npc_service"):
		if shop_stocks.has(npc.service_id):
			npc.restore_stock(shop_stocks[npc.service_id])

	print("✅ Partida cargada — pos: ", player.global_position)


# =========================================================
# 🔧 UTILS
# =========================================================
func _slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d" % slot + SAVE_EXT

func is_busy() -> bool:
	return _busy

func _log_stats(label: String) -> void:
	print("📊 [%s] dinero: %.1f | higiene: %.1f | sex_appeal: %.1f | sex_appeal_bonus: %.1f | perfume: %s" % [
		label,
		PlayerStats.dinero,
		PlayerStats.higiene,
		PlayerStats.sex_appeal,
		PlayerStats.sex_appeal_bonus,
		str(InventoryManager.get_equipped(ItemData.EquipSlot.NECK_PERFUME))
	])
