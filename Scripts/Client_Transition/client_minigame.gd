extends Control

# ============================================================
# CLIENT MINIGAME
# Minijuego de timing tipo "Super Strike".
# Dos pulsos de F (ida + vuelta) dentro de una zona dorada.
# Siempre se completa — si fallas, la zona crece y el pago baja.
#
# Emite: completed(satisfaction: float)  →  0.25 a 1.0
# ============================================================

signal completed(satisfaction: float)

# ============================================================
# CONFIG
# ============================================================
@export var input_action: StringName = &"interact"

@export var bar_width:      float = 460.0
@export var bar_height:     float = 20.0
@export var cursor_speed:   float = 1.4   # vueltas por segundo

@export var initial_zone:   float = 0.10  # 10% de la barra
@export var zone_growth:    float = 0.08  # crece 8% por fallo
@export var max_zone:       float = 0.55
@export var max_rounds:     int   = 5

# Multiplicadores de satisfacción por ronda
const SATISFACTION := [1.0, 0.85, 0.70, 0.55, 0.25]

# Colores
const COLOR_BG     := Color(0.06, 0.06, 0.06, 0.92)
const COLOR_ZONE   := Color(0.85, 0.72, 0.40, 1.0)   # dorado
const COLOR_HIT    := Color(0.40, 0.85, 0.50, 1.0)   # verde hit
const COLOR_MISS   := Color(0.85, 0.30, 0.30, 1.0)   # rojo miss
const COLOR_CURSOR := Color(1.0,  1.0,  1.0,  1.0)
const COLOR_BORDER := Color(1.0,  1.0,  1.0,  0.20)

# ============================================================
# ESTADO
# ============================================================
var _active:      bool  = false
var _cursor_t:    float = 0.0
var _direction:   int   = 1        # 1 = derecha, -1 = izquierda

var _round:       int   = 0
var _zone_size:   float = 0.10
var _zone_center: float = 0.5

var _waiting_return: bool  = false  # true tras primer hit correcto
var _flash_color:    Color = COLOR_ZONE
var _flash_timer:    float = 0.0
var _input_cooldown: float = 0.0
var _completed: bool = false

# ============================================================
# INIT
# ============================================================
func _ready() -> void:
	visible = false
	set_process(false)

func start() -> void:
	visible      = true
	_active      = true
	_cursor_t    = 0.0
	_direction   = 1
	_round        = 0
	_zone_size   = initial_zone
	_zone_center = 0.5
	_waiting_return = false
	_flash_timer = 0.0
	_input_cooldown = 0.18
	_completed = false
	_flash_color = COLOR_ZONE
	set_process(true)
	queue_redraw()

# ============================================================
# PROCESO
# ============================================================
func _process(delta: float) -> void:
	if not _active:
		return

	_cursor_t += float(_direction) * cursor_speed * delta

	if _cursor_t >= 1.0:
		_cursor_t  = 1.0
		_direction = -1
	elif _cursor_t <= 0.0:
		_cursor_t  = 0.0
		_direction = 1

	if _input_cooldown > 0.0:
		_input_cooldown = maxf(0.0, _input_cooldown - delta)

	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash_color = COLOR_ZONE

	queue_redraw()

# ============================================================
# INPUT
# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if _input_cooldown > 0.0:
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.echo:
			return
	if event.is_action_pressed(input_action):
		_handle_press()
		get_viewport().set_input_as_handled()

func _handle_press() -> void:
	if _completed:
		return

	var inside := _is_inside_zone(_cursor_t)

	if not _waiting_return:
		# Primer pulso — dirección ida (→)
		if inside:
			_waiting_return = true
			_flash(COLOR_HIT)
		else:
			_fail()
	else:
		# Segundo pulso — dirección vuelta (←)
		if inside:
			_success()
		else:
			_fail()

# ============================================================
# RESULTADO
# ============================================================
func _success() -> void:
	if _completed:
		return

	_completed = true
	_active = false
	set_process(false)

	var sat: float = SATISFACTION[clamp(_round, 0, SATISFACTION.size() - 1)]
	await get_tree().create_timer(0.3).timeout
	completed.emit(sat)

func _fail() -> void:
	if _completed:
		return

	_round += 1

	if _round >= max_rounds:
		_completed = true
		_active = false
		set_process(false)
		_flash(COLOR_MISS)
		await get_tree().create_timer(0.4).timeout
		completed.emit(SATISFACTION[max_rounds - 1])
		return

	_zone_size      = min(_zone_size + zone_growth, max_zone)
	_waiting_return = false
	_cursor_t       = 0.0
	_direction      = 1
	_flash(COLOR_MISS)
	queue_redraw()

# ============================================================
# HELPERS
# ============================================================
func _is_inside_zone(t: float) -> bool:
	return abs(t - _zone_center) <= _zone_size * 0.5

func _flash(color: Color) -> void:
	_flash_color = color
	_flash_timer = 0.25

# ============================================================
# DRAW
# ============================================================
func _draw() -> void:
	var center := size * 0.5
	var bar_pos := Vector2(center.x - bar_width * 0.5, center.y - bar_height * 0.5)

	# Fondo de barra
	draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), COLOR_BG)

	# Zona objetivo
	var zone_px := _zone_size * bar_width
	var zone_x  := bar_pos.x + _zone_center * bar_width - zone_px * 0.5
	draw_rect(Rect2(Vector2(zone_x, bar_pos.y), Vector2(zone_px, bar_height)), _flash_color)

	# Cursor
	var cx := bar_pos.x + _cursor_t * bar_width
	draw_rect(Rect2(Vector2(cx - 3.0, bar_pos.y - 10.0), Vector2(6.0, bar_height + 20.0)), COLOR_CURSOR)

	# Borde
	draw_rect(Rect2(bar_pos, Vector2(bar_width, bar_height)), COLOR_BORDER, false, 1.5)

	# Texto de instrucción
	var font := ThemeDB.fallback_font
	var font_size := 16
	var msg := "[ F ]  ×  2" if not _waiting_return else "[ F ]  ←"
	var text_size := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos  := Vector2(center.x - text_size.x * 0.5, bar_pos.y - 28.0)
	draw_string(font, text_pos, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.8))

	# Indicador de ronda (puntos)
	var dot_spacing := 18.0
	var total_width  := (max_rounds - 1) * dot_spacing
	var dot_start_x  := center.x - total_width * 0.5
	var dot_y        := bar_pos.y + bar_height + 22.0
	for i in max_rounds:
		var dot_x  := dot_start_x + i * dot_spacing
		var dot_col := Color(0.85, 0.72, 0.40, 1.0) if i >= _round else Color(0.85, 0.30, 0.30, 0.7)
		draw_circle(Vector2(dot_x, dot_y), 5.0, dot_col)
