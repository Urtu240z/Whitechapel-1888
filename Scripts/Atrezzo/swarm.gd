@tool
extends Node2D

const ESTADO_MOVIENDO = 0
const ESTADO_PARADO = 1

@export var modo_superficie: bool = false : set = _set_modo

# --- MODO VUELO ---
@export_group("Vuelo")
@export var num_insects: int = 18
@export var radio_min: float = 8.0
@export var radio_max: float = 28.0
@export var velocidad_min: float = 1.8
@export var velocidad_max: float = 3.5
@export var wander_amplitud: float = 5.0

# --- MODO SUPERFICIE ---
@export_group("Superficie")
@export var num_insects_sup: int = 12
@export var rect_ancho: float = 40.0
@export var rect_alto: float = 14.0
@export var velocidad_sup_min: float = 0.3
@export var velocidad_sup_max: float = 0.9
@export var wander_sup_amplitud: float = 6.0
@export var wander_sup_frecuencia: float = 0.6

# --- VISUAL ---
@export_group("Visual")
@export var color_insecto: Color = Color(0.05, 0.02, 0.0, 0.85)
@export var tamano_insecto: float = 1.5

var insects: Array = []

class Insect:
	# Vuelo
	var angulo: float
	var radio: float
	var velocidad: float
	var wander_fase: float
	var wander_vel: float
	var punto: Vector2
	# Superficie
	var pos: Vector2
	var dir: Vector2
	var vel: float
	var wander_timer: float
	var wander_target_dir: Vector2
	# Estado
	var estado: int
	var estado_timer: float

func _set_modo(_val: bool) -> void:
	modo_superficie = _val
	_init_insects()
	queue_redraw()

func _ready() -> void:
	_init_insects()
	if not Engine.is_editor_hint():
		_setup_visibility_notifier()

func _setup_visibility_notifier() -> void:
	var notifier = VisibleOnScreenNotifier2D.new()
	var margen = radio_max
	notifier.rect = Rect2(-margen, -margen, margen * 2.0, margen * 2.0)
	add_child(notifier)
	notifier.screen_entered.connect(_on_screen_entered)
	notifier.screen_exited.connect(_on_screen_exited)
	set_process(false)

func _on_screen_entered() -> void:
	set_process(true)

func _on_screen_exited() -> void:
	set_process(false)
	queue_redraw()

func _init_insects() -> void:
	insects.clear()
	var count = num_insects_sup if modo_superficie else num_insects
	for i in count:
		var ins = Insect.new()
		if modo_superficie:
			ins.pos = Vector2(
				randf_range(-rect_ancho * 0.5, rect_ancho * 0.5),
				randf_range(-rect_alto * 0.5, rect_alto * 0.5)
			)
			var angle = randf() * TAU
			ins.dir = Vector2(cos(angle), sin(angle))
			ins.vel = randf_range(velocidad_sup_min, velocidad_sup_max)
			ins.wander_timer = randf_range(0.3, 1.2)
			ins.wander_target_dir = ins.dir
			ins.wander_fase = randf() * TAU
			ins.estado = ESTADO_MOVIENDO
			ins.estado_timer = randf_range(0.5, 2.0)
		else:
			ins.angulo     = randf() * TAU
			ins.radio      = randf_range(radio_min, radio_max)
			ins.velocidad  = randf_range(velocidad_min, velocidad_max) * (1.0 if randf() > 0.5 else -1.0)
			ins.wander_fase = randf() * TAU
			ins.wander_vel  = randf_range(0.5, 1.5)
		insects.append(ins)

func _process(delta: float) -> void:
	var t = Time.get_ticks_msec() * 0.001

	if modo_superficie:
		for ins in insects:
			ins.estado_timer -= delta

			if ins.estado == ESTADO_MOVIENDO:
				ins.wander_timer -= delta
				if ins.wander_timer <= 0.0:
					var angle = randf() * TAU
					ins.wander_target_dir = Vector2(cos(angle), sin(angle))
					ins.wander_timer = randf_range(0.4, 1.4)
				ins.dir = ins.dir.lerp(ins.wander_target_dir, delta * wander_sup_frecuencia).normalized()
				var jitter = sin(ins.wander_fase + t * 3.0) * 0.3
				var move_dir = ins.dir.rotated(jitter)
				ins.pos += move_dir * ins.vel * delta

				# Rebotes
				if ins.pos.x < -rect_ancho * 0.5 or ins.pos.x > rect_ancho * 0.5:
					ins.dir.x *= -1.0
					ins.pos.x = clamp(ins.pos.x, -rect_ancho * 0.5, rect_ancho * 0.5)
				if ins.pos.y < -rect_alto * 0.5 or ins.pos.y > rect_alto * 0.5:
					ins.dir.y *= -1.0
					ins.pos.y = clamp(ins.pos.y, -rect_alto * 0.5, rect_alto * 0.5)

				if ins.estado_timer <= 0.0:
					ins.estado = ESTADO_PARADO
					ins.estado_timer = randf_range(0.3, 1.8)

				ins.punto = ins.pos

			else: # ESTADO_PARADO
				var buzz = Vector2(
					sin(ins.wander_fase + t * 18.0),
					cos(ins.wander_fase + t * 22.0)
				) * 0.4
				ins.punto = ins.pos + buzz

				if ins.estado_timer <= 0.0:
					ins.estado = ESTADO_MOVIENDO
					ins.estado_timer = randf_range(0.8, 3.5)
					var angle = randf() * TAU
					ins.wander_target_dir = Vector2(cos(angle), sin(angle))
	else:
		for ins in insects:
			ins.angulo += ins.velocidad * delta
			var r_offset = sin(ins.wander_fase + t * ins.wander_vel) * wander_amplitud
			ins.punto = Vector2(cos(ins.angulo), sin(ins.angulo) * 0.5) * (ins.radio + r_offset)

	queue_redraw()

func _draw() -> void:
	if modo_superficie:
		if Engine.is_editor_hint():
			draw_rect(Rect2(-rect_ancho * 0.5, -rect_alto * 0.5, rect_ancho, rect_alto),
				Color(1, 1, 0, 0.15), false)
		for ins in insects:
			draw_circle(ins.punto, tamano_insecto, color_insecto)
	else:
		for ins in insects:
			var alpha_mod = remap(ins.punto.y, -radio_max, radio_max, 0.4, 1.0)
			var c = Color(color_insecto.r, color_insecto.g, color_insecto.b,
				color_insecto.a * alpha_mod)
			draw_circle(ins.punto, tamano_insecto, c)
