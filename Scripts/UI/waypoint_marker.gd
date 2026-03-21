extends Sprite2D

# --- Configurable ---
@export var edge_distance: float = 360.0
@export var screen_margin: float = 4.0
@export var smoothing_speed: float = 8.0
@export var appear_delay: float = 5.0
@export var hide_distance: float = 180.0     # distancia donde empieza a desaparecer
@export var full_visible_distance: float = 250.0  # distancia donde está totalmente visible
@export var fade_duration: float = 0.5       # duración del fade in/out

# --- Interno ---
var camera_node: Camera2D
var player: Node2D
var _appeared := false
var _tween: Tween
var _current_fade_state: int = 0  # 0=invisible, 1=visible

func _ready():
	camera_node = get_viewport().get_camera_2d()
	player = get_tree().get_first_node_in_group("player")
	if not player:
		player = get_node_or_null("/root/Flashback_2/Fairy")
	
	# inicia invisible
	modulate.a = 0.0
	visible = false
	
	# arranca el "desbloqueo" tras appear_delay
	if appear_delay > 0.0:
		await get_tree().create_timer(appear_delay).timeout
	_appeared = true

func _process(delta: float) -> void:
	if not _appeared:
		return
	
	if not camera_node:
		camera_node = get_viewport().get_camera_2d()
		return
	
	if not player:
		player = get_tree().get_first_node_in_group("player")
		if not player:
			player = get_node_or_null("/root/Flashback_2/Fairy")
			return
	
	# --- posicionamiento en borde de pantalla ---
	var target_global: Vector2 = get_parent().global_position
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var screen_coords: Vector2 = (target_global - camera_node.global_position) * camera_node.zoom + vp * 0.5
	var inset := Rect2(Vector2.ZERO, vp).grow(-screen_margin)
	
	var target_pos: Vector2
	var target_rot: float
	
	if inset.has_point(screen_coords):
		# en pantalla: muéstralo sobre el objetivo
		target_pos = target_global
		target_rot = 0.0
	else:
		# fuera de pantalla: clámpar a bordes
		var cx = clamp(screen_coords.x, screen_margin, vp.x - screen_margin)
		var cy = clamp(screen_coords.y, screen_margin, vp.y - screen_margin)
		var clamped := Vector2(cx, cy)
		target_pos = camera_node.global_position + (clamped - vp * 0.5) / camera_node.zoom
		var v = target_global - target_pos
		target_rot = v.angle() - PI * 0.5
	
	global_position = lerp(global_position, target_pos, delta * smoothing_speed)
	rotation = lerp(rotation, target_rot, delta * smoothing_speed)
	
	# --- LÓGICA DE FADE CON TWEEN ---
	var dist := player.global_position.distance_to(target_global)
	
	# Determina si debe estar visible u oculto
	if dist >= full_visible_distance and _current_fade_state != 1:
		# LEJOS: debe aparecer con fade in
		_fade_to(1.0)
		_current_fade_state = 1
	elif dist <= hide_distance and _current_fade_state != 0:
		# CERCA: debe desaparecer con fade out
		_fade_to(0.0)
		_current_fade_state = 0

func _fade_to(target_alpha: float) -> void:
	# Cancela tween anterior si existe
	if _tween and _tween.is_valid():
		_tween.kill()
	
	# Asegura que sea visible antes de hacer fade in
	if target_alpha > 0.0:
		visible = true
	
	# Crea el tween de fade
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", target_alpha, fade_duration)
	
	# Si es fade out, oculta al terminar
	if target_alpha == 0.0:
		_tween.finished.connect(func():
			if modulate.a < 0.01:
				visible = false
		, CONNECT_ONE_SHOT)
