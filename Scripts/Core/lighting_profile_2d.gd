extends Resource
class_name LightingProfile2D

# ================================================================
# LIGHTING PROFILE 2D
# Perfil de iluminación por escena.
# Se asigna desde LevelRoot y DayNightManager lo usa como override.
# ================================================================

@export_group("☀️ Sun")
@export var sun_max_energy: float = 1.0
@export var sun_color_rojizo: Color = Color(1.0, 0.28, 0.08)
@export var sun_color_naranja: Color = Color(1.0, 0.529, 0.341)
@export var sun_color_rosado: Color = Color(1.0, 0.38, 0.52)

@export_group("🌙 Moon")
@export var moon_max_energy: float = 0.1
@export var moon_color_azulado: Color = Color(0.55, 0.68, 1.0)

@export_group("🌫 Ambient")
@export var ambient_day_color: Color = Color("5995b0")
@export var ambient_night_color: Color = Color(0.0, 0.0, 0.0, 1.0)
@export var ambient_day_max_energy: float = 1.0
@export var ambient_night_max_energy: float = 0.7

@export_group("📐 Rotation")
@export var rotation_start_deg: float = -65.0
@export var rotation_mid_deg: float = 0.0
@export var rotation_end_deg: float = 65.0
