extends CanvasLayer

# ----------------------------------------
# UI script: ui_stats.gd
# Muestra los atributos del jugador en tiempo real
# y permite mostrar/ocultar con la tecla Q (acción "stats")
# ----------------------------------------

@onready var bars := {
	"miedo":       $Panel/VBoxContainer/GridContainer/BarMiedo,
	"estres":      $Panel/VBoxContainer/GridContainer/BarEstres,
	"felicidad":   $Panel/VBoxContainer/GridContainer/BarFelicidad,
	"nervios":     $Panel/VBoxContainer/GridContainer/BarNervios,
	"hambre":      $Panel/VBoxContainer/GridContainer/BarHambre,
	"higiene":     $Panel/VBoxContainer/GridContainer/BarHigiene,
	"sueno":       $Panel/VBoxContainer/GridContainer/BarSueno,
	"alcohol":     $Panel/VBoxContainer/GridContainer/BarAlcohol,
	"laudano":     $Panel/VBoxContainer/GridContainer/BarLaudano,
	"salud":       $Panel/VBoxContainer/GridContainer/BarSalud,
	"stamina":     $Panel/VBoxContainer/GridContainer/BarStamina,
	"enfermedad":  $Panel/VBoxContainer/GridContainer/BarEnfermedad,
	"sex_appeal":  $Panel/VBoxContainer/BarSexAppeal,
}

# Stats donde ALTO es malo (rojo cuando sube)
const STATS_INVERTIDOS := ["miedo", "estres", "nervios", "hambre", "alcohol", "laudano", "enfermedad"]

@onready var label_estado: Label = $Panel/VBoxContainer/LabelEstado
@onready var label_dinero: Label = $Panel/VBoxContainer/LabelDinero
@onready var label_hora: Label   = $Panel/VBoxContainer/LabelHora

@export var fade_time := 0.3

var visible_stats := false
var transitioning := false

# ----------------------------------------
# SETUP
# ----------------------------------------
func _ready() -> void:
	$Panel.visible = false
	$Panel.modulate.a = 0.0

	PlayerStats.stats_updated.connect(_actualizar_todo)
	PlayerStats.atributo_critico.connect(_on_atributo_critico)
	PlayerStats.objetivo_completado.connect(_on_objetivo_completado)
	PlayerStats.enfermedad_cambiada.connect(_on_enfermedad_cambiada)
	DayNightManager.hora_cambiada.connect(_on_hora_cambiada)

	for bar in bars.values():
		bar.min_value = 0
		bar.max_value = 100

	_actualizar_todo()

# ----------------------------------------
# INPUT: Toggle con tecla Q ("stats")
# ----------------------------------------
func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("stats") and not transitioning:
		if visible_stats:
			await _hide_ui()
		else:
			await _show_ui()

# ----------------------------------------
# Mostrar/Ocultar con fade
# ----------------------------------------
func _show_ui() -> void:
	visible_stats = true
	transitioning = true
	$Panel.visible = true
	$Panel.scale = Vector2(0.9, 0.9)
	var tw := create_tween()
	tw.tween_property($Panel, "modulate:a", 1.0, fade_time)
	tw.parallel().tween_property($Panel, "scale", Vector2.ONE, fade_time)
	await tw.finished
	transitioning = false

func _hide_ui() -> void:
	visible_stats = false
	transitioning = true
	var tw := create_tween()
	tw.tween_property($Panel, "modulate:a", 0.0, fade_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	$Panel.visible = false
	transitioning = false

# ----------------------------------------
# Actualización completa
# ----------------------------------------
func _actualizar_todo() -> void:
	for key in bars.keys():
		var bar = bars[key]
		if bar == null:
			push_warning("UIStats: barra no encontrada: " + key)
			continue
		var valor: float = PlayerStats.get(key)
		bar.value = valor
		bar.modulate = _color_para_stat(key, valor)

	label_estado.text = PlayerStats.obtener_estado_general()
	label_dinero.text = "💰 %.1f chelines" % PlayerStats.dinero

# ----------------------------------------
# Color de cada barra
# Stats normales: verde alto, rojo bajo
# Stats invertidos: verde bajo, rojo alto
# ----------------------------------------
func _color_para_stat(stat: String, valor: float) -> Color:
	if stat in STATS_INVERTIDOS:
		if valor >= 70:
			return Color.RED
		elif valor >= 40:
			return Color.ORANGE
		else:
			return Color.GREEN
	else:
		return PlayerStats.obtener_color_atributo(valor)

# ----------------------------------------
# Señales específicas
# ----------------------------------------
func _on_atributo_critico(cual: String) -> void:
	if bars.has(cual):
		var bar = bars[cual]
		var tw = create_tween().set_loops(3)
		tw.tween_property(bar, "modulate", Color.WHITE, 0.1)
		tw.tween_property(bar, "modulate", Color.RED, 0.1)

func _on_enfermedad_cambiada(enferma: bool) -> void:
	if enferma:
		# Parpadeo en la barra de enfermedad para llamar la atención
		var bar = bars["enfermedad"]
		var tw = create_tween().set_loops(5)
		tw.tween_property(bar, "modulate", Color.WHITE, 0.15)
		tw.tween_property(bar, "modulate", Color.RED, 0.15)

func _on_objetivo_completado() -> void:
	label_estado.text = "🏆 ¡Has reunido el dinero para escapar!"

func _on_hora_cambiada(hora_actual: float) -> void:
	var hora_int := int(hora_actual)
	var minutos := int((hora_actual - hora_int) * 60)
	label_hora.text = "🕒 %02d:%02d" % [hora_int, minutos]
