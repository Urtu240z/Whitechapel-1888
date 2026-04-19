extends Sprite2D

# ================================================================
# CHARACTER SHADOW
# Para NPC Client y NPC Companion
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
	modulate = Color(0.0, 0.0, 0.0, 0.0)

	var shader := Shader.new()
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
	var lamp: Node2D = _get_nearest_lit_lamp(shadow_max_distance)

	if lamp == null:
		_ocultar_sombra()
		return

	var lamp_pos: Vector2 = _get_lamp_position(lamp)
	var light_factor: float = _get_lamp_light_factor(lamp)

	if light_factor <= 0.001:
		_ocultar_sombra()
		return

	var dir: Vector2 = lamp_pos - global_position
	var dist: float = dir.length()
	var factor: float = clamp(1.0 - (dist / shadow_max_distance), 0.0, 1.0)

	modulate.a = shadow_base_alpha * factor * light_factor

	var inv: float = 1.0 - factor
	var factor_rot: float = inv * inv * (3.0 - 2.0 * inv)
	var side: float = sign(dir.x)
	var max_rot: float = shadow_max_rotation_right if side > 0.0 else shadow_max_rotation_left
	rotation = deg_to_rad(max_rot) * factor_rot

	var s: float = 1.0 + (shadow_max_scale - 1.0) * factor
	scale = _base_scale * s

	var inv_skew: float = 1.0 - factor
	var skew_val: float = shadow_max_skew * inv_skew * sign(dir.x) * -1.0
	_shader_mat.set_shader_parameter("skew_x", skew_val)
	_shader_mat.set_shader_parameter("skew_y", 0.0)


func _ocultar_sombra() -> void:
	modulate.a = 0.0
	rotation = 0.0
	scale = _base_scale
	_shader_mat.set_shader_parameter("skew_x", 0.0)
	_shader_mat.set_shader_parameter("skew_y", 0.0)


func _get_nearest_lit_lamp(search_distance: float) -> Node2D:
	var lamps: Array = get_tree().get_nodes_in_group("street_lamp")
	var nearest: Node2D = null
	var nearest_dist: float = search_distance

	for lamp_variant in lamps:
		var lamp: Node2D = lamp_variant as Node2D
		if not is_instance_valid(lamp):
			continue

		var light_factor: float = _get_lamp_light_factor(lamp)
		if light_factor <= 0.001:
			continue

		var lamp_pos: Vector2 = _get_lamp_position(lamp)
		var d: float = global_position.distance_to(lamp_pos)

		if d < nearest_dist:
			nearest_dist = d
			nearest = lamp

	return nearest


func _get_lamp_position(lamp: Node2D) -> Vector2:
	if lamp.has_method("get_shadow_source_position"):
		return lamp.get_shadow_source_position()
	return lamp.global_position


func _get_lamp_light_factor(lamp: Node2D) -> float:
	if lamp.has_method("get_shadow_light_factor"):
		return lamp.get_shadow_light_factor()
	return 0.0
