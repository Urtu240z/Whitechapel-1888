@tool
extends EditorPlugin

# UI elements
var popup: AcceptDialog
var name_field: LineEdit
var pickup_selector: OptionButton
var delete_button: Button
var reload_button: Button
var cost_field: SpinBox
var display_name_field: LineEdit
var open_button: Button
var stat_fields := {}

const PICKUP_DIR := "res://Data/Pickups/"
const PICKUP_SCRIPT := "res://Scripts/Core/pickup.gd"

# Stats que afectan al jugador
const STATS := [
	"miedo", "estres", "felicidad", "nervios", "hambre",
	"higiene", "sueno", "alcohol", "laudano", "salud", "enfermedad"
]

func _enter_tree():
	add_tool_menu_item("🧩 Gestionar Pickups", Callable(self, "_show_popup"))
	_build_popup()
	add_child(popup)

func _exit_tree():
	remove_tool_menu_item("🧩 Gestionar Pickups")

# =============================================================
# 🧱 Construir popup
# =============================================================
func _build_popup():
	popup = AcceptDialog.new()
	popup.title = "Gestor avanzado de Pickups"
	popup.min_size = Vector2(550, 550)
	#popup.get_ok_button().text = "💾 Guardar cambios"
	#popup.confirmed.connect(Callable(self, "_save_current_pickup"))

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	popup.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(520, 520)
	scroll.add_child(vbox)

	# ---------- Sección superior ----------
	var hbox_top = HBoxContainer.new()
	vbox.add_child(hbox_top)

	pickup_selector = OptionButton.new()
	pickup_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_top.add_child(pickup_selector)

	var save_button = Button.new()
	save_button.text = "💾"
	save_button.tooltip_text = "Guardar pickup actual"
	save_button.pressed.connect(Callable(self, "_save_current_pickup"))
	hbox_top.add_child(save_button)

	reload_button = Button.new()
	reload_button.text = "🔄"
	reload_button.tooltip_text = "Recargar lista"
	reload_button.pressed.connect(Callable(self, "_reload_pickup_list"))
	hbox_top.add_child(reload_button)

	open_button = Button.new()
	open_button.text = "🧭"
	open_button.tooltip_text = "Abrir en inspector"
	open_button.pressed.connect(Callable(self, "_open_in_inspector"))
	hbox_top.add_child(open_button)

	delete_button = Button.new()
	delete_button.text = "🗑️"
	delete_button.tooltip_text = "Borrar seleccionado"
	delete_button.pressed.connect(Callable(self, "_delete_selected_pickup"))
	hbox_top.add_child(delete_button)
	vbox.add_child(HSeparator.new())

	# ---------- Campos básicos ----------
	var grid_basic = GridContainer.new()
	grid_basic.columns = 2
	vbox.add_child(grid_basic)

	var lbl_display = Label.new()
	lbl_display.text = "📝 Display Name"
	grid_basic.add_child(lbl_display)
	display_name_field = LineEdit.new()
	grid_basic.add_child(display_name_field)

	var lbl_cost = Label.new()
	lbl_cost.text = "💰 Coste (peniques)"
	grid_basic.add_child(lbl_cost)
	cost_field = SpinBox.new()
	cost_field.min_value = 0
	cost_field.max_value = 240 # 20 chelines = 1 libra
	cost_field.step = 1
	grid_basic.add_child(cost_field)

	vbox.add_child(HSeparator.new())

	# ---------- Campos de efectos ----------
	var lbl_mods = Label.new()
	lbl_mods.text = "🎯 Modificadores de Stats (0 si no aplica)"
	vbox.add_child(lbl_mods)

	var grid_stats = GridContainer.new()
	grid_stats.columns = 2
	vbox.add_child(grid_stats)

	for stat_name in STATS:
		var stat_label = Label.new()
		stat_label.text = stat_name.capitalize()
		grid_stats.add_child(stat_label)
		var spin = SpinBox.new()
		spin.min_value = -100
		spin.max_value = 100
		spin.step = 1
		grid_stats.add_child(spin)
		stat_fields[stat_name] = spin

	vbox.add_child(HSeparator.new())

	# ---------- Crear nuevo pickup ----------
	name_field = LineEdit.new()
	name_field.placeholder_text = "➕ Nuevo pickup (nombre interno)"
	vbox.add_child(name_field)

	var btn_create = Button.new()
	btn_create.text = "Crear nuevo pickup"
	btn_create.pressed.connect(Callable(self, "_create_pickup_data"))
	vbox.add_child(btn_create)

	# Conectar el selector UNA sola vez
	if not pickup_selector.is_connected("item_selected", Callable(self, "_load_selected_pickup")):
		pickup_selector.item_selected.connect(Callable(self, "_load_selected_pickup"))

	_reload_pickup_list()

# =============================================================
# 📜 Mostrar popup
# =============================================================
func _show_popup():
	_reload_pickup_list()
	popup.popup_centered_ratio(0.6)

# =============================================================
# 🔄 Recargar lista
# =============================================================
func _reload_pickup_list():
	pickup_selector.clear()

	# Asegurar directorio
	if not DirAccess.dir_exists_absolute(PICKUP_DIR):
		DirAccess.make_dir_recursive_absolute(PICKUP_DIR)

	var dir := DirAccess.open(PICKUP_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres"):
				pickup_selector.add_item(file_name.get_basename())
			file_name = dir.get_next()
		dir.list_dir_end()

	# Seleccionar y cargar el primero si hay
	if pickup_selector.item_count > 0:
		pickup_selector.select(0)
		_load_selected_pickup(0)

	# También actualiza pickup.gd
	_update_pickup_enum()

# =============================================================
# 📂 Cargar pickup seleccionado
# =============================================================
func _load_selected_pickup(index: int):
	if index < 0 or index >= pickup_selector.item_count:
		return
	var file_name := pickup_selector.get_item_text(index)
	var path := PICKUP_DIR + file_name + ".tres"
	if not ResourceLoader.exists(path):
		return

	var pickup: Resource = load(path)
	if pickup == null:
		return

	# Suponiendo clase PickupData con props display_name, cost, effects (Dictionary)
	display_name_field.text = pickup.display_name
	cost_field.value = float(pickup.cost)

	for stat_name in STATS:
		var v := 0.0
		if stat_name in pickup.effects:
			v = float(pickup.effects[stat_name])
		(stat_fields[stat_name] as SpinBox).value = v

	print("📖 Cargado pickup:", file_name)

# =============================================================
# 💾 Guardar cambios
# =============================================================
func _save_current_pickup():
	var sel := pickup_selector.get_selected_id()
	if pickup_selector.selected < 0:
		push_warning("No hay pickup seleccionado.")
		return

	var file_name := pickup_selector.get_item_text(pickup_selector.selected)
	var path := PICKUP_DIR + file_name + ".tres"
	if not ResourceLoader.exists(path):
		push_warning("❌ No se encontró el recurso.")
		return

	var pickup: Resource = load(path)
	if pickup == null:
		return

	pickup.display_name = display_name_field.text
	pickup.cost = cost_field.value
	pickup.effects.clear()

	for stat_name in STATS:
		var val := (stat_fields[stat_name] as SpinBox).value
		if absf(val) > 0.01:
			pickup.effects[stat_name] = val

	var result := ResourceSaver.save(pickup, path)
	if result == OK:
		print("💾 Pickup actualizado:", file_name)
		get_editor_interface().get_resource_filesystem().scan()
		_update_pickup_enum()
	else:
		printerr("❌ Error guardando:", path)

# =============================================================
# ➕ Crear nuevo pickup
# =============================================================
func _create_pickup_data():
	var pickup_name := name_field.text.strip_edges()
	if pickup_name.is_empty():
		push_warning("⚠️ Debes introducir un nombre para el nuevo pickup.")
		return

	var path := PICKUP_DIR + pickup_name + ".tres"
	if ResourceLoader.exists(path):
		push_warning("⚠️ Ya existe un pickup con ese nombre.")
		return

	var pickup := PickupData.new()
	pickup.name = pickup_name
	pickup.display_name = pickup_name.capitalize()
	pickup.cost = 0.0
	pickup.effects = {}

	var result := ResourceSaver.save(pickup, path)
	if result == OK:
		print("✅ Pickup creado en:", path)
		get_editor_interface().get_resource_filesystem().scan()
		_reload_pickup_list()
	else:
		printerr("❌ Error al crear el pickup:", path)

# =============================================================
# 🗑️ Borrar pickup seleccionado
# =============================================================
func _delete_selected_pickup():
	if pickup_selector.selected < 0:
		push_warning("Ningún pickup seleccionado para borrar.")
		return

	var file_name := pickup_selector.get_item_text(pickup_selector.selected)
	var path := PICKUP_DIR + file_name + ".tres"

	if FileAccess.file_exists(path):
		var ok := DirAccess.remove_absolute(path)
		if ok == OK:
			print("🗑️ Pickup borrado:", file_name)
			_reload_pickup_list()
		else:
			push_warning("No se pudo borrar el archivo.")
	else:
		push_warning("No se encontró el archivo a borrar.")

# =============================================================
# 🧭 Abrir en inspector
# =============================================================
func _open_in_inspector():
	if pickup_selector.selected < 0:
		push_warning("Selecciona un pickup primero.")
		return

	var file_name := pickup_selector.get_item_text(pickup_selector.selected)
	var path := PICKUP_DIR + file_name + ".tres"

	if not ResourceLoader.exists(path):
		push_warning("No se encontró el recurso.")
		return

	var pickup: Resource = load(path)
	if pickup:
		get_editor_interface().edit_resource(pickup)
		print("🧭 Abriendo en inspector:", file_name)

# =============================================================
# ⚙️ Actualizar export_enum en pickup.gd
# =============================================================
func _update_pickup_enum():
	if not FileAccess.file_exists(PICKUP_SCRIPT):
		printerr("⚠️ No se encontró pickup.gd para actualizar export_enum.")
		return

	var file := FileAccess.open(PICKUP_SCRIPT, FileAccess.READ)
	if file == null:
		return
	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()

	# --- recopilar pickups .tres ---
	var pickups: PackedStringArray = PackedStringArray()
	var dir := DirAccess.open(PICKUP_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres"):
				pickups.append(file_name.get_basename())
			file_name = dir.get_next()
		dir.list_dir_end()

	# Por defecto, el primero o vacío
	var default_pickup := pickups[0] if pickups.size() > 0 else ""

	# Construir lista de argumentos separados
	var enum_args := '"' + '", "'.join(pickups) + '"' if pickups.size() > 0 else ""
	var new_enum_line := '@export_enum(%s) var pickup_type: String = "%s"' % [enum_args, default_pickup]


	# Reescribir el archivo
	var new_lines := PackedStringArray()
	for line in lines:
		if line.strip_edges().begins_with("@export_enum("):
			new_lines.append(new_enum_line)
		else:
			new_lines.append(line)

	var file_save := FileAccess.open(PICKUP_SCRIPT, FileAccess.WRITE)
	if file_save:
		file_save.store_string("\n".join(new_lines))
		file_save.close()
		print("🔁 pickup.gd sincronizado con %d pickups." % pickups.size())
