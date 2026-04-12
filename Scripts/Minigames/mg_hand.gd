extends Control

signal minigame_finished(result: Dictionary)

# =========================================================
# MG HAND
# ---------------------------------------------------------
# IZQUIERDA:
# - F / acción "interact" / botón X = ritmo
#
# DERECHA:
# - ratón horizontal / stick derecho horizontal = estado mental
#
# ESTADO MENTAL:
# - izquierda  = REALIDAD
# - centro     = CORAZA
# - derecha    = DISOCIACIÓN
#
# EFECTOS:
# - REALIDAD acelera el ritmo
# - DISOCIACIÓN lo vuelve inestable
#
# IMPORTANTE:
# - NO falla si dejas pasar la zona
# - SOLO falla si pulsas F fuera de la zona correcta
# =========================================================

# =========================================================
# CONFIG GENERAL
# =========================================================
const TOTAL_HITS: int = 6
const MAX_MISTAKES: int = 5

@export var input_action: String = "interact"
@export var auto_start_delay: float = 0.0

# Ritmo base
@export var start_speed: float = 180.0
@export var speed_step_per_hit: float = 18.0
@export var max_speed: float = 320.0
@export var start_direction: float = -1.0 # -1 = sube, 1 = baja

# Barra mental
@export var mouse_sensitivity: float = 0.006
@export var stick_sensitivity: float = 1.8
@export var armor_half_width: float = 0.18

# Deriva mental automática
@export var mental_drift_strength: float = 0.18
@export var mental_drift_change_min: float = 0.35
@export var mental_drift_change_max: float = 0.85

# Más inestabilidad mental
@export var mental_noise_strength: float = 0.32
@export var mental_wobble_amplitude: float = 0.10
@export var mental_wobble_frequency: float = 1.25
@export var center_repulsion_strength: float = 0.22

# REALIDAD
@export var reality_speed_bonus_max: float = 0.55

# DISOCIACIÓN
@export var dissociation_wave_amplitude: float = 0.30
@export var dissociation_wave_frequency: float = 7.0
@export var dissociation_jitter_amplitude: float = 0.20
@export var dissociation_jitter_change_time: float = 0.18
@export var dissociation_jitter_lerp_speed: float = 5.0

# =========================================================
# GAME FEEL
# =========================================================
@export var hit_flash_alpha: float = 0.16
@export var hit_zone_pulse_extra: float = 0.18
@export var hit_zone_pulse_decay: float = 7.0
@export var hit_cursor_squash_x: float = 1.10
@export var hit_cursor_squash_y: float = 0.88

@export var fail_flash_alpha: float = 0.24
@export var fail_shake_distance: float = 10.0
@export var fail_shake_steps: int = 4

@export var target_pulse_speed: float = 1.5
@export var target_pulse_strength: float = 0.10

@export var reality_tint_strength: float = 0.22
@export var dissociation_tint_strength: float = 0.18
@export var dissociation_cursor_fade_strength: float = 0.10

# =========================================================
# DATOS OPCIONALES SI SE LLAMA DESDE OTRO SISTEMA
# =========================================================
var acto: String = "mano"
var tipo_cliente: String = ""
var skin_name: String = ""

func setup(p_acto: String = "mano", p_tipo_cliente: String = "", p_skin_name: String = "") -> void:
	acto = p_acto
	tipo_cliente = p_tipo_cliente
	skin_name = p_skin_name

# =========================================================
# NODOS
# =========================================================
@onready var bg: ColorRect = get_node_or_null("BG") as ColorRect
@onready var panel: Control = get_node_or_null("Center/Panel") as Control

@onready var title_label: Label = get_node_or_null("Center/Panel/Title") as Label
@onready var subtitle_label: Label = get_node_or_null("Center/Panel/Subtitle") as Label

@onready var bar_bg: Control = get_node_or_null("Center/Panel/RhythmArea/BarBG") as Control
@onready var top_zone: Control = get_node_or_null("Center/Panel/RhythmArea/BarBG/TopZone") as Control
@onready var bottom_zone: Control = get_node_or_null("Center/Panel/RhythmArea/BarBG/BottomZone") as Control
@onready var cursor: Control = get_node_or_null("Center/Panel/RhythmArea/BarBG/Cursor") as Control

@onready var mental_bar_bg: Control = get_node_or_null("Center/Panel/MentalArea/MentalBarBG") as Control
@onready var armor_zone: Control = get_node_or_null("Center/Panel/MentalArea/MentalBarBG/ArmorZone") as Control
@onready var mental_cursor: Control = get_node_or_null("Center/Panel/MentalArea/MentalBarBG/MentalCursor") as Control
@onready var reality_label: Label = get_node_or_null("Center/Panel/MentalArea/RealityLabel") as Label
@onready var dissociation_label: Label = get_node_or_null("Center/Panel/MentalArea/DissociationLabel") as Label

@onready var progress_label: Label = get_node_or_null("Center/Panel/ProgressLabel") as Label
@onready var mistakes_label: Label = get_node_or_null("Center/Panel/MistakesLabel") as Label
@onready var left_hint: Label = get_node_or_null("Center/Panel/LeftHint") as Label
@onready var right_hint: Label = get_node_or_null("Center/Panel/RightHint") as Label

@onready var success_flash: ColorRect = get_node_or_null("SuccessFlash") as ColorRect
@onready var fail_flash: ColorRect = get_node_or_null("FailFlash") as ColorRect

@onready var animation_player: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer
@onready var success_sfx: AudioStreamPlayer = get_node_or_null("SuccessSFX") as AudioStreamPlayer
@onready var fail_sfx: AudioStreamPlayer = get_node_or_null("FailSFX") as AudioStreamPlayer
@onready var timer_start: Timer = get_node_or_null("TimerStart") as Timer

# =========================================================
# ESTADO
# =========================================================
var running: bool = false
var finished: bool = false

var cursor_dir: float = -1.0
var current_base_speed: float = 0.0
var target_is_top: bool = true

# mental_value:
# -1.0 = REALIDAD
#  0.0 = CORAZA
# +1.0 = DISOCIACIÓN
var mental_value: float = 0.0
var drift_direction: float = 0.0
var drift_change_timer: float = 0.0

var dissociation_jitter_timer: float = 0.0
var dissociation_jitter_target: float = 0.0
var dissociation_jitter_current: float = 0.0

var current_hits: int = 0
var current_mistakes: int = 0

var elapsed_time: float = 0.0
var precision_total: float = 0.0
var mental_quality_total: float = 0.0

var time_in_reality: float = 0.0
var time_in_armor: float = 0.0
var time_in_dissociation: float = 0.0

# Game feel
var base_panel_position: Vector2 = Vector2.ZERO
var base_cursor_scale: Vector2 = Vector2.ONE
var base_top_zone_scale: Vector2 = Vector2.ONE
var base_bottom_zone_scale: Vector2 = Vector2.ONE
var pulse_time: float = 0.0
var top_zone_hit_boost: float = 0.0
var bottom_zone_hit_boost: float = 0.0

# =========================================================
# READY
# =========================================================
func _ready() -> void:
	randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS

	if timer_start:
		timer_start.process_mode = Node.PROCESS_MODE_ALWAYS

	current_base_speed = start_speed
	cursor_dir = start_direction

	if panel:
		base_panel_position = panel.position

	if cursor:
		base_cursor_scale = cursor.scale

	if top_zone:
		base_top_zone_scale = top_zone.scale

	if bottom_zone:
		base_bottom_zone_scale = bottom_zone.scale

	if bg:
		bg.color = Color(0, 0, 0, 0.80)

	if success_flash:
		success_flash.color = Color(1, 1, 1, 0)

	if fail_flash:
		fail_flash.color = Color(1, 0.15, 0.15, 0)

	if title_label:
		title_label.text = "HAND / TRÁMITE"

	if left_hint:
		left_hint.text = "F / X = ritmo"

	if right_hint:
		right_hint.text = "Ratón / Stick derecho = coraza"

	_reset_cursor()
	_reset_mental_cursor()
	_update_ui()
	_update_state_visuals()

	if auto_start_delay <= 0.0 or timer_start == null:
		_start_minigame()
	else:
		timer_start.wait_time = auto_start_delay
		timer_start.one_shot = true
		if not timer_start.timeout.is_connected(_on_timer_start_timeout):
			timer_start.timeout.connect(_on_timer_start_timeout)
		timer_start.start()

# =========================================================
# INPUT
# =========================================================
func _input(event: InputEvent) -> void:
	if finished:
		return

	if event is InputEventMouseMotion and running:
		var mm := event as InputEventMouseMotion
		mental_value += mm.relative.x * mouse_sensitivity
		mental_value = clamp(mental_value, -1.0, 1.0)
		_update_mental_cursor()

	if running and _is_rhythm_press(event):
		accept_event()
		_try_hit()

func _is_rhythm_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.physical_keycode == KEY_F or key_event.keycode == KEY_F:
				return true

	if event is InputEventJoypadButton:
		var joy_event := event as InputEventJoypadButton
		if joy_event.pressed and joy_event.button_index == JOY_BUTTON_X:
			return true

	if input_action != "" and event.is_action_pressed(input_action):
		return true

	return false

# =========================================================
# PROCESS
# =========================================================
func _process(delta: float) -> void:
	if not running or finished:
		return

	elapsed_time += delta
	pulse_time += delta

	_update_gamepad_mental_input(delta)
	_update_mental_drift(delta)
	_update_dissociation_jitter(delta)
	_update_zone_timers(delta)

	_decay_hit_boosts(delta)
	_update_mental_cursor()
	_update_target_pulse()
	_update_state_visuals()
	_update_rhythm_cursor(delta)

# =========================================================
# START / FINISH
# =========================================================
func _on_timer_start_timeout() -> void:
	_start_minigame()

func _start_minigame() -> void:
	running = true

func _finish(success: bool) -> void:
	if finished:
		return

	finished = true
	running = false

	var result := {
		"success": success,
		"satisfaction": _calculate_satisfaction(success),
		"acto": acto,
		"tipo_cliente": tipo_cliente,
		"skin_name": skin_name,
		"correct_hits": current_hits,
		"mistakes": current_mistakes,
		"time_in_reality": time_in_reality,
		"time_in_armor": time_in_armor,
		"time_in_dissociation": time_in_dissociation
	}

	if subtitle_label:
		subtitle_label.text = "Terminado" if success else "Fallido"

	print("MG_Hand result: ", result)
	minigame_finished.emit(result)

# =========================================================
# RITMO
# =========================================================
func _update_rhythm_cursor(delta: float) -> void:
	if bar_bg == null or cursor == null:
		return

	var min_y: float = 0.0
	var max_y: float = max(0.0, bar_bg.size.y - cursor.size.y)

	var speed := _get_modified_rhythm_speed()
	cursor.position.y += speed * cursor_dir * delta

	if cursor.position.y <= min_y:
		cursor.position.y = min_y
		cursor_dir = 1.0
	elif cursor.position.y >= max_y:
		cursor.position.y = max_y
		cursor_dir = -1.0

func _get_modified_rhythm_speed() -> float:
	var speed: float = current_base_speed

	# REALIDAD = acelera
	if mental_value < -armor_half_width:
		var reality_strength := inverse_lerp(-armor_half_width, -1.0, mental_value)
		reality_strength = clamp(reality_strength, 0.0, 1.0)
		speed *= 1.0 + reality_strength * reality_speed_bonus_max

	# DISOCIACIÓN = ritmo inestable
	elif mental_value > armor_half_width:
		var diss_strength := inverse_lerp(armor_half_width, 1.0, mental_value)
		diss_strength = clamp(diss_strength, 0.0, 1.0)

		var wave := sin(elapsed_time * dissociation_wave_frequency * TAU) * dissociation_wave_amplitude
		var jitter := dissociation_jitter_current * dissociation_jitter_amplitude
		var factor := 1.0 + (wave + jitter) * diss_strength

		speed *= max(0.45, factor)

	return speed

func _try_hit() -> void:
	var zone: Control = _get_target_zone()

	if zone and _cursor_overlaps_zone(zone):
		_play_hit_feedback(zone)

		current_hits += 1
		precision_total += _get_hit_precision(zone)
		mental_quality_total += _get_mental_quality()
		current_base_speed = min(current_base_speed + speed_step_per_hit, max_speed)

		target_is_top = not target_is_top

		if success_sfx and success_sfx.stream:
			success_sfx.play()

		_update_ui()

		if current_hits >= TOTAL_HITS:
			_finish(true)
	else:
		_register_mistake()

func _register_mistake() -> void:
	current_mistakes += 1

	# Al fallar, Nell cae más hacia REALIDAD
	mental_value = clamp(mental_value - 0.16, -1.0, 1.0)

	if fail_sfx and fail_sfx.stream:
		fail_sfx.play()

	_play_fail_feedback()
	_update_ui()

	if current_mistakes >= MAX_MISTAKES:
		_finish(false)

func _get_target_zone() -> Control:
	return top_zone if target_is_top else bottom_zone

func _cursor_overlaps_zone(zone: Control) -> bool:
	if cursor == null or zone == null:
		return false

	var cursor_top: float = cursor.position.y
	var cursor_bottom: float = cursor.position.y + cursor.size.y

	var zone_top: float = zone.position.y
	var zone_bottom: float = zone.position.y + zone.size.y

	return cursor_bottom >= zone_top and cursor_top <= zone_bottom

func _get_hit_precision(zone: Control) -> float:
	if cursor == null or zone == null:
		return 0.0

	var cursor_center: float = cursor.position.y + cursor.size.y * 0.5
	var zone_center: float = zone.position.y + zone.size.y * 0.5
	var half_zone: float = max(zone.size.y * 0.5, 1.0)

	var dist: float = abs(cursor_center - zone_center)
	return clamp(1.0 - (dist / half_zone), 0.0, 1.0)

# =========================================================
# BARRA MENTAL
# =========================================================
func _update_gamepad_mental_input(delta: float) -> void:
	var stick_x: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)

	if abs(stick_x) > 0.12:
		mental_value += stick_x * stick_sensitivity * delta
		mental_value = clamp(mental_value, -1.0, 1.0)

func _update_mental_drift(delta: float) -> void:
	drift_change_timer -= delta
	if drift_change_timer <= 0.0:
		drift_change_timer = randf_range(mental_drift_change_min, mental_drift_change_max)
		drift_direction = randf_range(-1.0, 1.0)

	# Deriva base aleatoria
	mental_value += drift_direction * mental_drift_strength * delta

	# Ruido fino continuo
	mental_value += randf_range(-mental_noise_strength, mental_noise_strength) * delta

	# Onda suave para que nunca esté quieta
	mental_value += sin(elapsed_time * mental_wobble_frequency * TAU) * mental_wobble_amplitude * delta

	# Repulsión del centro: sostener CORAZA cuesta
	var push_dir: float = 0.0
	if abs(mental_value) > 0.03:
		push_dir = sign(mental_value)
	else:
		push_dir = drift_direction if drift_direction != 0.0 else 1.0

	var center_strength: float = 1.0 - min(abs(mental_value), 1.0)
	mental_value += push_dir * center_strength * center_repulsion_strength * delta

	mental_value = clamp(mental_value, -1.0, 1.0)

func _update_dissociation_jitter(delta: float) -> void:
	dissociation_jitter_timer -= delta
	if dissociation_jitter_timer <= 0.0:
		dissociation_jitter_timer = dissociation_jitter_change_time
		dissociation_jitter_target = randf_range(-1.0, 1.0)

	dissociation_jitter_current = lerp(
		dissociation_jitter_current,
		dissociation_jitter_target,
		clamp(delta * dissociation_jitter_lerp_speed, 0.0, 1.0)
	)

func _update_zone_timers(delta: float) -> void:
	if mental_value < -armor_half_width:
		time_in_reality += delta
	elif mental_value > armor_half_width:
		time_in_dissociation += delta
	else:
		time_in_armor += delta

func _get_mental_quality() -> float:
	var distance_from_center: float = abs(mental_value)

	if distance_from_center <= armor_half_width:
		return 1.0

	var extra := inverse_lerp(armor_half_width, 1.0, distance_from_center)
	return clamp(1.0 - extra, 0.0, 1.0)

func _update_mental_cursor() -> void:
	if mental_bar_bg == null or mental_cursor == null:
		return

	var max_x: float = max(0.0, mental_bar_bg.size.x - mental_cursor.size.x)
	var normalized: float = (mental_value + 1.0) * 0.5
	mental_cursor.position.x = normalized * max_x

# =========================================================
# UI / VISUAL
# =========================================================
func _reset_cursor() -> void:
	if cursor == null or bar_bg == null:
		return
	cursor.position.y = (bar_bg.size.y - cursor.size.y) * 0.5

func _reset_mental_cursor() -> void:
	mental_value = 0.0
	_update_mental_cursor()

func _update_ui() -> void:
	if progress_label:
		progress_label.text = "Aciertos: %d / %d" % [current_hits, TOTAL_HITS]

	if mistakes_label:
		mistakes_label.text = "Fallos: %d / %d" % [current_mistakes, MAX_MISTAKES]

func _update_target_pulse() -> void:
	if top_zone == null or bottom_zone == null:
		return

	var pulse := 1.0 + sin(pulse_time * target_pulse_speed * TAU) * target_pulse_strength

	var top_mul: float = pulse if target_is_top else 1.0
	var bottom_mul: float = pulse if not target_is_top else 1.0

	top_zone.scale = base_top_zone_scale * (top_mul + top_zone_hit_boost)
	bottom_zone.scale = base_bottom_zone_scale * (bottom_mul + bottom_zone_hit_boost)

func _decay_hit_boosts(delta: float) -> void:
	top_zone_hit_boost = max(0.0, top_zone_hit_boost - hit_zone_pulse_decay * delta)
	bottom_zone_hit_boost = max(0.0, bottom_zone_hit_boost - hit_zone_pulse_decay * delta)

func _play_hit_feedback(zone: Control) -> void:
	if success_flash:
		var flash_tween := create_tween()
		flash_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		success_flash.color.a = 0.0
		flash_tween.tween_property(success_flash, "color:a", hit_flash_alpha, 0.035)
		flash_tween.tween_property(success_flash, "color:a", 0.0, 0.10)

	if cursor:
		var cursor_tween := create_tween()
		cursor_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		cursor.scale = Vector2(base_cursor_scale.x * hit_cursor_squash_x, base_cursor_scale.y * hit_cursor_squash_y)
		cursor_tween.tween_property(cursor, "scale", base_cursor_scale, 0.10)

	if zone == top_zone:
		top_zone_hit_boost = max(top_zone_hit_boost, hit_zone_pulse_extra)
	elif zone == bottom_zone:
		bottom_zone_hit_boost = max(bottom_zone_hit_boost, hit_zone_pulse_extra)

func _play_fail_feedback() -> void:
	if fail_flash:
		var flash_tween := create_tween()
		flash_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		fail_flash.color.a = 0.0
		flash_tween.tween_property(fail_flash, "color:a", fail_flash_alpha, 0.04)
		flash_tween.tween_property(fail_flash, "color:a", 0.0, 0.12)

	if panel:
		var shake_tween := create_tween()
		shake_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

		for i in range(fail_shake_steps):
			var dir := -1.0 if i % 2 == 0 else 1.0
			shake_tween.tween_property(
				panel,
				"position",
				base_panel_position + Vector2(dir * fail_shake_distance, 0.0),
				0.022
			)

		shake_tween.tween_property(panel, "position", base_panel_position, 0.04)

	if mental_cursor:
		var mental_tween := create_tween()
		mental_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		mental_cursor.scale = Vector2(1.15, 0.92)
		mental_tween.tween_property(mental_cursor, "scale", Vector2.ONE, 0.10)

func _update_state_visuals() -> void:
	var top_mod := Color(1, 1, 1, 1)
	var bottom_mod := Color(1, 1, 1, 1)

	if mental_value < -armor_half_width:
		var reality_strength := inverse_lerp(-armor_half_width, -1.0, mental_value)
		reality_strength = clamp(reality_strength, 0.0, 1.0)

		if bg:
			bg.color = Color(
				0.12 + reality_strength * 0.10,
				0.02,
				0.02,
				0.80 + reality_strength * reality_tint_strength
			)

		if panel:
			panel.scale = Vector2(
				1.0 + reality_strength * 0.012,
				1.0 + reality_strength * 0.006
			)

		if mental_cursor:
			mental_cursor.modulate = Color(1, 1, 1, 1)

		if reality_label:
			reality_label.modulate = Color(1, 1, 1, 1)

		if dissociation_label:
			dissociation_label.modulate = Color(0.6, 0.6, 0.6, 0.8)

		top_mod = Color(1.0, 0.92, 0.92, 1.0)
		bottom_mod = Color(1.0, 0.92, 0.92, 1.0)

	elif mental_value > armor_half_width:
		var diss_strength := inverse_lerp(armor_half_width, 1.0, mental_value)
		diss_strength = clamp(diss_strength, 0.0, 1.0)

		if bg:
			bg.color = Color(
				0.02 + diss_strength * 0.03,
				0.02 + diss_strength * 0.03,
				0.04 + diss_strength * 0.08,
				0.80 + diss_strength * dissociation_tint_strength
			)

		if panel:
			panel.scale = Vector2(
				1.0 - diss_strength * 0.008,
				1.0 + diss_strength * 0.004
			)

		if mental_cursor:
			mental_cursor.modulate = Color(1, 1, 1, 1.0 - diss_strength * dissociation_cursor_fade_strength)

		if reality_label:
			reality_label.modulate = Color(0.6, 0.6, 0.6, 0.8)

		if dissociation_label:
			dissociation_label.modulate = Color(1, 1, 1, 1)

		top_mod = Color(0.90, 0.90, 0.98, 1.0)
		bottom_mod = Color(0.90, 0.90, 0.98, 1.0)

	else:
		if bg:
			bg.color = Color(0, 0, 0, 0.80)

		if panel:
			panel.scale = Vector2.ONE

		if mental_cursor:
			mental_cursor.modulate = Color(1, 1, 1, 1)

		if reality_label:
			reality_label.modulate = Color(0.8, 0.8, 0.8, 0.9)

		if dissociation_label:
			dissociation_label.modulate = Color(0.8, 0.8, 0.8, 0.9)

	if top_zone and bottom_zone:
		if target_is_top:
			top_zone.modulate = top_mod
			bottom_zone.modulate = bottom_mod * Color(0.55, 0.55, 0.55, 0.85)
		else:
			top_zone.modulate = top_mod * Color(0.55, 0.55, 0.55, 0.85)
			bottom_zone.modulate = bottom_mod

	if subtitle_label:
		var mental_text := "CORAZA"
		if mental_value < -armor_half_width:
			mental_text = "REALIDAD"
		elif mental_value > armor_half_width:
			mental_text = "DISOCIACIÓN"

		var target_text := "ARRIBA" if target_is_top else "ABAJO"
		subtitle_label.text = "%s · %s" % [target_text, mental_text]

# =========================================================
# RESULTADO
# =========================================================
func _calculate_satisfaction(success: bool) -> float:
	var avg_precision: float = 0.0
	if current_hits > 0:
		avg_precision = precision_total / float(current_hits)

	var avg_mental: float = 0.0
	if current_hits > 0:
		avg_mental = mental_quality_total / float(current_hits)

	var progress_factor: float = float(current_hits) / float(TOTAL_HITS)
	var mistakes_factor: float = float(current_mistakes) / float(MAX_MISTAKES)

	var total_time: float = max(elapsed_time, 0.001)
	var armor_ratio: float = time_in_armor / total_time

	if success:
		return clamp(
			0.40 +
			avg_precision * 0.28 +
			avg_mental * 0.20 +
			armor_ratio * 0.20 -
			mistakes_factor * 0.22,
			0.0, 1.0
		)

	return clamp(
		progress_factor * 0.35 +
		avg_precision * 0.18 +
		avg_mental * 0.15 +
		armor_ratio * 0.12 -
		mistakes_factor * 0.18,
		0.0, 0.75
	)
