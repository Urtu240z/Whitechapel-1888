extends Node2D

@export var edge_distance: float = 360.0
@export var fade_speed: float = 2.0
@export var min_alpha: float = 0.15
@export var max_alpha: float = 0.8
@export var pulse_speed: float = 3.0  # velocidad del pulso

var word_ref: Node2D = null
@onready var glow: ColorRect = $Glow

func _ready():
	if glow:
		glow.color = Color(1, 1, 1, 1)  # Blanco puro

func _process(_delta):
	if not word_ref or not word_ref.is_inside_tree():
		queue_free()
		return
	
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		player = get_node_or_null("/root/Flashback_2/Fairy")
		if not player:
			return

	# ========================
	# 🔹 Calculamos dirección
	# ========================
	var dir = (word_ref.global_position - player.global_position).normalized()
	var viewport_size = get_viewport_rect().size

	# ========================
	# 🔹 Posición en el borde
	# ========================
	var x = viewport_size.x / 2.0 + dir.x * (viewport_size.x / 2.0 - edge_distance)
	var y = viewport_size.y / 2.0 + dir.y * (viewport_size.y / 2.0 - edge_distance)
	position = Vector2(x, y)

	# ========================
	# 🔹 Intensidad (alpha)
	# ========================
	var dist = player.global_position.distance_to(word_ref.global_position)
	var base_alpha = clamp(lerp(max_alpha, min_alpha, dist / 2000.0), min_alpha, max_alpha)
	
	# 🔸 Pulso suave
	var pulse = (sin(Time.get_ticks_msec() / 1000.0 * pulse_speed) + 1.0) * 0.5
	var final_alpha = base_alpha * (0.7 + pulse * 0.3)

	glow.modulate.a = final_alpha

	# Mantenerlo orientado sin rotar el ColorRect
	rotation = 0
