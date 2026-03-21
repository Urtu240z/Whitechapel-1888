extends Node2D

signal flash_image_finished(index: int)

# =========================================================
# ⚙️ SCENE CHANGE SETTINGS
# =========================================================
@export_category("⚙️ Scene Change Settings")
@export_file("*.tscn") var next_scene_path: String
@export var scene_fade_time: float = 0.8

# =========================================================
# ⚙️ FLASH EFFECT SETTINGS
# =========================================================
@export_category("⚡ Flash Effect Settings")
@export var flash_hold_time: float = 1.5
@export var fade_in_time: float = 0.08
@export var fade_out_time: float = 0.3
@export var camera_shake_intensity: float = 8.0
@export var camera_shake_duration: float = 0.25

# =========================================================
# 🎧 AMBIENT CORRUPTION SETTINGS
# =========================================================
@export_category("🎧 Ambient Corruption Settings")
@export var ambient_pitch_min: float = 0.5
@export var ambient_pitch_max: float = 1.5
@export var ambient_change_interval_min: float = 1.0
@export var ambient_change_interval_max: float = 5.0
@export var ambient_volume_min: float = -8.0
@export var ambient_volume_max: float = 0.0

# =========================================================
# 🎞️ BACKGROUND VIDEO SETTINGS
# =========================================================
@export_category("🎞️ Background Video Settings")
@export var video_streams: Array[VideoStream] = []
@export var min_speed_scale: float = 0.7
@export var max_speed_scale: float = 1.3
@export var speed_change_interval_min: float = 1.0
@export var speed_change_interval_max: float = 4.0
# (Parallax eliminado)

# =========================================================
# 🔗 NODE REFERENCES
# =========================================================
@export_category("🔗 Node References (Auto-linked)")
@onready var sfx: AudioStreamPlayer = $Scream
@onready var ambient: AudioStreamPlayer = $Ambient
@onready var player = $Fairy
@onready var camera: Camera2D = $Fairy/Camera2D
@onready var global_flash = $CanvasLayer_Lightning/GlobalFlash
@onready var video_player: VideoStreamPlayer = $CanvasLayer_Background/VideoStreamPlayer

# =========================================================
# INTERNAL STATE
# =========================================================
var flash_images: Array[TextureRect] = []
var _should_continue_glitch := true
var _should_continue_video := true

# =========================================================
# 🏁 INITIALIZATION
# =========================================================
func _ready():
	add_to_group("flash_manager")

	# CanvasLayer ordering
	if has_node("CanvasLayer"):
		$CanvasLayer.layer = 10
	if has_node("CanvasLayer_Lightning"):
		$CanvasLayer_Lightning.layer = 100
	if has_node("CanvasLayer_Background"):
		$CanvasLayer_Background.layer = -10

	# Collect FlashImages
	if has_node("CanvasLayer"):
		for node in $CanvasLayer.get_children():
			if node is TextureRect and node.name.begins_with("FlashImage"):
				flash_images.append(node)
				node.visible = false
				node.modulate.a = 0.0

	# 🎧 Start ambient glitch
	if ambient:
		ambient.pitch_scale = randf_range(ambient_pitch_min, ambient_pitch_max)
		ambient.volume_db = randf_range(ambient_volume_min, ambient_volume_max)
		ambient.play()
		_start_glitchy_ambient()

	# 🎞️ Start background video (pantalla completa)
	if video_player:
		video_player.expand = true     # fullscreen según tu versión (sin usar aspect)
		video_player.loop = false
		_play_random_video()
		_start_random_video_speed()

	if not self.flash_image_finished.is_connected(_on_flash_image_finished):
		self.flash_image_finished.connect(_on_flash_image_finished)
	if sfx:
		sfx.add_to_group("AudioStreamPlayer")
	if ambient:
		ambient.add_to_group("AudioStreamPlayer")

# =========================================================
# 💫 AMBIENT GLITCH LOOP
# =========================================================
func _start_glitchy_ambient():
	_should_continue_glitch = true
	_glitch_loop()

func _glitch_loop():
	while _should_continue_glitch and is_inside_tree() and ambient:
		ambient.pitch_scale = randf_range(ambient_pitch_min, ambient_pitch_max)
		ambient.volume_db = randf_range(ambient_volume_min, ambient_volume_max)

		if randf() < 0.25:
			ambient.stream_paused = true
			await get_tree().create_timer(randf_range(0.05, 0.25)).timeout
			if not is_inside_tree() or not ambient:
				return
			ambient.stream_paused = false

		var next_wait = randf_range(ambient_change_interval_min, ambient_change_interval_max)
		await get_tree().create_timer(next_wait).timeout

# =========================================================
# 🚪 CLEANUP
# =========================================================
func _exit_tree():
	_should_continue_glitch = false
	_should_continue_video = false

# =========================================================
# ⚡ FLASH IMAGE EFFECTS
# =========================================================
func show_flash_by_index(index: int):
	if index < 0 or index >= flash_images.size():
		return

	show_flash(flash_images[index])
	camera_shake(camera_shake_duration, camera_shake_intensity)

	if global_flash:
		global_flash.show_global_flash()

func show_flash(image: TextureRect):
	image.visible = true
	image.modulate = Color(1, 1, 1, 0)

	var fade_in: float = float(image.get_meta("fade_in")) if image.has_meta("fade_in") else fade_in_time
	var fade_out: float = float(image.get_meta("fade_out")) if image.has_meta("fade_out") else fade_out_time
	var hold_time: float = float(image.get_meta("hold_time")) if image.has_meta("hold_time") else flash_hold_time

	if sfx:
		sfx.pitch_scale = randf_range(0.9, 1.1)
		sfx.play()

	var tween: Tween = create_tween()
	# Fade in
	tween.tween_property(image, "modulate:a", 1.0, fade_in)
	# Espera (hold)
	tween.tween_interval(hold_time)
	# Fade out
	tween.tween_property(image, "modulate:a", 0.0, fade_out)
	# Ocultar + emitir señal
	tween.tween_callback(func():
		image.visible = false
		var idx: int = flash_images.find(image)
		if idx != -1:
			emit_signal("flash_image_finished", idx)
	)

# =========================================================
# 📸 CAMERA SHAKE
# =========================================================
func camera_shake(duration: float, intensity: float):
	if not camera:
		return

	var tween = create_tween()
	var original_offset = camera.offset

	tween.tween_method(
		func(time):
			var t = time / duration
			var decay = pow(1.0 - t, 2.0)
			var shake = Vector2(
				randf_range(-intensity, intensity) * decay,
				randf_range(-intensity, intensity) * decay
			)
			camera.offset = shake
	, 0.0, duration, duration)

	tween.tween_callback(func(): camera.offset = original_offset)

# =========================================================
# 🎬 BACKGROUND VIDEO SYSTEM
# =========================================================
func _play_random_video():
	if video_streams.is_empty():
		push_warning("No video streams configured in 'video_streams'.")
		return

	var chosen_stream: VideoStream = video_streams.pick_random()
	video_player.stream = chosen_stream
	video_player.play()

	video_player.finished.connect(_on_video_finished, CONNECT_ONE_SHOT)

func _on_video_finished():
	if not _should_continue_video or not is_inside_tree():
		return

	# ⚡✨ FLASH de cambio de video ✨⚡
	if global_flash:
		global_flash.show_global_flash(true)

	# (opcional: pequeño retardo antes de cargar el siguiente)
	await get_tree().create_timer(0.15).timeout

	_play_random_video()

# 🔄 Random playback speed
func _start_random_video_speed():
	_random_video_speed_loop()

func _random_video_speed_loop():
	while _should_continue_video and is_inside_tree() and video_player:
		video_player.speed_scale = randf_range(min_speed_scale, max_speed_scale)
		var wait = randf_range(speed_change_interval_min, speed_change_interval_max)
		await get_tree().create_timer(wait).timeout

func _on_flash_image_finished(index: int) -> void:
	# Si este flash es el último de la secuencia
	if index == flash_images.size() - 1:
		await get_tree().create_timer(0.5).timeout  # margen para terminar fade del flash

		# 🎧 Fade-out global del audio
		_fade_out_all_audio(3.0)

		# 🕶️ Fade negro suave + cambio de escena
		if next_scene_path != "":
			SceneManager.change_scene(next_scene_path, 3.0)

func _fade_out_all_audio(duration: float = 3.0):
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for audio_node in get_tree().get_nodes_in_group("AudioStreamPlayer"):
		if audio_node is AudioStreamPlayer and audio_node.playing:
			var start_vol = audio_node.volume_db
			tween.tween_property(audio_node, "volume_db", -80.0, duration).from(start_vol)
