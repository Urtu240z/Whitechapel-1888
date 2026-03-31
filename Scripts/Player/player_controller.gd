extends CharacterBody2D
class_name MainPlayer

# ==========================
# ✨ CONFIGURABLE PARAMETERS
# ==========================
@export_group("🏃 Movement Settings")
@export var move_speed: float = 150.0
@export var run_speed: float = 500.0
@export var jump_speed: float = 500.0
@export var acceleration: float = 300.0
@export var friction: float = 950.0
@export var run_friction: float = 3000.0

@export_group("⚙️ Physics Settings")
@export var gravity_scale: int = 1

@export_group("👗 Visual Settings")
@export_enum("London", "Farm") var default_outfit: String = "London"

@export_group("🔊 Audio Settings")
@export var breath_run_sounds: Array[AudioStream] = []

@export_group("📏 World Scale Compensation")
@export var motion_scale_multiplier: float = 5.0

@onready var movement: Node = $Movement
@onready var animation: Node = $Animation
@onready var interaction: Node = $Interaction
@onready var audio: Node = $Audio

# ==========================
# INTERNAL STATE
# ==========================
var can_move: bool = true
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

# ==========================
# SCALE COMPENSATION
# Compensa el movimiento cuando el Player root está a escala 1
# pero antes el gameplay se sentía bien a escala 0.2.
# 0.2 -> 1.0 = x5
# ==========================
func get_scaled_move_speed() -> float:
	return move_speed * motion_scale_multiplier

func get_scaled_run_speed() -> float:
	return run_speed * motion_scale_multiplier

func get_scaled_jump_speed() -> float:
	return jump_speed * motion_scale_multiplier

func get_scaled_acceleration() -> float:
	return acceleration * motion_scale_multiplier

func get_scaled_friction() -> float:
	return friction * motion_scale_multiplier

func get_scaled_run_friction() -> float:
	return run_friction * motion_scale_multiplier

func get_scaled_gravity() -> float:
	return gravity * gravity_scale * motion_scale_multiplier

# ==========================
# READY
# ==========================
func _ready() -> void:
	PlayerManager.register_player(self)
	if not has_node("Camera2D"):
		push_warning("MainPlayer: No Camera2D found. Add one manually to the scene.")
	movement.initialize(self)
	animation.initialize(self)
	interaction.initialize(self)
	audio.initialize(self)
	set_outfit(default_outfit)
	# Conectar colapso por agotamiento
	PlayerStats.sueno_agotado.connect(_on_sueno_agotado)

# ==========================
# COLAPSO POR AGOTAMIENTO
# ==========================
func _on_sueno_agotado() -> void:
	disable_movement()
	animation.play_collapse()
	await animation.collapse_finished
	SleepManager.start_sleep_forced("calle", tr("SLEEP_COLAPSO_MENSAJE"))

# ==========================
# MAIN LOOP
func _physics_process(delta: float) -> void:
	if not can_move:
		velocity = Vector2.ZERO  # ← añade esta línea
		move_and_slide()
		return
	movement.process_movement(delta)
	move_and_slide()
	animation.update_animation()
	interaction.process_interactions()

# ==========================
# OUTFIT
# Solo cambia la visibilidad de los skins.
# El audio no depende del outfit, depende del suelo.
# ==========================
func set_outfit(which: String) -> void:
	var farm = get_node_or_null("CharacterContainer/Skins/Farm")
	var london = get_node_or_null("CharacterContainer/Skins/London")
	if farm: farm.visible = (which == "Farm")
	if london: london.visible = (which == "London")
	default_outfit = which  # ← sincroniza siempre para que el save lo lea bien

# ==========================
# MOVEMENT CONTROL
# ==========================
func enable_movement() -> void:
	can_move = true

func disable_movement() -> void:
	can_move = false
	velocity = Vector2.ZERO
	animation.force_idle()

# ==========================
# 🎬 SEÑALES DE INTRO
# ==========================
func _on_intro_light_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Light_Move":
		enable_movement()

func _on_logo_fade_animation_started(anim_name: StringName) -> void:
	if anim_name == "Logo_Fade":
		disable_movement()
