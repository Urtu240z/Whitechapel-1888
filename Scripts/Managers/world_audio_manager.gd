extends Node

# ================================================================
# WORLD AUDIO MANAGER — Autoload
# ================================================================
# Autoridad única para el audio global del mundo.
#
# Responsabilidades:
# - Fade out / fade in de música y ambiente del mundo.
# - Pausar/reanudar audio del mundo durante transiciones especiales.
# - Hacer ducking temporal para diálogos, UI, sueño, tensión, etc.
# - Centralizar grupos de audio para que otros scripts no toquen nodos sueltos.
#
# Grupos esperados:
# - world_music
# - world_ambience
#
# API principal:
# - fade_out_world_audio()
# - fade_in_world_audio()
# - pause_world_audio_immediate()
# - resume_world_audio_immediate()
# - duck_world_audio()
# - restore_ducked_world_audio()
# ================================================================

signal world_audio_fade_started(fade_out: bool, duration: float, reason: String)
signal world_audio_fade_finished(fade_out: bool, reason: String)
signal world_audio_paused(reason: String)
signal world_audio_resumed(reason: String)
signal world_audio_ducked(reason: String, duck_db: float)
signal world_audio_duck_restored(reason: String)

const GROUP_WORLD_MUSIC: String = "world_music"
const GROUP_WORLD_AMBIENCE: String = "world_ambience"
const DEFAULT_WORLD_GROUPS: PackedStringArray = [GROUP_WORLD_MUSIC, GROUP_WORLD_AMBIENCE]

const DEFAULT_SILENT_DB: float = -40.0
const DEFAULT_DUCK_DB: float = -10.0
const WORLD_MUTE_REASON: String = "world_audio_mute"

const DEBUG_LOGS: bool = false

# _snapshots[reason][instance_id] = {
#   "path": NodePath,
#   "volume_db": float,
#   "was_playing": bool,
#   "was_paused": bool,
# }
var _snapshots: Dictionary = {}
var _duck_snapshots: Dictionary = {}
var _active_tweens: Dictionary = {}


# ================================================================
# READY
# ================================================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# ================================================================
# API PRINCIPAL — AUDIO DEL MUNDO
# ================================================================
func fade_out_world_audio(duration: float = 0.5, reason: String = WORLD_MUTE_REASON) -> void:
	var clean_reason := _clean_reason(reason)
	var nodes := get_world_audio_nodes()

	_snapshot_nodes(clean_reason, nodes, true)
	world_audio_fade_started.emit(true, duration, clean_reason)

	await _fade_nodes_to_db(nodes, DEFAULT_SILENT_DB, duration, clean_reason, true)
	_pause_snapshot_nodes(clean_reason)

	world_audio_fade_finished.emit(true, clean_reason)
	_debug("fade_out_world_audio terminado: %s" % clean_reason)


func fade_in_world_audio(duration: float = 0.7, reason: String = WORLD_MUTE_REASON) -> void:
	var clean_reason := _clean_reason(reason)

	if not _snapshots.has(clean_reason):
		_debug("fade_in_world_audio ignorado. No hay snapshot: %s" % clean_reason)
		return

	var nodes := _get_nodes_from_snapshot(clean_reason)
	_resume_snapshot_nodes(clean_reason, DEFAULT_SILENT_DB)

	world_audio_fade_started.emit(false, duration, clean_reason)
	await _fade_nodes_to_snapshot_volume(clean_reason, nodes, duration)
	world_audio_fade_finished.emit(false, clean_reason)

	_clear_snapshot(clean_reason)
	_debug("fade_in_world_audio terminado: %s" % clean_reason)


func pause_world_audio_immediate(reason: String = WORLD_MUTE_REASON) -> void:
	var clean_reason := _clean_reason(reason)
	var nodes := get_world_audio_nodes()

	_snapshot_nodes(clean_reason, nodes, true)
	_pause_snapshot_nodes(clean_reason)
	world_audio_paused.emit(clean_reason)

	_debug("pause_world_audio_immediate: %s" % clean_reason)


func resume_world_audio_immediate(reason: String = WORLD_MUTE_REASON) -> void:
	var clean_reason := _clean_reason(reason)

	if not _snapshots.has(clean_reason):
		_debug("resume_world_audio_immediate ignorado. No hay snapshot: %s" % clean_reason)
		return

	_resume_snapshot_nodes(clean_reason)
	_clear_snapshot(clean_reason)
	world_audio_resumed.emit(clean_reason)

	_debug("resume_world_audio_immediate: %s" % clean_reason)


# ================================================================
# API — DUCKING
# Baja volumen sin pausar. Útil para diálogo, UI, tensión, etc.
# ================================================================
func duck_world_audio(duck_db: float = DEFAULT_DUCK_DB, duration: float = 0.25, reason: String = "duck") -> void:
	var duck_reason := _clean_reason(reason)
	var nodes := get_world_audio_nodes()

	if not _duck_snapshots.has(duck_reason):
		_duck_snapshots[duck_reason] = _make_snapshot(nodes, true)

	var targets: Dictionary = {}
	var snapshot: Dictionary = _duck_snapshots[duck_reason]

	for id in snapshot.keys():
		var node := _node_from_snapshot_entry(snapshot[id])
		if not _is_valid_audio_node(node):
			continue

		var original_db: float = float(snapshot[id].get("volume_db", _get_volume_db(node)))
		targets[id] = original_db + duck_db

	world_audio_ducked.emit(duck_reason, duck_db)
	await _fade_nodes_to_custom_targets(nodes, targets, duration, duck_reason)


func restore_ducked_world_audio(duration: float = 0.25, reason: String = "duck") -> void:
	var duck_reason := _clean_reason(reason)

	if not _duck_snapshots.has(duck_reason):
		return

	var snapshot: Dictionary = _duck_snapshots[duck_reason]
	var nodes := _get_nodes_from_custom_snapshot(snapshot)

	await _fade_nodes_to_custom_snapshot(snapshot, nodes, duration, duck_reason)

	_duck_snapshots.erase(duck_reason)
	world_audio_duck_restored.emit(duck_reason)


func clear_all_ducks(duration: float = 0.2) -> void:
	var reasons: Array = _duck_snapshots.keys()
	for reason in reasons:
		await restore_ducked_world_audio(duration, str(reason))


# ================================================================
# API — GRUPOS CONCRETOS
# ================================================================
func fade_group_to_db(group_name: String, target_db: float, duration: float = 0.5, reason: String = "fade_group") -> void:
	var nodes := get_audio_nodes_in_group(group_name)
	await _fade_nodes_to_db(nodes, target_db, duration, reason, false)


func fade_groups_to_db(groups: PackedStringArray, target_db: float, duration: float = 0.5, reason: String = "fade_groups") -> void:
	var nodes := get_audio_nodes_in_groups(groups)
	await _fade_nodes_to_db(nodes, target_db, duration, reason, false)


func pause_group_immediate(group_name: String) -> void:
	for node in get_audio_nodes_in_group(group_name):
		if _is_valid_audio_node(node):
			_set_stream_paused(node, true)


func resume_group_immediate(group_name: String) -> void:
	for node in get_audio_nodes_in_group(group_name):
		if _is_valid_audio_node(node):
			_set_stream_paused(node, false)


# ================================================================
# API — CONSULTA
# ================================================================
func get_world_audio_nodes() -> Array[Node]:
	return get_audio_nodes_in_groups(DEFAULT_WORLD_GROUPS)


func get_audio_nodes_in_groups(groups: PackedStringArray) -> Array[Node]:
	var result: Array[Node] = []
	var seen: Dictionary = {}

	for group_name in groups:
		for node in get_tree().get_nodes_in_group(group_name):
			if not _is_valid_audio_node(node):
				continue

			var id := node.get_instance_id()
			if seen.has(id):
				continue

			seen[id] = true
			result.append(node)

	return result


func get_audio_nodes_in_group(group_name: String) -> Array[Node]:
	var groups: PackedStringArray = PackedStringArray([group_name])
	return get_audio_nodes_in_groups(groups)


func has_active_snapshot(reason: String = WORLD_MUTE_REASON) -> bool:
	return _snapshots.has(_clean_reason(reason))


func has_active_duck(reason: String = "duck") -> bool:
	return _duck_snapshots.has(_clean_reason(reason))


func kill_all_fades() -> void:
	for id in _active_tweens.keys():
		_kill_tween(int(id))
	_active_tweens.clear()


# ================================================================
# SNAPSHOTS
# ================================================================
func _snapshot_nodes(reason: String, nodes: Array[Node], only_active: bool) -> void:
	var clean_reason := _clean_reason(reason)
	_snapshots[clean_reason] = _make_snapshot(nodes, only_active)


func _make_snapshot(nodes: Array[Node], only_active: bool) -> Dictionary:
	var snapshot: Dictionary = {}

	for node in nodes:
		if not _is_valid_audio_node(node):
			continue

		if only_active and not _is_audio_active(node):
			continue

		var id := node.get_instance_id()
		snapshot[id] = {
			"path": node.get_path(),
			"volume_db": _get_volume_db(node),
			"was_playing": _get_playing(node),
			"was_paused": _get_stream_paused(node),
		}

	return snapshot


func _clear_snapshot(reason: String) -> void:
	var clean_reason := _clean_reason(reason)

	if not _snapshots.has(clean_reason):
		return

	var snapshot: Dictionary = _snapshots[clean_reason]
	for id in snapshot.keys():
		_kill_tween(int(id))

	_snapshots.erase(clean_reason)


func _get_nodes_from_snapshot(reason: String) -> Array[Node]:
	var clean_reason := _clean_reason(reason)

	if not _snapshots.has(clean_reason):
		return []

	return _get_nodes_from_custom_snapshot(_snapshots[clean_reason])


func _get_nodes_from_custom_snapshot(snapshot: Dictionary) -> Array[Node]:
	var result: Array[Node] = []

	for id in snapshot.keys():
		var node := _node_from_snapshot_entry(snapshot[id])
		if _is_valid_audio_node(node):
			result.append(node)

	return result


func _node_from_snapshot_entry(entry: Dictionary) -> Node:
	if not entry.has("path"):
		return null

	var path: NodePath = entry["path"]
	return get_node_or_null(path)


# ================================================================
# PAUSA / REANUDACIÓN SEGÚN SNAPSHOT
# ================================================================
func _pause_snapshot_nodes(reason: String) -> void:
	var clean_reason := _clean_reason(reason)

	if not _snapshots.has(clean_reason):
		return

	var snapshot: Dictionary = _snapshots[clean_reason]

	for id in snapshot.keys():
		var node := _node_from_snapshot_entry(snapshot[id])
		if not _is_valid_audio_node(node):
			continue

		_kill_tween(int(id))
		_set_stream_paused(node, true)

	world_audio_paused.emit(clean_reason)


func _resume_snapshot_nodes(reason: String, optional_start_db = null) -> void:
	var clean_reason := _clean_reason(reason)

	if not _snapshots.has(clean_reason):
		return

	var snapshot: Dictionary = _snapshots[clean_reason]

	for id in snapshot.keys():
		var node := _node_from_snapshot_entry(snapshot[id])
		if not _is_valid_audio_node(node):
			continue

		var was_playing: bool = bool(snapshot[id].get("was_playing", false))
		var was_paused: bool = bool(snapshot[id].get("was_paused", false))

		if was_playing:
			if optional_start_db != null:
				_set_volume_db(float(optional_start_db), node)

			_set_stream_paused(node, was_paused)

	world_audio_resumed.emit(clean_reason)


# ================================================================
# FADES INTERNOS
# ================================================================
func _fade_nodes_to_db(nodes: Array[Node], target_db: float, duration: float, reason: String, only_snapshot_nodes: bool) -> void:
	var tweens: Array[Tween] = []
	var clean_reason := _clean_reason(reason)
	var snapshot: Dictionary = {}

	if _snapshots.has(clean_reason):
		snapshot = _snapshots[clean_reason]

	for node in nodes:
		if not _is_valid_audio_node(node):
			continue

		var id := node.get_instance_id()

		if only_snapshot_nodes and not snapshot.has(id):
			continue

		_kill_tween(id)

		var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_active_tweens[id] = tw
		tw.tween_method(_set_volume_db.bind(node), _get_volume_db(node), target_db, maxf(duration, 0.0))
		tweens.append(tw)

	await _await_tweens(tweens)

	for node in nodes:
		if _is_valid_audio_node(node):
			_kill_tween(node.get_instance_id())


func _fade_nodes_to_snapshot_volume(reason: String, nodes: Array[Node], duration: float) -> void:
	var clean_reason := _clean_reason(reason)

	if not _snapshots.has(clean_reason):
		return

	await _fade_nodes_to_custom_snapshot(_snapshots[clean_reason], nodes, duration, clean_reason)


func _fade_nodes_to_custom_snapshot(snapshot: Dictionary, nodes: Array[Node], duration: float, _reason: String) -> void:
	var tweens: Array[Tween] = []

	for node in nodes:
		if not _is_valid_audio_node(node):
			continue

		var id := node.get_instance_id()
		if not snapshot.has(id):
			continue

		var target_db: float = float(snapshot[id].get("volume_db", _get_volume_db(node)))
		_kill_tween(id)

		var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_active_tweens[id] = tw
		tw.tween_method(_set_volume_db.bind(node), _get_volume_db(node), target_db, maxf(duration, 0.0))
		tweens.append(tw)

	await _await_tweens(tweens)

	for node in nodes:
		if _is_valid_audio_node(node):
			_kill_tween(node.get_instance_id())


func _fade_nodes_to_custom_targets(nodes: Array[Node], targets: Dictionary, duration: float, _reason: String) -> void:
	var tweens: Array[Tween] = []

	for node in nodes:
		if not _is_valid_audio_node(node):
			continue

		var id := node.get_instance_id()
		if not targets.has(id):
			continue

		_kill_tween(id)

		var target_db: float = float(targets[id])
		var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_active_tweens[id] = tw
		tw.tween_method(_set_volume_db.bind(node), _get_volume_db(node), target_db, maxf(duration, 0.0))
		tweens.append(tw)

	await _await_tweens(tweens)

	for node in nodes:
		if _is_valid_audio_node(node):
			_kill_tween(node.get_instance_id())


func _await_tweens(tweens: Array[Tween]) -> void:
	for tw in tweens:
		if is_instance_valid(tw):
			await tw.finished


func _kill_tween(id: int) -> void:
	if not _active_tweens.has(id):
		return

	var tw: Tween = _active_tweens[id]
	if is_instance_valid(tw):
		tw.kill()

	_active_tweens.erase(id)


# ================================================================
# AUDIO NODE HELPERS
# ================================================================
func _is_valid_audio_node(node: Node) -> bool:
	return (
		node is AudioStreamPlayer
		or node is AudioStreamPlayer2D
		or node is AudioStreamPlayer3D
	)


func _is_audio_active(node: Node) -> bool:
	if not _is_valid_audio_node(node):
		return false

	return _get_playing(node) or _get_stream_paused(node)


func _get_volume_db(node: Node) -> float:
	return float(node.get("volume_db"))


func _set_volume_db(value: float, node: Node) -> void:
	if not _is_valid_audio_node(node):
		return

	node.set("volume_db", value)


func _get_playing(node: Node) -> bool:
	return bool(node.get("playing"))


func _get_stream_paused(node: Node) -> bool:
	return bool(node.get("stream_paused"))


func _set_stream_paused(node: Node, paused: bool) -> void:
	if not _is_valid_audio_node(node):
		return

	node.set("stream_paused", paused)


func _clean_reason(reason: String) -> String:
	var clean := reason.strip_edges()
	if clean.is_empty():
		return "unknown"
	return clean


func _debug(message: String) -> void:
	if not OS.is_debug_build():
		return

	if not DEBUG_LOGS:
		return

	print("🔊 WorldAudioManager: %s" % message)
