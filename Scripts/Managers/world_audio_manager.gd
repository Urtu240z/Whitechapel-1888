extends Node
# =========================================================
# WORLD AUDIO MANAGER
# Gestiona fade/pause/resume del audio del mundo actual.
# Usa grupos:
# - world_music
# - world_ambience
# =========================================================

const SILENT_DB := -40.0

var _stored_volumes: Dictionary = {}
var _active_tweens: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

# =========================================================
# API
# =========================================================
func fade_out_world_audio(duration: float = 0.5) -> void:
	var nodes := _get_world_audio_nodes()

	# Guardar solo los que realmente están sonando
	_stored_volumes.clear()

	for node in nodes:
		if not _is_audio_playing(node):
			continue

		var id := node.get_instance_id()
		_stored_volumes[id] = node.volume_db
		_kill_tween(id)

	var tweens: Array[Tween] = []

	for node in nodes:
		var id := node.get_instance_id()
		if not _stored_volumes.has(id):
			continue

		var tw := create_tween()
		_active_tweens[id] = tw
		tw.tween_property(node, "volume_db", SILENT_DB, duration)
		tweens.append(tw)

	for tw in tweens:
		await tw.finished

	for node in nodes:
		var id := node.get_instance_id()
		if not _stored_volumes.has(id):
			continue
		if not is_instance_valid(node):
			continue

		node.stream_paused = true
		_kill_tween(id)


func fade_in_world_audio(duration: float = 0.7) -> void:
	var nodes := _get_world_audio_nodes()
	var tweens: Array[Tween] = []

	for node in nodes:
		var id := node.get_instance_id()
		if not _stored_volumes.has(id):
			continue
		if not is_instance_valid(node):
			continue

		var target_db: float = _stored_volumes[id]
		_kill_tween(id)

		node.stream_paused = false
		node.volume_db = SILENT_DB

		var tw := create_tween()
		_active_tweens[id] = tw
		tw.tween_property(node, "volume_db", target_db, duration)
		tweens.append(tw)

	for tw in tweens:
		await tw.finished

	for id in _active_tweens.keys():
		_kill_tween(id)

	_stored_volumes.clear()


func pause_world_audio_immediate() -> void:
	var nodes := _get_world_audio_nodes()

	_stored_volumes.clear()

	for node in nodes:
		if not _is_audio_playing(node):
			continue

		var id := node.get_instance_id()
		_stored_volumes[id] = node.volume_db
		_kill_tween(id)
		node.stream_paused = true


func resume_world_audio_immediate() -> void:
	var nodes := _get_world_audio_nodes()

	for node in nodes:
		var id := node.get_instance_id()
		if not _stored_volumes.has(id):
			continue
		if not is_instance_valid(node):
			continue

		node.stream_paused = false
		node.volume_db = _stored_volumes[id]

	_stored_volumes.clear()

# =========================================================
# HELPERS
# =========================================================
func _get_world_audio_nodes() -> Array[Node]:
	var result: Array[Node] = []
	var seen: Dictionary = {}

	for group_name in ["world_music", "world_ambience"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node):
				continue
			if not _is_valid_audio_node(node):
				continue

			var id := node.get_instance_id()
			if seen.has(id):
				continue

			seen[id] = true
			result.append(node)

	return result


func _is_valid_audio_node(node: Node) -> bool:
	return node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D


func _is_audio_playing(node: Node) -> bool:
	if not _is_valid_audio_node(node):
		return false
	return node.playing


func _kill_tween(id: int) -> void:
	if not _active_tweens.has(id):
		return

	var tw: Tween = _active_tweens[id]
	if is_instance_valid(tw):
		tw.kill()

	_active_tweens.erase(id)
