@tool
extends CharacterBody2D
class_name NPCAmbient

# ============================================================================
# NPC AMBIENT
# NPC pasivo/ambiental usando el sistema moderno de componentes.
#
# Pensado para sustituir NPCs legacy tipo npc_main.gd / NPC_Charger.
# Responsabilidad:
# - Skin preview en editor.
# - Movimiento STATIC / WANDER por NPCMovementComponent.
# - Animación/audio vía componentes comunes.
# - Diálogo simple opcional con Dialogic.
#
# No contiene lógica de cliente, trato, servicio, tienda ni companion.
# ============================================================================

# ============================================================================
# TIPOS
# ============================================================================
enum BehaviorMode { STATIC, WANDER }

# ============================================================================
# DATOS DEL NPC
# ============================================================================
@export_group("NPC Ambient")
@export var npc_display_name: String = ""
@export_file("*.dtl") var dialog_timeline: String = ""
@export var can_talk_to_player: bool = true
@export var initial_facing_right: bool = true

@export_group("Behavior")
@export var behavior_mode: BehaviorMode = BehaviorMode.WANDER

@export_group("Appearance")
@export var body_scale: float = 1.0
@export var show_name_when_near: bool = true

@export_group("Name")
@export var use_random_name_if_empty: bool = true
@export var name_pools: NPCNamePools

@export_group("Movement")
@export var walk_speed: float = 120.0
@export var walk_accel: float = 300.0
@export var gravity: float = 980.0
@export var can_use_pois: bool = true
@export var allow_building_travel: bool = true

# Propiedad dinámica para dropdown de skin.
# Si duplicas NPC_Client, cambia este valor desde el inspector.
var skin_name: String = "NPC_AmbientPoor"
var current_display_name: String = ""

# ============================================================================
# REFERENCIAS
# ============================================================================
@onready var skin: NPCSkinComponent = get_node_or_null("CharacterContainer") as NPCSkinComponent
@onready var movement: NPCMovementComponent = get_node_or_null("Movement") as NPCMovementComponent
@onready var animation: NPCAnimationComponent = get_node_or_null("Animation") as NPCAnimationComponent
@onready var conversation: NPCInteractionArea = _get_conversation_component()
@onready var audio: NPCAudioComponent = get_node_or_null("Audio") as NPCAudioComponent
@onready var name_tag: NameTag = get_node_or_null("NameTag") as NameTag

@onready var character_container: Node2D = get_node_or_null("CharacterContainer") as Node2D
@onready var body_collision: CollisionShape2D = get_node_or_null("Collision") as CollisionShape2D
@onready var conversation_collision: CollisionShape2D = _get_conversation_collision()
@onready var shadow_sprite: Sprite2D = get_node_or_null("Shadow") as Sprite2D

# ============================================================================
# ESTADO
# ============================================================================
const PLAYER_LOCK_DIALOG: String = "npc_ambient_dialog"

var _enabled: bool = true
var _dialog_active: bool = false

var _editor_preview_queued: bool = false
var _last_preview_skin_name: String = ""
var _last_preview_facing_right: bool = true
var _last_preview_body_scale: float = 1.0
var _last_preview_display_name: String = ""

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _base_shadow_position: Vector2 = Vector2.ZERO
var _base_shadow_scale: Vector2 = Vector2.ONE
var _body_scale_refs_cached: bool = false


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

	add_to_group("npc")
	add_to_group("npcs")
	add_to_group("npcs_active")
	add_to_group("npc_ambient")

	velocity = Vector2.ZERO

	_rng.randomize()
	_resolve_runtime_display_name()

	if skin:
		skin.set_skin(skin_name)

	_apply_body_scale()
	_apply_initial_facing()

	if movement:
		movement.initialize(self)
		_configure_movement_component()
		call_deferred("_apply_behavior_mode")

	if animation:
		animation.initialize(self, initial_facing_right)

	if conversation:
		conversation.initialize(self)
		conversation.set_interaction_enabled(_should_enable_conversation())

	if audio:
		audio.initialize(self)

	if name_tag:
		name_tag.set_text(get_display_name())
		name_tag.hide_tag()

	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)

	set_enabled(is_visible_in_tree())


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
		result.append("NPC_Charger")
		return result

	for child in skins_root.get_children():
		if child is Node2D:
			result.append(child.name)

	if result.is_empty():
		result.append("NPC_Charger")

	return result


func _build_enum_hint(values: PackedStringArray) -> String:
	var text := ""
	for i in range(values.size()):
		if i > 0:
			text += ","
		text += values[i]
	return text


func _apply_selected_skin_preview() -> void:
	var skin_node := get_node_or_null("CharacterContainer") as NPCSkinComponent
	if skin_node:
		skin_node.preview_skin(skin_name)


func _cache_body_scale_refs() -> void:
	if _body_scale_refs_cached:
		return

	if shadow_sprite:
		_base_shadow_position = shadow_sprite.position
		_base_shadow_scale = shadow_sprite.scale

	_body_scale_refs_cached = true


func _apply_body_scale() -> void:
	_cache_body_scale_refs()

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
		shadow_sprite.position = _base_shadow_position * s
		shadow_sprite.scale = _base_shadow_scale * s


func _apply_initial_facing() -> void:
	var character_container_node := get_node_or_null("CharacterContainer") as Node2D
	if character_container_node == null:
		return

	var s: float = max(body_scale, 0.01)
	character_container_node.scale.x = s if initial_facing_right else -s
	character_container_node.scale.y = s

	# En editor, Movement puede ser una placeholder instance si su script no es @tool.
	# No llamamos métodos del componente en modo editor.
	if Engine.is_editor_hint():
		return

	var movement_node := get_node_or_null("Movement") as NPCMovementComponent
	if movement_node and movement_node.has_method("set_facing_right"):
		movement_node.set_facing_right(initial_facing_right)


# ============================================================================
# LOOP
# ============================================================================
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if bool(get_meta("_building_transit_active", false)):
		velocity = Vector2.ZERO
		return

	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0

	if _enabled and movement:
		movement.process_movement(delta)

	move_and_slide()

	if not _enabled:
		return

	var player := _get_player()
	var player_in_range: bool = false

	if conversation:
		player_in_range = conversation.is_player_in_range()

	if current_display_name.is_empty():
		_resolve_runtime_display_name()
		if name_tag:
			name_tag.set_text(get_display_name())

	if name_tag:
		name_tag.set_tag_visible(show_name_when_near and player_in_range)

	if animation:
		animation.update_service(delta, player, player_in_range)


# ============================================================================
# API PÚBLICA
# ============================================================================
func get_display_name() -> String:
	if current_display_name.is_empty() and not Engine.is_editor_hint():
		_resolve_runtime_display_name()

	if not current_display_name.is_empty():
		return current_display_name

	if not npc_display_name.is_empty():
		return npc_display_name

	return str(name)


func set_enabled(value: bool) -> void:
	_enabled = value
	set_physics_process(value)

	if conversation:
		conversation.set_interaction_enabled(value and _should_enable_conversation())

	if not value and animation:
		animation.force_idle_counter()

	if name_tag and not value:
		name_tag.hide_tag()


func set_behavior_mode(mode: BehaviorMode) -> void:
	behavior_mode = mode
	_apply_behavior_mode()


func set_static_mode() -> void:
	set_behavior_mode(BehaviorMode.STATIC)


func set_wander_mode() -> void:
	set_behavior_mode(BehaviorMode.WANDER)


func freeze_movement() -> void:
	if movement:
		movement.freeze()


func unfreeze_movement() -> void:
	if movement:
		movement.unfreeze()


func get_interaction_label() -> String:
	return "Hablar"


# ============================================================================
# MOVIMIENTO
# ============================================================================
func _configure_movement_component() -> void:
	if not movement:
		return

	movement.walk_speed = walk_speed
	movement.walk_accel = walk_accel
	movement.follow_speed = walk_speed
	movement.follow_accel = walk_accel
	movement.can_wander = true
	movement.can_follow = false
	movement.can_use_pois = can_use_pois
	movement.allow_building_travel = allow_building_travel
	movement.use_distance_warning = false


func _apply_behavior_mode() -> void:
	if not movement:
		return

	match behavior_mode:
		BehaviorMode.STATIC:
			movement.stop_follow()
			movement.stop_wander()

		BehaviorMode.WANDER:
			movement.stop_follow()
			movement.start_wander()


# ============================================================================
# DIALOGIC
# ============================================================================
func start_dialog() -> void:
	if not can_talk_to_player:
		return

	if dialog_timeline.is_empty():
		push_warning("NPCAmbient '%s': no tiene dialog_timeline asignado." % get_display_name())
		return

	if not get_tree().root.has_node("Dialogic"):
		return

	if _dialog_active:
		return

	if not StateManager.can_start_dialog():
		return

	_dialog_active = true

	PlayerManager.lock_player(PLAYER_LOCK_DIALOG)

	if movement:
		movement.freeze()

	var player := _get_player()
	if animation and player:
		animation.lock_facing(player.global_position.x > global_position.x)

	StateManager.change_to(StateManager.State.DIALOG, "start_ambient_dialog")

	Dialogic.timeline_ended.connect(func():
		_finish_dialog_flow()
	, CONNECT_ONE_SHOT)

	Dialogic.start(dialog_timeline)


func _finish_dialog_flow() -> void:
	StateManager.return_to_gameplay("end_ambient_dialog")

	if is_instance_valid(self) and movement:
		movement.unfreeze()

	if animation:
		animation.unlock_facing()

	PlayerManager.unlock_player(PLAYER_LOCK_DIALOG)
	_dialog_active = false


# ============================================================================
# HELPERS
# ============================================================================
func _resolve_runtime_display_name() -> void:
	if not current_display_name.is_empty():
		return

	if not npc_display_name.is_empty():
		current_display_name = npc_display_name
		return

	if not use_random_name_if_empty:
		current_display_name = str(name)
		return

	var pool := _get_name_pool()
	if pool.is_empty():
		current_display_name = str(name)
		return

	current_display_name = pool[_rng.randi_range(0, pool.size() - 1)]


func _get_preview_display_name() -> String:
	if not npc_display_name.is_empty():
		return npc_display_name

	if not use_random_name_if_empty:
		return str(name)

	var pool := _get_name_pool()
	if not pool.is_empty():
		return pool[0]

	return str(name)


func _get_name_pool() -> Array[String]:
	if name_pools == null:
		return []

	# Tu recurso actual no tiene todavía ambient_names.
	# Para ambientales usamos companion_names como primera opción,
	# y luego client_names/service_names como fallback.
	if not name_pools.companion_names.is_empty():
		return name_pools.companion_names

	if not name_pools.client_names.is_empty():
		return name_pools.client_names

	if not name_pools.service_names.is_empty():
		return name_pools.service_names

	return []


func _get_player() -> Node2D:
	if PlayerManager:
		var player := PlayerManager.get_player_node2d()
		if player:
			return player

	return get_tree().get_first_node_in_group("player") as Node2D


func _get_conversation_component() -> NPCInteractionArea:
	var node := get_node_or_null("Conversation") as NPCInteractionArea
	if node:
		return node

	return get_node_or_null("InteractionArea") as NPCInteractionArea


func _get_conversation_collision() -> CollisionShape2D:
	var conv := get_node_or_null("Conversation")
	if conv:
		return conv.get_node_or_null("CollisionShape2D") as CollisionShape2D

	var interaction := get_node_or_null("InteractionArea")
	if interaction:
		return interaction.get_node_or_null("CollisionShape2D") as CollisionShape2D

	return null


func _should_enable_conversation() -> bool:
	return can_talk_to_player and not dialog_timeline.is_empty()


func _on_visibility_changed() -> void:
	# Los NPCs reparentados a Interior deben seguir simulándose aunque el Interior esté oculto.
	# El interior está físicamente offscreen, así que no hace falta apagar su IA/física por visibilidad.
	if movement and movement.has_method("is_inside_building") and movement.is_inside_building():
		set_enabled(true)
		return

	set_enabled(is_visible_in_tree())
