extends Resource
class_name ItemData

enum ItemType { CONSUMABLE, EQUIPPABLE, KEY }
enum EquipSlot { NONE, HEAD, NECK_COLLAR, NECK_PERFUME, BODY, HAND_LEFT, HAND_RIGHT, GLOVES, SHOES, ACCESSORY }

# — Campos originales (compatibles con .tres existentes) —
@export var name: String = ""
@export var display_name: String = ""
@export var cost: float = 0.0
@export var effects: Dictionary = {}
@export var sound: AudioStream = null
@export var icon: Texture2D = null

# — Campos nuevos para inventario —
@export var item_type: ItemType = ItemType.CONSUMABLE
@export var equip_slot: EquipSlot = EquipSlot.NONE
@export var max_stack: int = 5
@export var can_pickup_to_inventory: bool = false
