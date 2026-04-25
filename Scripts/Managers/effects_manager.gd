extends Node

# ================================================================
# EFFECTS MANAGER — Autoload
# ================================================================
# Autoridad global de efectos visuales de pantalla/cámara.
#
# Cambios clave:
# - Blur + distorsión se componen en UN SOLO postproceso.
#   Así correr cansada no apaga la distorsión por alcohol/laudano.
# - Los efectos siguen activos durante TRANSITIONING.
# - La capa queda por encima del fade de SceneManager y por debajo
#   de textos de transición si estos usan layer 1100.
# ================================================================

signal effects_refreshed
signal effects_suppression_changed(is_suppressed: bool, reasons: PackedStringArray)
signal screen_shake_started(intensity: float, duration: float)

# ================================================================
# CONFIG
# ================================================================
# SceneManager fade = 1000.
# Building transition labels recomendados = 1100.
const EFFECTS_LAYER: int = 1050

const BLINK_DURATION: float = 0.12
const DEFAULT_FLASH_DURATION: float = 0.15

@export var stamina_reference: float = 50.0
@export var stamina_blur_max: float = 3.0
@export var stamina_shake_max: float = 4.0

@export var fear_threshold: float = 50.0
@export var fear_vignette_max: float = 0.8

@export var sleep_blink_threshold: float = 35.0
@export var blink_interval_min: float = 1.0
@export var blink_interval_max: float = 8.0

@export var substances_threshold: float = 40.0
@export var substances_reference: float = 160.0
@export var distortion_multiplier: float = 2.5

@export var disease_threshold: float = 60.0
@export var disease_reference: float = 40.0

# ================================================================
# SHADERS EMBEBIDOS
# ================================================================
const POST_EFFECTS_SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 8.0) = 0.0;
uniform float distortion_amount : hint_range(0.0, 1.0) = 0.0;
uniform float chromatic_amount : hint_range(0.0, 2.0) = 0.0;
uniform float time_scale : hint_range(0.0, 4.0) = 1.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME * time_scale;
	float d = distortion_amount;

	vec2 wave = vec2(
		sin((uv.y * 18.0) + (t * 1.7)) * 0.010,
		cos((uv.x * 15.0) + (t * 1.2)) * 0.007
	);
	uv += wave * d;

	float radius = blur_amount * 1.25;
	vec2 px = SCREEN_PIXEL_SIZE * radius;

	vec4 col = texture(screen_texture, uv) * 0.36;
	col += texture(screen_texture, uv + vec2( px.x,  0.0)) * 0.12;
	col += texture(screen_texture, uv + vec2(-px.x,  0.0)) * 0.12;
	col += texture(screen_texture, uv + vec2( 0.0,  px.y)) * 0.12;
	col += texture(screen_texture, uv + vec2( 0.0, -px.y)) * 0.12;
	col += texture(screen_texture, uv + vec2( px.x,  px.y)) * 0.04;
	col += texture(screen_texture, uv + vec2(-px.x,  px.y)) * 0.04;
	col += texture(screen_texture, uv + vec2( px.x, -px.y)) * 0.04;
	col += texture(screen_texture, uv + vec2(-px.x, -px.y)) * 0.04;

	float ca = chromatic_amount * d * 2.0;
	if (ca > 0.001) {
		col.r = texture(screen_texture, uv + vec2(SCREEN_PIXEL_SIZE.x * ca, 0.0)).r;
		col.b = texture(screen_texture, uv - vec2(SCREEN_PIXEL_SIZE.x * ca, 0.0)).b;
	}

	COLOR = vec4(col.rgb, 1.0);
}
"""

const VIGNETTE_SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float softness : hint_range(0.1, 2.0) = 1.05;
uniform vec4 tint_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 centered = (UV * 2.0) - vec2(1.0);
	float dist = length(centered);
	float alpha = smoothstep(0.25, softness, dist) * intensity * tint_color.a;
	COLOR = vec4(tint_color.rgb, alpha);
}
"""

const DISEASE_SHADER_CODE := """
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint_color : source_color = vec4(0.36, 0.55, 0.22, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	float n = hash(floor((UV + vec2(TIME * 0.015, TIME * -0.01)) * 160.0));
	float pulse = 0.65 + 0.35 * sin(TIME * 1.4);
	float alpha = intensity * pulse * mix(0.08, 0.22, n);
	COLOR = vec4(tint_color.rgb, alpha);
}
"""

# ================================================================
# RUNTIME
# ================================================================
var _canvas: CanvasLayer
var _post_effects: ColorRect
var _blink: ColorRect
var _vignette: ColorRect
var _disease: ColorRect
var _flash: ColorRect

var _camera: Camera2D = null

var _blink_active: bool = false
var _blink_timer: float = 0.0
var _blink_interval: float = 3.0

var _stamina_blur_amount: float = 0.0
var _hit_blur_amount: float = 0.0
var _distortion_amount: float = 0.0

var _hit_blur_active: bool = false
var _trauma_shake_active: bool = false
var _effects_hidden_by_state: bool = false

var _suppression_reasons: Dictionary = {}
var _force_visible_reasons: Dictionary = {}

# ================================================================
# READY
# ================================================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_nodes()
	_connect_signals()

	call_deferred("refresh_effects")


func _build_nodes() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = EFFECTS_LAYER
	_canvas.name = "EffectsCanvas"
	add_child(_canvas)

	# Orden visual:
	# 1) PostEffects: blur + distorsión juntos.
	# 2) Blink.
	# 3) Vignette.
	# 4) Disease.
	# 5) Flash.
	_post_effects = _make_fullscreen_rect("PostEffects")
	_post_effects.material = _make_shader_material(POST_EFFECTS_SHADER_CODE)
	_canvas.add_child(_post_effects)

	_blink = _make_fullscreen_rect("Blink")
	_blink.color = Color(0, 0, 0, 1)
	_canvas.add_child(_blink)

	_vignette = _make_fullscreen_rect("Vignette")
	_vignette.material = _make_shader_material(VIGNETTE_SHADER_CODE)
	_canvas.add_child(_vignette)

	_disease = _make_fullscreen_rect("Disease")
	_disease.material = _make_shader_material(DISEASE_SHADER_CODE)
	_canvas.add_child(_disease)

	_flash = _make_fullscreen_rect("Flash")
	_flash.color = Color(1, 1, 1, 0)
	_canvas.add_child(_flash)

	_set_visible_all(false)
	_apply_post_effects()


func _make_fullscreen_rect(node_name: String) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.visible = false
	return rect


func _make_shader_material(shader_code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = shader_code

	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


func _connect_signals() -> void:
	if PlayerStats and not PlayerStats.stats_updated.is_connected(_on_stats_updated):
		PlayerStats.stats_updated.connect(_on_stats_updated)

	if StateManager and not StateManager.state_changed.is_connected(_on_state_changed):
		StateManager.state_changed.connect(_on_state_changed)


# ================================================================
# PROCESS
# ================================================================
func _process(delta: float) -> void:
	_refresh_runtime_camera()

	if not _should_show_effects():
		_hide_effects_for_state_or_suppression()
		return

	if _effects_hidden_by_state:
		_effects_hidden_by_state = false
		refresh_effects()

	_update_stamina_effects()
	_update_blink(delta)


func _should_show_effects() -> bool:
	if is_suppressed():
		return false

	if not _force_visible_reasons.is_empty():
		return true

	if not StateManager:
		return true

	return (
		StateManager.is_gameplay()
		or StateManager.is_hiding()
		or StateManager.is_dialog()
		or StateManager.is_journal()
		or StateManager.is_transitioning()
		or StateManager.is_debug_menu()
	)


func _hide_effects_for_state_or_suppression() -> void:
	if _effects_hidden_by_state:
		return

	_set_visible_all(false)
	_reset_camera_offset()
	_blink_active = false
	_effects_hidden_by_state = true


func _update_blink(delta: float) -> void:
	if not _blink_active:
		return

	_blink_timer += delta
	if _blink_timer >= _blink_interval:
		_blink_timer = 0.0
		_do_blink()


# ================================================================
# STATS / REFRESH
# ================================================================
func _on_stats_updated() -> void:
	refresh_effects()


func _on_state_changed(_from_state, _to_state) -> void:
	if _should_show_effects():
		refresh_effects()
	else:
		_hide_effects_for_state_or_suppression()


func refresh_effects() -> void:
	if not _should_show_effects():
		_hide_effects_for_state_or_suppression()
		return

	_update_vignette()
	_update_distortion()
	_update_blink_state()
	_update_disease()
	_apply_post_effects()
	effects_refreshed.emit()


func _update_stamina_effects() -> void:
	var stamina := _get_stat_float("stamina", stamina_reference)
	var stamina_ratio: float = clamp(stamina / max(stamina_reference, 0.001), 0.0, 1.0)
	var intensity: float = 1.0 - stamina_ratio

	_stamina_blur_amount = intensity * stamina_blur_max
	_apply_post_effects()

	if intensity > 0.0:
		if not _trauma_shake_active and _camera and is_instance_valid(_camera):
			var t: float = Time.get_ticks_msec() * 0.01
			_camera.offset = Vector2(
				sin(t * 7.3) * intensity * stamina_shake_max,
				cos(t * 6.1) * intensity * stamina_shake_max
			)
	else:
		if not _trauma_shake_active:
			_reset_camera_offset()


func _update_vignette() -> void:
	var miedo := _get_stat_float("miedo", 0.0)

	if miedo > fear_threshold:
		_vignette.visible = true
		var intensity: float = clamp((miedo - fear_threshold) / max(100.0 - fear_threshold, 0.001), 0.0, 1.0)
		_set_shader_param(_vignette, "intensity", intensity * fear_vignette_max)
	else:
		_vignette.visible = false


func _update_distortion() -> void:
	var alcohol := _get_stat_float("alcohol", 0.0)
	var laudano := _get_stat_float("laudano", 0.0)
	var sustancias := alcohol + laudano

	if sustancias > substances_threshold:
		var intensity: float = clamp((sustancias - substances_threshold) / max(substances_reference, 0.001), 0.0, 1.0)
		_distortion_amount = clamp(intensity * distortion_multiplier, 0.0, 1.0)
	else:
		_distortion_amount = 0.0

	_apply_post_effects()


func _update_blink_state() -> void:
	var sueno := _get_stat_float("sueno", 100.0)

	if sueno < sleep_blink_threshold:
		_blink_active = true
		var ratio: float = clamp(sueno / max(sleep_blink_threshold, 0.001), 0.0, 1.0)
		_blink_interval = lerp(blink_interval_min, blink_interval_max, ratio)
	else:
		_blink_active = false
		_blink.visible = false


func _update_disease() -> void:
	var enfermedad := _get_stat_float("enfermedad", 0.0)

	if enfermedad >= disease_threshold:
		_disease.visible = true
		var intensity: float = clamp((enfermedad - disease_threshold) / max(disease_reference, 0.001), 0.0, 1.0)
		_set_shader_param(_disease, "intensity", intensity)
	else:
		_disease.visible = false


func _apply_post_effects() -> void:
	if not _post_effects:
		return

	var total_blur: float = max(_stamina_blur_amount, _hit_blur_amount)
	var has_post_effect: bool = total_blur > 0.001 or _distortion_amount > 0.001

	_post_effects.visible = has_post_effect and _should_show_effects()
	_set_shader_param(_post_effects, "blur_amount", total_blur)
	_set_shader_param(_post_effects, "distortion_amount", _distortion_amount)
	_set_shader_param(_post_effects, "chromatic_amount", 1.0)


func _do_blink() -> void:
	_blink.modulate.a = 0.85
	_blink.visible = true

	var tw := create_tween()
	tw.tween_property(_blink, "modulate:a", 0.0, BLINK_DURATION)
	tw.tween_callback(func(): _blink.visible = false)




# ================================================================
# API PÚBLICA — COMPATIBILIDAD STAMINA
# ================================================================
func on_stamina_exhausted(_exhausted: bool) -> void:
	# PlayerMovement avisa cuando Nell queda agotada o se recupera.
	# El efecto de stamina se calcula de forma progresiva en _process(),
	# así que aquí solo forzamos una actualización inmediata para evitar
	# frames raros y mantener compatibilidad con el script de movimiento.
	if not _should_show_effects():
		return

	_update_stamina_effects()
	_apply_post_effects()


# ================================================================
# API PÚBLICA — SUPRESIÓN
# ================================================================
func suppress_for_ui(reason: String = "ui") -> void:
	var clean_reason := _clean_reason(reason)
	_suppression_reasons[clean_reason] = true
	_hide_effects_for_state_or_suppression()
	effects_suppression_changed.emit(true, get_suppression_reasons())


func restore_after_ui(reason: String = "ui") -> void:
	var clean_reason := _clean_reason(reason)
	if _suppression_reasons.has(clean_reason):
		_suppression_reasons.erase(clean_reason)

	var suppressed := is_suppressed()
	if not suppressed:
		_effects_hidden_by_state = false
		refresh_effects()

	effects_suppression_changed.emit(suppressed, get_suppression_reasons())


func set_suppressed(value: bool, reason: String = "manual") -> void:
	if value:
		suppress_for_ui(reason)
	else:
		restore_after_ui(reason)


func is_suppressed() -> bool:
	return not _suppression_reasons.is_empty()


func get_suppression_reasons() -> PackedStringArray:
	var result := PackedStringArray()
	for key in _suppression_reasons.keys():
		result.append(str(key))
	return result


# ================================================================
# API PÚBLICA — VISIBILIDAD FORZADA
# ================================================================
func force_visible(reason: String = "transition") -> void:
	var clean_reason := _clean_reason(reason)
	_force_visible_reasons[clean_reason] = true
	_effects_hidden_by_state = false
	refresh_effects()


func clear_force_visible(reason: String = "transition") -> void:
	var clean_reason := _clean_reason(reason)

	if _force_visible_reasons.has(clean_reason):
		_force_visible_reasons.erase(clean_reason)

	if _force_visible_reasons.is_empty():
		if _should_show_effects():
			refresh_effects()
		else:
			_hide_effects_for_state_or_suppression()


func clear_all_force_visible() -> void:
	_force_visible_reasons.clear()

	if _should_show_effects():
		refresh_effects()
	else:
		_hide_effects_for_state_or_suppression()


func is_force_visible() -> bool:
	return not _force_visible_reasons.is_empty()


# ================================================================
# API PÚBLICA — FLASH / SHAKE
# ================================================================
func pulse_flash(color: Color = Color(1, 1, 1, 0.75), duration: float = DEFAULT_FLASH_DURATION) -> void:
	if not _flash:
		return

	if not _should_show_effects():
		return

	_flash.visible = true
	_flash.color = color

	var tw := create_tween()
	tw.tween_property(_flash, "color", Color(color.r, color.g, color.b, 0.0), max(duration, 0.01))
	tw.tween_callback(func(): _flash.visible = false)


func trauma_shake(intensity: float = 10.0, duration: float = 0.3, flash_color: Color = Color(1.0, 0.47, 0.39, 0.9)) -> void:
	_refresh_runtime_camera()

	pulse_flash(flash_color, min(duration, 0.2))
	_do_hit_blur(duration)
	_do_camera_shake(intensity, duration)

	screen_shake_started.emit(intensity, duration)


func screen_shake(intensity: float = 10.0, duration: float = 0.3) -> void:
	# Alias compatible con llamadas antiguas.
	trauma_shake(intensity, duration)


func clear_screen_effects(reset_camera: bool = true) -> void:
	_set_visible_all(false)
	_blink_active = false
	_hit_blur_active = false
	_trauma_shake_active = false
	_stamina_blur_amount = 0.0
	_hit_blur_amount = 0.0
	_distortion_amount = 0.0
	_apply_post_effects()

	if reset_camera:
		_reset_camera_offset()


# ================================================================
# INTERNOS — SHAKE / BLUR
# ================================================================
func _do_hit_blur(duration: float) -> void:
	if not _should_show_effects():
		return

	_hit_blur_active = true
	_hit_blur_amount = stamina_blur_max
	_apply_post_effects()

	var tw := create_tween()
	tw.tween_method(
		func(value: float) -> void:
			_hit_blur_amount = value
			_apply_post_effects(),
		stamina_blur_max,
		0.0,
		max(duration, 0.05)
	)
	tw.tween_callback(func():
		_hit_blur_active = false
		_hit_blur_amount = 0.0
		_apply_post_effects()
	)


func _do_camera_shake(intensity: float, duration: float) -> void:
	if not _camera or not is_instance_valid(_camera):
		return

	_trauma_shake_active = true

	var tw := create_tween()
	var steps: int = max(4, int(duration / 0.025))

	for i in range(steps):
		var progress := float(i) / float(max(steps - 1, 1))
		var decay := 1.0 - progress
		tw.tween_property(
			_camera,
			"offset",
			Vector2(
				randf_range(-intensity, intensity) * decay,
				randf_range(-intensity * 0.8, intensity * 0.8) * decay
			),
			0.025
		)

	tw.tween_property(_camera, "offset", Vector2.ZERO, 0.04)
	tw.tween_callback(func():
		_trauma_shake_active = false
		_reset_camera_offset()
	)


# ================================================================
# UTILS
# ================================================================
func _refresh_runtime_camera() -> void:
	_camera = get_viewport().get_camera_2d()


func _reset_camera_offset() -> void:
	if _camera and is_instance_valid(_camera):
		_camera.offset = Vector2.ZERO


func _set_visible_all(value: bool) -> void:
	for node in [_post_effects, _vignette, _blink, _disease, _flash]:
		if node:
			node.visible = value


func _set_shader_param(rect: ColorRect, param_name: String, value) -> void:
	if rect and rect.material:
		rect.material.set_shader_parameter(param_name, value)


func _get_stat_float(property_name: String, fallback: float = 0.0) -> float:
	if not PlayerStats:
		return fallback

	var value = PlayerStats.get(property_name)
	if value == null:
		return fallback

	return float(value)


func _clean_reason(reason: String) -> String:
	var clean := reason.strip_edges()
	if clean.is_empty():
		return "unknown"
	return clean
