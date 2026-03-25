@tool
class_name PageFlip2D
extends Node2D

## Versión simplificada del controlador de libro.
## Solo maneja la animación de paso de hojas sobre un fondo de diario ya existente.
## No incluye: portadas, lógica de apertura/cierre, escenas interactivas, volumen 3D ni transform 3D.

enum PageStretchOption {
	SCALE = TextureRect.STRETCH_SCALE,
	KEEP_ASPECT_CENTERED = TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
	KEEP_ASPECT_COVERED = TextureRect.STRETCH_KEEP_ASPECT_COVERED
}


# ==============================================================================
# REFERENCIAS Y CONFIGURACIÓN
# ==============================================================================
@export_category("Structure References")
@export var visuals_container: Node2D
@export var static_left: Polygon2D
@export var static_right: Polygon2D
@export var dynamic_poly: Polygon2D
@export var anim_player: AnimationPlayer


@export_category("Audio")
@export var sfx_page_flip: AudioStream
@export var audio_player: AudioStreamPlayer


@export_category("Book Size Control")
@export var target_page_size: Vector2 = Vector2(512, 820)
@export var apply_size_change: bool = false : set = _on_apply_size_pressed


@export_category("Content Source")
@export_file("*.png", "*.jpg", "*.jpeg", "*.tscn") var pages_paths: Array[String] = []
@export var page_stretch_mode: PageStretchOption = PageStretchOption.SCALE
@export var blank_page_color: Color = Color.WHITE
@export var blank_page_texture: Texture2D
@export var enable_composite_pages: bool = false


# ==============================================================================
# ESTADO INTERNO
# ==============================================================================
var current_spread: int = 0
var total_spreads: int = 0
var is_animating: bool = false
var going_forward: bool = true
var page_width: float

var _runtime_pages: Array[String] = []

var _slot_1: SubViewport  # Página izquierda estática
var _slot_2: SubViewport  # Página derecha estática
var _slot_3: SubViewport  # Cara A animación
var _slot_4: SubViewport  # Cara B animación

var _scene_cache = {}

var _is_jumping: bool = false
var _jump_target_spread: int = 0
var _pending_target_spread_idx: int = 0


signal started_page_flip_animation()
signal ended_page_flip_animation()


# ==============================================================================
# BUILD & INIT
# ==============================================================================
func _ensure_structure():
	var viewports_cont = __ensure_node("Viewports", Node, self)
	var slots_cont = __ensure_node("Slots", Node, viewports_cont)
	var visual_cont = __ensure_node("Visual", Node2D, self)

	_slot_1 = __ensure_node("Slot1", SubViewport, slots_cont)
	_slot_2 = __ensure_node("Slot2", SubViewport, slots_cont)
	_slot_3 = __ensure_node("Slot3", SubViewport, slots_cont)
	_slot_4 = __ensure_node("Slot4", SubViewport, slots_cont)

	for slot in [_slot_1, _slot_2, _slot_3, _slot_4]:
		slot.transparent_bg = true
		slot.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		slot.size = target_page_size

	var s_left = __ensure_node("StaticPageLeft", Polygon2D, visual_cont)
	s_left.z_index = 1
	var s_right = __ensure_node("StaticPageRight", Polygon2D, visual_cont)
	s_right.z_index = 1
	var d_poly = __ensure_node("DynamicFlipPoly", Polygon2D, visual_cont)
	d_poly.z_index = 10
	d_poly.clip_children = Control.ClipChildrenMode.CLIP_CHILDREN_AND_DRAW

	if d_poly.get_script() == null:
		d_poly.set_script(load("res://addons/PageFlip/page_rigger.gd"))

	var anim = __ensure_node("AnimationPlayer", AnimationPlayer, self)
	var stream_player = __ensure_node("AudioStreamPlayer", AudioStreamPlayer, self)

	if not visuals_container: visuals_container = visual_cont
	if not static_left: static_left = s_left
	if not static_right: static_right = s_right
	if not dynamic_poly: dynamic_poly = d_poly
	if not anim_player: anim_player = anim
	if not audio_player: audio_player = stream_player

	if dynamic_poly and anim_player:
		if dynamic_poly.get("anim_player") == null:
			dynamic_poly.set("anim_player", anim_player)

	if _slot_1 and Vector2(_slot_1.size) != target_page_size:
		_apply_new_size()


func __ensure_node(target_name: String, type: Variant, parent_node: Node) -> Node:
	var node = parent_node.get_node_or_null(target_name)
	if node:
		return node

	node = type.new()
	node.name = target_name

	if node is SubViewport:
		node.transparent_bg = true

	parent_node.add_child(node)

	if Engine.is_editor_hint():
		node.owner = parent_node.owner if parent_node.owner else self

	return node


func _enter_tree() -> void:
	if not is_in_group("FlipBook2D"):
		add_to_group("FlipBook2D")
	BookAPI.set_current_book(self)


func _exit_tree() -> void:
	if BookAPI.get_current_book() == self:
		BookAPI.set_current_book(null)


func _ready():
	BookAPI.set_current_book(self)

	if not _slot_1: _slot_1 = find_child("Slot1", true, false)
	if not _slot_2: _slot_2 = find_child("Slot2", true, false)
	if not _slot_3: _slot_3 = find_child("Slot3", true, false)
	if not _slot_4: _slot_4 = find_child("Slot4", true, false)

	if Engine.is_editor_hint():
		_ensure_structure()
		if dynamic_poly:
			dynamic_poly.rebuild(target_page_size)
		return
	elif _slot_1 and Vector2(_slot_1.size) != target_page_size:
		_apply_new_size()

	if dynamic_poly and not dynamic_poly.material:
		dynamic_poly.material = preload("uid://ddw2ie8wnrnre")

	if dynamic_poly:
		dynamic_poly.rebuild(target_page_size)

	if not blank_page_texture:
		var w = int(target_page_size.x)
		var h = int(target_page_size.y)
		if w > 0 and h > 0:
			var img = Image.create(w, h, false, Image.FORMAT_RGBA8)
			img.fill(blank_page_color)
			blank_page_texture = ImageTexture.create_from_image(img)

	_prepare_book_content()

	# Siempre empieza abierto en spread 0 (no hay portadas)
	current_spread = 0

	if dynamic_poly and not dynamic_poly.is_connected("change_page_requested", _on_midpoint_signal):
		dynamic_poly.connect("change_page_requested", _on_midpoint_signal)

	if anim_player and not anim_player.is_connected("animation_finished", _on_animation_finished):
		anim_player.animation_finished.connect(_on_animation_finished)

	await get_tree().process_frame

	if _slot_3 and dynamic_poly:
		dynamic_poly.texture = _slot_3.get_texture()

	_initial_config()
	_set_flying_slots_active(false)


func _initial_config():
	page_width = target_page_size.x
	_set_page_visible(dynamic_poly, false)
	# Sin reposicionamiento automático: el nodo se coloca desde el editor
	_update_static_visuals_immediate()


# ==============================================================================
# TAMAÑO Y EDITOR
# ==============================================================================
func _on_apply_size_pressed(val):
	if not val:
		return
	apply_size_change = false
	_apply_new_size()


func _apply_new_size():
	print("[BookController] Rebuilding Book with size: ", target_page_size)

	page_width = target_page_size.x
	_update_viewports_recursive(self, target_page_size)

	var w = target_page_size.x
	var h = target_page_size.y
	var poly_shape = PackedVector2Array([
		Vector2(0, -h / 2.0),
		Vector2(w, -h / 2.0),
		Vector2(w, h / 2.0),
		Vector2(0, h / 2.0)
	])
	var uv_rect = PackedVector2Array([
		Vector2(0, 0),
		Vector2(w, 0),
		Vector2(w, h),
		Vector2(0, h)
	])

	if static_left:
		static_left.polygon = poly_shape
		static_left.uv = uv_rect
		static_left.position = Vector2(-w, 0)
		static_left.visible = false

	if static_right:
		static_right.polygon = poly_shape
		static_right.uv = uv_rect
		static_right.position = Vector2(0, 0)
		static_right.visible = true

	if dynamic_poly:
		dynamic_poly.position = Vector2(0.0, -h / 2.0)
		dynamic_poly.visible = false
		if dynamic_poly.has_method("rebuild"):
			dynamic_poly.rebuild(target_page_size)

	_fit_camera_to_book()


func _update_viewports_recursive(node: Node, new_size: Vector2):
	for child in node.get_children():
		if child is SubViewport:
			child.size = new_size
			child.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		if child.get_child_count() > 0:
			_update_viewports_recursive(child, new_size)


func _fit_camera_to_book():
	var cam = get_node_or_null("Camera2D")
	if not cam:
		return

	var total_book_width = target_page_size.x * 2.0
	var total_book_height = target_page_size.y * 2.0
	var screen_size = get_viewport_rect().size

	if screen_size == Vector2.ZERO:
		return

	var zoom_x = screen_size.x / total_book_width
	var zoom_y = screen_size.y / total_book_height
	cam.zoom = Vector2(min(zoom_x, zoom_y), min(zoom_x, zoom_y))


# ==============================================================================
# CONTENIDO DE PÁGINAS
# ==============================================================================
func _prepare_book_content():
	_runtime_pages = pages_paths.duplicate()

	# Rellena con página en blanco si el número es impar
	if _runtime_pages.size() > 0 and _runtime_pages.size() % 2 != 0:
		_runtime_pages.append("internal://blank_page")

	var num = _runtime_pages.size()

	# Sin portadas: total_spreads = páginas / 2
	# spread 0 = páginas 1-2, spread 1 = páginas 3-4, etc.
	total_spreads = max(1, num / 2)


func _get_page_index_for_spread(spread_idx: int, is_left: bool) -> int:
	# Sin portadas: spread 0 = páginas [0, 1], spread 1 = páginas [2, 3], etc.
	var base = spread_idx * 2

	if is_left:
		# Página izquierda: base (par)
		if base >= _runtime_pages.size():
			return -999
		return base
	else:
		# Página derecha: base + 1 (impar)
		if base + 1 >= _runtime_pages.size():
			return -999
		return base + 1


func _update_slot_content(slot: SubViewport, content_index: int) -> void:
	if not slot:
		return

	for child in slot.get_children():
		if child is TextureRect:
			child.queue_free()
		else:
			slot.remove_child(child)

	if content_index == -999:
		return  # Slot vacío / invisible

	var resource_path = ""
	if content_index >= 0 and content_index < _runtime_pages.size():
		resource_path = _runtime_pages[content_index]

	if resource_path != "":
		if resource_path == "internal://blank_page":
			_setup_texture_in_slot(slot, blank_page_texture)
		elif ResourceLoader.exists(resource_path):
			var res = load(resource_path)
			if res is PackedScene:
				_setup_scene_in_slot(slot, res, content_index)
			elif res is Texture2D:
				_setup_texture_in_slot(slot, res)
			else:
				_setup_texture_in_slot(slot, blank_page_texture)
	else:
		_setup_texture_in_slot(slot, blank_page_texture)


func _setup_scene_in_slot(slot: SubViewport, scene_pkg: PackedScene, content_index: int):
	if enable_composite_pages:
		_add_composite_blank_bg(slot)

	var cache_key = scene_pkg.get_path() + "#" + str(content_index)
	var instance

	if not cache_key in _scene_cache:
		instance = scene_pkg.instantiate()
		instance.position = Vector2.ZERO
		slot.add_child(instance)
		_scene_cache[cache_key] = instance
	else:
		instance = _scene_cache[cache_key]
		if instance.is_inside_tree():
			instance.reparent(slot)
		else:
			slot.add_child(instance)


func _setup_texture_in_slot(slot: SubViewport, tex: Texture2D):
	if enable_composite_pages:
		_add_composite_blank_bg(slot)

	if not tex:
		tex = blank_page_texture
		if not tex:
			return

	var rect = TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = page_stretch_mode as TextureRect.StretchMode
	rect.size = slot.size
	rect.position = Vector2.ZERO
	slot.add_child(rect)


func _add_composite_blank_bg(slot: SubViewport):
	if not blank_page_texture:
		return

	var bg = TextureRect.new()
	bg.texture = blank_page_texture
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = page_stretch_mode as TextureRect.StretchMode
	bg.size = slot.size
	bg.position = Vector2.ZERO
	slot.add_child(bg)


func _update_static_visuals_immediate():
	var idx_l = _get_page_index_for_spread(current_spread, true)
	var idx_r = _get_page_index_for_spread(current_spread, false)

	_update_slot_content(_slot_1, idx_l)
	_update_slot_content(_slot_2, idx_r)

	static_left.texture = _slot_1.get_texture()
	static_right.texture = _slot_2.get_texture()

	_set_page_visible(static_left, idx_l != -999)
	_set_page_visible(static_right, idx_r != -999)


# ==============================================================================
# INPUT
# ==============================================================================
func _unhandled_input(event):
	if Engine.is_editor_hint():
		return
	if not visible or is_animating:
		return

	# Bloquear input si el CanvasLayer padre no es visible
	var parent = get_parent()
	while parent:
		if parent is CanvasLayer and not parent.visible:
			return
		parent = parent.get_parent()

	if event.is_action_pressed("ui_right"):
		next_page()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		prev_page()
		get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_pos = visuals_container.get_local_mouse_position()
		if local_pos.x > 0.0:
			next_page()
		else:
			prev_page()
		get_viewport().set_input_as_handled()


# ==============================================================================
# NAVEGACIÓN PÚBLICA
# ==============================================================================
func next_page():
	if is_animating or current_spread >= total_spreads - 1:
		return
	_start_animation(true)


func prev_page():
	if is_animating or current_spread <= 0:
		return
	_start_animation(false)


func go_to_page(page_num: int = 1) -> void:
	if is_animating:
		return

	var safe_page = max(1, page_num)
	var target_spread = int(safe_page / 2.0)
	target_spread = clampi(target_spread, 0, total_spreads - 1)

	if target_spread == current_spread:
		return

	_is_jumping = true
	_jump_target_spread = target_spread
	_start_animation(target_spread > current_spread)


func _pageflip_set_input_enabled(give_control_to_book: bool):
	set_process_unhandled_input(give_control_to_book)


# ==============================================================================
# ANIMACIÓN
# ==============================================================================
func _set_flying_slots_active(is_active: bool) -> void:
	var mode = SubViewport.UPDATE_ALWAYS if is_active else SubViewport.UPDATE_DISABLED
	if _slot_3:
		_slot_3.render_target_update_mode = mode
	if _slot_4:
		_slot_4.render_target_update_mode = mode


func _start_animation(forward: bool) -> void:
	started_page_flip_animation.emit()
	is_animating = true
	going_forward = forward
	_set_flying_slots_active(true)

	var target_spread_idx = current_spread + 1 if forward else current_spread - 1
	if _is_jumping:
		target_spread_idx = _jump_target_spread
	_pending_target_spread_idx = target_spread_idx

	# --- Configuración de slots ---
	var idx_static_left: int
	var idx_static_right: int
	var idx_anim_a: int
	var idx_anim_b: int

	if forward:
		idx_static_left = _get_page_index_for_spread(current_spread, true)
		idx_static_right = _get_page_index_for_spread(target_spread_idx, false)
		idx_anim_a = _get_page_index_for_spread(current_spread, false)
		idx_anim_b = _get_page_index_for_spread(target_spread_idx, true)
	else:
		idx_static_left = _get_page_index_for_spread(target_spread_idx, true)
		idx_static_right = _get_page_index_for_spread(current_spread, false)
		idx_anim_a = _get_page_index_for_spread(current_spread, true)
		idx_anim_b = _get_page_index_for_spread(target_spread_idx, false)

	_update_slot_content(_slot_1, idx_static_left)
	_update_slot_content(_slot_2, idx_static_right)
	_update_slot_content(_slot_3, idx_anim_a)
	_update_slot_content(_slot_4, idx_anim_b)

	static_left.texture = _slot_1.get_texture()
	static_right.texture = _slot_2.get_texture()

	var tex_front = _slot_3.get_texture()
	var tex_back = _slot_4.get_texture()
	dynamic_poly.texture = tex_back

	if dynamic_poly.material is ShaderMaterial:
		dynamic_poly.material.set_shader_parameter("shadow_intensity", 0.0)
		var shadow_tex = dynamic_poly.get("shadow_gradient")
		if shadow_tex:
			dynamic_poly.material.set_shader_parameter("spine_shadow_gradient", shadow_tex)

		if forward:
			dynamic_poly.material.set_shader_parameter("front_texture", tex_front)
			dynamic_poly.material.set_shader_parameter("back_texture", tex_back)
		else:
			dynamic_poly.material.set_shader_parameter("front_texture", tex_back)
			dynamic_poly.material.set_shader_parameter("back_texture", tex_front)

	var final_anim_name = "turn_flexible_page" if forward else "turn_flexible_page_mirror"
	var anim_len = 1.0

	if anim_player.has_animation(final_anim_name):
		anim_len = anim_player.get_animation(final_anim_name).length
		anim_player.current_animation = final_anim_name
		anim_player.seek(0.0, true)

	_set_page_visible.call_deferred(dynamic_poly, true)
	dynamic_poly.z_index = 10

	await RenderingServer.frame_post_draw

	var motion_duration = anim_len / max(0.01, anim_player.speed_scale)

	# Sombra shader
	if dynamic_poly.material is ShaderMaterial:
		# Leemos el max_shadow_spread configurado en el material para respetarlo
		var target_spread_val = dynamic_poly.material.get_shader_parameter("max_shadow_spread")
		if target_spread_val == null or target_spread_val == 0.0:
			target_spread_val = 0.5

		var shadow_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		shadow_tween.tween_property(dynamic_poly.material, "shader_parameter/shadow_intensity", 0.65, motion_duration * 0.5)
		# max_shadow_spread ya está fijado en el material, no lo tocamos durante la animación
		shadow_tween.set_ease(Tween.EASE_IN)
		shadow_tween.tween_property(dynamic_poly.material, "shader_parameter/shadow_intensity", 0.0, motion_duration * 0.4)

	anim_player.play(final_anim_name)
	_play_sound(sfx_page_flip)


func _on_midpoint_signal():
	pass  # El shader maneja el flip visual automáticamente


func _on_animation_finished(_anim_name: String):
	_set_page_visible(dynamic_poly, false)
	_set_flying_slots_active(false)
	dynamic_poly.z_index = 10

	if _is_jumping:
		_is_jumping = false
		current_spread = _jump_target_spread
	else:
		if going_forward:
			current_spread = min(current_spread + 1, total_spreads - 1)
		else:
			current_spread = max(current_spread - 1, 0)

	_update_static_visuals_immediate()
	is_animating = false
	ended_page_flip_animation.emit()


# ==============================================================================
# HELPERS
# ==============================================================================
func _set_page_visible(node: Node2D, show: bool):
	if node:
		node.visible = show


func _play_sound(stream: AudioStream):
	if not audio_player or not stream:
		return
	audio_player.stream = stream
	audio_player.pitch_scale = randf_range(0.95, 1.05)
	audio_player.play()
