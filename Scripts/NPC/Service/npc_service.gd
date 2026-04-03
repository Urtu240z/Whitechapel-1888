extends CharacterBody2D
class_name NPCService

# ============================================================================
# NPC SERVICE
# NPC fijo de servicio: hostelero, doctor, vendedor, etc.
# ============================================================================

const CONFIG = preload("res://Data/Game/game_config.tres")
const SHOP_SCENE = preload("res://Scenes/UI/Shop.tscn")

# ============================================================================
# DATOS DEL NPC
# ============================================================================
@export_group("NPC Service")
@export var npc_display_name: String = "Service NPC"
@export_file("*.dtl") var dialog_timeline: String = ""
@export var service_id: String = ""
@export var skin_name: String = "NPC_HostalKeeper"
@export var initial_facing_right: bool = true

@export_group("Shop")
@export var shop_items: Array[ShopItemData] = []

# ============================================================================
# REFERENCIAS
# ============================================================================
@onready var skin: NPCServiceSkin = $CharacterContainer
@onready var movement: NPCServiceMovement = $Movement
@onready var animation: NPCServiceAnimation = $Animation
@onready var conversation: NPCServiceConversation = $Conversation
@onready var audio: NPCServiceAudio = $Audio

# ============================================================================
# ESTADO
# ============================================================================
var _service_enabled: bool = true
var _stock_variable: Dictionary = {}   # item_id -> bool (disponible hoy)
var _stock_actual: Dictionary = {}     # item_id -> unidades restantes hoy

# ============================================================================
# READY
# ============================================================================
func _ready() -> void:
	add_to_group("npc_service")
	velocity = Vector2.ZERO

	if skin:
		skin.set_skin(skin_name)
	if movement:
		movement.initialize(self)
	if animation:
		animation.initialize(self, initial_facing_right)
	if conversation:
		conversation.initialize(self)
	if audio:
		audio.initialize(self)

	visibility_changed.connect(_on_visibility_changed)
	set_service_enabled(is_visible_in_tree())

	_reset_stock_diario()
	DayNightManager.hora_cambiada.connect(_on_hora_cambiada)

# ============================================================================
# LOOP
# ============================================================================
func _physics_process(delta: float) -> void:
	if not _service_enabled:
		return

	velocity = Vector2.ZERO

	var player := _get_player()
	var player_in_range: bool = false

	if conversation:
		player_in_range = conversation.is_player_in_range()

	if animation:
		animation.update_service(delta, player, player_in_range)

# ============================================================================
# API
# ============================================================================
func set_skin(new_skin: String) -> void:
	skin_name = new_skin
	if skin:
		skin.set_skin(new_skin)

func get_display_name() -> String:
	if not npc_display_name.is_empty():
		return npc_display_name
	return name

func set_service_enabled(value: bool) -> void:
	_service_enabled = value
	set_physics_process(value)

	if conversation:
		conversation.set_interaction_enabled(value)

	if not value and animation:
		animation.force_idle_counter()

# ============================================================================
# API STOCK — usada por SaveManager
# ============================================================================
func get_stock() -> Dictionary:
	return _stock_actual.duplicate()

func restore_stock(data: Dictionary) -> void:
	_stock_actual = data.duplicate()

# ============================================================================
# SEÑALES
# ============================================================================
func _on_visibility_changed() -> void:
	set_service_enabled(is_visible_in_tree())

func _on_hora_cambiada(hora: float) -> void:
	if int(hora) == 0:
		_reset_stock_diario()

# ============================================================================
# HELPERS
# ============================================================================
func _get_player() -> Node2D:
	if PlayerManager and PlayerManager.player_instance:
		return PlayerManager.player_instance as Node2D
	return get_tree().get_first_node_in_group("player") as Node2D

# ============================================================================
# DIALOGIC — PREPARAR VARIABLES
# ============================================================================
func prepare_dialogic_variables() -> void:
	match service_id:
		"lodge_reception":
			PlayerStats._sync_dialogic_variables()
			Dialogic.VAR.set_variable("hostel.hostel_open", true)
			Dialogic.VAR.set_variable("hostel.player_money", PlayerStats.dinero)
			Dialogic.VAR.set_variable("hostel.hostel_price", CONFIG.coste_hostal)
			Dialogic.VAR.set_variable("hostel.hostel_result", "")
		"barman":
			Dialogic.VAR.set_variable("barman.barman_result", "")

# ============================================================================
# DIALOGIC — RESOLVER RESULTADO
# ============================================================================
func resolve_dialogic_result() -> void:
	match service_id:
		"lodge_reception":
			var result = str(Dialogic.VAR.get_variable("hostel.hostel_result"))
			Dialogic.VAR.set_variable("hostel.hostel_result", "")
			if result != "rent_room":
				return
			var ok := PlayerStats.gastar_dinero(CONFIG.coste_hostal)
			if not ok:
				return
			PlayerStats.dias_sin_pagar_hostal = 0
			SleepManager.start_sleep("hostal")

		"barman":
			var result = str(Dialogic.VAR.get_variable("barman.barman_result"))
			Dialogic.VAR.set_variable("barman.barman_result", "")
			if result == "open_shop":
				_open_shop()

# ============================================================================
# SHOP — STOCK DIARIO
# ============================================================================
func _reset_stock_diario() -> void:
	_stock_variable.clear()
	_stock_actual.clear()
	for item_entry in shop_items:
		if item_entry.item == null:
			continue
		var item_id = item_entry.item.name
		if not item_entry.is_variable or _item_disponible_hoy(item_entry):
			_stock_actual[item_id] = item_entry.max_qty

func _item_disponible_hoy(item_entry: ShopItemData) -> bool:
	var item_id = item_entry.item.name
	if not _stock_variable.has(item_id):
		_stock_variable[item_id] = randf() < item_entry.variable_chance
	return _stock_variable[item_id]

# ============================================================================
# SHOP — ABRIR TIENDA
# ============================================================================
func _open_shop() -> void:
	var items_hoy: Array = []
	for item_entry in shop_items:
		if item_entry.item == null:
			continue
		var item_id = item_entry.item.name
		var stock = _stock_actual.get(item_id, 0)
		if stock <= 0:
			continue
		items_hoy.append({
			"id": item_id,
			"max_qty": stock
		})

	if items_hoy.is_empty():
		return

	var shop = SHOP_SCENE.instantiate()
	get_tree().root.add_child(shop)
	shop.open(tr("BARMAN_SHOP_NAME"), items_hoy)
	GameManager.show_mouse()

	var player = PlayerManager.player_instance
	if player:
		player.disable_movement()

	shop.items_purchased.connect(func(purchased: Dictionary):
		for item_id in purchased:
			if _stock_actual.has(item_id):
				_stock_actual[item_id] = max(0, _stock_actual[item_id] - purchased[item_id])
	)

	shop.shop_closed.connect(func():
		GameManager.hide_mouse()
		if is_instance_valid(player):
			player.enable_movement()
	)
