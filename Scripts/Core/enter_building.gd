extends Node2D

@export var enter_action := "interact"
@export var fade_time := 0.8
@export var zoom_in := Vector2(2.2, 2.2)
@export var zoom_out := Vector2(1.68, 1.68)

@export var open_sounds: Array[AudioStream] = []
@export var close_sounds: Array[AudioStream] = []

# Ahora apuntamos a los contenedores de audio, no a un solo stream
@export var outside_audio_root_path: NodePath
@export var inside_audio_root_path: NodePath

@onready var area: Area2D = $Area2D
@onready var interior: TileMapLayer = $Interior
@onready var walls: StaticBody2D = $Interior/Wall
@onready var player := get_tree().current_scene.get_node("Player")
@onready var camera: Camera2D = player.get_node("Camera2D")
@onready var overlay: Sprite2D = camera.get_node("OverlayBlack")
@onready var audio: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
@onready var exit_area: Area2D = $Interior/ExitArea

var _player_near_exit := false
var outside_audio_root: Node
var inside_audio_root: Node

var _player_in_range := false
var _inside := false
var _transitioning := false


func _ready():
	add_child(audio)
	interior.visible = false
	interior.modulate.a = 0.0
	_set_walls_enabled(false)

	if outside_audio_root_path != NodePath():
		outside_audio_root = get_node(outside_audio_root_path)
	if inside_audio_root_path != NodePath():
		inside_audio_root = get_node(inside_audio_root_path)
		# Inicialmente silenciamos todo el audio interior
		for child in inside_audio_root.get_children():
			if child is AudioStreamPlayer2D:
				child.volume_db = -40
				child.playing = true 

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	exit_area.process_mode = Node.PROCESS_MODE_ALWAYS
	exit_area.body_entered.connect(_on_exit_entered)
	exit_area.body_exited.connect(_on_exit_exited)

func _on_body_entered(body):
	if body.is_in_group("player"):
		_player_in_range = true

func _on_body_exited(body):
	if body.is_in_group("player"):
		_player_in_range = false

func _on_exit_entered(body):
	if body.is_in_group("player"):
		_player_near_exit = true

func _on_exit_exited(body):
	if body.is_in_group("player"):
		_player_near_exit = false

func _process(_delta):
	if Input.is_action_just_pressed(enter_action) and not _transitioning:
		if _inside:
			if _player_near_exit:  # ← CAMBIO AQUÍ
				_transitioning = true
				await _fade_out()
				_transitioning = false
			else:
				print("No puedes salir por aquí.")
		else:
			if _player_in_range:
				_transitioning = true
				await _fade_in()
				_transitioning = false

func _set_group_visibility(group_name: String, value: bool):
	for node in get_tree().get_nodes_in_group(group_name):
		if node is CanvasItem:
			node.visible = value



# =====================================================
# 🌑 Entrar: fade + zoom in + activar paredes + PAUSA MUNDO
# =====================================================
func _fade_in():
	_inside = true
	_play_random_sound(open_sounds)
	
	# Ocultamos NPCs exteriores
	_set_group_visibility("npcs_outside", false)
	
	interior.modulate.a = 0.0
	interior.visible = true
	_set_walls_enabled(true)

	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	camera.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	interior.process_mode = Node.PROCESS_MODE_ALWAYS

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Fade visual
	tw.tween_property(overlay, "modulate:a", 1.0, fade_time * 0.5)
	tw.parallel().tween_property(camera, "zoom", zoom_in, fade_time)
	tw.parallel().tween_property(interior, "modulate:a", 1.0, fade_time * 0.6).set_delay(fade_time * 0.2)

	# Fade de audio (varios hijos)
	_fade_audio_group(outside_audio_root, -40, fade_time * 0.8, tw)
	_fade_audio_group(inside_audio_root, 0, fade_time * 0.8, tw, true)

	await tw.finished


# =====================================================
# ☀️ Salir: fade inverso + desactivar paredes + DESPAUSA
# =====================================================
func _fade_out():
	_inside = false
	_play_random_sound(close_sounds)

	# Mostramos NPCs exteriores otra vez
	_set_group_visibility("npcs_outside", true)

	get_tree().paused = false
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Fade de audio
	_fade_audio_group(outside_audio_root, 0, fade_time * 0.8, tw)
	_fade_audio_group(inside_audio_root, -40, fade_time * 0.8, tw)

	# Fade visual
	tw.parallel().tween_property(interior, "modulate:a", 0.0, fade_time * 0.5)
	await tw.finished

	interior.visible = false
	_set_walls_enabled(false)

	tw = create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(overlay, "modulate:a", 0.0, fade_time)
	tw.parallel().tween_property(camera, "zoom", zoom_out, fade_time * 0.8)
	await tw.finished





# =====================================================
# 🔊 Función helper para fundir grupos de AudioStreamPlayer2D
# =====================================================
func _fade_audio_group(root: Node, target_db: float, duration: float, tw: Tween, play_if_stopped := false):
	if not root:
		return
	for child in root.get_children():
		if child is AudioStreamPlayer2D:
			if play_if_stopped and not child.playing:
				child.playing = true
			tw.parallel().tween_property(child, "volume_db", target_db, duration)


# =====================================================
# 🧱 Activar / desactivar colisiones
# =====================================================
func _set_walls_enabled(enabled: bool):
	if not is_instance_valid(walls):
		return
	for shape in walls.get_children():
		if shape is CollisionShape2D:
			shape.disabled = not enabled


# =====================================================
# 🎧 Sonido aleatorio abrir/cerrar
# =====================================================
func _play_random_sound(sounds: Array[AudioStream]) -> void:
	if sounds.is_empty():
		return
	var sound: AudioStream = sounds.pick_random()
	audio.stream = sound
	audio.pitch_scale = randf_range(0.95, 1.05)
	audio.volume_db = randf_range(-2.0, 0.0)
	audio.play()
