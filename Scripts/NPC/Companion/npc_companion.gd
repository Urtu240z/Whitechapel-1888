@tool
extends CharacterBody2D
class_name NPCCompanion

# ============================================================================
# NPC COMPANION
# Companion NPC con wander por POIs, modo follow y diálogo.
# Arquitectura modular.
# ============================================================================

enum BehaviorMode {
	STATIC,
	WANDER,
	FOLLOW
}

# ============================================================================
# DATOS
# ============================================================================
@export_group("NPC Companion")
@export var companion_name: String = ""
@export_file("*.dtl") var dialog_timeline: String = ""
@export var initial_facing_right: bool = true

@export_group("Behavior")
@export var behavior_mode: BehaviorMode = BehaviorMode.WANDER

@export_group("Appearance")
@export var body_scale: float = 1.0

@export_group("Name")
@export var use_random_name_if_empty: bool = true
@export var name_pools: NPCNamePools

# Propiedad dinámica para dropdown de skin
var skin_name: String = "Mary"
var current_display_name: String = ""

# ============================================================================
# 🏃 MOVIMIENTO
# ============================================================================
@export_group("🏃 Movement")
@export var walk_speed: float = 650.0
@export var walk_accel: float = 650.0
@export var follow_speed: float = 650.0
@export var follow_dist_min: float = 150.0
@export var follow_dist_max: float = 350.0

# ============================================================================
# 🔗 REFERENCIAS
# ============================================================================
@onready var skin: NPCSkinComponent = $CharacterContainer
@onready var movement: NPCMovementComponent = $Movement
@onready var animation: NPCAnimationComponent = $Animation
@onready var conversation: NPCInteractionArea = $Conversation
@onready var audio: NPCAudioComponent = $Audio
@onready var name_tag: NameTag = $NameTag

@onready var character_container: Node2D = $CharacterContainer
@onready var body_collision: CollisionShape2D = $Collision
@onready var conversation_collision: CollisionShape2D = $Conversation/CollisionShape2D
@onready var shadow_sprite: Sprite2D = $Shadow

# ============================================================================
# ESTADO
# ============================================================================
var _enabled: bool = true
var _editor_preview_queued: bool = false
var _last_preview_skin_name: String = ""
var _last_preview_facing_right: bool = true
var _last_preview_body_scale: float = 1.0
var _last_preview_display_name: String = ""
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _base_shadow_position: Vector2 = Vector2.ZERO
var _base_shadow_scale: Vector2 = Vector2.ONE
var _dialog_active: bool = false

const PLAYER_LOCK_DIALOG: String = "npc_companion_dialog"
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

	add_to_group("npc_companion")
	velocity = Vector2.ZERO

	_rng.randomize()
	_resolve_runtime_display_name()

	if skin:
		skin.set_skin(skin_name)

	_apply_body_scale()

	if movement:
		movement.initialize(self)
		movement.configure_for_companion(
			walk_speed,
			walk_accel,
			follow_speed,
			follow_dist_min,
			follow_dist_max
		)
		call_deferred("_apply_behavior_mode")

	if animation:
		animation.initialize(self, initial_facing_right)
	if conversation:
		conversation.initialize(self)
	if audio:
		audio.initialize(self)
	if name_tag:
		name_tag.set_text(get_display_name())

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
	_apply_facing_preview()

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
		result.append("Mary")
		return result

	for child in skins_root.get_children():
		if child is Node2D:
			result.append(child.name)

	if result.is_empty():
		result.append("Mary")

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

func _apply_facing_preview() -> void:
	var container := get_node_or_null("CharacterContainer") as Node2D
	if not container:
		return

	var s: float = max(body_scale, 0.01)
	container.scale.x = s if initial_facing_right else -s
	container.scale.y = s

# ============================================================================
# LOOP
# ============================================================================
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if bool(get_meta("_building_transit_active", false)):
		velocity = Vector2.ZERO
		return

	const GRAVITY: float = 980.0
	if not is_on_floor():
		velocity.y += GRAVITY * delta
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
	if name_tag:
		name_tag.set_tag_visible(player_in_range)
	if animation:
		animation.update_service(delta, player, player_in_range)

# ============================================================================
# API
# ============================================================================
func get_display_name() -> String:
	if current_display_name.is_empty() and not Engine.is_editor_hint():
		_resolve_runtime_display_name()

	if not current_display_name.is_empty():
		return current_display_name

	if not companion_name.is_empty():
		return companion_name

	return str(name)

func set_enabled(value: bool) -> void:
	_enabled = value
	set_physics_process(value)

	if conversation:
		conversation.set_interaction_enabled(value)

	if not value and animation:
		animation.force_idle_counter()

	if name_tag and not value:
		name_tag.hide_tag()

func start_follow() -> void:
	set_follow_mode()

func stop_follow() -> void:
	if movement:
		movement.stop_follow()

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

		BehaviorMode.FOLLOW:
			movement.stop_wander()
			movement.start_follow(_get_player())

# ============================================================================
# DIALOGIC
# ============================================================================
func start_dialog() -> void:
	if dialog_timeline.is_empty():
		push_warning("NPCCompanion '%s': no tiene dialog_timeline asignado." % get_display_name())
		return
	if not get_tree().root.has_node("Dialogic"):
		return
	if _dialog_active:
		return
	if not StateManager.can_start_dialog():
		return

	_dialog_active = true
	var player := _get_player()
	PlayerManager.lock_player(PLAYER_LOCK_DIALOG)
	if movement:
		movement.freeze()
	if animation and player:
		animation.lock_facing(player.global_position.x > global_position.x)

	StateManager.change_to(StateManager.State.DIALOG, "start_companion_dialog")

	Dialogic.timeline_ended.connect(func():
		_finish_dialog_flow(PLAYER_LOCK_DIALOG, "end_companion_dialog")
	, CONNECT_ONE_SHOT)

	Dialogic.start(dialog_timeline)

func _finish_dialog_flow(lock_reason: String, return_reason: String) -> void:
	StateManager.return_to_gameplay(return_reason)

	if is_instance_valid(self) and movement:
		movement.unfreeze()

	if animation:
		animation.unlock_facing()

	PlayerManager.unlock_player(lock_reason)
	_dialog_active = false

# ============================================================================
# HELPERS
# ============================================================================
func set_behavior_mode(mode: BehaviorMode) -> void:
	behavior_mode = mode
	_apply_behavior_mode()

func set_static_mode() -> void:
	set_behavior_mode(BehaviorMode.STATIC)

func set_wander_mode() -> void:
	set_behavior_mode(BehaviorMode.WANDER)

func set_follow_mode() -> void:
	set_behavior_mode(BehaviorMode.FOLLOW)

func _resolve_runtime_display_name() -> void:
	if not current_display_name.is_empty():
		return

	if not companion_name.is_empty():
		current_display_name = companion_name
		return

	if not use_random_name_if_empty:
		current_display_name = str(name)
		return

	if name_pools == null:
		current_display_name = str(name)
		return

	var pool := name_pools.companion_names
	if pool.is_empty():
		current_display_name = str(name)
		return

	current_display_name = pool[_rng.randi_range(0, pool.size() - 1)]

func _get_preview_display_name() -> String:
	if not companion_name.is_empty():
		return companion_name

	if not use_random_name_if_empty:
		return str(name)

	if name_pools and not name_pools.companion_names.is_empty():
		return name_pools.companion_names[0]

	return str(name)

func _get_player() -> Node2D:
	if PlayerManager and PlayerManager.player_instance:
		return PlayerManager.player_instance as Node2D
	return get_tree().get_first_node_in_group("player") as Node2D

func _on_visibility_changed() -> void:
	# Los NPCs reparentados a Interior deben seguir simulándose aunque el Interior esté oculto.
	# El interior está físicamente offscreen, así que no hace falta apagar su IA/física por visibilidad.
	if movement and movement.has_method("is_inside_building") and movement.is_inside_building():
		set_enabled(true)
		return

	set_enabled(is_visible_in_tree())
