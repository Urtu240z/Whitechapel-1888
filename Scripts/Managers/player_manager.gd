extends Node

# =========================================================
# 🧩 PlayerManager
# Responsabilidades:
# - Mantener la instancia del player entre escenas
# - Colocar al player en la posición correcta tras cambio de escena
# - Gestionar sonidos de puerta al entrar/salir de edificios
#
# ℹ️ El fade negro lo gestiona SceneManager, no este script.
# =========================================================

var player_scene := preload("res://Scenes/Player/Player.tscn")
var player_instance: MainPlayer

# =========================================================
# 🧠 Asegura que el jugador exista en la escena actual
# =========================================================
func ensure_player(parent: Node, position: Vector2) -> void:
	if parent == null:
		printerr("❌ ensure_player(): El parent es nulo, abortando.")
		return

	if player_instance == null:
		player_instance = player_scene.instantiate()

	if not player_instance.is_inside_tree():
		parent.add_child(player_instance)

	player_instance.global_position = position

# =========================================================
# 🚪 Cambio de escena con sonidos de puerta
# Usa SceneManager para el fade — no duplica esa lógica.
#
# Uso:
#   PlayerManager.enter_building(
#       "res://Scenes/Bar.tscn",
#       Vector2(100, 200),
#       preload("res://Assets/Audio/door_open.ogg"),
#       preload("res://Assets/Audio/door_close.ogg")
#   )
# =========================================================
func enter_building(
	scene_path: String,
	spawn_position: Vector2,
	open_sound: AudioStream = null,
	close_sound: AudioStream = null,
	fade_time: float = 0.5
) -> void:
	# Sonido de abrir puerta antes del fade
	if open_sound:
		_play_sfx(open_sound)

	# Fade out → cambio de escena → fade in (via SceneManager)
	await SceneManager._fade_out(fade_time)
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	ensure_player(get_tree().current_scene, spawn_position)

	# Sonido de cerrar puerta tras aparecer en la nueva escena
	if close_sound:
		await get_tree().create_timer(0.25).timeout
		_play_sfx(close_sound)

	await SceneManager._fade_in(fade_time)

# =========================================================
# 🔊 Reproduce un sonido puntual sin nodo persistente
# =========================================================
func _play_sfx(stream: AudioStream) -> void:
	var sfx := AudioStreamPlayer.new()
	sfx.stream = stream
	sfx.bus = "SFX"
	get_tree().root.add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)
