extends ColorRect

# =========================================================
# ⚙️ FLASH CONFIGURATION
# =========================================================
@export var fade_in_time: float = 0.08
@export var fade_out_time: float = 0.3
@export var lightning_color: Color = Color(1, 1, 1, 1)
@export var replica_chance: float = 0.6      # probabilidad de un segundo destello
@export var max_replicas: int = 4            # máximo de réplicas
@export var min_delay: float = 0.05          # retardo mínimo entre destellos
@export var max_delay: float = 0.25          # retardo máximo entre destellos

# =========================================================
# 🏁 INITIALIZATION
# =========================================================
func _ready():
	color = lightning_color
	modulate.a = 0.0
	visible = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = -1
	offset_top = -1
	offset_right = 1
	offset_bottom = 1
	set_process_mode(Node.PROCESS_MODE_ALWAYS)

	self.material = CanvasItemMaterial.new()
	self.material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

# =========================================================
# ⚡ GLOBAL FLASH
# =========================================================
## 🔹 Si single_flash = true → solo un flash limpio (sin réplicas)
## 🔹 Si single_flash = false (por defecto) → secuencia con réplicas aleatorias
func show_global_flash(single_flash: bool = false):
	if single_flash:
		await _flash_once()
		return

	# ⚡🌩️ Secuencia con posibles réplicas (modo glitch)
	await _flash_once()
	var count := 0
	while randf() < replica_chance and count < max_replicas:
		await get_tree().create_timer(randf_range(min_delay, max_delay)).timeout
		await _flash_once()
		count += 1

# =========================================================
# ✨ FLASH IMPLEMENTATION
# =========================================================
func _flash_once() -> void:
	visible = true
	modulate.a = 0.0

	var t := 0.0
	while t < fade_in_time:
		t += get_process_delta_time()
		modulate.a = clamp(t / fade_in_time, 0.0, 1.0)
		await get_tree().process_frame

	t = 0.0
	while t < fade_out_time:
		t += get_process_delta_time()
		modulate.a = 1.0 - clamp(t / fade_out_time, 0.0, 1.0)
		await get_tree().process_frame

	modulate.a = 0.0
	visible = false
