@tool
extends Node2D
class_name NameTag

# ============================================================================
# NAME TAG
# Cartel simple con nombre encima del NPC.
# ============================================================================

@export_group("NameTag")
@export var starts_visible: bool = false
@export var fade_time: float = 0.15
@export var text: String = "NPC":
	set(value):
		text = value
		_update_text()

@onready var panel: CanvasItem = $Panel
@onready var label: Label = $Panel/Label

var _fade_tween: Tween = null

func _ready() -> void:
	visible = starts_visible
	modulate.a = 1.0 if starts_visible else 0.0
	_update_text()

func set_text(new_text: String) -> void:
	text = new_text
	_update_text()

func show_tag() -> void:
	_fade_to(1.0)

func hide_tag() -> void:
	_fade_to(0.0)

func set_tag_visible(value: bool) -> void:
	if value:
		show_tag()
	else:
		hide_tag()

func _update_text() -> void:
	if label:
		label.text = text

func _fade_to(target_alpha: float) -> void:
	if _fade_tween:
		_fade_tween.kill()
		_fade_tween = null

	if target_alpha > 0.0 and not visible:
		visible = true

	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", target_alpha, fade_time)

	if is_zero_approx(target_alpha):
		_fade_tween.tween_callback(func():
			visible = false
		)
