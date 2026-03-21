extends Node2D

@export var word_scene: PackedScene
@export var spawn_distance: float = 150.0
@export var distance_to_next_word: float = 400.0  # 🔹 distancia que debe volar la Fairy antes del próximo spawn
@export var words: Array[String] = ["HOPELESS", "RUIN", "SAD", "SHAME", "COWARD", "DEAD", "HATE"]

@onready var fairy = $"../Player/Fairy"

var current_index: int = 0
var can_spawn_next: bool = true
var distance_traveled: float = 0.0
var last_position: Vector2 = Vector2.ZERO

func _ready():
	add_to_group("word_spawner")
	call_deferred("spawn_next_word")

func _physics_process(_delta):
	if not fairy or not can_spawn_next:
		return

	# Suma la distancia recorrida desde la última posición
	var delta_distance = fairy.global_position.distance_to(last_position)
	distance_traveled += delta_distance
	last_position = fairy.global_position

	# Cuando haya volado suficiente, spawnea la siguiente palabra
	if distance_traveled >= distance_to_next_word:
		spawn_next_word()
		distance_traveled = 0.0

func spawn_next_word():
	if not can_spawn_next or current_index >= words.size() or not fairy:
		return

	can_spawn_next = false

	var word_instance = word_scene.instantiate()
	word_instance.word_text = words[current_index]
	word_instance.flash_index = current_index
	current_index += 1

	var dir = fairy.velocity.normalized() if fairy.velocity.length() > 0.1 else Vector2.RIGHT
	var spawn_pos = fairy.global_position + dir * spawn_distance
	spawn_pos += Vector2(randf_range(-50, 50), randf_range(-30, 30))

	word_instance.global_position = spawn_pos
	get_parent().call_deferred("add_child", word_instance)

func on_word_finished():
	can_spawn_next = true
	last_position = fairy.global_position  # reinicia el punto de referencia
	distance_traveled = 0.0  # empieza a contar de nuevo
