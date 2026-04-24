extends Node

# ================================================================
# DAMAGE MANAGER — Autoload
# ================================================================
# Autoridad central para daño recibido por Nell.
#
# Responsabilidades:
# - Aplicar daño a PlayerStats.
# - Gestionar iframes de golpes físicos.
# - Pedir knockback al PlayerManager.
# - Pedir efectos globales al EffectsManager.
#
# No debe:
# - Decidir estado global. Eso pertenece a StateManager.
# - Abrir UI o transiciones.
# - Gestionar enfermedad/hambre como sistema. Solo aplica daño cuando se le pide.
# ================================================================

signal damage_taken(amount: float, source: Source)
signal physical_hit_taken(source: Source, knockback_dir: float, attack_type: String)
signal invincibility_started(duration: float)
signal invincibility_ended

# ================================================================
# FUENTES DE DAÑO
# ================================================================
enum Source {
	CLIENT,
	JACK,
	POLICE,
	DISEASE,
	HUNGER,
	EXHAUSTION,
	GENERIC,
}

# ================================================================
# CONFIG
# ================================================================
const IFRAME_DURATION: float = 1.5

const KNOCKBACK_CLIENT: float = 1500.0
const KNOCKBACK_JACK: float = 2500.0
const KNOCKBACK_POLICE: float = 1800.0
const KNOCKBACK_GENERIC: float = 1200.0

const SHAKE_CLIENT: float = 60.0
const SHAKE_JACK: float = 50.0
const SHAKE_POLICE: float = 35.0
const SHAKE_GENERIC: float = 25.0

const PHYSICAL_SOURCES := [
	Source.CLIENT,
	Source.JACK,
	Source.POLICE,
	Source.GENERIC,
]

# ================================================================
# RUNTIME
# ================================================================
var _iframe_timer: float = 0.0
var _iframes_active: bool = false

# ================================================================
# READY / PROCESS
# ================================================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func _process(delta: float) -> void:
	if _iframe_timer <= 0.0:
		_end_iframes()
		return

	_iframe_timer -= delta

	if _iframe_timer <= 0.0:
		_end_iframes()


# ================================================================
# API PÚBLICA
# ================================================================
func take_damage(
	amount: float,
	source: Source = Source.GENERIC,
	knockback_dir: float = 0.0,
	attack_type: String = "Kick"
) -> void:
	if amount <= 0.0:
		return

	if is_physical_source(source) and is_invincible():
		return

	_apply_health_damage(amount)
	damage_taken.emit(amount, source)

	if is_physical_source(source):
		_apply_physical_hit(source, knockback_dir, attack_type)
		_start_iframes()


func take_condition_damage(amount: float, source: Source) -> void:
	# Para enfermedad, hambre, agotamiento, etc.
	# No activa knockback, flash fuerte ni iframes.
	take_damage(amount, source, 0.0, "")


func is_invincible() -> bool:
	return _iframe_timer > 0.0


func clear_invincibility() -> void:
	_end_iframes()


func is_physical_source(source: Source) -> bool:
	return PHYSICAL_SOURCES.has(source)


func source_name(source: Source) -> String:
	return Source.keys()[source]


# ================================================================
# DAÑO / HIT FÍSICO
# ================================================================
func _apply_health_damage(amount: float) -> void:
	if not PlayerStats:
		push_warning("DamageManager: PlayerStats no disponible. No se aplica daño.")
		return

	if PlayerStats.has_method("damage_health"):
		PlayerStats.damage_health(amount)
	else:
		# Fallback defensivo por si se renombra damage_health más adelante.
		var current_health := float(PlayerStats.get("salud"))
		PlayerStats.set("salud", max(0.0, current_health - amount))


func _apply_physical_hit(source: Source, knockback_dir: float, attack_type: String) -> void:
	var knockback_force := _get_knockback_force(source)
	var shake_intensity := _get_shake_intensity(source)

	if knockback_dir != 0.0:
		PlayerManager.apply_knockback(Vector2(knockback_dir, 0.0), knockback_force)

	_apply_player_hit_visual(attack_type)

	if EffectsManager:
		EffectsManager.trauma_shake(shake_intensity, 0.3)

	physical_hit_taken.emit(source, knockback_dir, attack_type)


func _get_knockback_force(source: Source) -> float:
	match source:
		Source.CLIENT:
			return KNOCKBACK_CLIENT
		Source.JACK:
			return KNOCKBACK_JACK
		Source.POLICE:
			return KNOCKBACK_POLICE
		_:
			return KNOCKBACK_GENERIC


func _get_shake_intensity(source: Source) -> float:
	match source:
		Source.CLIENT:
			return SHAKE_CLIENT
		Source.JACK:
			return SHAKE_JACK
		Source.POLICE:
			return SHAKE_POLICE
		_:
			return SHAKE_GENERIC


func _apply_player_hit_visual(attack_type: String) -> void:
	var player := PlayerManager.get_player()
	if not is_instance_valid(player):
		return

	# Flash rojo local del sprite/root del player.
	var tw := create_tween()
	tw.tween_property(player, "modulate", Color(1.5, 0.3, 0.3, 1.0), 0.05)
	tw.tween_property(player, "modulate", Color.WHITE, 0.25)

	# Partículas de golpe, si existen.
	var particles := player.get_node_or_null("HitParticle")
	if particles and particles.has_method("restart"):
		particles.restart()

	# Animación de golpe, si existe AnimationTree.
	if attack_type.strip_edges() == "":
		return

	var animation_tree := player.get_node_or_null("AnimationTree")
	if animation_tree:
		var playback = animation_tree.get("parameters/playback")
		if playback and playback.has_method("travel"):
			playback.travel(attack_type)


# ================================================================
# IFRAMES
# ================================================================
func _start_iframes() -> void:
	_iframe_timer = IFRAME_DURATION
	_iframes_active = true
	set_process(true)
	invincibility_started.emit(IFRAME_DURATION)


func _end_iframes() -> void:
	var was_active := _iframes_active

	_iframe_timer = 0.0
	_iframes_active = false
	set_process(false)

	var player := PlayerManager.get_player()
	if is_instance_valid(player):
		player.modulate.a = 1.0

	if was_active:
		invincibility_ended.emit()
