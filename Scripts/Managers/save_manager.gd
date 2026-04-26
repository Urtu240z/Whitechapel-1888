extends Node
# ================================================================
# SAVE MANAGER — Autoload
# ================================================================
# Orquestador de guardado/carga.
#
# Responsabilidad:
# - Leer/escribir archivos de guardado.
# - Orquestar datos de PlayerStats, InventoryManager, DayNightManager,
#   SleepManager y estado de mundo.
#
# No debe:
# - Modificar stats variable a variable si PlayerStats expone API.
# - Tocar internals del player si PlayerManager expone API.
# - Cambiar escena sin pasar por SceneManager/fade global.
# ================================================================

const SAVE_DIR: String = "user://saves/"
const SAVE_EXT: String = ".sav"
const MAX_SLOTS: int = 3
const SAVE_VERSION: int = 3
const CONFIG = preload("res://Data/Game/game_config.tres")

const LOAD_LOCK_REASON: String = "load_game"

var _busy: bool = false


# ================================================================
# API — GUARDAR
# ================================================================
func save_game(slot: int = 0) -> bool:
	if _busy:
		push_warning("SaveManager.save_game(): operación ya en curso.")
		return false

	if not _is_valid_slot(slot):
		return false

	_busy = true

	var data: Dictionary = _collect_data()
	var path: String = _slot_path(slot)

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_busy = false
		push_error("SaveManager.save_game(): no se pudo abrir: %s" % path)
		return false

	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	_busy = false
	return true


# ================================================================
# API — CARGAR
# ================================================================
func load_game(slot: int = 0) -> void:
	if _busy:
		push_warning("SaveManager.load_game(): operación ya en curso.")
		return

	if not _is_valid_slot(slot):
		return

	var path: String = _slot_path(slot)
	if not FileAccess.file_exists(path):
		push_warning("SaveManager.load_game(): no existe: %s" % path)
		return

	_busy = true

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_busy = false
		push_error("SaveManager.load_game(): no se pudo leer: %s" % path)
		return

	var content: String = file.get_as_text()
	file.close()

	var parsed_variant = JSON.parse_string(content)
	if parsed_variant == null or not (parsed_variant is Dictionary):
		_busy = false
		push_error("SaveManager.load_game(): JSON inválido o formato no Dictionary.")
		return

	var data: Dictionary = parsed_variant as Dictionary
	await _do_load(data)

	_busy = false


func _do_load(data: Dictionary) -> void:
	var world_data: Dictionary = _get_world_data(data)
	var scene_path: String = str(world_data.get("escena", data.get("escena", "")))

	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_warning("SaveManager._do_load(): escena no encontrada: %s" % scene_path)
		return

	# Datos que no dependen de la escena pueden aplicarse antes del cambio.
	_apply_persistent_data(data)

	# Carga = estado duro. Forzamos para salir limpiamente de pausa/journal/etc.
	if StateManager:
		StateManager.force_state(StateManager.State.TRANSITIONING, "load_game_start")

	PlayerManager.lock_player(LOAD_LOCK_REASON, true)
	PlayerManager.force_stop()
	SceneManager.clear_pending_portal_spawn()

	await SceneManager.fade_out(0.5, true, "load_game_fade_out")

	var err: Error = get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("SaveManager._do_load(): no se pudo cambiar a escena '%s'. Error: %s" % [scene_path, str(err)])
		await _finish_failed_load()
		return

	# Espera fuerte: la escena nueva debe estar completamente dentro del árbol
	# antes de restaurar interior/cámara/player.
	await get_tree().tree_changed
	await get_tree().process_frame
	await get_tree().process_frame

	await _apply_world(data)

	# Dejar el estado final preparado ANTES del fade in.
	# El player sigue bloqueado por LOAD_LOCK_REASON hasta acabar el fade,
	# pero PlayerManager ya puede quitar el lock de StateManager correctamente.
	if StateManager:
		StateManager.force_state(StateManager.State.GAMEPLAY, "load_game_ready")

	PlayerManager.refresh_control_from_state()

	# Frames extra para que PhantomCamera/LevelRoot/BuildingEntrance apliquen prioridades,
	# límites y follow target antes de enseñar la escena.
	await get_tree().physics_frame
	await get_tree().process_frame

	await SceneManager.fade_in(0.75, true, "load_game_fade_in")

	PlayerManager.unlock_player(LOAD_LOCK_REASON)
	_restore_player_runtime_after_load()
	PlayerManager.refresh_control_from_state()


func _finish_failed_load() -> void:
	PlayerManager.unlock_player(LOAD_LOCK_REASON)
	if StateManager:
		StateManager.force_state(StateManager.State.GAMEPLAY, "load_game_failed")
	await SceneManager.fade_in(0.35, true, "load_game_failed_fade_in")


# ================================================================
# API — BORRAR
# ================================================================
func delete_save(slot: int = 0) -> void:
	if _busy:
		push_warning("SaveManager.delete_save(): no se puede borrar mientras hay una operación en curso.")
		return

	if not _is_valid_slot(slot):
		return

	var path: String = _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# ================================================================
# API — INFO DE SLOT
# ================================================================
func slot_exists(slot: int) -> bool:
	if not _is_valid_slot(slot, false):
		return false
	return FileAccess.file_exists(_slot_path(slot))


func get_slot_info(slot: int) -> Dictionary:
	if not slot_exists(slot):
		return {}

	var file := FileAccess.open(_slot_path(slot), FileAccess.READ)
	if file == null:
		return {}

	var parsed_variant = JSON.parse_string(file.get_as_text())
	file.close()

	if parsed_variant == null or not (parsed_variant is Dictionary):
		return {}

	var data: Dictionary = parsed_variant as Dictionary
	var world_data: Dictionary = _get_world_data(data)
	var time_data: Dictionary = _get_time_data(data)
	var stats_data: Dictionary = _get_player_stats_data(data)

	var tiempo_guardado: float = float(time_data.get("tiempo_acumulado", data.get("tiempo_acumulado", 0.0)))
	var dia_guardado: int = int(time_data.get("dia", data.get("dia", 1)))

	if tiempo_guardado > 0.0:
		dia_guardado = int(floor(tiempo_guardado / (CONFIG.duracion_hora_segundos * 24.0))) + 1

	return {
		"version": int(data.get("version", 1)),
		"dia": dia_guardado,
		"hora": float(time_data.get("hora", data.get("hora", 8.0))),
		"dinero": float(stats_data.get("dinero", data.get("dinero", 0.0))),
		"escena": str(world_data.get("escena", data.get("escena", ""))),
		"timestamp": str(data.get("timestamp", "")),
	}


# ================================================================
# RECOPILAR DATOS
# ================================================================
func _collect_data() -> Dictionary:
	var world_data: Dictionary = _collect_world_data()
	var time_data: Dictionary = _collect_time_data()
	var player_stats_data: Dictionary = _collect_player_stats_data()
	var inventory_data: Dictionary = _collect_inventory_data()
	var sleep_data: Dictionary = _collect_sleep_data()
	var shop_stocks: Dictionary = _collect_shop_stocks()
	var npc_runtime_names: Dictionary = _collect_npc_runtime_names(get_tree().current_scene)

	var data: Dictionary = {
		"version": SAVE_VERSION,
		"timestamp": Time.get_datetime_string_from_system(),
		"world": world_data,
		"time": time_data,
		"player_stats": player_stats_data,
		"inventory": inventory_data,
		"sleep": sleep_data,
		"shop_stocks": shop_stocks,
		"npc_runtime_names": npc_runtime_names,
	}

	# Compatibilidad/legibilidad con saves antiguos y menús existentes.
	_add_legacy_flat_keys(data, world_data, time_data, player_stats_data, inventory_data)

	return data


func _collect_world_data() -> Dictionary:
	var player: Node = PlayerManager.get_player()
	var current_scene: Node = get_tree().current_scene

	var pos: Vector2 = Vector2.ZERO
	var scene_path: String = ""
	var outfit: String = "London"

	if is_instance_valid(player):
		pos = (player as Node2D).global_position if player is Node2D else Vector2.ZERO
		outfit = _get_player_outfit(player)

	if current_scene:
		scene_path = current_scene.scene_file_path

	var interior_data: Dictionary = _collect_interior_data(current_scene, pos)

	return {
		"escena": scene_path,
		"player_x": pos.x,
		"player_y": pos.y,
		"outfit": outfit,
		"en_interior": bool(interior_data.get("en_interior", false)),
		"inside_building_path": str(interior_data.get("inside_building_path", "")),
		"inside_local_x": float(interior_data.get("inside_local_x", 0.0)),
		"inside_local_y": float(interior_data.get("inside_local_y", 0.0)),
	}


func _collect_interior_data(current_scene: Node, player_position: Vector2) -> Dictionary:
	var result: Dictionary = {
		"en_interior": false,
		"inside_building_path": "",
		"inside_local_x": 0.0,
		"inside_local_y": 0.0,
	}

	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building):
			continue

		var entrance: Node = building.get_node_or_null("BuildingEntrance")
		if not is_instance_valid(entrance):
			continue

		if not _is_building_entrance_inside(entrance):
			continue

		result["en_interior"] = true

		if current_scene:
			result["inside_building_path"] = str(current_scene.get_path_to(building))
		else:
			result["inside_building_path"] = str(building.get_path())

		var local_pos: Vector2 = (building as Node2D).to_local(player_position) if building is Node2D else Vector2.ZERO
		result["inside_local_x"] = local_pos.x
		result["inside_local_y"] = local_pos.y
		break

	return result


func _is_building_entrance_inside(entrance: Node) -> bool:
	# Ideal futuro: añadir is_inside() a enter_building.gd.
	if entrance.has_method("is_inside"):
		return bool(entrance.call("is_inside"))

	# Fallback controlado para tu BuildingEntrance actual.
	var value = entrance.get("_inside")
	if value == null:
		return false

	return bool(value)


func _get_player_outfit(player: Node) -> String:
	if player.has_method("get_outfit_id"):
		return str(player.call("get_outfit_id"))

	var default_outfit = player.get("default_outfit")
	if default_outfit != null:
		return str(default_outfit)

	return PlayerManager.get_outfit()


func _collect_time_data() -> Dictionary:
	return {
		"hora": DayNightManager.hora_actual,
		"tiempo_acumulado": DayNightManager.tiempo_acumulado,
		"dia": DayNightManager.get_current_day(),
	}


func _collect_player_stats_data() -> Dictionary:
	var data: Dictionary = PlayerStats.get_save_data()

	# Guardamos stats base sin bonuses de equipamiento, porque InventoryManager
	# re-aplicará equipamiento al cargar. Así evitamos doble bonus.
	_subtract_equipment_bonuses_from_stats(data)

	return data


func _subtract_equipment_bonuses_from_stats(stats_data: Dictionary) -> void:
	var equipped_now: Dictionary = InventoryManager.get_equipped_all()

	for slot_key in equipped_now.keys():
		var item: ItemData = equipped_now[slot_key] as ItemData
		if item == null:
			continue

		if stats_data.has("higiene"):
			stats_data["higiene"] = float(stats_data["higiene"]) - float(item.higiene_bonus)
		if stats_data.has("nervios"):
			stats_data["nervios"] = float(stats_data["nervios"]) - float(item.nervios_bonus)
		if stats_data.has("sex_appeal_bonus"):
			stats_data["sex_appeal_bonus"] = float(stats_data["sex_appeal_bonus"]) - float(item.sex_appeal_bonus)


func _collect_inventory_data() -> Dictionary:
	return InventoryManager.get_save_data()


func _collect_sleep_data() -> Dictionary:
	if SleepManager and SleepManager.has_method("get_save_data"):
		return SleepManager.get_save_data()
	return {}


func _collect_shop_stocks() -> Dictionary:
	var result: Dictionary = {}

	for npc in get_tree().get_nodes_in_group("npc_service"):
		if not is_instance_valid(npc):
			continue
		if not npc.has_method("get_stock"):
			continue

		var service_id_value = npc.get("service_id")
		if service_id_value == null:
			continue

		var service_id: String = str(service_id_value)
		if service_id.is_empty():
			continue

		result[service_id] = npc.call("get_stock")

	return result


func _collect_npc_runtime_names(current_scene: Node) -> Dictionary:
	var result: Dictionary = {}
	var groups: Array[String] = ["npc_companion", "npc_client", "npc_service"]

	for group_name: String in groups:
		for npc in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(npc):
				continue
			if current_scene == null or not current_scene.is_ancestor_of(npc):
				continue

			var runtime_name_value = npc.get("current_display_name")
			if runtime_name_value == null:
				continue

			var runtime_name: String = str(runtime_name_value)
			if runtime_name.is_empty():
				continue

			result[str(current_scene.get_path_to(npc))] = runtime_name

	return result


func _add_legacy_flat_keys(
	data: Dictionary,
	world_data: Dictionary,
	time_data: Dictionary,
	player_stats_data: Dictionary,
	inventory_data: Dictionary
) -> void:
	for key in world_data.keys():
		data[key] = world_data[key]

	for key in time_data.keys():
		data[key] = time_data[key]

	for key in player_stats_data.keys():
		data[key] = player_stats_data[key]

	for key in inventory_data.keys():
		data[key] = inventory_data[key]


# ================================================================
# APLICAR DATOS PERSISTENTES — NO DEPENDEN DE ESCENA
# ================================================================
func _apply_persistent_data(data: Dictionary) -> void:
	_apply_time_data(data)
	_apply_player_stats_and_inventory(data)
	_apply_sleep_data(data)


func _apply_time_data(data: Dictionary) -> void:
	var time_data: Dictionary = _get_time_data(data)
	var total_time: float = float(time_data.get("tiempo_acumulado", data.get("tiempo_acumulado", 0.0)))

	DayNightManager.set_total_time(total_time, false)
	DayNightManager.set_paused(false)


func _apply_player_stats_and_inventory(data: Dictionary) -> void:
	var stats_data: Dictionary = _get_player_stats_data(data).duplicate(true)
	stats_data["medicina_timer"] = _convert_medicina_timer_from_save(data, stats_data)

	PlayerStats.apply_save_data(stats_data)
	InventoryManager.apply_save_data(_get_inventory_data(data))

	PlayerStats.sincronizar_reloj()
	PlayerStats.actualizar_stats()


func _apply_sleep_data(data: Dictionary) -> void:
	if not SleepManager or not SleepManager.has_method("apply_save_data"):
		return

	SleepManager.apply_save_data(_get_sleep_data(data))


func _convert_medicina_timer_from_save(root_data: Dictionary, stats_data: Dictionary) -> float:
	var timer: float = float(stats_data.get("medicina_timer", root_data.get("medicina_timer", 0.0)))
	var version: int = int(root_data.get("version", 1))

	# Saves antiguos guardaban segundos; ahora PlayerStats usa horas.
	if version <= 1:
		timer = timer / CONFIG.duracion_hora_segundos

	return timer


# ================================================================
# APLICAR MUNDO — NECESITA ESCENA CARGADA
# ================================================================
func _apply_world(data: Dictionary) -> void:
	var world_data: Dictionary = _get_world_data(data)
	var current_scene: Node = get_tree().current_scene

	var px: float = float(world_data.get("player_x", data.get("player_x", 0.0)))
	var py: float = float(world_data.get("player_y", data.get("player_y", 0.0)))
	var outfit: String = str(world_data.get("outfit", data.get("outfit", "London")))
	var target_position := Vector2(px, py)

	var player: Node = PlayerManager.get_player()
	if not is_instance_valid(player):
		player = PlayerManager.ensure_player(current_scene, target_position)

	if not is_instance_valid(player):
		push_warning("SaveManager._apply_world(): player no encontrado tras cargar escena.")
		return

	PlayerManager.set_player_position(target_position, true)
	PlayerManager.set_outfit(outfit)
	PlayerManager.set_animation_tree_active(true)

	await _restore_interior_if_needed(world_data)

	# Después de restaurar interior/cámara puede haber cambiado la posición final.
	# Reforzamos runtime del player antes de restaurar NPCs/stock.
	_restore_player_runtime_after_load()

	_restore_shop_stocks(_get_shop_stocks_data(data))
	_restore_npc_runtime_names(_get_npc_runtime_names_data(data))


func _restore_interior_if_needed(world_data: Dictionary) -> void:
	var en_interior: bool = bool(world_data.get("en_interior", false))
	var building_path: String = str(world_data.get("inside_building_path", ""))

	if not en_interior or building_path.is_empty():
		return

	var current_scene: Node = get_tree().current_scene
	var building: Node = _find_building_from_save_path(current_scene, building_path)

	if not is_instance_valid(building):
		push_warning("SaveManager: edificio no encontrado: %s" % building_path)
		return

	var entrance: Node = building.get_node_or_null("BuildingEntrance")
	if not is_instance_valid(entrance):
		push_warning("SaveManager: BuildingEntrance no válido en %s" % building.name)
		return

	if entrance.has_method("force_inside_state"):
		entrance.call("force_inside_state", true)
		await get_tree().process_frame

	var local_x: float = float(world_data.get("inside_local_x", 0.0))
	var local_y: float = float(world_data.get("inside_local_y", 0.0))

	if building is Node2D:
		PlayerManager.set_player_position((building as Node2D).to_global(Vector2(local_x, local_y)), true)

	# Reaplicar estado interior tras colocar al player en su posición final.
	# Esto re-fija follow target, límites y prioridad de la cámara interior.
	if entrance.has_method("force_inside_state"):
		entrance.call("force_inside_state", true)
		await get_tree().physics_frame
		await get_tree().process_frame


func _find_building_from_save_path(current_scene: Node, building_path: String) -> Node:
	if current_scene:
		var by_path: Node = current_scene.get_node_or_null(NodePath(building_path))
		if is_instance_valid(by_path):
			return by_path

	var last_name: String = building_path.get_file()
	for building in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(building) and building.name == last_name:
			return building

	return null


func _restore_shop_stocks(shop_stocks: Dictionary) -> void:
	if shop_stocks.is_empty():
		return

	for npc in get_tree().get_nodes_in_group("npc_service"):
		if not is_instance_valid(npc):
			continue
		if not npc.has_method("restore_stock"):
			continue

		var service_id_value = npc.get("service_id")
		if service_id_value == null:
			continue

		var service_id: String = str(service_id_value)
		if service_id.is_empty():
			continue

		if shop_stocks.has(service_id):
			npc.call("restore_stock", shop_stocks[service_id])


func _restore_npc_runtime_names(data: Dictionary) -> void:
	if data.is_empty():
		return

	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return

	for node_path_str in data.keys():
		var npc: Node = current_scene.get_node_or_null(NodePath(str(node_path_str)))
		if not is_instance_valid(npc):
			continue

		var runtime_name: String = str(data[node_path_str])
		if runtime_name.is_empty():
			continue

		npc.set("current_display_name", runtime_name)

		var tag: Node = npc.get_node_or_null("NameTag")
		if is_instance_valid(tag) and tag.has_method("set_text"):
			tag.call("set_text", runtime_name)


# ================================================================
# RESTAURACIÓN RUNTIME DEL PLAYER TRAS CARGA
# ================================================================
func _restore_player_runtime_after_load() -> void:
	var player: Node = PlayerManager.get_player()
	if not is_instance_valid(player):
		return

	# Estado físico base.
	if player is CharacterBody2D:
		(player as CharacterBody2D).velocity = Vector2.ZERO

	# El player root puede estar desbloqueado, pero el módulo Movement
	# puede quedar desactivado si veníamos de pausa/journal/transición.
	var movement: Node = player.get_node_or_null("Movement")
	if is_instance_valid(movement):
		movement.set("enabled", true)
		movement.set("ignore_movement_until_release", false)
		if movement.has_method("force_stop"):
			movement.call("force_stop")

	# Asegurar árbol de animación y control base sin saltarse PlayerManager.
	PlayerManager.set_animation_tree_active(true)
	PlayerManager.refresh_control_from_state()

	PlayerManager.force_stop()


# ================================================================
# LECTURA DE FORMATO NUEVO / ANTIGUO
# ================================================================
func _get_world_data(data: Dictionary) -> Dictionary:
	if data.has("world") and data["world"] is Dictionary:
		return data["world"] as Dictionary
	return data


func _get_time_data(data: Dictionary) -> Dictionary:
	if data.has("time") and data["time"] is Dictionary:
		return data["time"] as Dictionary
	return data


func _get_player_stats_data(data: Dictionary) -> Dictionary:
	if data.has("player_stats") and data["player_stats"] is Dictionary:
		return data["player_stats"] as Dictionary
	return data


func _get_inventory_data(data: Dictionary) -> Dictionary:
	if data.has("inventory") and data["inventory"] is Dictionary:
		return data["inventory"] as Dictionary
	return data


func _get_sleep_data(data: Dictionary) -> Dictionary:
	if data.has("sleep") and data["sleep"] is Dictionary:
		return data["sleep"] as Dictionary
	return {}


func _get_shop_stocks_data(data: Dictionary) -> Dictionary:
	if data.has("shop_stocks") and data["shop_stocks"] is Dictionary:
		return data["shop_stocks"] as Dictionary
	return {}


func _get_npc_runtime_names_data(data: Dictionary) -> Dictionary:
	if data.has("npc_runtime_names") and data["npc_runtime_names"] is Dictionary:
		return data["npc_runtime_names"] as Dictionary
	return {}


# ================================================================
# UTILS
# ================================================================
func _slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d" % slot + SAVE_EXT


func _is_valid_slot(slot: int, warn: bool = true) -> bool:
	var valid: bool = slot >= 0 and slot < MAX_SLOTS
	if not valid and warn:
		push_warning("SaveManager: slot inválido %d. Rango válido: 0-%d." % [slot, MAX_SLOTS - 1])
	return valid


func is_busy() -> bool:
	return _busy
