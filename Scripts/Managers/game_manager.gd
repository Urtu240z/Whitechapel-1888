extends Node

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		toggle_mouse()

func toggle_mouse():
	if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func hide_mouse():
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func show_mouse():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
