extends Sprite2D
class_name NPCShadowComponent

# ================================================================
# NPC SHADOW COMPONENT
# ================================================================
# Sombra dinámica para NPCs.
#
# Sustituye:
# - npc_client_shadow.gd
# - npc_companion_shadow.gd
# - npc_character_shadow.gd
#
# Requiere:
# - Farolas en grupo "street_lamp".
# - Idealmente las farolas tienen:
#     get_shadow_source_position()
#     get_shadow_light_factor()
#
# Sin fallback antiguo:
# - Si una farola no expone get_shadow_light_factor(), no proyecta sombra.
# ================================================================

@export_group("Shadow")
@export var shadow_max_distance: float = 1000.0
@export var shadow_base_alpha: float = 1.7
@export var shadow_max_rotation_left: float = 45.0
@export var shadow_max_rotation_right: float = -45.0
@export var shadow_max_scale: float = 1.5
@export var shadow_max_skew: float = 0.05

@export_group("Lamp Source")
@export var lamp_group: String = "street_lamp"
@export var require_lit_lamp: bool = true

var _shader_mat: ShaderMaterial
var _base_scale: Vector2 = Vector2.ONE


func _ready() -> void:
	_base_scale = scale
	modulate = Color(0.0, 0.0, 0.0, 0.0)

	_build_material()


func _process(_delta: float) -> void:
	var lamp: Node2D = _get_nearest_valid_lamp(shadow_max_distance)

	if lamp == null:
		_hide_shadow()
		return

	var lamp_pos: Vector2 = _get_lamp_position(lamp)
	var light_factor: float = _get_lamp_light_factor(lamp)

	if require_lit_lamp and light_factor <= 0.001:
		_hide_shadow()
		return

	var dir: Vector2 = lamp_pos - global_position
	var dist: float = dir.length()
	var distance_factor: float = clamp(1.0 - (dist / shadow_max_distance), 0.0, 1.0)

	if distance_factor <= 0.001:
		_hide_shadow()
		return

	_apply_shadow(dir, distance_factor, light_factor)


# ================================================================
# MATERIAL
# ================================================================
func _build_material() -> void:
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


# ================================================================
# SHADOW LOGIC
# ================================================================
func _apply_shadow(dir: Vector2, distance_factor: float, light_factor: float) -> void:
	modulate.a = shadow_base_alpha * distance_factor * light_factor

	var inv: float = 1.0 - distance_factor
	var factor_rot: float = inv * inv * (3.0 - 2.0 * inv)

	var side: float = sign(dir.x)
	var max_rot: float = shadow_max_rotation_right if side > 0.0 else shadow_max_rotation_left
	rotation = deg_to_rad(max_rot) * factor_rot

	var s: float = 1.0 + (shadow_max_scale - 1.0) * distance_factor
	scale = _base_scale * s

	var inv_skew: float = 1.0 - distance_factor
	var skew_val: float = shadow_max_skew * inv_skew * sign(dir.x) * -1.0

	_shader_mat.set_shader_parameter("skew_x", skew_val)
	_shader_mat.set_shader_parameter("skew_y", 0.0)


func _hide_shadow() -> void:
	modulate.a = 0.0
	rotation = 0.0
	scale = _base_scale

	if _shader_mat:
		_shader_mat.set_shader_parameter("skew_x", 0.0)
		_shader_mat.set_shader_parameter("skew_y", 0.0)


# ================================================================
# LAMPS
# ================================================================
func _get_nearest_valid_lamp(search_distance: float) -> Node2D:
	var lamps: Array = get_tree().get_nodes_in_group(lamp_group)
	var nearest: Node2D = null
	var nearest_dist: float = search_distance

	for lamp_variant in lamps:
		var lamp: Node2D = lamp_variant as Node2D
		if not is_instance_valid(lamp):
			continue

		var light_factor: float = _get_lamp_light_factor(lamp)
		if require_lit_lamp and light_factor <= 0.001:
			continue

		var lamp_pos: Vector2 = _get_lamp_position(lamp)
		var d: float = global_position.distance_to(lamp_pos)

		if d < nearest_dist:
			nearest_dist = d
			nearest = lamp

	return nearest


func _get_lamp_position(lamp: Node2D) -> Vector2:
	if not lamp.has_method("get_shadow_source_position"):
		push_error("NPCShadowComponent: la farola '%s' no tiene get_shadow_source_position()." % lamp.name)
		return lamp.global_position

	return lamp.get_shadow_source_position()


func _get_lamp_light_factor(lamp: Node2D) -> float:
	if not lamp.has_method("get_shadow_light_factor"):
		push_error("NPCShadowComponent: la farola '%s' no tiene get_shadow_light_factor()." % lamp.name)
		return 0.0

	return float(lamp.get_shadow_light_factor())
