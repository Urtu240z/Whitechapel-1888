extends Node

# =========================================================
# 🎨 EffectsManager
# Autoload que gestiona efectos visuales por estado del personaje.
# Crea sus propios nodos al iniciarse — no depende de nada en la escena.
#
# 🎯 EFECTOS:
# - Stamina < 50%        → Blur + Camera shake progresivos (máximo en 0%)
# - Miedo > 50           → Viñeta oscura progresiva
# - Sueno < 35           → Parpadeos progresivos
# - Alcohol+Laudano > 40 → Distorsión ondulada progresiva
#
# 📋 SHADERS en res://Assets/Shaders/:
# - blur.gdshader
# - vignette.gdshader
# - distortion.gdshader
# =========================================================

var _canvas: CanvasLayer
var _blur: ColorRect
var _vignette: ColorRect
var _blink: ColorRect
var _distortion: ColorRect
var _disease: ColorRect
var _camera: Camera2D = null

var _blink_active: bool = false
var _blink_timer: float = 0.0
var BLINK_INTERVAL: float = 3.0
const BLINK_DURATION: float = 0.12

# =========================================================
# ⚙️ READY
# =========================================================
func _ready() -> void:
	_build_nodes()
	_connect_signals()
	# Buscar cámara cuando cambia la escena — usando scene_tree_changed
	# en lugar de tree_changed para no dispararse miles de veces
	get_tree().node_added.connect(_on_node_added)

func _build_nodes() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 10
	add_child(_canvas)

	# Orden importante — el último va encima
	_distortion = _make_fullscreen_rect()  # 1º — más abajo
	_distortion.material = _load_shader("res://Assets/Shaders/distortion.gdshader")
	_canvas.add_child(_distortion)

	_blur = _make_fullscreen_rect()        # 2º
	_blur.material = _load_shader("res://Assets/Shaders/blur.gdshader")
	_canvas.add_child(_blur)

	_blink = _make_fullscreen_rect()       # 3º
	_blink.color = Color(0, 0, 0, 1)
	_canvas.add_child(_blink)

	_vignette = _make_fullscreen_rect()    # 4º — más arriba
	_vignette.material = _load_shader("res://Assets/Shaders/vignette.gdshader")
	_canvas.add_child(_vignette)

	_disease = _make_fullscreen_rect()     # 5º — encima de todo
	_disease.material = _load_shader("res://Assets/Shaders/disease.gdshader")
	_canvas.add_child(_disease)

	_set_visible_all(false)

func _make_fullscreen_rect() -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.visible = false
	return rect

func _load_shader(path: String) -> ShaderMaterial:
	if not ResourceLoader.exists(path):
		push_warning("EffectsManager: No se encontró shader en %s" % path)
		return null
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	return mat

func _connect_signals() -> void:
	# stats_updated para viñeta, distorsión y parpadeos — no cada frame
	PlayerStats.stats_updated.connect(_on_stats_updated)

# =========================================================
# 📷 BUSCAR CÁMARA — solo cuando se añade un nodo Camera2D
# Mucho más eficiente que tree_changed que se dispara constantemente
# =========================================================
func _on_node_added(node: Node) -> void:
	if node is Camera2D:
		# Esperar un frame para que is_current() sea válido
		await get_tree().process_frame
		if is_instance_valid(node) and node.is_current():
			_camera = node

# =========================================================
# 🔄 PROCESS — solo stamina (necesita ser fluido) y parpadeos
# Viñeta y distorsión se actualizan via señal stats_updated
# =========================================================
func _process(delta: float) -> void:
	_update_stamina_effects()
	if _blink_active:
		_blink_timer += delta
		if _blink_timer >= BLINK_INTERVAL:
			_blink_timer = 0.0
			_do_blink()

# =========================================================
# 💨 STAMINA — blur + shake progresivos cada frame
# Necesita _process para ser suave visualmente
# =========================================================
func _update_stamina_effects() -> void:
	var stamina_ratio: float = clamp(PlayerStats.stamina / 50.0, 0.0, 1.0)
	var intensity: float = 1.0 - stamina_ratio

	if intensity > 0.0:
		_blur.visible = true
		if _blur.material:
			_blur.material.set_shader_parameter("blur_amount", intensity * 3.0)
		if _camera and is_instance_valid(_camera):
			var t: float = Time.get_ticks_msec() * 0.01
			_camera.offset = Vector2(
				sin(t * 7.3) * intensity * 4.0,
				cos(t * 6.1) * intensity * 4.0
			)
	else:
		_blur.visible = false
		if _camera and is_instance_valid(_camera):
			_camera.offset = Vector2.ZERO

func on_stamina_exhausted(_exhausted: bool) -> void:
	pass  # efecto gestionado progresivamente en _process

# =========================================================
# 📊 STATS UPDATED — viñeta, distorsión, parpadeos
# Se actualiza via señal, no cada frame — más eficiente
# =========================================================
func _on_stats_updated() -> void:
	_update_vignette()
	_update_distortion()
	_update_blink_state()
	_update_disease()

func _update_vignette() -> void:
	if PlayerStats.miedo > 50:
		_vignette.visible = true
		var intensity: float = clamp((PlayerStats.miedo - 50) / 50.0, 0.0, 1.0)
		if _vignette.material:
			_vignette.material.set_shader_parameter("intensity", intensity * 0.8)
	else:
		_vignette.visible = false

func _update_distortion() -> void:
	var sustancias: float = PlayerStats.alcohol + PlayerStats.laudano
	if sustancias > 40:
		_distortion.visible = true
		var intensity: float = clamp((sustancias - 40) / 160.0, 0.0, 1.0)
		if _distortion.material:
			_distortion.material.set_shader_parameter("intensity", intensity)
	else:
		_distortion.visible = false

func _update_blink_state() -> void:
	if PlayerStats.sueno < 35:
		_blink_active = true
		# Intervalo progresivo: 8s en sueno 35%, 1s en sueno 0%
		var ratio: float = clamp(PlayerStats.sueno / 35.0, 0.0, 1.0)
		BLINK_INTERVAL = lerp(1.0, 8.0, ratio)
	else:
		_blink_active = false
		_blink.visible = false

func _do_blink() -> void:
	_blink.modulate.a = 0.85
	_blink.visible = true
	var tw = create_tween()
	tw.tween_property(_blink, "modulate:a", 0.0, BLINK_DURATION)
	tw.tween_callback(func(): _blink.visible = false)

func _update_disease() -> void:
	if PlayerStats.enfermedad >= 60:
		_disease.visible = true
		# Intensidad progresiva: 0.0 en enfermedad 60, 1.0 en enfermedad 100
		var intensity: float = clamp((PlayerStats.enfermedad - 60) / 40.0, 0.0, 1.0)
		if _disease.material:
			_disease.material.set_shader_parameter("intensity", intensity)
	else:
		_disease.visible = false

# =========================================================
# 🔧 UTILS
# =========================================================
func _set_visible_all(value: bool) -> void:
	for node in [_blur, _vignette, _blink, _distortion, _disease]:
		if node:
			node.visible = value
