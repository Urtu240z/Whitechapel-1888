extends Node2D

# =========================================================
# ⚙️ WORD SETTINGS
# =========================================================
@export var word_text: String = "HATE"
@export var flash_index: int = 0
@export var float_amplitude: float = 10.0
@export var float_speed: float = 2.0
@export var flicker_intensity: float = 0.2
@export var flicker_speed: float = 8.0
@export var fade_out_time: float = 0.6
@export var hint_delay: float = 5.0  # segundos antes de mostrar el destello

# =========================================================
# 🔗 NODE REFERENCES
# =========================================================
@onready var label: Label = $Label
@onready var area: Area2D = $Area2D
@onready var indicator_scene = preload("res://Scenes/Story/Word_Indicator.tscn")

# =========================================================
# INTERNAL STATE
# =========================================================
var indicator_instance: Node2D = null
var base_y: float
var is_fading: bool = false
var hint_timer: float = 0.0

# =========================================================
# 🏁 INITIALIZATION
# =========================================================
func _ready():
	label.text = word_text
	label.modulate = Color(1, 1, 1, 1)
	base_y = position.y
	area.body_entered.connect(_on_body_entered)
	add_to_group("words")

	# Crear indicador visual (HUD)
	if get_tree().has_group("flash_manager"):
		var flash_mgr = get_tree().get_nodes_in_group("flash_manager")[0]
		if flash_mgr.has_node("CanvasLayer_Lightning/HUD_WordIndicators"):
			indicator_instance = indicator_scene.instantiate()
			indicator_instance.word_ref = self
			flash_mgr.get_node("CanvasLayer_Lightning/HUD_WordIndicators").add_child(indicator_instance)

# =========================================================
# ✨ FLOATING + FLICKER EFFECT
# =========================================================
func _process(delta):
	# Movimiento flotante
	position.y = base_y + sin(Time.get_ticks_msec() / 1000.0 * float_speed) * float_amplitude
	
	# Parpadeo (flicker)
	var flicker = 1.0 + sin(Time.get_ticks_msec() / 1000.0 * flicker_speed) * flicker_intensity
	label.modulate = Color(flicker, flicker, flicker, label.modulate.a)

	# Flash hint automático
	if not is_fading:
		hint_timer += delta
		if hint_timer >= hint_delay:
			hint_timer = 0.0
			if get_tree().has_group("flash_manager"):
				get_tree().call_group("flash_manager", "hint_flash_from_word", global_position)

# =========================================================
# 💥 INTERACCIÓN CON EL PLAYER
# =========================================================
func _on_body_entered(body):
	if is_fading or not (body.name == "Player" or body.name == "Fairy"):
		return

	is_fading = true
	var fade_total: float = fade_out_time
	var flash_mgr: Node = null

	# Buscar el Flash Manager
	if get_tree().has_group("flash_manager"):
		flash_mgr = get_tree().get_nodes_in_group("flash_manager")[0]

	# Obtener duración del flash asociado
	if flash_mgr and flash_index >= 0 and flash_index < flash_mgr.flash_images.size():
		var img = flash_mgr.flash_images[flash_index]
		if img:
			var fade_in: float = float(img.get_meta("fade_in")) if img.has_meta("fade_in") else flash_mgr.fade_in_time
			var fade_out: float = float(img.get_meta("fade_out")) if img.has_meta("fade_out") else flash_mgr.fade_out_time
			fade_total = fade_in + fade_out

	# Disparar flash visual
	if flash_mgr:
		flash_mgr.show_flash_by_index(flash_index)

	# 🌩️ Crear la palabra glitcheada en el CanvasLayer superior
	_spawn_glitched_word()

	# Desvanecer la palabra y limpiar
	var tween = create_tween()
	tween.tween_property(label, "modulate:a", 0.0, fade_total)
	tween.tween_callback(func ():
		if indicator_instance:
			indicator_instance.queue_free()
		queue_free()
		get_tree().call_group("word_spawner", "on_word_finished")
	)

# =========================================================
# 🌩️ GLITCHED WORD (visual only, CanvasLayer_Glitch)
# =========================================================
func _spawn_glitched_word():
	var flash_mgrs = get_tree().get_nodes_in_group("flash_manager")
	if flash_mgrs.is_empty():
		return

	var flash_mgr = flash_mgrs[0]
	if not flash_mgr.has_node("CanvasLayer_Glitch/Control"):
		return

	var glitch_parent = flash_mgr.get_node("CanvasLayer_Glitch/Control")

	# Instanciar la palabra visual (escena Word_Glitch)
	var glitch_scene = preload("res://Scenes/Story/Word_Glitch.tscn")
	var glitch_label: Label = glitch_scene.instantiate()

	# Copiar texto, fuente y tamaño exactos del label original
	glitch_label.text = word_text
	var font_res: Font = label.get("custom_fonts/font") as Font
	if font_res:
		glitch_label.add_theme_font_override("font", font_res)
	var size_val: Variant = label.get("custom_constants/font_size")
	if typeof(size_val) in [TYPE_INT, TYPE_FLOAT]:
		glitch_label.add_theme_font_size_override("font_size", int(size_val))

	# Posición aleatoria dentro del viewport
	var viewport_size = get_viewport_rect().size
	glitch_label.position = Vector2(
		randf_range(0.2, 0.8) * viewport_size.x,
		randf_range(0.2, 0.8) * viewport_size.y
	)

	# Añadir al CanvasLayer de glitch
	glitch_parent.add_child(glitch_label)
