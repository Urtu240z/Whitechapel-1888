extends Sprite2D

# ================================================================
# PLAYER SHADOW
# Sombra falsa que se proyecta en dirección contraria al farol más cercano
# ================================================================

const SHADER_CODE = """
shader_type canvas_item;
uniform float skew_x : hint_range(-3.0, 3.0) = 0.0;
uniform float skew_y : hint_range(-3.0, 3.0) = 0.0;
void vertex() {
	VERTEX.x += VERTEX.y * skew_x;
	VERTEX.y += VERTEX.x * skew_y;
}
"""


@export var max_distance: float = 400.0
@export var max_skew: float = 1.5
@export var base_alpha: float = 0.35

var _shader_mat: ShaderMaterial

func _ready() -> void:
	print("ShadowProjection _ready ejecutado")
	texture = preload("res://Assets/Sprites/Player/Player_Shadow.png")
	z_index = -1
	modulate = Color(0, 0, 0, base_alpha)

	var shader = Shader.new()
	shader.code = SHADER_CODE
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	material = _shader_mat

func _process(_delta: float) -> void:
	var lamps = get_tree().get_nodes_in_group("street_lamp")
	print("Faroles: ", lamps.size())
	var lamp = _get_nearest_lamp()
	if lamp == null:
		_shader_mat.set_shader_parameter("skew_x", 0.0)
		_shader_mat.set_shader_parameter("skew_y", 0.0)
		modulate.a = base_alpha * 0.3
		return

	var dir = global_position - lamp.global_position
	var dist = dir.length()
	var factor = clamp(1.0 - (dist / max_distance), 0.0, 1.0)

	var shadow_skew = dir.normalized() * max_skew * factor
	_shader_mat.set_shader_parameter("skew_x", shadow_skew.x)
	_shader_mat.set_shader_parameter("skew_y", 0.0)

	modulate.a = base_alpha * factor

func _get_nearest_lamp() -> Node2D:
	var lamps = get_tree().get_nodes_in_group("street_lamp")
	var nearest: Node2D = null
	var nearest_dist: float = max_distance

	for lamp in lamps:
		if not is_instance_valid(lamp):
			continue
		var d = global_position.distance_to(lamp.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = lamp

	return nearest
