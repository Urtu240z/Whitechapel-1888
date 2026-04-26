@tool
extends CharacterBody2D
class_name NPCClient

# ============================================================================
# NPC CLIENT
# NPC cliente: interacción con F, diálogo de Dialogic,
# resolución del acto elegido.
# ============================================================================

# ============================================================================
# TIPOS
# ============================================================================
enum ClientType { POOR, MEDIUM, RICH }
enum BehaviorMode {
	STATIC,
	WANDER,
	FOLLOW
}

# ============================================================================
# DATOS DEL CLIENTE
# ============================================================================
@export_group("NPC Client")
@export var npc_display_name: String = ""
@export_file("*.dtl") var dialog_timeline: String = ""
@export var client_type: ClientType = ClientType.POOR
@export var initial_facing_right: bool = true

@export_group("Behavior")
@export var behavior_mode: BehaviorMode = BehaviorMode.STATIC

@export_group("Appearance")
@export var body_scale: float = 1.0

@export_group("Name")
@export var use_random_name_if_empty: bool = true
@export var name_pools: NPCNamePools

# Propiedad dinámica para dropdown
var skin_name: String = "NPC_ClientPoor"
var current_display_name: String = ""

# ============================================================================
# 🏃 MOVIMIENTO — configuración exportada
# ============================================================================
@export_group("🏃 Movement")
@export var follow_speed: float = 650.0
@export var follow_accel: float = 650.0
@export var follow_dist_min: float = 200.0
@export var follow_dist_max: float = 500.0
@export var follow_dist_warning: float = 2000.0
@export var follow_dist_cancel: float = 3000.0
@export var follow_gravity: float = 980.0

# ============================================================================
# ⚔️ COMBATE
# ============================================================================
@export_group("⚔️ Combat")
@export var attack_damage: float = 5.0

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
var _refused: bool = false
var _refused_timer: float = 0.0
const REFUSED_RESET_SECS: float = 120.0
const PLAYER_LOCK_DIALOG: String = "npc_client_dialog"
const PLAYER_LOCK_DISTANCE_WARNING: String = "npc_client_distance_warning"
const PLAYER_LOCK_DISTANCE_CANCEL: String = "npc_client_distance_cancel"
var _editor_preview_queued: bool = false
var _last_preview_skin_name: String = ""
var _last_preview_facing_right: bool = true
var _last_preview_body_scale: float = 1.0
var _last_preview_display_name: String = ""
var _last_attack: String = "Slap"

var _behavior_before_follow: BehaviorMode = BehaviorMode.STATIC
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

	add_to_group("npc_client")
	velocity = Vector2.ZERO

	_rng.randomize()
	_resolve_runtime_display_name()

	if skin:
		skin.set_skin(skin_name)

	_apply_body_scale()

	if int(behavior_mode) < 0 or int(behavior_mode) > BehaviorMode.FOLLOW:
		behavior_mode = BehaviorMode.STATIC

	if movement:
		movement.initialize(self)
		movement.configure_for_client(
			follow_speed,
			follow_accel,
			follow_dist_min,
			follow_dist_max,
			follow_gravity,
			follow_dist_warning,
			follow_dist_cancel
		)
		_behavior_before_follow = behavior_mode
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
	if not Engine.is_editor_hint():
		return
	if _editor_preview_queued:
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
		result.append("NPC_ClientPoor")
		return result

	for child in skins_root.get_children():
		if child is Node2D:
			result.append(child.name)

	if result.is_empty():
		result.append("NPC_ClientPoor")

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
	var character_container_node := get_node_or_null("CharacterContainer") as Node2D
	if character_container_node == null:
		return

	var s: float = max(body_scale, 0.01)
	character_container_node.scale.x = s if initial_facing_right else -s
	character_container_node.scale.y = s

# ============================================================================
# LOOP
# ============================================================================
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if bool(get_meta("_building_transit_active", false)):
		velocity = Vector2.ZERO
		return

	if _refused and _refused_timer > 0.0:
		_refused_timer -= delta
		if _refused_timer <= 0.0:
			_refused = false
			_refused_timer = 0.0

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

	if current_display_name.is_empty():
		_resolve_runtime_display_name()
		if name_tag:
			name_tag.set_text(get_display_name())

	if name_tag:
		name_tag.set_tag_visible(player_in_range)

	if animation:
		animation.update_service(delta, player, player_in_range)

# ============================================================================
# API
# ============================================================================
func get_display_name() -> String:
	if current_display_name.is_empty():
		_resolve_runtime_display_name()

	if not current_display_name.is_empty():
		return current_display_name

	if not npc_display_name.is_empty():
		return npc_display_name

	return name

func set_enabled(value: bool) -> void:
	_enabled = value
	set_physics_process(value)

	if conversation:
		conversation.set_interaction_enabled(value)

	if not value and animation:
		animation.force_idle_counter()

	if name_tag and not value:
		name_tag.hide_tag()

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

func set_behavior_mode(mode: BehaviorMode) -> void:
	behavior_mode = mode
	_apply_behavior_mode()

func set_static_mode() -> void:
	set_behavior_mode(BehaviorMode.STATIC)

func set_wander_mode() -> void:
	set_behavior_mode(BehaviorMode.WANDER)

func set_follow_mode() -> void:
	if behavior_mode != BehaviorMode.FOLLOW:
		_behavior_before_follow = behavior_mode
	set_behavior_mode(BehaviorMode.FOLLOW)

func restore_behavior_after_follow() -> void:
	var restore_mode: BehaviorMode = _behavior_before_follow
	if restore_mode == BehaviorMode.FOLLOW:
		restore_mode = BehaviorMode.STATIC
	set_behavior_mode(restore_mode)

# ============================================================================
# DIALOGIC — ABRIR DIÁLOGO
# ============================================================================
func start_dialog() -> void:
	if not get_tree().root.has_node("Dialogic"):
		return

	prepare_dialogic_variables()

	if not StateManager.can_start_dialog():
		return

	PlayerManager.lock_player(PLAYER_LOCK_DIALOG)
	if movement:
		movement.freeze()

	StateManager.change_to(StateManager.State.DIALOG, "start_client_dialog")
	Dialogic.start(dialog_timeline)

	if _refused and animation:
		var attack_player := _get_player()
		var facing_right: bool = true
		if attack_player:
			facing_right = attack_player.global_position.x > global_position.x

		animation.lock_facing(facing_right)
		await get_tree().create_timer(1.0).timeout

		var next_attack: String = "Kick" if _last_attack == "Slap" else "Slap"
		_last_attack = next_attack
		animation.play_attack(next_attack)
		animation.attack_hit.connect(_on_attack_hit, CONNECT_ONE_SHOT)

	Dialogic.timeline_ended.connect(func():
		resolve_dialogic_result()
		StateManager.return_to_gameplay("end_client_dialog")

		if is_instance_valid(self) and movement:
			movement.unfreeze()

		if animation:
			animation.unlock_facing()

		PlayerManager.unlock_player(PLAYER_LOCK_DIALOG)
	, CONNECT_ONE_SHOT)

# ============================================================================
# ATAQUE
# ============================================================================
func _on_attack_hit(attack_type: String) -> void:
	var hit_player := _get_player()
	if not hit_player:
		return

	var knockback_dir: float = 1.0 if hit_player.global_position.x > global_position.x else -1.0
	DamageManager.take_damage(attack_damage, DamageManager.Source.CLIENT, knockback_dir, attack_type)

# ============================================================================
# DIALOGIC — PREPARAR VARIABLES
# ============================================================================
func prepare_dialogic_variables() -> void:
	if Engine.is_editor_hint():
		return
	if not get_tree().root.has_node("Dialogic"):
		return

	PlayerStats._sync_dialogic_variables()
	Dialogic.VAR.set_variable("client.result", "")
	Dialogic.VAR.set_variable("client.deal_state", "")
	Dialogic.VAR.set_variable("client.deal_active", has_active_deal())
	Dialogic.VAR.set_variable("client.refused", _refused)

	var precios = _get_precios()
	Dialogic.VAR.set_variable("client.precio_mano", precios.mano)
	Dialogic.VAR.set_variable("client.precio_oral", precios.oral)
	Dialogic.VAR.set_variable("client.precio_completo", precios.completo)

# ============================================================================
# DIALOGIC — RESOLVER RESULTADO
# ============================================================================
const CLIENT_TRANSITION_SCENE = preload("res://Scenes/Client_Transition/Client_Transition.tscn")

# ============================================================================
# DEAL — sistema de dos fases
# ============================================================================
var _deal_acto: String = ""
signal deal_accepted(npc, acto)

func has_active_deal() -> bool:
	return not _deal_acto.is_empty()

func get_deal_acto() -> String:
	return _deal_acto

func resolve_dialogic_result() -> void:
	if Engine.is_editor_hint():
		return
	if not get_tree().root.has_node("Dialogic"):
		return

	var dialogic_refused: bool = bool(Dialogic.VAR.get_variable("client.refused"))
	if dialogic_refused and not _refused:
		_refused = true
		_refused_timer = REFUSED_RESET_SECS

	var result: String = str(Dialogic.VAR.get_variable("client.result"))
	Dialogic.VAR.set_variable("client.result", "")

	if result.is_empty():
		return

	accept_deal(result)

func accept_deal(acto: String) -> void:
	_deal_acto = acto

	if movement:
		set_follow_mode()
		movement.player_too_far_warning.connect(_on_player_too_far_warning, CONNECT_ONE_SHOT)
		movement.player_too_far_cancel.connect(_on_player_too_far_cancel, CONNECT_ONE_SHOT)

	if get_tree().root.has_node("Dialogic"):
		Dialogic.VAR.set_variable("client.deal_active", true)

	deal_accepted.emit(self, acto)

func _on_player_too_far_warning() -> void:
	if not get_tree().root.has_node("Dialogic"):
		return
	if not StateManager.can_start_dialog():
		return

	Dialogic.VAR.set_variable("client.deal_state", "warning")

	PlayerManager.lock_player(PLAYER_LOCK_DISTANCE_WARNING)
	if movement:
		movement.freeze()

	StateManager.change_to(StateManager.State.DIALOG, "start_client_dialog")
	Dialogic.start(dialog_timeline)

	Dialogic.timeline_ended.connect(func():
		Dialogic.VAR.set_variable("client.deal_state", "")
		StateManager.return_to_gameplay("end_client_dialog")

		if is_instance_valid(self) and movement:
			movement.unfreeze()

		PlayerManager.unlock_player(PLAYER_LOCK_DISTANCE_WARNING)
	, CONNECT_ONE_SHOT)

func _on_player_too_far_cancel() -> void:
	_deal_acto = ""
	_refused = true
	_refused_timer = REFUSED_RESET_SECS

	if not get_tree().root.has_node("Dialogic"):
		return
	if not StateManager.can_start_dialog():
		return

	Dialogic.VAR.set_variable("client.deal_state", "cancel")

	PlayerManager.lock_player(PLAYER_LOCK_DISTANCE_CANCEL)
	if movement:
		movement.freeze()

	StateManager.change_to(StateManager.State.DIALOG, "start_client_dialog")
	Dialogic.start(dialog_timeline)

	Dialogic.timeline_ended.connect(func():
		Dialogic.VAR.set_variable("client.deal_state", "")
		Dialogic.VAR.set_variable("client.deal_active", has_active_deal())
		StateManager.return_to_gameplay("end_client_dialog")

		if is_instance_valid(self) and movement:
			movement.unfreeze()
			if not has_active_deal():
				restore_behavior_after_follow()

		PlayerManager.unlock_player(PLAYER_LOCK_DISTANCE_CANCEL)
	, CONNECT_ONE_SHOT)

func complete_deal() -> void:
	if _deal_acto.is_empty():
		return

	var acto: String = _deal_acto
	var tipo: String = _get_tipo_string()
	_deal_acto = ""

	if movement:
		movement.stop_follow()

	restore_behavior_after_follow()

	ClientServiceManager.world_hidden.connect(queue_free, CONNECT_ONE_SHOT)

	var data: Dictionary = await ClientServiceManager.start_service(acto, tipo, skin_name)
	if not data.is_empty():
		PlayerStats.tener_acto(data["acto"], data["tipo"], data["satisfaction"])

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
		current_display_name = name
		return

	if name_pools == null:
		current_display_name = name
		return

	var pool := name_pools.client_names
	if pool.is_empty():
		current_display_name = name
		return

	current_display_name = pool[_rng.randi_range(0, pool.size() - 1)]

func _get_preview_display_name() -> String:
	if not npc_display_name.is_empty():
		return npc_display_name

	if not use_random_name_if_empty:
		return name

	if name_pools and not name_pools.client_names.is_empty():
		return name_pools.client_names[0]

	return name

func _get_player() -> Node2D:
	if PlayerManager and PlayerManager.player_instance:
		return PlayerManager.player_instance as Node2D
	return get_tree().get_first_node_in_group("player") as Node2D

func _get_tipo_string() -> String:
	match client_type:
		ClientType.POOR:
			return "poor"
		ClientType.MEDIUM:
			return "medium"
		ClientType.RICH:
			return "rich"
	return "poor"

func _get_precios() -> Dictionary:
	match client_type:
		ClientType.POOR:
			return { "mano": 0.5, "oral": 1.0, "completo": 2.0 }
		ClientType.MEDIUM:
			return { "mano": 1.0, "oral": 2.0, "completo": 4.0 }
		ClientType.RICH:
			return { "mano": 2.0, "oral": 4.0, "completo": 8.0 }
	return { "mano": 0.5, "oral": 1.0, "completo": 2.0 }

func _on_visibility_changed() -> void:
	# Los NPCs reparentados a Interior deben seguir simulándose aunque el Interior esté oculto.
	# El interior está físicamente offscreen, así que no hace falta apagar su IA/física por visibilidad.
	if movement and movement.has_method("is_inside_building") and movement.is_inside_building():
		set_enabled(true)
		return

	set_enabled(is_visible_in_tree())
