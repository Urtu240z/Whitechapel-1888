extends Node
# ================================================================
# INVENTORY MANAGER — Autoload
# ================================================================
# Autoridad de inventario/equipamiento.
#
# Responsabilidad de este manager:
# - Bolsillo posicional de 12 slots, con 6 activos base.
# - Bolso / ampliación de slots.
# - Añadir, quitar, mover y usar objetos.
# - Equipar / desequipar.
# - Serialización del inventario.
#
# Lo que NO debe hacer directamente:
# - Modificar variables sueltas de PlayerStats con set/get manual.
#   Para eso usa la API oficial de PlayerStats:
#     apply_stat_deltas()
#     apply_equipment_bonus()
#     remove_equipment_bonus()
# ================================================================

signal inventory_changed
signal item_equipped(slot: ItemData.EquipSlot, item: ItemData)
signal item_unequipped(slot: ItemData.EquipSlot)
signal item_used(item: ItemData)
signal perfume_already_active
signal item_add_failed(item_id: String, quantity_left: int)
signal item_removed(item_id: String, quantity: int)

const MAX_SLOTS_BASE: int = 6
const MAX_SLOTS_CON_BOLSO: int = 12
const MAX_SLOTS: int = 12

var _slots_activos: int = MAX_SLOTS_BASE
var _pocket: Array = []
var _item_db: Dictionary = {}
var _equipped: Dictionary = {}
var _equip_timers: Dictionary = {}

# Contenido de los slots 6-11 cuando el bolso está desequipado.
# Así no se pierden objetos al quitar el bolso.
var _bolso_contents: Array = []


# ================================================================
# INIT
# ================================================================
func _ready() -> void:
	_pocket.resize(MAX_SLOTS)
	_slots_activos = MAX_SLOTS_BASE

	_load_item_database()

	if DayNightManager and not DayNightManager.hora_cambiada.is_connected(_on_hora_cambiada):
		DayNightManager.hora_cambiada.connect(_on_hora_cambiada)


func _load_item_database() -> void:
	_item_db.clear()
	_load_items_from_folder("res://Data/Pickups/")
	_load_items_from_folder("res://Data/Equip/")


func _load_items_from_folder(path: String) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return

	dir.list_dir_begin()
	var file := dir.get_next()

	while file != "":
		if file.ends_with(".tres"):
			var item := load(path + file) as ItemData
			if item and not item.name.is_empty():
				_item_db[item.name] = item

		file = dir.get_next()

	dir.list_dir_end()


# ================================================================
# HORA — TIMERS DE EQUIPAMIENTO TEMPORAL
# ================================================================
func _on_hora_cambiada(_hora: float) -> void:
	var slots_a_quitar: Array = []

	for slot in _equip_timers.keys():
		_equip_timers[slot] = int(_equip_timers[slot]) - 1
		if int(_equip_timers[slot]) <= 0:
			slots_a_quitar.append(slot)

	for slot in slots_a_quitar:
		_equip_timers.erase(slot)
		_unequip_temporal(slot)


func _unequip_temporal(slot: ItemData.EquipSlot) -> void:
	if not _equipped.has(slot):
		return

	var item: ItemData = _equipped[slot]
	_remove_equipment_bonuses(item, "temporal_expired")
	_equipped.erase(slot)

	item_unequipped.emit(slot)
	inventory_changed.emit()


# ================================================================
# BOLSILLO POSICIONAL
# ================================================================
func add_item(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0:
		return true

	var item := get_item_data(item_id)
	if not item:
		push_warning("InventoryManager.add_item(): item '%s' no existe en la DB." % item_id)
		return false

	var restante: int = quantity

	# 1. Rellenar stacks existentes.
	for i in range(_slots_activos):
		if restante <= 0:
			break

		if _pocket[i] == null:
			continue

		if str(_pocket[i].get("id", "")) != item_id:
			continue

		var current: int = int(_pocket[i].get("qty", 0))
		if current >= item.max_stack:
			continue

		var caben: int = item.max_stack - current
		var a_meter: int = min(restante, caben)
		_pocket[i]["qty"] = current + a_meter
		restante -= a_meter

	# 2. Abrir slots nuevos.
	for i in range(_slots_activos):
		if restante <= 0:
			break

		if _pocket[i] == null:
			var a_meter: int = min(restante, item.max_stack)
			_pocket[i] = { "id": item_id, "qty": a_meter }
			restante -= a_meter

	inventory_changed.emit()

	if restante > 0:
		push_warning("InventoryManager.add_item(): inventario lleno, no caben %d unidades de '%s'." % [restante, item_id])
		item_add_failed.emit(item_id, restante)
		return false

	return true


func add_item_to_slot(item_id: String, slot_index: int, quantity: int = 1) -> bool:
	if quantity <= 0:
		return true

	if not _is_valid_slot(slot_index):
		return false

	var item := get_item_data(item_id)
	if not item:
		return false

	if quantity > item.max_stack:
		push_warning("InventoryManager.add_item_to_slot(): quantity %d supera max_stack %d para '%s'." % [quantity, item.max_stack, item_id])
		return false

	if _pocket[slot_index] != null:
		push_warning("InventoryManager.add_item_to_slot(): slot %d ocupado." % slot_index)
		return false

	_pocket[slot_index] = { "id": item_id, "qty": quantity }
	inventory_changed.emit()
	return true


func remove_item(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0:
		return true

	if not has_item(item_id, quantity):
		return false

	var restante: int = quantity

	for i in range(MAX_SLOTS):
		if restante <= 0:
			break

		if _pocket[i] == null:
			continue

		if str(_pocket[i].get("id", "")) != item_id:
			continue

		var current: int = int(_pocket[i].get("qty", 0))
		var quitar: int = min(restante, current)
		current -= quitar
		restante -= quitar

		if current <= 0:
			_pocket[i] = null
		else:
			_pocket[i]["qty"] = current

	inventory_changed.emit()
	item_removed.emit(item_id, quantity)
	return true


func remove_item_from_slot(slot_index: int, quantity: int = 1) -> bool:
	if quantity <= 0:
		return true

	if not _is_valid_slot(slot_index):
		return false

	if _pocket[slot_index] == null:
		return false

	var item_id: String = str(_pocket[slot_index].get("id", ""))
	var current: int = int(_pocket[slot_index].get("qty", 0))
	var quitar: int = min(quantity, current)

	current -= quitar

	if current <= 0:
		_pocket[slot_index] = null
	else:
		_pocket[slot_index]["qty"] = current

	inventory_changed.emit()	
	item_removed.emit(item_id, quitar)
	return true


func move_item(from_slot: int, to_slot: int) -> bool:
	if not _is_valid_slot(from_slot):
		return false

	if not _is_valid_slot(to_slot):
		return false

	var temp = _pocket[to_slot]
	_pocket[to_slot] = _pocket[from_slot]
	_pocket[from_slot] = temp
	inventory_changed.emit()
	return true


func has_item(item_id: String, quantity: int = 1) -> bool:
	var total: int = 0

	for i in range(MAX_SLOTS):
		if _pocket[i] != null and str(_pocket[i].get("id", "")) == item_id:
			total += int(_pocket[i].get("qty", 0))

	return total >= quantity


func can_add_item(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0:
		return true

	var item := get_item_data(item_id)
	if not item:
		return false

	var restante: int = quantity

	for i in range(_slots_activos):
		if restante <= 0:
			return true

		if _pocket[i] == null:
			restante -= item.max_stack
			continue

		if str(_pocket[i].get("id", "")) == item_id:
			var current: int = int(_pocket[i].get("qty", 0))
			restante -= max(0, item.max_stack - current)

	return restante <= 0


func get_slot(slot_index: int) -> Dictionary:
	if not _is_valid_slot(slot_index):
		return {}

	return _pocket[slot_index] if _pocket[slot_index] != null else {}


func use_item_from_slot(slot_index: int) -> bool:
	if not _is_valid_slot(slot_index):
		return false

	if _pocket[slot_index] == null:
		return false

	var item_id: String = str(_pocket[slot_index].get("id", ""))
	var item := get_item_data(item_id)
	if not item:
		return false

	# Perfume — flujo especial temporal.
	if item.equip_slot == ItemData.EquipSlot.NECK_PERFUME:
		return _apply_perfume(slot_index, item)

	# Equipable normal.
	if item.item_type == ItemData.ItemType.EQUIPPABLE:
		return equip_from_slot(slot_index)

	# Consumible.
	_apply_consumable_effects(item)
	remove_item_from_slot(slot_index, 1)
	item_used.emit(item)
	return true


func use_item(item_id: String) -> bool:
	for i in range(MAX_SLOTS):
		if _pocket[i] != null and str(_pocket[i].get("id", "")) == item_id:
			return use_item_from_slot(i)

	return false


func _pocket_count() -> int:
	var count: int = 0

	for i in range(MAX_SLOTS):
		if _pocket[i] != null:
			count += 1

	return count


# ================================================================
# PERFUME — FLUJO ESPECIAL
# ================================================================
func _apply_perfume(slot_index: int, item: ItemData) -> bool:
	if _equipped.has(ItemData.EquipSlot.NECK_PERFUME):
		perfume_already_active.emit()
		return false

	remove_item_from_slot(slot_index, 1)

	_equipped[ItemData.EquipSlot.NECK_PERFUME] = item
	_equip_timers[ItemData.EquipSlot.NECK_PERFUME] = int(item.duracion_horas)

	_apply_equipment_bonuses(item, "equip_perfume")

	item_equipped.emit(ItemData.EquipSlot.NECK_PERFUME, item)
	inventory_changed.emit()
	return true


# ================================================================
# EQUIPAMIENTO
# ================================================================
func equip_from_slot(slot_index: int) -> bool:
	if not _is_valid_slot(slot_index):
		return false

	if _pocket[slot_index] == null:
		return false

	var item_id: String = str(_pocket[slot_index].get("id", ""))
	var item := get_item_data(item_id)
	if not item:
		return false

	if item.equip_slot == ItemData.EquipSlot.NONE:
		return false

	if _equipped.has(item.equip_slot):
		if not unequip(item.equip_slot):
			return false

	_equipped[item.equip_slot] = item
	_pocket[slot_index] = null

	# Equipable normal: mantiene la semántica previa.
	# - item.effects se aplica mientras está equipado.
	# - item.amplia_slots activa/desactiva el bolso.
	_apply_item_stat_effects(item, "equip_item_%s" % item.name)
	_apply_bag_capacity_if_needed(item)

	item_equipped.emit(item.equip_slot, item)
	inventory_changed.emit()
	return true


func equip(item_id: String) -> bool:
	for i in range(MAX_SLOTS):
		if _pocket[i] != null and str(_pocket[i].get("id", "")) == item_id:
			return equip_from_slot(i)

	return false


func unequip(slot: ItemData.EquipSlot) -> bool:
	if not _equipped.has(slot):
		return false

	var item: ItemData = _equipped[slot]

	if item.equip_slot != ItemData.EquipSlot.NECK_PERFUME:
		if not can_add_item(item.name, 1):
			push_warning("InventoryManager.unequip(): no se puede desequipar '%s', inventario lleno." % item.name)
			return false

	if item.equip_slot == ItemData.EquipSlot.NECK_PERFUME:
		_remove_equipment_bonuses(item, "unequip_perfume")
	else:
		_remove_item_stat_effects(item, "unequip_item_%s" % item.name)
		_remove_bag_capacity_if_needed(item)

	_equipped.erase(slot)
	_equip_timers.erase(slot)

	if item.equip_slot != ItemData.EquipSlot.NECK_PERFUME:
		add_item(item.name, 1)

	item_unequipped.emit(slot)
	inventory_changed.emit()
	return true


func _puede_añadir(item_id: String) -> bool:
	# Compatibilidad con llamadas antiguas.
	return can_add_item(item_id, 1)


func unequip_perfume_on_shower() -> void:
	if not _equipped.has(ItemData.EquipSlot.NECK_PERFUME):
		return

	_unequip_temporal(ItemData.EquipSlot.NECK_PERFUME)
	_equip_timers.erase(ItemData.EquipSlot.NECK_PERFUME)


func get_equipped(slot: ItemData.EquipSlot) -> ItemData:
	return _equipped.get(slot, null)


func get_perfume_horas_restantes() -> int:
	return int(_equip_timers.get(ItemData.EquipSlot.NECK_PERFUME, 0))


func get_equip_timer(slot: ItemData.EquipSlot) -> int:
	return int(_equip_timers.get(slot, 0))


# ================================================================
# EFECTOS — CONSUMIBLES / EQUIPABLES
# ================================================================
func _apply_consumable_effects(item: ItemData) -> void:
	_apply_item_stat_effects(item, "use_item_%s" % item.name)

	if item.quita_perfume:
		unequip_perfume_on_shower()

	if item.amplia_slots:
		_apply_bag_capacity_if_needed(item)


func _apply_item_stat_effects(item: ItemData, reason: String) -> void:
	if item == null:
		return

	var deltas: Dictionary = _get_item_effect_deltas(item)
	if deltas.is_empty():
		return

	PlayerStats.apply_stat_deltas(deltas, reason)


func _remove_item_stat_effects(item: ItemData, reason: String) -> void:
	if item == null:
		return

	var deltas: Dictionary = _get_item_effect_deltas(item)
	if deltas.is_empty():
		return

	var inverse: Dictionary = {}
	for key in deltas.keys():
		inverse[key] = -float(deltas[key])

	PlayerStats.apply_stat_deltas(inverse, reason)


func _get_item_effect_deltas(item: ItemData) -> Dictionary:
	var result: Dictionary = {}

	if item == null:
		return result

	for raw_key in item.effects.keys():
		var stat_name := str(raw_key)
		var value := float(item.effects[raw_key])

		if is_zero_approx(value):
			continue

		if not PlayerStats.has(stat_name):
			push_warning("InventoryManager: stat '%s' no existe en PlayerStats. Item: %s" % [stat_name, item.name])
			continue

		result[stat_name] = value

	return result


# Compatibilidad con nombres anteriores.
func _apply_effects(item: ItemData) -> void:
	_apply_consumable_effects(item)


func _remove_effects(item: ItemData) -> void:
	_remove_item_stat_effects(item, "remove_item_%s" % item.name)
	_remove_bag_capacity_if_needed(item)


# ================================================================
# BONUSES — PERFUMES / EQUIPABLES TEMPORALES
# ================================================================
func _apply_equipment_bonuses(item: ItemData, reason: String = "equip_bonus") -> void:
	if item == null:
		return

	PlayerStats.apply_equipment_bonus(item, reason)
	_apply_bag_capacity_if_needed(item)


func _remove_equipment_bonuses(item: ItemData, reason: String = "remove_bonus") -> void:
	if item == null:
		return

	PlayerStats.remove_equipment_bonus(item, reason)
	_remove_bag_capacity_if_needed(item)


# Compatibilidad con nombres anteriores.
func _apply_equip_bonuses(item: ItemData) -> void:
	_apply_equipment_bonuses(item, "legacy_apply_equip_bonuses")


func _remove_equip_bonuses(item: ItemData) -> void:
	_remove_equipment_bonuses(item, "legacy_remove_equip_bonuses")


# ================================================================
# BOLSO / SLOTS EXTRA
# ================================================================
func _apply_bag_capacity_if_needed(item: ItemData) -> void:
	if item == null or not item.amplia_slots:
		return

	if _slots_activos == MAX_SLOTS_CON_BOLSO:
		return

	_slots_activos = MAX_SLOTS_CON_BOLSO

	for i in range(_bolso_contents.size()):
		var target_slot: int = MAX_SLOTS_BASE + i
		if target_slot >= MAX_SLOTS_CON_BOLSO:
			break
		_pocket[target_slot] = _bolso_contents[i]

	_bolso_contents = []
	inventory_changed.emit()


func _remove_bag_capacity_if_needed(item: ItemData) -> void:
	if item == null or not item.amplia_slots:
		return

	if _slots_activos == MAX_SLOTS_BASE:
		return

	_bolso_contents = []

	for i in range(MAX_SLOTS_BASE, MAX_SLOTS_CON_BOLSO):
		_bolso_contents.append(_pocket[i])
		_pocket[i] = null

	_slots_activos = MAX_SLOTS_BASE
	inventory_changed.emit()


# ================================================================
# UTILS / GETTERS
# ================================================================
func get_item_data(item_id: String) -> ItemData:
	return _item_db.get(item_id, null)


func get_pocket() -> Array:
	return _pocket.slice(0, _slots_activos)


func get_slots_activos() -> int:
	return _slots_activos


func tiene_bolso() -> bool:
	return _slots_activos == MAX_SLOTS_CON_BOLSO


func get_equipped_all() -> Dictionary:
	return _equipped.duplicate()


func get_item_database_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for key in _item_db.keys():
		ids.append(str(key))
	return ids


func _is_valid_slot(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < MAX_SLOTS


# ================================================================
# SERIALIZACIÓN ACTUAL — COMPATIBLE CON SAVEMANAGER EXISTENTE
# ================================================================
func get_pocket_serializable() -> Array:
	var result: Array = []

	for i in range(MAX_SLOTS):
		if _pocket[i] != null:
			result.append({
				"slot": i,
				"id": _pocket[i]["id"],
				"qty": _pocket[i]["qty"],
			})
		else:
			result.append(null)

	return result


func get_bolso_contents_serializable() -> Array:
	var result: Array = []

	for entry in _bolso_contents:
		if entry != null:
			result.append({
				"id": entry["id"],
				"qty": entry["qty"],
			})
		else:
			result.append(null)

	return result


func restore_bolso_contents_from_save(data: Array) -> void:
	_bolso_contents = []

	for entry in data:
		if entry != null:
			_bolso_contents.append({
				"id": entry["id"],
				"qty": entry["qty"],
			})
		else:
			_bolso_contents.append(null)


func restore_pocket_from_serializable(data: Array) -> void:
	_pocket.resize(MAX_SLOTS)

	for i in range(MAX_SLOTS):
		_pocket[i] = null

	for i in range(min(data.size(), MAX_SLOTS)):
		if data[i] != null:
			_pocket[i] = {
				"id": data[i]["id"],
				"qty": data[i]["qty"],
			}

	inventory_changed.emit()


func clear_all_equipped(apply_effect_removal: bool = false) -> void:
	# Por defecto NO toca PlayerStats.
	# Esto es importante para carga de partida: SaveManager restaura stats base
	# y luego vuelve a aplicar equipamiento guardado.
	for slot in _equipped.keys().duplicate():
		var item: ItemData = _equipped[slot]

		if apply_effect_removal:
			if item and item.equip_slot == ItemData.EquipSlot.NECK_PERFUME:
				_remove_equipment_bonuses(item, "clear_all_equipped")
			else:
				_remove_item_stat_effects(item, "clear_all_equipped")
				_remove_bag_capacity_if_needed(item)

		_equipped.erase(slot)
		_equip_timers.erase(slot)
		item_unequipped.emit(slot)

	inventory_changed.emit()


func restore_equipped_from_save(slot_int: int, item_id: String, horas_restantes: int) -> void:
	var slot := slot_int as ItemData.EquipSlot
	var item := get_item_data(item_id)
	if not item:
		return

	_equipped[slot] = item

	if horas_restantes > 0:
		_equip_timers[slot] = horas_restantes

	if item.equip_slot == ItemData.EquipSlot.NECK_PERFUME:
		_apply_equipment_bonuses(item, "restore_equipped")
	else:
		_apply_item_stat_effects(item, "restore_equipped_%s" % item.name)
		_apply_bag_capacity_if_needed(item)

	item_equipped.emit(slot, item)
	inventory_changed.emit()


# ================================================================
# SERIALIZACIÓN NUEVA — PARA SAVEMANAGER FUTURO
# ================================================================
func get_save_data() -> Dictionary:
	var equipment_data: Dictionary = {}

	for slot_key in _equipped.keys():
		var item: ItemData = _equipped[slot_key]
		if item == null:
			continue

		var horas: int = 0
		if item.duracion_horas > 0:
			horas = get_equip_timer(slot_key)

		equipment_data[str(slot_key)] = {
			"id": item.name,
			"horas": horas,
		}

	return {
		"pocket": get_pocket_serializable(),
		"bolso_contents": get_bolso_contents_serializable(),
		"equipment": equipment_data,
	}


func apply_save_data(data: Dictionary) -> void:
	clear_all_equipped(false)

	_bolso_contents = []
	_slots_activos = MAX_SLOTS_BASE

	restore_bolso_contents_from_save(data.get("bolso_contents", []))
	restore_pocket_from_serializable(data.get("pocket", []))

	var equipment: Dictionary = data.get("equipment", {})
	for slot_str in equipment.keys():
		var entry: Dictionary = equipment[slot_str]
		var item_id: String = str(entry.get("id", ""))
		var horas: int = int(entry.get("horas", 0))

		if item_id != "":
			restore_equipped_from_save(int(slot_str), item_id, horas)

	inventory_changed.emit()


# ================================================================
# RESET
# ================================================================
func reset() -> void:
	_pocket.resize(MAX_SLOTS)

	for i in range(MAX_SLOTS):
		_pocket[i] = null

	_equipped.clear()
	_equip_timers.clear()
	_bolso_contents = []
	_slots_activos = MAX_SLOTS_BASE

	inventory_changed.emit()
