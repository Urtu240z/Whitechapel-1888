extends Sprite2D

# ================================================================
# NPC COMPANION SHADOW
# Igual que player_shadow.gd pero con sus propios exports,
# sin depender de propiedades del nodo padre.
# ================================================================

@export var shadow_max_distance: float = 1000.0
@export var shadow_base_alpha: float = 1.7
@export var shadow_max_rotation_left: float = 45.0
@export var shadow_max_rotation_right: float = -45.0
@export var shadow_max_scale: float = 1.5
@export var shadow_max_skew: float = 0.05

var _shader_mat: ShaderMaterial
var _base_scale: Vector2 = Vector2.ONE

func _ready() -> void:
	_base_scale = scale
	modulate = Color(0, 0, 0, 0.0)

	var shader = Shader.new()
	shader.code = """
	shader_type canvas_item;
	uniform float skew_x : hint_range(-3.0, 3.0) = 0.0;
	uniform float skew_y : hint_range(-3.0, 3.0) = 0.0;
	void fragment() {
		float tex_alpha = texture(TEXTURE, UV).a;
		COLOR = vec4(0.0, 0.0, 0.0, tex_alpha * COLOR.a);
	}
	void vertex() {
		VERTEX.x += VERTEX.y * skew_x;
		VERTEX.y += VERTEX.x * skew_y;
	}
	"""
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	material = _shader_mat

func _process(_delta: float) -> void:
	var lamp = _get_nearest_lamp(shadow_max_distance)

	if lamp == null:
		modulate.a = 0.0
		rotation = 0.0
		scale = _base_scale
		_shader_mat.set_shader_parameter("skew_x", 0.0)
		_shader_mat.set_shader_parameter("skew_y", 0.0)
		return

	var dir = lamp.global_position - global_position
	var dist = dir.length()
	var factor = clamp(1.0 - (dist / shadow_max_distance), 0.0, 1.0)

	modulate.a = shadow_base_alpha * factor

	var inv = 1.0 - factor
	var factor_rot = inv * inv * (3.0 - 2.0 * inv)
	var side = sign(dir.x)
	var max_rot = shadow_max_rotation_right if side > 0 else shadow_max_rotation_left
	rotation = deg_to_rad(max_rot) * factor_rot

	var s = 1.0 + (shadow_max_scale - 1.0) * factor
	scale = _base_scale * s

	var inv_skew = 1.0 - factor
	var skew_val = shadow_max_skew * inv_skew * sign(dir.x) * -1.0
	_shader_mat.set_shader_parameter("skew_x", skew_val)
	_shader_mat.set_shader_parameter("skew_y", 0.0)

func _get_nearest_lamp(search_distance: float) -> Node2D:
	var lamps = get_tree().get_nodes_in_group("street_lamp")
	var nearest: Node2D = null
	var nearest_dist: float = search_distance

	for lamp in lamps:
		if not is_instance_valid(lamp):
			continue

		var lamp_base = lamp.get_node_or_null("LampBase")
		var lamp_pos = lamp_base.global_position if lamp_base else lamp.global_position
		var d = global_position.distance_to(lamp_pos)

		if d < nearest_dist:
			nearest_dist = d
			nearest = lamp_base if lamp_base else lamp

	return nearest
