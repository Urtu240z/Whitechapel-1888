extends Node2D

func _ready() -> void:
	# Registra el player existente en la escena en PlayerManager
	PlayerManager.player_instance = $Player

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				SleepManager.start_sleep("hostal")
			KEY_2:
				SleepManager.start_sleep("calle")
			KEY_3:
				SleepManager.start_sleep("callejon")
