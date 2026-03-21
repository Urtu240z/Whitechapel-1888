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
var breath_delay: float = 1.5    # ⏱️ tiempo antes de empezar a sonar al correr
var breath_interval: float = 2.0 # ⏱️ intervalo entre respiraciones mientras corre

# ==========================
# STEP SOUNDS TABLE
# surface -> Array[AudioStream]
# Rellena los arrays desde el Inspector o desde código
# ==========================
@export var step_sounds: Dictionary = {
	"stone": [],
	"wood":  [],
	"dirt":  [],
	"grass": [],
	"water": [],
}

# ==========================
# INIT
# ==========================
func initialize(p: MainPlayer) -> void:
	player = p
	if player.has_node("Movement"):
		movement_module = player.get_node("Movement")

	# Excluir al propio player del raycast de sombra
	var shadow_ray: RayCast2D = player.get_node_or_null("CharacterContainer/Shadow/ShadowRAY")
	if shadow_ray:
		shadow_ray.add_exception(player)

# ==========================
# PROCESS
# ==========================
func _process(delta: float) -> void:
	_update_surface()
	_handle_breath_run(delta)

# ==========================
# SURFACE DETECTION
# Reutiliza el ShadowRAY que ya existe en la escena
# ==========================
func _update_surface() -> void:
	var shadow_ray: RayCast2D = player.get_node_or_null("CharacterContainer/Shadow/ShadowRAY")
	if not shadow_ray or not shadow_ray.is_colliding():
		return

	var collider = shadow_ray.get_collider()
	if not collider:
		return

	var detected := SURFACE_DEFAULT

	# TileMap → necesita Custom Data Layer llamada "surface_type" (String)
	if collider is TileMap:
		var tile_pos: Vector2i = collider.local_to_map(
			collider.to_local(shadow_ray.get_collision_point())
		)
		var tile_data: TileData = collider.get_cell_tile_data(0, tile_pos)
		if tile_data:
			var surface = tile_data.get_custom_data("surface_type")
			if surface != "":
				detected = surface

	# StaticBody2D → necesita metadata "surface_type" (String)
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
# AUDIO PLAYBACK
# ==========================
func play_random_step(run: bool = false) -> void:
	if not player.is_on_floor():
		return

	var sounds: Array = step_sounds.get(current_surface, [])

	# Fallback a stone si la superficie actual no tiene sonidos asignados aún
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
