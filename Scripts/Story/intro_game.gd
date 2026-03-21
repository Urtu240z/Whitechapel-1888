extends Node2D

# Referencias a tus AudioStreamPlayer2D
@onready var forest_ambient = $ForestAmbient
@onready var london_ambient = $LondonAmbient

# Variable para controlar el tween
var audio_tween: Tween

func _ready():
	# Inicia con el audio del bosque
	forest_ambient.volume_db = 0
	london_ambient.volume_db = -80  # Silencio
	
	# Asegúrate de que ambos estén reproduciéndose
	forest_ambient.play()
	london_ambient.play()
	
	# Conecta las señales de las zonas
	$OutfitZone_Forest.body_entered.connect(_on_zona_forest_body_entered)
	$OutfitZone_London.body_entered.connect(_on_zona_london_body_entered)

func cambiar_zona_audio(zona_destino: String, duracion: float = 2.0):
	# Cancela el tween anterior si existe
	if audio_tween:
		audio_tween.kill()
	
	audio_tween = create_tween()
	audio_tween.set_parallel(true)  # Ambas animaciones al mismo tiempo
	
	match zona_destino:
		"forest":
			audio_tween.tween_property(forest_ambient, "volume_db", 0, duracion)
			audio_tween.tween_property(london_ambient, "volume_db", -80, duracion)
		
		"london":
			audio_tween.tween_property(forest_ambient, "volume_db", -80, duracion)
			audio_tween.tween_property(london_ambient, "volume_db", 0, duracion)

# Detecta cuando entras en la zona forest
func _on_zona_forest_body_entered(body):
	if body.is_in_group("Player"):
		cambiar_zona_audio("forest", 2.0)

# Detecta cuando entras en la zona london
func _on_zona_london_body_entered(body):
	if body.is_in_group("Player"):
		cambiar_zona_audio("london", 2.0)


func _on_zona_city_body_entered(body: Node2D) -> void:
	pass # Replace with function body.
