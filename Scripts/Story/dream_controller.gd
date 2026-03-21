extends Node2D

# =========================================================
# ⚙️ CONFIGURACIÓN EXPORTADA
# =========================================================
@export_file("*.tscn") var next_scene: String
@export var ambient_volume: float = -6.0
@export var fade_time: float = 1.5
@export var default_hold_time: float = 1.5  # tiempo de la imagen visible sin fade
@export var global_gravity: float = 980.0
# =========================================================
# ⚡ FLASH TIMES (por defecto si no hay metadatos)
# =========================================================
@export_category("⚡ Flash Effect Settings")
@export var default_fade_in_time: float = 0.2
@export var default_fade_out_time: float = 0.6

# =========================================================
# 📸 CAMERA SHAKE SETTINGS
# =========================================================
@export_category("📸 Camera Shake")
@export var base_shake_intensity: float = 8.0   # fuerza inicial del shake
@export var shake_intensity_multiplier: float = 10.0  # cuánto aumenta con flashes largos
@export var shake_duration_scale: float = 1.0   # factor de duración (1.0 = igual que flash)

# =========================================================
# 🔗 REFERENCIAS AUTOMÁTICAS
# =========================================================
@onready var camera: Camera2D = $Player/Fairy/Camera2D
@onready var fairy: Node = $Player/Fairy
@onready var world: Node = $World
@onready var flash_layer: Node = $CanvasLayer_UI/CanvasLayer_Flashbacks
@onready var global_flash: Node = $CanvasLayer_UI/CanvasLayer_Lightning/GlobalFlash
@onready var glitch_layer: Node = $CanvasLayer_UI/CanvasLayer_Glitch
@onready var video: VideoStreamPlayer = $CanvasLayer_UI/CanvasLayer_Background/VideoStreamPlayer
@onready var ambient: AudioStreamPlayer = $Audio/Ambient
@onready var sound_fx: AudioStreamPlayer = $Audio/SoundFX
@onready var player: CharacterBody2D = $Player/Fairy
# =========================================================
# 🔒 ESTADO INTERNO
# =========================================================
var _flash_images: Array[TextureRect] = []
var _dream_finished: bool = false

# =========================================================
# 🏁 READY
# =========================================================
func _ready():
	print("🌙 DreamController activo en escena: ", name)
	add_to_group("dream_controller")

	# Recolectar las imágenes de flashback
	if flash_layer:
		for node in flash_layer.get_children():
			if node is TextureRect:
				node.visible = false
				_flash_images.append(node)
		print("🖼️ Flashbacks detectados:", _flash_images.size())
	else:
		push_warning("⚠️ No se encontró CanvasLayer_Flashbacks")

	# Música y video
	if ambient:
		ambient.volume_db = ambient_volume
		ambient.play()
	if video:
		video.play()

	# Esperar un frame para que Fairy esté totalmente inicializada
	await get_tree().process_frame

	if player:
		player.gravity = global_gravity
		print("✅ Gravedad global aplicada:", global_gravity)
	else:
		push_warning("⚠️ No se encontró el jugador")

# =========================================================
# 🚀 LLAMADO DESDE WORDS_COLLISION
# =========================================================
func trigger_flashback(index: int, word_text: String):
	if _dream_finished:
		return

	if index < 0 or index >= _flash_images.size():
		push_warning("⚠️ Índice de flashback fuera de rango: %s" % index)
		return

	var flash_node: TextureRect = _flash_images[index]

	# --- Leer tiempos ---
	var fade_in_t: float  = float(flash_node.get_meta("fade_in"))  if flash_node.has_meta("fade_in")  else default_fade_in_time
	var fade_out_t: float = float(flash_node.get_meta("fade_out")) if flash_node.has_meta("fade_out") else default_fade_out_time
	var hold_t: float     = float(flash_node.get_meta("hold_time")) if flash_node.has_meta("hold_time") else default_hold_time

	var total_flash_time: float = fade_in_t + hold_t + fade_out_t

	# --- Flash global + SFX ---
	if global_flash:
		global_flash.show_global_flash()
	if sound_fx:
		sound_fx.pitch_scale = randf_range(0.9, 1.1)
		sound_fx.play()

	# --- Mostrar imagen y glitch sincronizado ---
	_show_flash(flash_node, fade_in_t, hold_t, fade_out_t)
	_spawn_glitched_word(word_text, total_flash_time)

	# --- Shake sincronizado ---
	var shake_duration: float = total_flash_time * shake_duration_scale
	var shake_intensity: float = base_shake_intensity + total_flash_time * shake_intensity_multiplier
	_camera_shake(shake_duration, shake_intensity)

# =========================================================
# ⚡ MOSTRAR FLASH IMAGE
# =========================================================
func _show_flash(flash_node: TextureRect, fade_in_t: float, hold_t: float, fade_out_t: float):
	if not flash_node:
		return

	flash_node.visible = true
	flash_node.modulate.a = 0.0

	var tw := create_tween()
	tw.tween_property(flash_node, "modulate:a", 1.0, fade_in_t) # fade in
	tw.tween_interval(hold_t)                                   # tiempo visible
	tw.tween_property(flash_node, "modulate:a", 0.0, fade_out_t)# fade out
	tw.tween_callback(func():
		flash_node.visible = false
	)

# =========================================================
# 📸 CAMERA SHAKE
# =========================================================
func _camera_shake(duration: float, intensity: float):
	if not camera:
		return

	var tw := create_tween()
	var original_offset := camera.offset

	tw.tween_method(
		func(time):
			var t : float = time / duration
			var decay := pow(1.0 - t, 2.0)
			var shake := Vector2(
				randf_range(-intensity, intensity) * decay,
				randf_range(-intensity, intensity) * decay
			)
			camera.offset = shake
	, 0.0, duration, duration)

	tw.tween_callback(func():
		camera.offset = original_offset)

# =========================================================
# 🌩️ GLITCH WORD
# =========================================================
func _spawn_glitched_word(word_text: String, total_duration: float):
	if not glitch_layer:
		return

	var glitch_scene := preload("res://Scenes/Story/Word_Glitch.tscn")
	var glitch_label: Label = glitch_scene.instantiate()
	glitch_label.text = word_text
	glitch_label.set_meta("lifetime", total_duration)

	# Posición inicial aleatoria
	var vp := get_viewport_rect().size
	glitch_label.position = Vector2(
		randf_range(0.2, 0.8) * vp.x,
		randf_range(0.2, 0.8) * vp.y
	)

	glitch_layer.add_child(glitch_label)
