extends Node

# ============================================================================
# 💥 DAMAGE MANAGER
# Autoload centralizado para gestionar todo el daño recibido por el player.
#
# USO:
#   DamageManager.take_damage(5.0, DamageManager.Source.CLIENT, -1.0)
#   DamageManager.take_damage(10.0, DamageManager.Source.JACK, 1.0)
#   DamageManager.take_damage(2.0, DamageManager.Source.HUNGER)
# ============================================================================

# ============================================================================
# FUENTES DE DAÑO
# ============================================================================
enum Source {
	CLIENT,     # Golpe de cliente rechazado
	JACK,       # Jack el Destripador
	POLICE,     # Policía
	DISEASE,    # Enfermedad (daño por tiempo)
	HUNGER,     # Hambre (daño por tiempo)
	EXHAUSTION, # Agotamiento (daño por tiempo)
	GENERIC,    # Cualquier otra fuente
}

# ============================================================================
# CONFIG
# ============================================================================
const IFRAME_DURATION: float = 1.5       # segundos de invencibilidad tras golpe físico
const BLINK_INTERVAL: float = 0.1        # intervalo de parpadeo durante iframes
const KNOCKBACK_CLIENT: float = 1500.0
const KNOCKBACK_JACK: float = 2500.0
const KNOCKBACK_POLICE: float = 1800.0
const KNOCKBACK_GENERIC: float = 1200.0

# Fuentes que activan iframes y efectos físicos
const PHYSICAL_SOURCES: Array = [
	Source.CLIENT,
	Source.JACK,
	Source.POLICE,
	Source.GENERIC,
]

# ============================================================================
# ESTADO
# ============================================================================
var _iframe_timer: float = 0.0
var _blink_timer: float = 0.0
var _is_blinking: bool = false

# ============================================================================
# READY
# ============================================================================
func _ready() -> void:
	set_process(false)

# ============================================================================
# PROCESS — gestiona iframes y parpadeo
# ============================================================================
func _process(delta: float) -> void:
	if _iframe_timer <= 0.0:
		_end_iframes()
		return

	_iframe_timer -= delta

# ============================================================================
# API PÚBLICA
# ============================================================================
func take_damage(amount: float, source: Source = Source.GENERIC, knockback_dir: float = 0.0, attack_type: String = "Kick") -> void:
	# Iframes — solo bloquea fuentes físicas
	if source in PHYSICAL_SOURCES and is_invincible():
		return

	# Daño a salud
	PlayerStats.damage_health(amount)

	# Efectos según fuente
	match source:
		Source.CLIENT:
			_apply_physical_hit(knockback_dir, attack_type, 60.0)
			_start_iframes()
		Source.JACK:
			_apply_physical_hit(knockback_dir, attack_type, 50.0, KNOCKBACK_JACK)
			_start_iframes()
		Source.POLICE:
			_apply_physical_hit(knockback_dir, attack_type, 35.0, KNOCKBACK_POLICE)
			_start_iframes()
		Source.GENERIC:
			_apply_physical_hit(knockback_dir, attack_type, 25.0, KNOCKBACK_GENERIC)
			_start_iframes()
		Source.DISEASE, Source.HUNGER, Source.EXHAUSTION:
			# Daño silencioso — sin efectos visuales de golpe
			pass

func is_invincible() -> bool:
	return _iframe_timer > 0.0

# ============================================================================
# EFECTOS FÍSICOS
# ============================================================================
func _apply_physical_hit(knockback_dir: float, attack_type: String, shake_intensity: float, knockback_force: float = KNOCKBACK_CLIENT) -> void:
	var player := _get_player()
	if not player:
		return

	# Knockback
	if knockback_dir != 0.0:
		player.velocity.x = knockback_dir * knockback_force

	# Flash rojo
	var tween := create_tween()
	tween.tween_property(player, "modulate", Color(1.5, 0.3, 0.3, 1.0), 0.05)
	tween.tween_property(player, "modulate", Color.WHITE, 0.25)

	# Partículas
	var particles := player.get_node_or_null("HitParticle")
	if particles and particles.has_method("restart"):
		particles.restart()

	# Animación del player
	var playback = player.get_node_or_null("AnimationTree")
	if playback:
		var pb = playback.get("parameters/playback")
		if pb:
			pb.travel(attack_type)

	# Screen shake + blur
	EffectsManager.screen_shake(shake_intensity, 0.3)

# ============================================================================
# IFRAMES
# ============================================================================
func _start_iframes() -> void:
	_iframe_timer = IFRAME_DURATION
	_blink_timer = BLINK_INTERVAL
	_is_blinking = true
	set_process(true)

func _end_iframes() -> void:
	_iframe_timer = 0.0
	_is_blinking = false
	set_process(false)
	# Restaurar alpha del player
	var player := _get_player()
	if player:
		player.modulate.a = 1.0

# ============================================================================
# HELPERS
# ============================================================================
func _get_player() -> Node2D:
	if PlayerManager and PlayerManager.player_instance:
		return PlayerManager.player_instance as Node2D
	return get_tree().get_first_node_in_group("player") as Node2D
