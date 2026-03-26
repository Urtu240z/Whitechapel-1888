extends Node

# ============================================================================
# MÓDULO DE MOVIMIENTO
# Gestiona todo el movimiento del personaje: caminar, correr, saltar, agacharse
# La stamina se lee desde el autoload Stats y se gestiona aquí.
# ============================================================================

# ============================================================================
# REFERENCIAS
# ============================================================================
var player: MainPlayer = null

# ============================================================================
# ESTADO DE MOVIMIENTO
# ============================================================================
var is_crouching: bool = false
var facing_right: bool = true
var was_moving: bool = false
var enabled: bool = true
var ignore_movement_until_release: bool = false

# ============================================================================
# STAMINA
# Se gasta al correr, se recupera al soltar shift.
# Recuperación rápida parado, lenta caminando.
# Si llega a 0 no puede correr hasta llegar al 20%.
# ============================================================================

# Velocidades de gasto y recuperación (unidades/segundo)
const STAMINA_DRAIN_RATE: float = 100.0 / 15.0   # agota en 15s corriendo
const STAMINA_RECOVER_IDLE: float = 100.0 / 7.0   # llena en 7s parado
const STAMINA_RECOVER_WALK: float = 100.0 / 14.0  # llena en 14s caminando
const STAMINA_MIN_TO_RUN: float = 20.0             # mínimo para volver a correr

var stamina_exhausted: bool = false  # true cuando se agota, hasta llegar al 20%

# ============================================================================
# SEÑALES
# ============================================================================
signal stamina_exhausted_changed(is_exhausted: bool)

# ============================================================================
# INICIALIZACIÓN
# ============================================================================
func initialize(p: MainPlayer) -> void:
	player = p

# ============================================================================
# PROCESAMIENTO DE MOVIMIENTO
# ============================================================================
func process_movement(delta: float) -> void:
	if not player:
		return

	# 🔴 Journal abierto → bloqueo total
	if not enabled:
		player.velocity = Vector2.ZERO
		was_moving = false
		return

	# 🔴 NUEVO — bloqueo hasta soltar teclas
	if _is_movement_input_blocked():
		player.velocity.x = 0.0
		was_moving = false
		_update_stamina(delta)
		apply_gravity(delta)
		return

	handle_input()
	apply_gravity(delta)
	handle_jump()
	_update_stamina(delta)
	handle_horizontal_movement(delta)

# ============================================================================
# ENTRADA DEL JUGADOR
# ============================================================================
func handle_input() -> void:
	if Input.is_action_just_pressed("crouch") and player.is_on_floor():
		if is_crouching:
			stop_crouch()
		else:
			start_crouch()

func start_crouch() -> void:
	is_crouching = true

func stop_crouch() -> void:
	is_crouching = false

# ============================================================================
# GRAVEDAD
# ============================================================================
func apply_gravity(delta: float) -> void:
	if not player.is_on_floor():
		player.velocity.y += player.get_scaled_gravity() * delta

# ============================================================================
# SALTO
# ============================================================================
func handle_jump() -> void:
	if is_crouching:
		return
	if player.is_on_floor() and Input.is_action_just_pressed("jump"):
		player.velocity.y = -player.get_scaled_jump_speed()

# ============================================================================
# STAMINA — estilo Zelda: BotW
# - Se gasta corriendo
# - Empieza a recuperarse al soltar shift
# - Más rápido parado, más lento caminando
# - Si se agota, bloquea correr hasta 20%
# ============================================================================
func _update_stamina(delta: float) -> void:
	var currently_running: bool = _wants_to_run() and not stamina_exhausted

	if currently_running:
		# Gastar stamina
		PlayerStats.stamina = max(0.0, PlayerStats.stamina - STAMINA_DRAIN_RATE * delta)
		if PlayerStats.stamina <= 0.0:
			_set_exhausted(true)
	else:
		# Recuperar solo si no está pulsando shift
		if not Input.is_action_pressed("run"):
			var recover_rate: float = STAMINA_RECOVER_IDLE if not is_moving() else STAMINA_RECOVER_WALK
			PlayerStats.stamina = min(100.0, PlayerStats.stamina + recover_rate * delta)

			# Cuando recupera al 100%, para el jadeo
			if PlayerStats.stamina >= 100.0 and stamina_exhausted:
				_set_exhausted(false)

			# Puede volver a correr cuando llega al 20%
			if stamina_exhausted and PlayerStats.stamina >= STAMINA_MIN_TO_RUN:
				_set_exhausted(false)

func _set_exhausted(value: bool) -> void:
	if stamina_exhausted == value:
		return
	stamina_exhausted = value
	stamina_exhausted_changed.emit(value)
	EffectsManager.on_stamina_exhausted(value)

func _wants_to_run() -> bool:
	# Enfermedad grave bloquea correr completamente
	if PlayerStats.enfermedad >= 70:
		return false
	return Input.is_action_pressed("run") and not is_crouching and is_moving()

# ============================================================================
# MOVIMIENTO HORIZONTAL
# ============================================================================
func handle_horizontal_movement(delta: float) -> void:
	var input_axis: float = Input.get_axis("move_left", "move_right")

	update_facing_direction(input_axis)

	var target_speed: float = calculate_target_speed(input_axis)

	if input_axis != 0.0:
		apply_movement(input_axis, target_speed, delta)
	else:
		apply_friction(delta)

	update_movement_state()

func update_facing_direction(input_axis: float) -> void:
	if input_axis > 0:
		facing_right = true
	elif input_axis < 0:
		facing_right = false

func calculate_target_speed(_input_axis: float) -> float:
	var target_speed: float = player.get_scaled_move_speed()

	# Aplicar penalizaciones de stats
	target_speed *= _get_speed_multiplier()

	# Correr — solo si no agotada y no agachada
	if _wants_to_run() and not stamina_exhausted:
		target_speed = player.get_scaled_run_speed() * _get_speed_multiplier()
	elif is_crouching:
		target_speed = player.get_scaled_move_speed() * 0.4

	return target_speed

func _get_speed_multiplier() -> float:
	var mult: float = 1.0

	# Hambre alta → más lento (penaliza a partir de 70)
	if PlayerStats.hambre > 70:
		mult -= (PlayerStats.hambre - 70) / 30.0 * 0.3  # hasta -30% con hambre 100

	# Sueño bajo → más lento (penaliza por debajo de 30)
	if PlayerStats.sueno < 30:
		mult -= (30 - PlayerStats.sueno) / 30.0 * 0.25  # hasta -25% con sueño 0

	# Salud baja → penaliza todo (por debajo de 40)
	if PlayerStats.salud < 40:
		mult -= (40 - PlayerStats.salud) / 40.0 * 0.4  # hasta -40% con salud 0

	# Enfermedad grave → penaliza velocidad progresivamente
	if PlayerStats.enfermedad >= 70:
		mult -= (PlayerStats.enfermedad - 70) / 30.0 * 0.35  # hasta -35% con enfermedad 100

	# Alcohol/laudano → efecto errático (velocidad que varía)
	var sustancias: float = PlayerStats.alcohol + PlayerStats.laudano
	if sustancias > 50:
		var erratic: float = sin(Time.get_ticks_msec() * 0.003) * 0.15
		mult += erratic  # oscila ±15%

	return clamp(mult, 0.1, 1.0)  # mínimo 10% de velocidad

func apply_movement(input_axis: float, target_speed: float, delta: float) -> void:
	var changing_direction: bool = (input_axis > 0 and player.velocity.x < 0) or \
								  (input_axis < 0 and player.velocity.x > 0)

	if changing_direction and abs(player.velocity.x) > player.get_scaled_move_speed():
		player.velocity.x = move_toward(player.velocity.x, 0.0, player.get_scaled_run_friction() * delta)
	else:
		player.velocity.x = move_toward(
			player.velocity.x,
			input_axis * target_speed,
			player.get_scaled_acceleration() * delta
		)

func apply_friction(delta: float) -> float:
	var current_friction: float = player.get_scaled_friction()

	if abs(player.velocity.x) > player.get_scaled_move_speed():
		current_friction = player.get_scaled_run_friction()

	player.velocity.x = move_toward(player.velocity.x, 0.0, current_friction * delta)
	return player.velocity.x

func update_movement_state() -> void:
	var speed: float = abs(player.velocity.x)
	var moving_threshold: float = 20.0 * player.motion_scale_multiplier
	var stop_threshold: float = 5.0 * player.motion_scale_multiplier

	if speed > moving_threshold:
		was_moving = true
	elif speed < stop_threshold:
		was_moving = false

# ============================================================================
# GETTERS
# ============================================================================
func is_moving() -> bool:
	return was_moving

func is_running() -> bool:
	return _wants_to_run() and not stamina_exhausted

func is_player_crouching() -> bool:
	return is_crouching

func get_facing_direction() -> bool:
	return facing_right

func get_movement_speed() -> float:
	return abs(player.velocity.x)

func is_stamina_exhausted() -> bool:
	return stamina_exhausted

# ============================================================================
# 🔴 CONTROL DE BLOQUEO DE INPUT (Journal fix)
# ============================================================================

func force_stop() -> void:
	if not player:
		return

	player.velocity = Vector2.ZERO
	was_moving = false


func block_movement_input_until_release() -> void:
	ignore_movement_until_release = true


func _movement_inputs_released() -> bool:
	return (
		not Input.is_action_pressed("move_left")
		and not Input.is_action_pressed("move_right")
		and not Input.is_action_pressed("jump")
		and not Input.is_action_pressed("crouch")
		and not Input.is_action_pressed("run")
	)


func _is_movement_input_blocked() -> bool:
	if not ignore_movement_until_release:
		return false

	if _movement_inputs_released():
		ignore_movement_until_release = false
		return false

	return true
