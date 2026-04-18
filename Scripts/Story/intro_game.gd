extends Node2D

# Referencias a tus AudioStreamPlayer2D
@onready var forest_ambient = $ForestAmbient
@onready var london_ambient = $LondonAmbient
@onready var top_left = $TopLeft      # Marker2D
@onready var bottom_right = $BottomRight  # Marker2D

# Variable para controlar el tween
var audio_tween: Tween

func _ready():
	forest_ambient.volume_db = 0
	london_ambient.volume_db = -80

	forest_ambient.play()
	london_ambient.play()

	$OutfitZone_Forest.body_entered.connect(_on_zona_forest_body_entered)
	$OutfitZone_London.body_entered.connect(_on_zona_london_body_entered)

	call_deferred("_apply_camera_limits")

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
	if body.is_in_group("player"):
		cambiar_zona_audio("forest", 2.0)

# Detecta cuando entras en la zona london
func _on_zona_london_body_entered(body):
	if body.is_in_group("player"):
		cambiar_zona_audio("london", 2.0)

func _apply_camera_limits() -> void:
	await get_tree().process_frame

	var player: Node = PlayerManager.player_instance
	if not is_instance_valid(player):
		return

	var camera_target: Node2D = player.get_node_or_null("CameraTarget") as Node2D
	if not is_instance_valid(camera_target):
		return

	var pcam: PhantomCamera2D = get_node_or_null("ExteriorPhantomCamera2D") as PhantomCamera2D
	if not is_instance_valid(pcam):
		return

	pcam.set_follow_target(camera_target)

	pcam.set_limit_left(int(top_left.global_position.x))
	pcam.set_limit_top(int(top_left.global_position.y))
	pcam.set_limit_right(int(bottom_right.global_position.x))
	pcam.set_limit_bottom(int(bottom_right.global_position.y))
