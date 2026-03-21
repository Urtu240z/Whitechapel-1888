extends Node2D
# O Area2D, si lo prefieres
@export var player_path: NodePath
@export var light_path: NodePath
@export var zone_shape_path: NodePath        # CollisionShape2D (RectangleShape2D)
@export var left_falloff: float = 600.0      # distancia de transición izquierda
@export var right_falloff: float = 300.0     # distancia de transición derecha
@export var min_energy: float = 0.0          # energía dentro de la zona
@export var max_energy: float = 2.0          # energía fuera
@export var player_color_outside: Color = Color(1, 1, 1, 1)  # color normal
@export var player_color_inside: Color = Color(0.6, 0.6, 0.8, 1) # color dentro (más oscuro/frío)

@onready var player: Node2D = get_node(player_path)
@onready var light = get_node(light_path)
@onready var shape: CollisionShape2D = get_node(zone_shape_path)

func _process(_delta):
	if !player or !light or !shape or shape.shape == null:
		return
	
	var rect := shape.shape
	if !(rect is RectangleShape2D):
		return
	
	# Calcular bordes globales (asumiendo sin rotación)
	var half_w := (rect as RectangleShape2D).size.x * 0.5
	half_w *= abs(shape.global_transform.get_scale().x)
	var left_edge := shape.global_position.x - half_w
	var right_edge := shape.global_position.x + half_w
	var px := player.global_position.x
	
	var energy := max_energy
	var player_color := player_color_outside
	
	if px < left_edge:
		var d := left_edge - px
		var t : float = clamp(1.0 - d / max(1.0, left_falloff), 0.0, 1.0)
		energy = lerp(max_energy, min_energy, t)
		player_color = player_color_outside.lerp(player_color_inside, t)
	elif px > right_edge:
		var d := px - right_edge
		var t : float = clamp(1.0 - d / max(1.0, right_falloff), 0.0, 1.0)
		energy = lerp(max_energy, min_energy, t)
		player_color = player_color_outside.lerp(player_color_inside, t)
	else:
		# Dentro del rectángulo
		energy = min_energy
		player_color = player_color_inside
	
	# Aplicar a la luz
	if light is DirectionalLight2D:
		light.energy = energy
	elif light is DirectionalLight3D:
		light.light_energy = energy
	
	# Aplicar modulate al jugador
	player.modulate = player_color
