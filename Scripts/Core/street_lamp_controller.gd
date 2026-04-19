extends Node2D

@export var hora_encendido: int = 18
@export var hora_apagado: int = 9
@export var fade_duration: float = 2.0

@onready var sprite_off: Sprite2D = get_node_or_null("Sprite_Off") as Sprite2D
@onready var sprite_on: Sprite2D = get_node_or_null("Sprite_On") as Sprite2D
@onready var point_light: PointLight2D = get_node_or_null("PointLight2D") as PointLight2D
@onready var lamp_glow: CanvasItem = get_node_or_null("Lamp_Glow") as CanvasItem
@onready var swarm: CanvasItem = get_node_or_null("Swarm") as CanvasItem
@onready var swarm2: CanvasItem = get_node_or_null("Swarm2") as CanvasItem
@onready var lamp_base: Node2D = get_node_or_null("LampBase") as Node2D

var _lampara_encendida: bool = false
var _tween: Tween

var _sprite_off_alpha_on: float = 1.0
var _sprite_on_alpha_on: float = 1.0
var _light_energy_on: float = 1.0
var _lamp_glow_alpha_on: float = 1.0
var _swarm_alpha_on: float = 1.0
var _swarm2_alpha_on: float = 1.0


func _ready() -> void:
	if sprite_off:
		_sprite_off_alpha_on = sprite_off.modulate.a

	if sprite_on:
		_sprite_on_alpha_on = sprite_on.modulate.a

	if point_light:
		_light_energy_on = point_light.energy

	if lamp_glow:
		_lamp_glow_alpha_on = lamp_glow.modulate.a

	if swarm:
		_swarm_alpha_on = swarm.modulate.a

	if swarm2:
		_swarm2_alpha_on = swarm2.modulate.a

	if DayNightManager and DayNightManager.hora_cambiada:
		DayNightManager.hora_cambiada.connect(_on_hora_cambiada)

	var encendida_inicial: bool = _es_de_noche(DayNightManager.hora_actual)
	_aplicar_estado_instantaneo(encendida_inicial)
	_lampara_encendida = encendida_inicial


func _on_hora_cambiada(hora: float) -> void:
	_aplicar_estado(hora)


func _aplicar_estado(hora: float) -> void:
	var encendida: bool = _es_de_noche(hora)

	if encendida == _lampara_encendida:
		return

	_lampara_encendida = encendida
	_animar_lampara(encendida)


func _es_de_noche(hora: float) -> bool:
	if hora_encendido > hora_apagado:
		return hora >= hora_encendido or hora < hora_apagado
	else:
		return hora >= hora_encendido and hora < hora_apagado


func _aplicar_estado_instantaneo(encendida: bool) -> void:
	if sprite_off:
		sprite_off.visible = true
		_set_canvas_item_alpha(sprite_off, _sprite_off_alpha_on if not encendida else 0.0)

	if sprite_on:
		sprite_on.visible = encendida
		_set_canvas_item_alpha(sprite_on, _sprite_on_alpha_on if encendida else 0.0)

	if point_light:
		point_light.visible = encendida
		point_light.energy = _light_energy_on if encendida else 0.0

	_set_canvas_item_alpha(lamp_glow, _lamp_glow_alpha_on if encendida else 0.0)
	_set_canvas_item_alpha(swarm, _swarm_alpha_on if encendida else 0.0)
	_set_canvas_item_alpha(swarm2, _swarm2_alpha_on if encendida else 0.0)

	_set_canvas_item_visible(lamp_glow, encendida)
	_set_canvas_item_visible(swarm, encendida)
	_set_canvas_item_visible(swarm2, encendida)

	_set_swarm_active(swarm, encendida)
	_set_swarm_active(swarm2, encendida)


func _animar_lampara(encendida: bool) -> void:
	if is_instance_valid(_tween):
		_tween.kill()

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if encendida:
		_prepare_canvas_item_for_fade_in(sprite_on)
		_prepare_canvas_item_for_fade_in(lamp_glow)
		_prepare_canvas_item_for_fade_in(swarm)
		_prepare_canvas_item_for_fade_in(swarm2)

		if sprite_off:
			sprite_off.visible = true
		if sprite_on:
			sprite_on.visible = true

		_set_swarm_active(swarm, true)
		_set_swarm_active(swarm2, true)

		if point_light:
			point_light.visible = true
			if point_light.energy <= 0.0:
				point_light.energy = 0.0
			_tween.tween_property(point_light, "energy", _light_energy_on, fade_duration)

		if sprite_off:
			_tween.tween_property(sprite_off, "modulate:a", 0.0, fade_duration)
		if sprite_on:
			_tween.tween_property(sprite_on, "modulate:a", _sprite_on_alpha_on, fade_duration)

		if lamp_glow:
			_tween.tween_property(lamp_glow, "modulate:a", _lamp_glow_alpha_on, fade_duration)
		if swarm:
			_tween.tween_property(swarm, "modulate:a", _swarm_alpha_on, fade_duration)
		if swarm2:
			_tween.tween_property(swarm2, "modulate:a", _swarm2_alpha_on, fade_duration)

		_tween.set_parallel(false)
		_tween.tween_callback(_finalizar_encendido)

	else:
		if sprite_off:
			sprite_off.visible = true
		if sprite_on:
			sprite_on.visible = true

		if point_light:
			_tween.tween_property(point_light, "energy", 0.0, fade_duration)

		if sprite_off:
			_tween.tween_property(sprite_off, "modulate:a", _sprite_off_alpha_on, fade_duration)
		if sprite_on:
			_tween.tween_property(sprite_on, "modulate:a", 0.0, fade_duration)

		if lamp_glow:
			_tween.tween_property(lamp_glow, "modulate:a", 0.0, fade_duration)
		if swarm:
			_tween.tween_property(swarm, "modulate:a", 0.0, fade_duration)
		if swarm2:
			_tween.tween_property(swarm2, "modulate:a", 0.0, fade_duration)

		_tween.set_parallel(false)
		_tween.tween_callback(_finalizar_apagado)


func _finalizar_encendido() -> void:
	if sprite_off:
		sprite_off.visible = false

	if sprite_on:
		sprite_on.visible = true

	if point_light:
		point_light.visible = true


func _finalizar_apagado() -> void:
	if sprite_off:
		sprite_off.visible = true

	if sprite_on:
		sprite_on.visible = false

	if point_light:
		point_light.visible = false

	_set_canvas_item_visible(lamp_glow, false)
	_set_canvas_item_visible(swarm, false)
	_set_canvas_item_visible(swarm2, false)

	_set_swarm_active(swarm, false)
	_set_swarm_active(swarm2, false)


func get_shadow_light_factor() -> float:
	if not is_instance_valid(point_light):
		return 0.0

	if not point_light.visible:
		return 0.0

	return clampf(
		point_light.energy / maxf(_light_energy_on, 0.001),
		0.0,
		1.0
	)


func get_shadow_source_position() -> Vector2:
	if is_instance_valid(lamp_base):
		return lamp_base.global_position
	return global_position


func _prepare_canvas_item_for_fade_in(item: CanvasItem) -> void:
	if not item:
		return

	item.visible = true
	var c := item.modulate
	c.a = 0.0
	item.modulate = c


func _set_canvas_item_visible(item: CanvasItem, visible_value: bool) -> void:
	if item:
		item.visible = visible_value


func _set_canvas_item_alpha(item: CanvasItem, alpha: float) -> void:
	if not item:
		return

	var c := item.modulate
	c.a = alpha
	item.modulate = c


func _set_swarm_active(item: CanvasItem, active: bool) -> void:
	if not item:
		return

	if item is Node:
		(item as Node).set_process(active)

	if active:
		item.visible = true

	if item is Node2D:
		(item as Node2D).queue_redraw()
