@tool
extends EditorScript

func _run() -> void:
	var scenes: Array[String] = []
	_collect_scenes("res://Scenes", scenes)

	for scene_path in scenes:
		var res := ResourceLoader.load(scene_path)
		if res == null:
			push_warning("No se pudo cargar: %s" % scene_path)
			continue

		var err := ResourceSaver.save(res, scene_path)
		if err != OK:
			push_warning("No se pudo guardar: %s | error: %s" % [scene_path, err])
		else:
			print("Re-guardada: ", scene_path)

	print("Listo. Escenas procesadas: ", scenes.size())


func _collect_scenes(path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()

	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break

		if file_name.begins_with("."):
			continue

		var full_path := path.path_join(file_name)

		if dir.current_is_dir():
			_collect_scenes(full_path, out)
		elif file_name.ends_with(".tscn"):
			out.append(full_path)

	dir.list_dir_end()
