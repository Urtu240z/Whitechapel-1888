extends Sprite2D

@export var hora_encendido: int = 18
@export var hora_apagado: int = 9

@onready var point_light = $PointLight2D
@onready var lamp_glow   = get_node_or_null("Lamp_Glow")
@onready var swarm       = get_node_or_null("Swarm")
@onready var swarm2      = get_node_or_null("Swarm2")

func _ready() -> void:
	DayNightManager.hora_cambiada.connect(_on_hora_cambiada)
	_aplicar_estado(DayNightManager.hora_actual)

func _on_hora_cambiada(hora: float) -> void:
	_aplicar_estado(hora)

func _aplicar_estado(hora: float) -> void:
	_set_lampara(_es_de_noche(hora))

func _es_de_noche(hora: float) -> bool:
	# Cruza medianoche: encendido >= 18, apagado <= 8
	if hora_encendido > hora_apagado:
		return hora >= hora_encendido or hora < hora_apagado
	else:
		return hora >= hora_encendido and hora < hora_apagado

func _set_lampara(encendida: bool) -> void:
	if point_light:
		point_light.visible = encendida
	if lamp_glow:
		lamp_glow.visible = encendida
	if swarm:
		swarm.visible = encendida
		swarm.set_process(encendida)
	if swarm2:
		swarm2.visible = encendida
		swarm2.set_process(encendida)
