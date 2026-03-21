extends Area2D

# =========================================================
# 🏷️ PROPIEDADES EXPORTADAS
# =========================================================
@export var word_text: String = ""
@export var memory_index: int = 0
@export var custom_font: Font
@export var font_size: int = 64
@export var fade_out_time: float = 0.6

# =========================================================
# 🔗 NODOS
# =========================================================
@onready var label: Label = $Label
@onready var shape: CollisionShape2D = $CollisionShape2D

# =========================================================
# 💾 VARIABLES INTERNAS
# =========================================================
var _is_fading := false

# =========================================================
# 🏁 READY
# =========================================================
func _ready():
	_apply_font()
	_apply_text()
	if label:
		label.connect("resized", Callable(self, "_update_shape"))
	_update_shape()
	body_entered.connect(_on_body_entered)

# =========================================================
# 🖋️ TEXTO Y FUENTE
# =========================================================
func _apply_text():
	if label:
		label.text = word_text
		_update_shape()

func _apply_font():
	if not label:
		return
	if label.label_settings:
		var settings = label.label_settings.duplicate()
		if custom_font:
			settings.font = custom_font
		settings.font_size = font_size
		label.label_settings = settings
	else:
		if custom_font:
			label.add_theme_font_override("font", custom_font)
		label.add_theme_font_size_override("font_size", font_size)
	_update_shape()

func _update_shape():
	if not label or not shape:
		return

	var local_font: Font
	var local_font_size: int

	if label.label_settings:
		local_font = label.label_settings.get_font()
		local_font_size = label.label_settings.get_font_size()
	else:
		local_font = label.get_theme_font("font")
		local_font_size = label.get_theme_font_size("font_size")

	if not local_font:
		return

	var text_size = local_font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, local_font_size)
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = text_size
	shape.shape = rect_shape
	shape.position = text_size * 0.5

# =========================================================
# 💥 COLISIÓN CON FAIRY
# =========================================================
func _on_body_entered(body):
	if _is_fading or not (body.is_in_group("player") or body.name == "Fairy"):
		return

	_is_fading = true

	# Buscar el Dream Controller
	var dream_ctrl := get_tree().get_first_node_in_group("dream_controller")
	if dream_ctrl:
		dream_ctrl.trigger_flashback(memory_index, word_text)

	# Fade y eliminar palabra
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 0.0, fade_out_time)
	tween.tween_callback(func():
		queue_free()
	)
