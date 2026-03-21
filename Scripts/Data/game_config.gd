extends Resource
class_name GameConfig

# ================================================================
# GAME CONFIG — game_config.gd
# Resource editable desde el Inspector.
# Contiene todos los parámetros configurables del juego.
# Uso: const CONFIG = preload("res://Data/Game/game_config.tres")
# ================================================================

@export_group("⏰ Tiempo")
# Segundos reales que dura una hora de juego
# 60.0 → 1 minuto real = 1 hora de juego
# 120.0 → 2 minutos reales = 1 hora de juego
@export var duracion_hora_segundos: float = 60.0

@export_group("😴 Sueño")
# Puntos de sueño recuperados por hora en hostal (sueno 0→100 en ~12h)
@export var recuperacion_hostal_por_hora: float = 8.5
# Puntos de sueño recuperados por hora en calle (más lento)
@export var recuperacion_calle_por_hora: float = 4.5
# Máximo de horas que se puede dormir en la calle
@export var horas_max_calle: float = 8.0

@export_group("💰 Economía")
# Objetivo de dinero para escapar de Whitechapel
@export var objetivo_dinero: float = 200.0
# Costes de servicios
@export var coste_hostal: float = 2.0
@export var coste_comida: float = 0.5
@export var coste_medicina: float = 3.0
@export var coste_medico: float = 15.0
