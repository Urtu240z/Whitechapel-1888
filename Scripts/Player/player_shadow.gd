extends Sprite2D
# ================================================================
# PLAYER SHADOW
# Parámetros configurables desde MainPlayer (exports).
# ================================================================

var _shader_mat: ShaderMaterial

func _ready() -> void:
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
	var player = get_parent()
	var max_distance: float = player.shadow_max_distance
	var base_alpha: float   = player.shadow_base_alpha
	var max_rot_l: float    = player.shadow_max_rotation_left
	var max_rot_r: float    = player.shadow_max_rotation_right

	var lamp = _get_nearest_lamp(max_distance)

	if lamp == null:
		modulate.a = 0.0
		rotation = 0.0
		scale = Vector2.ONE
		_shader_mat.set_shader_parameter("skew_x", 0.0)
		_shader_mat.set_shader_parameter("skew_y", 0.0)
		return

	var dir = lamp.global_position - global_position
	var dist = dir.length()
	var factor = clamp(1.0 - (dist / max_distance), 0.0, 1.0)

	# Alpha directo
	modulate.a = base_alpha * factor

	# Rotación — 0 cerca de la farola, máximo lejos
	var inv = 1.0 - factor
	var factor_rot = inv * inv * (3.0 - 2.0 * inv)
	var side = sign(dir.x)
	var max_rot = max_rot_r if side > 0 else max_rot_l
	rotation = deg_to_rad(max_rot) * factor_rot

	# Escala — más grande cuando más cerca de la luz
	var s = 1.0 + (player.shadow_max_scale - 1.0) * factor
	scale = Vector2(s, s)

	# Skew — aumenta al alejarse
	var inv_skew = 1.0 - factor
	var skew_val = player.shadow_max_skew * inv_skew * sign(dir.x) * -1.0
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
