@tool
extends CharacterBody2D
class_name NPCCompanion

# ============================================================================
# NPC COMPANION
# Companion NPC con wander por waypoints (ping-pong), modo follow y diálogo.
# Arquitectura modular idéntica a NPCClient.
# ============================================================================

# ============================================================================
# DATOS
# ============================================================================
@export_group("NPC Companion")
@export var companion_name: String = "Mary"
@export_file("*.dtl") var dialog_timeline: String = ""
@export var initial_facing_right: bool = true

# Propiedad dinámica para dropdown de skin
var skin_name: String = "Mary"

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
@onready var skin: NPCCompanionSkin = $CharacterContainer
@onready var movement: NPCCompanionMovement = $Movement
@onready var animation: NPCCompanionAnimation = $Animation
@onready var conversation: NPCCompanionConversation = $Conversation
@onready var audio: NPCCompanionAudio = $Audio

# ============================================================================
# ESTADO
# ============================================================================
var _enabled: bool = true
var _editor_preview_queued: bool = false
var _last_preview_skin_name: String = ""
var _last_preview_facing_right: bool = true

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

	if skin:
		skin.set_skin(skin_name)
	if movement:
		movement.initialize(self, walk_speed, walk_accel, follow_speed,
			follow_dist_min, follow_dist_max)
		movement.start_wander()
	if animation:
		animation.initialize(self, initial_facing_right)
	if conversation:
		conversation.initialize(self)
	if audio:
		audio.initialize(self)

	visibility_changed.connect(_on_visibility_changed)
	set_enabled(is_visible_in_tree())

# ============================================================================
# EDITOR
# ============================================================================
func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if skin_name != _last_preview_skin_name or initial_facing_right != _last_preview_facing_right:
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
	_apply_facing_preview()
	_last_preview_skin_name = skin_name
	_last_preview_facing_right = initial_facing_right

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
	var skin_node := get_node_or_null("CharacterContainer") as NPCCompanionSkin
	if skin_node:
		skin_node.preview_skin(skin_name)

func _apply_facing_preview() -> void:
	var container := get_node_or_null("CharacterContainer") as Node2D
	if not container:
		return
	var base_scale := container.scale
	base_scale.x = abs(base_scale.x)
	base_scale.y = abs(base_scale.y)
	if is_zero_approx(base_scale.x): base_scale.x = 1.0
	if is_zero_approx(base_scale.y): base_scale.y = 1.0
	container.scale.x = base_scale.x if initial_facing_right else -base_scale.x
	container.scale.y = base_scale.y

# ============================================================================
# LOOP
# ============================================================================
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	const GRAVITY: float = 980.0
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	if not _enabled:
		return

	var player := _get_player()
	var player_in_range: bool = false
	if conversation:
		player_in_range = conversation.is_player_in_range()

	if movement:
		movement.process_movement(delta)
	if animation:
		animation.update_service(delta, player, player_in_range)

# ============================================================================
# API
# ============================================================================
func get_display_name() -> String:
	return companion_name if not companion_name.is_empty() else str(name)

func set_enabled(value: bool) -> void:
	_enabled = value
	set_physics_process(value)
	if conversation:
		conversation.set_interaction_enabled(value)
	if not value and animation:
		animation.force_idle_counter()

func start_follow() -> void:
	if movement:
		movement.stop_wander()
		movement.start_follow(_get_player())

func stop_follow() -> void:
	if movement:
		movement.stop_follow()
		movement.start_wander()

# ============================================================================
# DIALOGIC
# ============================================================================
func start_dialog() -> void:
	if dialog_timeline.is_empty():
		push_warning("NPCCompanion '%s': no tiene dialog_timeline asignado." % companion_name)
		return
	if not get_tree().root.has_node("Dialogic"):
		return
	if not StateManager.can_enter(StateManager.State.DIALOG):
		return

	var player := _get_player()
	if player:
		player.disable_movement()
	if movement:
		movement.freeze()
	if animation and player:
		animation.lock_facing(player.global_position.x > global_position.x)

	StateManager.enter(StateManager.State.DIALOG)
	Dialogic.start(dialog_timeline)
	Dialogic.timeline_ended.connect(func():
		StateManager.exit(StateManager.State.DIALOG)
		if is_instance_valid(self) and movement:
			movement.unfreeze()
		if animation:
			animation.unlock_facing()
		var p := _get_player()
		if p:
			p.enable_movement()
	, CONNECT_ONE_SHOT)

# ============================================================================
# HELPERS
# ============================================================================
func _get_player() -> Node2D:
	if PlayerManager and PlayerManager.player_instance:
		return PlayerManager.player_instance as Node2D
	return get_tree().get_first_node_in_group("player") as Node2D

func _on_visibility_changed() -> void:
	set_enabled(is_visible_in_tree())
