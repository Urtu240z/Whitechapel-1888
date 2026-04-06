extends Resource
class_name GameConfig

# ================================================================
# GAME CONFIG — game_config.gd
# Resource editable desde el Inspector.
# Contiene todos los parámetros configurables del juego.
# Uso: const CONFIG = preload("res://Data/Game/game_config.tres")
# ================================================================

@export_group("⏰ Tiempo")
@export var duracion_hora_segundos: float = 60.0

@export_group("😴 Hostal")
@export var hora_apertura_hostal: float = 22.0
@export var hora_cierre_hostal: float = 8.0
@export var duracion_hora_sueno_segundos: float = 0.35
@export var recuperacion_hostal_por_hora: float = 8.5
@export var recuperacion_calle_por_hora: float = 4.5
@export var horas_max_calle: float = 8.0

@export_group("💰 Economía")
@export var objetivo_dinero: float = 200.0
@export var coste_hostal: float = 2.0
@export var coste_comida: float = 0.5
@export var coste_medicina: float = 3.0
@export var coste_medico: float = 15.0

@export_group("🩺 Salud — Umbrales de daño")
@export var salud_umbral_hambre_1: float = 60.0
@export var salud_umbral_hambre_2: float = 75.0
@export var salud_umbral_hambre_3: float = 90.0

@export var salud_umbral_higiene_1: float = 40.0
@export var salud_umbral_higiene_2: float = 25.0
@export var salud_umbral_higiene_3: float = 10.0

@export var salud_umbral_enfermedad_1: float = 25.0
@export var salud_umbral_enfermedad_2: float = 50.0
@export var salud_umbral_enfermedad_3: float = 75.0

@export_group("🩺 Salud — Daño por hora")
@export var salud_dano_hambre_1: float = 0.10
@export var salud_dano_hambre_2: float = 0.25
@export var salud_dano_hambre_3: float = 0.60

@export var salud_dano_higiene_1: float = 0.08
@export var salud_dano_higiene_2: float = 0.20
@export var salud_dano_higiene_3: float = 0.45

@export var salud_dano_enfermedad_1: float = 0.15
@export var salud_dano_enfermedad_2: float = 0.35
@export var salud_dano_enfermedad_3: float = 0.75

@export_group("🩺 Salud — Recuperación por hora")
@export var salud_umbral_sueno_1: float = 55.0
@export var salud_umbral_sueno_2: float = 75.0
@export var salud_recuperacion_sueno_1: float = 0.06
@export var salud_recuperacion_sueno_2: float = 0.15

@export var salud_umbral_felicidad_1: float = 55.0
@export var salud_umbral_felicidad_2: float = 70.0
@export var salud_recuperacion_felicidad_1: float = 0.03
@export var salud_recuperacion_felicidad_2: float = 0.08

@export_group("🩺 Salud — Enfermedad crítica")
@export var salud_umbral_enfermedad_critica: float = 85.0
@export var salud_umbral_enfermedad_terminal: float = 100.0
@export var salud_dano_enfermedad_critica: float = 0.5
@export var salud_dano_enfermedad_terminal: float = 1.5
