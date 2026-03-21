extends Node2D

@export var radio_deambular := 60.0
@export var velocidad := 2.0
@onready var luz = $Sprite2D/PointLight2D
@onready var sprite = $Sprite2D

var centro : Vector2
var destino : Vector2
var activa := false

func _ready():
	hide()
	luz.energy = 0
	sprite.modulate.a = 0

func aparecer(player):
	activa = true
	show()
	centro = player.global_position + Vector2(0, -30)
	global_position = centro
	_set_nuevo_destino()

	var tw = create_tween()
	tw.tween_property(sprite, "modulate:a", 1.0, 0.5)
	tw.parallel().tween_property(luz, "energy", 2.0, 0.5)

func desaparecer():
	activa = false
	var tw = create_tween()
	tw.tween_property(sprite, "modulate:a", 0.0, 0.5)
	tw.parallel().tween_property(luz, "energy", 0.0, 0.5)
	await get_tree().create_timer(0.5).timeout
	hide()

func _process(delta):
	if not activa:
		return
	if global_position.distance_to(destino) < 5:
		_set_nuevo_destino()
	global_position = global_position.lerp(destino, delta * velocidad)

func _set_nuevo_destino():
	var ang = randf() * TAU
	destino = centro + Vector2(cos(ang), sin(ang)) * radio_deambular
