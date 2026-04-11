@tool
extends CharacterBody2D
class_name NPCService

# ============================================================================
# NPC SERVICE
# NPC fijo de servicio: hostelero, doctor, vendedor, etc.
# Con preview en editor para skin, facing, body_scale y NameTag.
# ============================================================================

const CONFIG = preload("res://Data/Game/game_config.tres")
const SHOP_SCENE = preload("res://Scenes/UI/Shop.tscn")

# ============================================================================
# DATOS DEL NPC
# ============================================================================
@export_group("NPC Service")
@export var npc_display_name: String = ""
@export_file("*.dtl") var dialog_timeline: String = ""
@export var service_id: String = ""
@export var initial_facing_right: bool = true

@export_group("Appearance")
@export var body_scale: float = 1.0

@export_group("Name")
@export var use_random_name_if_empty: bool = true
@export var name_pools: NPCNamePools

@export_group("Shop")
@export var shop_items: Array[ShopItemData] = []
@export var shop_name_key: String = ""

# Propiedad dinámica para dropdown de skin
var skin_name: String = "NPC_HostalKeeper"
var current_display_name: String = ""

# ============================================================================
# REFERENCIAS
# ============================================================================
@onready var skin: NPCServiceSkin = $CharacterContainer
@onready var movement: NPCServiceMovement = $Movement
@onready var animation: NPCServiceAnimation = $Animation
@onready var conversation: NPCServiceConversation = $Conversation
@onready var audio: NPCServiceAudio = $Audio
@onready var name_tag: NameTag = $NameTag

@onready var character_container: Node2D = $CharacterContainer
@onready var body_collision: CollisionShape2D = $Collision
@onready var conversation_collision: CollisionShape2D = $Conversation/CollisionShape2D
@onready var shadow_sprite: Sprite2D = $Shadow

# ============================================================================
# ESTADO
# ============================================================================
var _service_enabled: bool = true
var _stock_variable: Dictionary = {}
var _stock_actual: Dictionary = {}

var _editor_preview_queued: bool = false
var _last_preview_skin_name: String = ""
var _last_preview_facing_right: bool = true
var _last_preview_body_scale: float = 1.0
var _last_preview_display_name: String = ""
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# ============================================================================
# CICLO DE VIDA
# ============================================================================
func _enter_tree() -> void:
	if Engine.is_editor_hint():
		call_deferred("notify_property_list_changed")

func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		_queue_editor_preview()
		return

	add_to_group("npc_service")
	velocity = Vector2.ZERO

	_rng.randomize()
	_resolve_runtime_display_name()

	if skin:
		skin.set_skin(skin_name)

	_apply_body_scale()
	_apply_initial_facing()

	if movement:
		movement.initialize(self)
	if animation:
		animation.initialize(self, initial_facing_right)
	if conversation:
		conversation.initialize(self)
	if audio:
		audio.initialize(self)
	if name_tag:
		name_tag.set_text(get_display_name())

	visibility_changed.connect(_on_visibility_changed)
	set_service_enabled(is_visible_in_tree())

	_reset_stock_diario()
	if DayNightManager and DayNightManager.hora_cambiada:
		DayNightManager.hora_cambiada.connect(_on_hora_cambiada)

# ============================================================================
# EDITOR
# ============================================================================
func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return

	if (
		skin_name != _last_preview_skin_name
		or initial_facing_right != _last_preview_facing_right
		or not is_equal_approx(body_scale, _last_preview_body_scale)
		or _get_preview_display_name() != _last_preview_display_name
	):
		_queue_editor_preview()

func _queue_editor_preview() -> void:
	if not Engine.is_editor_hint() or _editor_preview_queued:
		return

	_editor_preview_queued = true
	call_deferred("_apply_editor_preview")

func _apply_editor_preview() -> void:
	_editor_preview_queued = false

	if not Engine.is_editor_hint():
		return

	_apply_selected_skin_preview()
	_apply_body_scale()
	_apply_initial_facing()

	if name_tag:
		name_tag.set_text(_get_preview_display_name())

	_last_preview_skin_name = skin_name
	_last_preview_facing_right = initial_facing_right
	_last_preview_body_scale = body_scale
	_last_preview_display_name = _get_preview_display_name()

func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	var skins := _get_available_skin_names()

	properties.append({
		"name": "skin_name",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": _build_enum_hint(skins),
		"usage": PROPERTY_USAGE_DEFAULT
	})

	return properties

func _get(property: StringName) -> Variant:
	if property == &"skin_name":
		return skin_name
	return null

func _set(property: StringName, value: Variant) -> bool:
	if property == &"skin_name":
		var new_value := str(value)
		if skin_name != new_value:
			skin_name = new_value
			_queue_editor_preview()
		return true
	return false

func _get_available_skin_names() -> PackedStringArray:
	var result: PackedStringArray = []
	var skins_root := get_node_or_null("CharacterContainer/Skins")

	if skins_root == null:
		result.append("NPC_HostalKeeper")
		return result

	for child in skins_root.get_children():
		if child is Node2D:
			result.append(child.name)

	if result.is_empty():
		result.append("NPC_HostalKeeper")

	return result

func _build_enum_hint(values: PackedStringArray) -> String:
	var text := ""
	for i in range(values.size()):
		if i > 0:
			text += ","
		text += values[i]
	return text

func _apply_selected_skin_preview() -> void:
	var skin_node := get_node_or_null("CharacterContainer") as NPCServiceSkin
	if skin_node:
		skin_node.preview_skin(skin_name)

# ============================================================================
# LOOP
# ============================================================================
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if not _service_enabled:
		return

	velocity = Vector2.ZERO

	var player := _get_player()
	var player_in_range: bool = false

	if conversation:
		player_in_range = conversation.is_player_in_range()
	if name_tag:
		name_tag.set_tag_visible(player_in_range)
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
	if current_display_name.is_empty() and not Engine.is_editor_hint():
		_resolve_runtime_display_name()

	if not current_display_name.is_empty():
		return current_display_name

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

	if name_tag and not value:
		name_tag.hide_tag()

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

func _apply_body_scale() -> void:
	var s: float = max(body_scale, 0.01)
	var scale_vec := Vector2(s, s)

	if character_container:
		var sign_x: float = -1.0 if character_container.scale.x < 0.0 else 1.0
		character_container.scale = Vector2(sign_x * s, s)

	if body_collision:
		body_collision.scale = scale_vec

	if conversation_collision:
		conversation_collision.scale = scale_vec

	if shadow_sprite:
		shadow_sprite.scale = scale_vec

func _apply_initial_facing() -> void:
	if not character_container:
		return

	var s: float = max(body_scale, 0.01)
	character_container.scale.x = s if initial_facing_right else -s
	character_container.scale.y = s

func _resolve_runtime_display_name() -> void:
	if not current_display_name.is_empty():
		return

	if not npc_display_name.is_empty():
		current_display_name = npc_display_name
		return

	if not use_random_name_if_empty:
		current_display_name = name
		return

	if name_pools == null:
		current_display_name = name
		return

	var pool := name_pools.service_names
	if pool.is_empty():
		current_display_name = name
		return

	current_display_name = pool[_rng.randi_range(0, pool.size() - 1)]

func _get_preview_display_name() -> String:
	if not npc_display_name.is_empty():
		return npc_display_name

	if not use_random_name_if_empty:
		return name

	if name_pools and not name_pools.service_names.is_empty():
		return name_pools.service_names[0]

	return name

# ============================================================================
# DIALOGIC — PREPARAR VARIABLES
# ============================================================================
func prepare_dialogic_variables() -> void:
	var dialogic_root := get_tree().root.get_node_or_null("Dialogic")
	if dialogic_root == null:
		return

	var dialogic_var = dialogic_root.get_node_or_null("VAR")
	if dialogic_var == null:
		return

	match service_id:
		"lodge_reception":
			PlayerStats.sync_dialogic_variables_now()
			dialogic_var.set_variable("hostel.hostel_result", "")
		"barman":
			dialogic_var.set_variable("barman.barman_result", "")
		"perfume_vendor":
			dialogic_var.set_variable("perfume_vendor.result", "")

# ============================================================================
# DIALOGIC — RESOLVER RESULTADO
# ============================================================================
func resolve_dialogic_result() -> void:
	var dialogic_root := get_tree().root.get_node_or_null("Dialogic")
	if dialogic_root == null:
		return

	var dialogic_var = dialogic_root.get_node_or_null("VAR")
	if dialogic_var == null:
		return

	match service_id:
		"lodge_reception":
			var result = str(dialogic_var.get_variable("hostel.hostel_result"))
			dialogic_var.set_variable("hostel.hostel_result", "")
			if result != "rent_room":
				return
			SleepManager.start_hostel_rental_flow(CONFIG.coste_hostal)

		"barman":
			var result = str(dialogic_var.get_variable("barman.barman_result"))
			dialogic_var.set_variable("barman.barman_result", "")
			if result == "open_shop":
				_open_shop()

		"perfume_vendor":
			var result = str(dialogic_var.get_variable("perfume_vendor.result"))
			dialogic_var.set_variable("perfume_vendor.result", "")
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

	if not StateManager.can_enter(StateManager.State.SHOP):
		return

	var shop = SHOP_SCENE.instantiate()
	get_tree().root.add_child(shop)

	StateManager.enter(StateManager.State.SHOP)
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
		StateManager.exit(StateManager.State.SHOP)
		GameManager.hide_mouse()
		if is_instance_valid(player):
			player.enable_movement()
	)

	shop.open(tr(shop_name_key) if not shop_name_key.is_empty() else npc_display_name, items_hoy)
