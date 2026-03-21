extends Label

# =========================================================
# ⚙️ GLITCH EFFECT SETTINGS
# =========================================================
@export_category("⚡ Glitch Effect Settings")
@export var display_time: float = 4.0
@export var fade_out_time: float = 0.8
@export var final_center_time: float = 1.5
@export var jump_interval_min: float = 0.4
@export var jump_interval_max: float = 1.0
@export var jump_strength: float = 0.45
@export var scale_min: float = 0.9
@export var scale_max: float = 1.1
@export var pulse_duration: float = 0.25
@export var red_flash_chance: float = 0.15

# =========================================================
# INTERNAL STATE
# =========================================================
var _start_time: float = 0.0
var _viewport_size: Vector2
var _is_fading: bool = false
var _next_jump_time: float = 0.0
var _active_tweens: Array[Tween] = []
var _in_final_center: bool = false

var _base_font_size: int = 0

# tiempos absolutos precomputados
var _jump_cutoff_time: float = 0.0       # fin de saltos aleatorios
var _center_end_time: float = 0.0        # fin de fase centrada (empieza el fade)
var _fade_duration_runtime: float = 0.0  # duración real del fade para cuadrar exacto

# =========================================================
# READY
# =========================================================

func _ready():
	_start_time = Time.get_ticks_msec() / 1000.0
	_viewport_size = get_viewport_rect().size
	modulate = Color(1, 1, 1, 1)
	scale = Vector2.ONE
	set_process(true)

	# Si dream_controller pasó una "lifetime", la usamos como display_time total
	if has_meta("lifetime"):
		display_time = float(get_meta("lifetime"))

	# Aseguramos que final_center_time no exceda el total
	final_center_time = clamp(final_center_time, 0.0, max(0.0, display_time))

	# Calculamos reparto:
	# 1) tiempo de saltos = display_time - (final_center_time + fade_out_time)
	#    si sale negativo, reducimos el fade_out_time para cuadrar exacto.
	var jump_phase = display_time - (final_center_time + fade_out_time)
	if jump_phase < 0.0:
		# Reducimos fade_out_time primero para que al menos haya centro
		var deficit = -jump_phase
		fade_out_time = max(0.0, fade_out_time - deficit)
		jump_phase = 0.0

	_jump_cutoff_time = _start_time + jump_phase
	_center_end_time = _jump_cutoff_time + final_center_time
	# El fade debe acabar exactamente en display_time total
	_fade_duration_runtime = max(0.0, ( _start_time + display_time ) - _center_end_time)

	_schedule_next_jump()

	if label_settings:
		_base_font_size = label_settings.font_size
	else:
		_base_font_size = get_theme_font_size("font_size")


# =========================================================
# PROCESS
# =========================================================
func _process(_delta):
	if _is_fading:
		return

	_viewport_size = get_viewport_rect().size
	var now = Time.get_ticks_msec() / 1000.0

	# 1) Fase de saltos -> hasta _jump_cutoff_time
	if not _in_final_center and now >= _jump_cutoff_time:
		_enter_final_center()
		return

	if _in_final_center:
		_lock_to_center()
		# ¿acabó el centro? arranca fade para llegar exacto al final
		if now >= _center_end_time:
			_fade_out_precise()
		return

	# Saltos aleatorios mientras estamos en fase de saltos
	if now >= _next_jump_time:
		_do_glitch_jump()
		_schedule_next_jump()

# =========================================================
# ⚡ INSTANT GLITCH JUMP
# =========================================================
func _do_glitch_jump():
	position = Vector2(
		randf_range(0.5 - jump_strength, 0.5 + jump_strength) * _viewport_size.x,
		randf_range(0.5 - jump_strength, 0.5 + jump_strength) * _viewport_size.y
	)

	var base_size: int = get_theme_font_size("font_size")
	var new_size: int = int(base_size * randf_range(scale_min, scale_max))

	var tween := create_tween()
	_active_tweens.append(tween)
	tween.tween_method(func(v): add_theme_font_size_override("font_size", int(v)),
		base_size, new_size, pulse_duration)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	modulate = Color(1, 0.1, 0.1, 1) if randf() < red_flash_chance else Color(1, 1, 1, 1)


# =========================================================
# 📅 NEXT JUMP
# =========================================================
func _schedule_next_jump():
	var now = Time.get_ticks_msec() / 1000.0
	_next_jump_time = now + randf_range(jump_interval_min, jump_interval_max)

# =========================================================
# 🌟 ENTER FINAL CENTER
# =========================================================
func _enter_final_center():
	_kill_all_tweens()
	_in_final_center = true

	# tamaño grande inmediato para la fase centrada
	if label_settings:
		label_settings.font_size = int(_base_font_size * 3.0)
	else:
		add_theme_font_size_override("font_size", int(_base_font_size * 3.0))

	await get_tree().process_frame
	_lock_to_center()

	# color blanco → rojo durante la fase centrada
	modulate = Color(1, 1, 1, 1)
	var t := create_tween()
	_active_tweens.append(t)
	t.tween_property(self, "modulate", Color(1, 0, 0, 1), max(0.0, _center_end_time - (Time.get_ticks_msec()/1000.0)))
	t.set_trans(Tween.TRANS_SINE)
	t.set_ease(Tween.EASE_IN_OUT)

# Mantener la Label centrada (si cambia tamaño/viewport en tiempo real)
func _lock_to_center():
	position = (_viewport_size - size) * 0.5


# =========================================================
# 🌫️ FADE OUT
# =========================================================

func _kill_all_tweens():
	for t in _active_tweens:
		if is_instance_valid(t):
			t.kill()
	_active_tweens.clear()

func _fade_out_precise():
	if _is_fading:
		return
	_is_fading = true
	_kill_all_tweens()
	set_process(false)

	var tween := create_tween()
	_active_tweens.append(tween)
	# usa la duración calculada para cuadrar al final exacto
	tween.tween_property(self, "modulate:a", 0.0, _fade_duration_runtime)
	tween.tween_callback(func ():
		# restaurar font size y limpiar
		if label_settings:
			label_settings.font_size = _base_font_size
		else:
			add_theme_font_size_override("font_size", _base_font_size)
		queue_free()
	)

# =========================================================
# 🔁 RESTART GLITCH
# =========================================================
func restart_glitch():
	_start_time = Time.get_ticks_msec() / 1000.0
	_is_fading = false
	_in_final_center = false
	modulate.a = 1.0
	scale = Vector2.ONE
	set_process(true)
	_schedule_next_jump()
