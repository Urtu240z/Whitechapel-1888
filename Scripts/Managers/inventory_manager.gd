extends Node
# ================================================================
# INVENTORY MANAGER — Autoload
# Gestiona bolsillo posicional (12 slots fijos) y equipamiento.
# ================================================================

signal inventory_changed
signal item_equipped(slot: ItemData.EquipSlot, item: ItemData)
signal item_unequipped(slot: ItemData.EquipSlot)
signal item_used(item: ItemData)
signal perfume_already_active

const MAX_SLOTS_BASE: int = 6
const MAX_SLOTS_CON_BOLSO: int = 12
const MAX_SLOTS: int = 12  # tamaño del array siempre 12, pero solo _slots_activos son usables

var _slots_activos: int = MAX_SLOTS_BASE
var _pocket: Array = []
var _item_db: Dictionary = {}
var _equipped: Dictionary = {}
var _equip_timers: Dictionary = {}

# Contenido del bolso cuando está desequipado — persiste entre equipar/desequipar
var _bolso_contents: Array = []

# ================================================================
# INIT
# ================================================================

func _ready() -> void:
	_pocket.resize(MAX_SLOTS)
	_slots_activos = MAX_SLOTS_BASE
	_load_item_database()
	DayNightManager.hora_cambiada.connect(_on_hora_cambiada)

func _load_item_database() -> void:
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

# ================================================================
# HORA — decrementar timers de equipamiento
# ================================================================

func _on_hora_cambiada(_hora: float) -> void:
	var slots_a_quitar: Array = []
	for slot in _equip_timers.keys():
		_equip_timers[slot] -= 1
		if _equip_timers[slot] <= 0:
			slots_a_quitar.append(slot)
	for slot in slots_a_quitar:
		_equip_timers.erase(slot)
		_unequip_temporal(slot)

func _unequip_temporal(slot: ItemData.EquipSlot) -> void:
	if not _equipped.has(slot):
		return
	var item: ItemData = _equipped[slot]
	_remove_equip_bonuses(item)
	_equipped.erase(slot)
	item_unequipped.emit(slot)
	inventory_changed.emit()

# ================================================================
# BOLSILLO POSICIONAL
# ================================================================

func add_item(item_id: String, quantity: int = 1) -> bool:
	var item := get_item_data(item_id)
	if not item:
		push_warning("InventoryManager: item '%s' no existe en la DB." % item_id)
		return false

	var restante: int = quantity

	# 1. Rellenar stacks existentes del mismo item
	for i in range(_slots_activos):
		if restante <= 0:
			break
		if _pocket[i] != null and _pocket[i]["id"] == item_id:
			var current: int = _pocket[i]["qty"]
			if current >= item.max_stack:
				continue
			var caben: int = item.max_stack - current
			var a_meter: int = min(restante, caben)
			_pocket[i]["qty"] += a_meter
			restante -= a_meter

	# 2. Abrir slots nuevos con el sobrante
	for i in range(_slots_activos):
		if restante <= 0:
			break
		if _pocket[i] == null:
			var a_meter: int = min(restante, item.max_stack)
			_pocket[i] = { "id": item_id, "qty": a_meter }
			restante -= a_meter

	if restante > 0:
		push_warning("InventoryManager: inventario lleno, no caben %d unidades de '%s'." % [restante, item_id])
		inventory_changed.emit()
		return false

	inventory_changed.emit()
	return true

func add_item_to_slot(item_id: String, slot_index: int, quantity: int = 1) -> bool:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return false
	var item := get_item_data(item_id)
	if not item:
		return false
	if _pocket[slot_index] != null:
		push_warning("InventoryManager: slot %d ocupado." % slot_index)
		return false
	_pocket[slot_index] = { "id": item_id, "qty": quantity }
	inventory_changed.emit()
	return true

func remove_item(item_id: String, quantity: int = 1) -> bool:
	for i in range(MAX_SLOTS):
		if _pocket[i] != null and _pocket[i]["id"] == item_id:
			_pocket[i]["qty"] -= quantity
			if _pocket[i]["qty"] <= 0:
				_pocket[i] = null
			inventory_changed.emit()
			return true
	return false

func remove_item_from_slot(slot_index: int, quantity: int = 1) -> bool:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return false
	if _pocket[slot_index] == null:
		return false
	_pocket[slot_index]["qty"] -= quantity
	if _pocket[slot_index]["qty"] <= 0:
		_pocket[slot_index] = null
	inventory_changed.emit()
	return true

func move_item(from_slot: int, to_slot: int) -> bool:
	if from_slot < 0 or from_slot >= MAX_SLOTS:
		return false
	if to_slot < 0 or to_slot >= MAX_SLOTS:
		return false
	var temp = _pocket[to_slot]
	_pocket[to_slot] = _pocket[from_slot]
	_pocket[from_slot] = temp
	inventory_changed.emit()
	return true

func has_item(item_id: String, quantity: int = 1) -> bool:
	var total: int = 0
	for i in range(_slots_activos):
		if _pocket[i] != null and _pocket[i]["id"] == item_id:
			total += _pocket[i]["qty"]
	return total >= quantity

func get_slot(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return {}
	return _pocket[slot_index] if _pocket[slot_index] != null else {}

func use_item_from_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return false
	if _pocket[slot_index] == null:
		return false
	var item_id: String = _pocket[slot_index]["id"]
	var item := get_item_data(item_id)
	if not item:
		return false

	# Perfume — flujo especial
	if item.equip_slot == ItemData.EquipSlot.NECK_PERFUME:
		return _apply_perfume(slot_index, item)

	# Equipable normal
	if item.item_type == ItemData.ItemType.EQUIPPABLE:
		return equip_from_slot(slot_index)

	# Consumable
	_apply_effects(item)
	remove_item_from_slot(slot_index, 1)
	item_used.emit(item)
	return true

func use_item(item_id: String) -> bool:
	for i in range(MAX_SLOTS):
		if _pocket[i] != null and _pocket[i]["id"] == item_id:
			return use_item_from_slot(i)
	return false

func _pocket_count() -> int:
	var count: int = 0
	for i in range(MAX_SLOTS):
		if _pocket[i] != null:
			count += 1
	return count

# ================================================================
# PERFUME — flujo especial
# ================================================================

func _apply_perfume(slot_index: int, item: ItemData) -> bool:
	if _equipped.has(ItemData.EquipSlot.NECK_PERFUME):
		perfume_already_active.emit()
		return false

	remove_item_from_slot(slot_index, 1)
	_equipped[ItemData.EquipSlot.NECK_PERFUME] = item
	_equip_timers[ItemData.EquipSlot.NECK_PERFUME] = int(item.duracion_horas)
	_apply_equip_bonuses(item)
	item_equipped.emit(ItemData.EquipSlot.NECK_PERFUME, item)
	inventory_changed.emit()
	return true

# ================================================================
# EQUIPAMIENTO
# ================================================================

func equip_from_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return false
	if _pocket[slot_index] == null:
		return false
	var item_id: String = _pocket[slot_index]["id"]
	var item := get_item_data(item_id)
	if not item or item.equip_slot == ItemData.EquipSlot.NONE:
		return false
	if _equipped.has(item.equip_slot):
		unequip(item.equip_slot)
	_equipped[item.equip_slot] = item
	_pocket[slot_index] = null
	_apply_effects(item)
	item_equipped.emit(item.equip_slot, item)
	inventory_changed.emit()
	return true

func equip(item_id: String) -> bool:
	for i in range(MAX_SLOTS):
		if _pocket[i] != null and _pocket[i]["id"] == item_id:
			return equip_from_slot(i)
	return false

func unequip(slot: ItemData.EquipSlot) -> bool:
	if not _equipped.has(slot):
		return false
	var item: ItemData = _equipped[slot]
	if item.equip_slot != ItemData.EquipSlot.NECK_PERFUME:
		if not _puede_añadir(item.name):
			push_warning("InventoryManager: no se puede desequipar '%s', inventario lleno." % item.name)
			return false
	_remove_effects(item)
	_equipped.erase(slot)
	_equip_timers.erase(slot)
	if item.equip_slot != ItemData.EquipSlot.NECK_PERFUME:
		add_item(item.name, 1)
	item_unequipped.emit(slot)
	inventory_changed.emit()
	return true

func _puede_añadir(item_id: String) -> bool:
	var item := get_item_data(item_id)
	if not item:
		return false
	for i in range(_slots_activos):
		if _pocket[i] == null:
			return true
		if _pocket[i]["id"] == item_id and _pocket[i]["qty"] < item.max_stack:
			return true
	return false

func unequip_perfume_on_shower() -> void:
	if not _equipped.has(ItemData.EquipSlot.NECK_PERFUME):
		return
	_unequip_temporal(ItemData.EquipSlot.NECK_PERFUME)
	_equip_timers.erase(ItemData.EquipSlot.NECK_PERFUME)

func get_equipped(slot: ItemData.EquipSlot) -> ItemData:
	return _equipped.get(slot, null)

func get_perfume_horas_restantes() -> int:
	return _equip_timers.get(ItemData.EquipSlot.NECK_PERFUME, 0)

func get_equip_timer(slot: ItemData.EquipSlot) -> int:
	return _equip_timers.get(slot, 0)

# ================================================================
# EFECTOS — consumables y equipables normales (bolso)
# ================================================================

func _apply_effects(item: ItemData) -> void:
	for stat_name in item.effects.keys():
		var valor: float = item.effects[stat_name]
		if not PlayerStats.has(stat_name):
			push_warning("InventoryManager: stat '%s' no existe en PlayerStats." % stat_name)
			continue
		PlayerStats.set(stat_name, clamp(PlayerStats.get(stat_name) + valor, 0.0, 100.0))
	if item.quita_perfume:
		unequip_perfume_on_shower()
	if item.amplia_slots:
		_slots_activos = MAX_SLOTS_CON_BOLSO
		# Restaurar contenido previo del bolso si existe
		for i in range(_bolso_contents.size()):
			_pocket[MAX_SLOTS_BASE + i] = _bolso_contents[i]
		_bolso_contents = []
		inventory_changed.emit()
	PlayerStats.actualizar_stats()

func _remove_effects(item: ItemData) -> void:
	for stat_name in item.effects.keys():
		var valor: float = item.effects[stat_name]
		if not PlayerStats.has(stat_name):
			continue
		PlayerStats.set(stat_name, clamp(PlayerStats.get(stat_name) - valor, 0.0, 100.0))
	if item.amplia_slots:
		# Guardar contenido del bolso (slots 6-11) sin perderlo
		_bolso_contents = []
		for i in range(MAX_SLOTS_BASE, MAX_SLOTS_CON_BOLSO):
			_bolso_contents.append(_pocket[i])
			_pocket[i] = null
		_slots_activos = MAX_SLOTS_BASE
		inventory_changed.emit()
	PlayerStats.actualizar_stats()

# ================================================================
# BONUSES — equipables temporales (perfumes)
# ================================================================

func _apply_equip_bonuses(item: ItemData) -> void:
	PlayerStats.sex_appeal_bonus += item.sex_appeal_bonus
	PlayerStats.higiene = clamp(PlayerStats.higiene + item.higiene_bonus, 0.0, 100.0)
	if item.nervios_bonus != 0.0:
		PlayerStats.nervios = clamp(PlayerStats.nervios + item.nervios_bonus, 0.0, 100.0)
	if item.amplia_slots:
		_slots_activos = MAX_SLOTS_CON_BOLSO
		for i in range(_bolso_contents.size()):
			_pocket[MAX_SLOTS_BASE + i] = _bolso_contents[i]
		_bolso_contents = []
		inventory_changed.emit()
	PlayerStats.actualizar_stats()

func _remove_equip_bonuses(item: ItemData) -> void:
	PlayerStats.sex_appeal_bonus -= item.sex_appeal_bonus
	PlayerStats.higiene = clamp(PlayerStats.higiene - item.higiene_bonus, 0.0, 100.0)
	if item.nervios_bonus != 0.0:
		PlayerStats.nervios = clamp(PlayerStats.nervios - item.nervios_bonus, 0.0, 100.0)
	if item.amplia_slots:
		_bolso_contents = []
		for i in range(MAX_SLOTS_BASE, MAX_SLOTS_CON_BOLSO):
			_bolso_contents.append(_pocket[i])
			_pocket[i] = null
		_slots_activos = MAX_SLOTS_BASE
		inventory_changed.emit()
	PlayerStats.actualizar_stats()

# ================================================================
# UTILS
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

func get_pocket_serializable() -> Array:
	var result: Array = []
	for i in range(MAX_SLOTS):
		if _pocket[i] != null:
			result.append({ "slot": i, "id": _pocket[i]["id"], "qty": _pocket[i]["qty"] })
		else:
			result.append(null)
	return result

func get_bolso_contents_serializable() -> Array:
	var result: Array = []
	for entry in _bolso_contents:
		if entry != null:
			result.append({ "id": entry["id"], "qty": entry["qty"] })
		else:
			result.append(null)
	return result

func restore_bolso_contents_from_save(data: Array) -> void:
	_bolso_contents = []
	for entry in data:
		if entry != null:
			_bolso_contents.append({ "id": entry["id"], "qty": entry["qty"] })
		else:
			_bolso_contents.append(null)

func restore_pocket_from_serializable(data: Array) -> void:
	_pocket.resize(MAX_SLOTS)
	for i in range(min(data.size(), MAX_SLOTS)):
		if data[i] != null:
			_pocket[i] = { "id": data[i]["id"], "qty": data[i]["qty"] }
		else:
			_pocket[i] = null
	inventory_changed.emit()

func clear_all_equipped() -> void:
	for slot in _equipped.keys().duplicate():
		_unequip_temporal(slot)
		_equip_timers.erase(slot)

func restore_equipped_from_save(slot_int: int, item_id: String, horas_restantes: int) -> void:
	var slot := slot_int as ItemData.EquipSlot
	var item := get_item_data(item_id)
	if not item:
		return
	_equipped[slot] = item
	if horas_restantes > 0:
		_equip_timers[slot] = horas_restantes
	if item.amplia_slots:
		_slots_activos = MAX_SLOTS_CON_BOLSO
	_apply_equip_bonuses(item)
	item_equipped.emit(slot, item)
	inventory_changed.emit()

func reset() -> void:
	_pocket.resize(MAX_SLOTS)
	for i in range(MAX_SLOTS):
		_pocket[i] = null
	_equipped.clear()
	_equip_timers.clear()
	_bolso_contents = []
	_slots_activos = MAX_SLOTS_BASE
	inventory_changed.emit()
