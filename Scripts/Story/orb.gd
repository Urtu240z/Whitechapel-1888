extends CharacterBody2D

# =========================================================
# ⚙️ CONFIGURACIÓN
# =========================================================
@export var move_speed: float = 160.0
@export var detection_radius: float = 250.0
@export var direction_change_interval: float = 0.5
@export var random_angle_range: float = 30.0
@export var bounce_damp: float = 0.8
@export var memory_index: int = 0
@export var orb_name: String = "Orb"

# =========================================================
# 🔗 NODOS
# =========================================================
@onready var detection_area: Area2D = $DetectionArea2D
@onready var hunt_area: Area2D = $HuntArea2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var anim: AnimationPlayer = $AnimationPlayer

# =========================================================
# 💾 VARIABLES INTERNAS
# =========================================================
var player: Node2D = null
var is_fleeing: bool = false
var flee_dir: Vector2 = Vector2.ZERO
var direction_timer: float = 0.0

# =========================================================
# 🏁 READY
# =========================================================
func _ready():
	# Configurar detección
	if detection_area.get_node("Detection") and detection_area.get_node("Detection").shape is CircleShape2D:
		(detection_area.get_node("Detection").shape as CircleShape2D).radius = detection_radius

	detection_area.body_entered.connect(_on_detection_entered)
	detection_area.body_exited.connect(_on_detection_exited)
	hunt_area.body_entered.connect(_on_hunt_entered)

	if anim.has_animation("Orb_Idle"):
		anim.play("Orb_Idle")

# =========================================================
# 🔄 MOVIMIENTO
# =========================================================
func _physics_process(delta):
	if is_fleeing and player:
		_flee_behavior(delta)
	else:
		velocity = Vector2.ZERO
	move_and_slide()

# =========================================================
# 👁️ DETECCIÓN DE PROXIMIDAD
# =========================================================
func _on_detection_entered(body):
	if body.name == "Player" or body.is_in_group("player"):
		player = body
		is_fleeing = true
		direction_timer = 0.0
		if anim.has_animation("Orb_Move"):
			anim.play("Orb_Move")

func _on_detection_exited(body):
	if body == player:
		player = null
		is_fleeing = false
		if anim.has_animation("Orb_Idle"):
			anim.play("Orb_Idle")

# =========================================================
# 🏃‍♂️ HUIDA
# =========================================================
func _flee_behavior(delta: float):
	if not player:
		return

	direction_timer -= delta
	if direction_timer <= 0.0:
		var away = (global_position - player.global_position).normalized()
		var random_angle = deg_to_rad(randf_range(-random_angle_range, random_angle_range))
		var new_dir = away.rotated(random_angle)
		flee_dir = flee_dir.slerp(new_dir, 0.15).normalized()
		direction_timer = direction_change_interval
	else:
		var away = (global_position - player.global_position).normalized()
		flee_dir = flee_dir.slerp(away, 0.08).normalized()

	velocity = flee_dir * move_speed

	# Rebote con paredes
	move_and_slide()
	for i in range(get_slide_collision_count()):
		var col = get_slide_collision(i)
		if col:
			flee_dir = flee_dir.bounce(col.get_normal()).normalized()
			velocity = flee_dir * move_speed * bounce_damp

# =========================================================
# 🎯 CAPTURA DEL PLAYER
# =========================================================
func _on_hunt_entered(body):
	if body.name == "Player" or body.is_in_group("player"):
		_on_captured()

func _on_captured():
	is_fleeing = false
	velocity = Vector2.ZERO
	if anim.has_animation("Orb_Idle"):
		anim.play("Orb_Idle")

	var controller := get_tree().get_first_node_in_group("dream_controller")
	if controller:
		controller.trigger_flashback(memory_index, orb_name)

	var tw := create_tween()
	tw.tween_property(sprite, "scale", sprite.scale * 1.5, 0.2)
	tw.tween_property(sprite, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): queue_free())
