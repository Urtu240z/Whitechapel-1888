extends Node

# ==========================
# AUDIO MODULE
# ==========================
# 📋 SETUP NECESARIO EN GODOT:
# Cada suelo necesita indicar su tipo de superficie:
#
# → StaticBody2D:
#      Inspector → Node → Metadata → añadir "surface_type" (String)
#      Valores válidos: "stone", "wood", "dirt", "grass", "water"
#
# → TileMap:
#      TileSet → Custom Data Layers → añadir "surface_type" (String)
#      Asignar el valor a cada tile en el TileSet
#
# → ShadowRAY (CharacterContainer/Shadow/ShadowRAY):
#      Collision Mask → solo capa 2 activa (la del suelo)
# ==========================

var player: MainPlayer = null
var movement_module: Node = null

@onready var step_player: AudioStreamPlayer = $StepPlayer
@onready var breath_player: AudioStreamPlayer = $BreathRun
@onready var cough_player: AudioStreamPlayer = $CoughPlayer

# ==========================
# SURFACE TYPES
# ==========================
const SURFACE_DEFAULT := "stone"
const VALID_SURFACES := ["stone", "wood", "dirt", "grass", "water"]

# ==========================
# STATE
# ==========================
var current_surface: String = SURFACE_DEFAULT
var is_playing_breath: bool = false
var breath_timer: float = 0.0
var breath_delay: float = 1.5
var breath_interval: float = 2.0

# ==========================
# COUGH STATE
# ==========================
var _cough_timer: float = 0.0

# ==========================
# STEP SOUNDS TABLE
# ==========================
@export var step_sounds: Dictionary = {
	"stone": [],
	"wood":  [],
	"dirt":  [],
	"grass": [],
	"water": [],
}

# ==========================
# COUGH SOUNDS
# 40-70%  → cough_sounds_light (woman_cough_light_1/2)
# 70-100% → cough_sounds_heavy (woman_cough_1/2/3/4 + woman_suffering_1/2 todos juntos)
# ==========================
@export var cough_sounds_light: Array[AudioStream] = []   # woman_cough_light_1/2
@export var cough_sounds_heavy: Array[AudioStream] = []   # woman_cough_1/2/3/4 + woman_suffering_1/2

# ==========================
# INIT
# ==========================
func initialize(p: MainPlayer) -> void:
	player = p
	if player.has_node("Movement"):
		movement_module = player.get_node("Movement")

	var shadow_ray: RayCast2D = player.get_node_or_null("CharacterContainer/Shadow/ShadowRAY")
	if shadow_ray:
		shadow_ray.add_exception(player)

# ==========================
# PROCESS
# ==========================
func _process(delta: float) -> void:
	_update_surface()
	_handle_breath_run(delta)
	_handle_cough(delta)

# ==========================
# SURFACE DETECTION
# ==========================
func _update_surface() -> void:
	var shadow_ray: RayCast2D = player.get_node_or_null("CharacterContainer/Shadow/ShadowRAY")
	if not shadow_ray or not shadow_ray.is_colliding():
		return

	var collider = shadow_ray.get_collider()
	if not collider:
		return

	var detected := SURFACE_DEFAULT

	if collider is TileMap:
		var tile_pos: Vector2i = collider.local_to_map(
			collider.to_local(shadow_ray.get_collision_point())
		)
		var tile_data: TileData = collider.get_cell_tile_data(0, tile_pos)
		if tile_data:
			var surface = tile_data.get_custom_data("surface_type")
			if surface != "":
				detected = surface

	elif collider.has_meta("surface_type"):
		detected = collider.get_meta("surface_type")

	if detected in VALID_SURFACES:
		current_surface = detected

# ==========================
# BREATH CONTROL
# ==========================
func _handle_breath_run(delta: float) -> void:
	if not movement_module:
		return

	var running: bool = movement_module.is_running() and movement_module.is_moving()

	if running:
		breath_timer += delta
		if not is_playing_breath and breath_timer >= breath_delay:
			_play_random_breath_run()
			is_playing_breath = true
			breath_timer = 0.0
		elif is_playing_breath and breath_timer >= breath_interval:
			_play_random_breath_run()
			breath_timer = 0.0
	else:
		is_playing_breath = false
		breath_timer = 0.0

# ==========================
# COUGH CONTROL
# 40-70%  → cough_light, frecuencia baja  (45s → 20s)
# 70-100% → cough_heavy, frecuencia alta  (20s → 3s)
# ==========================
func _handle_cough(delta: float) -> void:
	var interval: float = _get_cough_interval()

	if interval <= 0.0:
		_cough_timer = 0.0
		return

	_cough_timer += delta
	if _cough_timer >= interval:
		_cough_timer = 0.0
		_play_cough()


func _get_cough_interval() -> float:
	var enf: float = PlayerStats.enfermedad
	if enf >= 70:
		# 70-100% → de 20s a 3s
		return lerp(20.0, 3.0, (enf - 70.0) / 30.0)
	elif enf >= 40:
		# 40-70% → de 45s a 20s
		return lerp(45.0, 20.0, (enf - 40.0) / 30.0)
	else:
		return 0.0  # sin tos


var _last_cough: AudioStream = null

func _play_cough() -> void:
	var enf: float = PlayerStats.enfermedad
	var sounds: Array[AudioStream] = []

	if enf >= 70:
		sounds = cough_sounds_heavy
	else:
		sounds = cough_sounds_light

	if sounds.is_empty():
		return

	# Evitar repetir el mismo sonido dos veces seguidas
	var available: Array[AudioStream] = sounds.filter(func(s): return s != _last_cough)
	if available.is_empty():
		available = sounds  # fallback si solo hay un sonido

	var chosen: AudioStream = available.pick_random()
	_last_cough = chosen

	cough_player.stream = chosen

	# Pitch variado según gravedad — más grave y lento cuando peor está
	if enf >= 85:
		# Tos grave — más baja y lenta
		cough_player.pitch_scale = randf_range(0.75, 0.90)
	elif enf >= 70:
		# Tos moderada-grave
		cough_player.pitch_scale = randf_range(0.85, 1.00)
	else:
		# Tos leve — más aguda y rápida
		cough_player.pitch_scale = randf_range(0.95, 1.10)

	cough_player.volume_db = randf_range(-5.0, -1.0)
	cough_player.play()

# ==========================
# AUDIO PLAYBACK
# ==========================
func play_random_step(run: bool = false) -> void:
	if not player.is_on_floor():
		return

	var sounds: Array = step_sounds.get(current_surface, [])

	if sounds.is_empty():
		sounds = step_sounds.get(SURFACE_DEFAULT, [])

	if sounds.is_empty():
		return

	step_player.stream = sounds.pick_random()
	step_player.pitch_scale = randf_range(1.0, 1.3) if run else randf_range(0.9, 1.1)
	step_player.play()


func _play_random_breath_run() -> void:
	if player.breath_run_sounds.is_empty():
		return
	breath_player.stream = player.breath_run_sounds.pick_random()
	breath_player.pitch_scale = randf_range(0.95, 1.05)
	breath_player.volume_db = -2
	breath_player.play()
