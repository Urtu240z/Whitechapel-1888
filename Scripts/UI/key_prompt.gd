extends Node2D

# ============================================================================
# KEY PROMPT
# Muestra la tecla de interacción flotando sobre un objetivo.
# ============================================================================

@export var action: String = "interact"
@export var float_height: float = 60.0
@export var float_amplitude: float = 4.0
@export var float_speed: float = 2.0
@export var fade_speed: float = 8.0

@onready var label: Label = $Key/Label
@onready var sprite: Sprite2D = $Sprite2D

var _time: float = 0.0
var _visible_target: bool = false
var _base_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	_base_position = Vector2(0.0, -float_height)
	position = _base_position
	visible = true
	modulate.a = 0.0
	_update_label()

func _process(delta: float) -> void:
	_time += delta
	position = _base_position + Vector2(0.0, sin(_time * float_speed) * float_amplitude)

	var target_alpha: float = 1.0 if _visible_target else 0.0
	modulate.a = move_toward(modulate.a, target_alpha, fade_speed * delta)

	if _visible_target:
		visible = true
	elif is_zero_approx(modulate.a):
		visible = false

func show_prompt() -> void:
	visible = true
	_visible_target = true

func hide_prompt() -> void:
	_visible_target = false

func set_action(new_action: String) -> void:
	action = new_action
	_update_label()

func _update_label() -> void:
	if not label:
		return
	label.text = _get_key_display(action)

func _get_key_display(action_name: String) -> String:
	if not InputMap.has_action(action_name):
		return "?"

	var events := InputMap.action_get_events(action_name)
	for event in events:
		if event is InputEventKey:
			var key_event := event as InputEventKey

			if key_event.physical_keycode != 0:
				return OS.get_keycode_string(key_event.physical_keycode)

			if key_event.keycode != 0:
				return OS.get_keycode_string(key_event.keycode)

			return "?"

	return "?"
