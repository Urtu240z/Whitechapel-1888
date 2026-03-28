extends Node2D

@export var light_path: NodePath
@export var zone_shape_path: NodePath        # CollisionShape2D (RectangleShape2D)
@export var left_falloff: float = 600.0      # distancia de transición izquierda
@export var right_falloff: float = 600.0     # distancia de transición derecha
@export var min_energy: float = 0.0          # energía dentro de la zona
@export var max_energy: float = 2.0          # energía fuera
@export var player_color_outside: Color = Color(1, 1, 1, 1)
@export var player_color_inside: Color = Color(0.6, 0.6, 0.8, 1)

@onready var light = get_node(light_path)
@onready var shape: CollisionShape2D = get_node(zone_shape_path)

var _player: Node2D = null


func _process(_delta):
	# Obtener player fresco via PlayerManager
	if not is_instance_valid(_player):
		_player = PlayerManager.player_instance

	if not is_instance_valid(_player) or not light or not shape or shape.shape == null:
		return

	var rect = shape.shape
	if not (rect is RectangleShape2D):
		return

	# Calcular bordes globales
	var half_w: float = (rect as RectangleShape2D).size.x * 0.5
	half_w *= abs(shape.global_transform.get_scale().x)
	var left_edge: float  = shape.global_position.x - half_w
	var right_edge: float = shape.global_position.x + half_w
	var px: float = _player.global_position.x

	var energy: float       = max_energy
	var player_color: Color = player_color_outside

	if px < left_edge:
		var d: float = left_edge - px
		var t: float = clamp(1.0 - d / max(1.0, left_falloff), 0.0, 1.0)
		energy       = lerp(max_energy, min_energy, t)
		player_color = player_color_outside.lerp(player_color_inside, t)
	elif px > right_edge:
		var d: float = px - right_edge
		var t: float = clamp(1.0 - d / max(1.0, right_falloff), 0.0, 1.0)
		energy       = lerp(max_energy, min_energy, t)
		player_color = player_color_outside.lerp(player_color_inside, t)
	else:
		energy       = min_energy
		player_color = player_color_inside

	# Aplicar a la luz
	if light is DirectionalLight2D:
		light.energy = energy
	elif light is PointLight2D:
		light.energy = energy

	# Aplicar color al player
	_player.modulate = player_color
