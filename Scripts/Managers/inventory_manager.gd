extends Node
# ================================================================
# INVENTORY MANAGER — Autoload
# Gestiona bolsillo (consumibles/objetos) y equipamiento (slots).
# ================================================================

signal inventory_changed
signal item_equipped(slot: ItemData.EquipSlot, item: ItemData)
signal item_unequipped(slot: ItemData.EquipSlot)
signal item_used(item: ItemData)

const MAX_SLOTS: int = 16

# Bolsillo: { item_id: String -> cantidad: int }
var _pocket: Dictionary = {}

# Base de datos de items: { id -> ItemData }
var _item_db: Dictionary = {}

# Equipamiento: { EquipSlot -> ItemData }
var _equipped: Dictionary = {}

# ================================================================
# INIT
# ================================================================

func _ready() -> void:
	_load_item_database()

func _load_item_database() -> void:
	var dir := DirAccess.open("res://Data/Pickups/")
	if not dir:
		return
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".tres"):
			var item := load("res://Data/Pickups/" + file) as ItemData
			if item and not item.name.is_empty():
				_item_db[item.name] = item
		file = dir.get_next()

# ================================================================
# BOLSILLO
# ================================================================

func add_item(item_id: String, quantity: int = 1) -> bool:
	var item := get_item_data(item_id)
	if not item:
		push_warning("InventoryManager: item '%s' no existe en la DB." % item_id)
		return false
	if item.item_type == ItemData.ItemType.EQUIPPABLE:
		if _pocket_count() >= MAX_SLOTS:
			return false
		_pocket[item_id] = 1
	else:
		var current: int = _pocket.get(item_id, 0)
		if current >= item.max_stack:
			return false
		_pocket[item_id] = min(current + quantity, item.max_stack)
	inventory_changed.emit()
	return true

func remove_item(item_id: String, quantity: int = 1) -> bool:
	if not _pocket.has(item_id):
		return false
	_pocket[item_id] -= quantity
	if _pocket[item_id] <= 0:
		_pocket.erase(item_id)
	inventory_changed.emit()
	return true

func has_item(item_id: String, quantity: int = 1) -> bool:
	return _pocket.get(item_id, 0) >= quantity

func use_item(item_id: String) -> bool:
	var item := get_item_data(item_id)
	if not item or not has_item(item_id):
		return false
	if item.item_type == ItemData.ItemType.EQUIPPABLE:
		return equip(item_id)
	_apply_effects(item)
	remove_item(item_id, 1)
	item_used.emit(item)
	return true

func _pocket_count() -> int:
	return _pocket.size()

# ================================================================
# EQUIPAMIENTO
# ================================================================

func equip(item_id: String) -> bool:
	var item := get_item_data(item_id)
	if not item or item.equip_slot == ItemData.EquipSlot.NONE:
		return false
	if _equipped.has(item.equip_slot):
		unequip(item.equip_slot)
	_equipped[item.equip_slot] = item
	remove_item(item_id, 1)
	_apply_effects(item)
	item_equipped.emit(item.equip_slot, item)
	inventory_changed.emit()
	return true

func unequip(slot: ItemData.EquipSlot) -> bool:
	if not _equipped.has(slot):
		return false
	var item: ItemData = _equipped[slot]
	_remove_effects(item)
	_equipped.erase(slot)
	add_item(item.name, 1)
	item_unequipped.emit(slot)
	inventory_changed.emit()
	return true

func get_equipped(slot: ItemData.EquipSlot) -> ItemData:
	return _equipped.get(slot, null)

# ================================================================
# EFECTOS
# ================================================================

func _apply_effects(item: ItemData) -> void:
	for stat_name in item.effects.keys():
		var valor: float = item.effects[stat_name]
		if not PlayerStats.has(stat_name):
			push_warning("InventoryManager: stat '%s' no existe en PlayerStats." % stat_name)
			continue
		PlayerStats.set(stat_name, clamp(PlayerStats.get(stat_name) + valor, 0.0, 100.0))
	PlayerStats.actualizar_stats()

func _remove_effects(item: ItemData) -> void:
	for stat_name in item.effects.keys():
		var valor: float = item.effects[stat_name]
		if not PlayerStats.has(stat_name):
			continue
		PlayerStats.set(stat_name, clamp(PlayerStats.get(stat_name) - valor, 0.0, 100.0))
	PlayerStats.actualizar_stats()

# ================================================================
# UTILS
# ================================================================

func get_item_data(item_id: String) -> ItemData:
	return _item_db.get(item_id, null)

func get_pocket() -> Dictionary:
	return _pocket.duplicate()

func get_equipped_all() -> Dictionary:
	return _equipped.duplicate()
