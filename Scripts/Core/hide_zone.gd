extends Node2D
class_name HideZone
# ================================================================
# HIDE ZONE — hide_zone.gd
# Zona donde Nell puede esconderse o completar un acto con cliente.
#
# Lógica al pulsar F dentro del área:
#   - Si hay cliente cercano con deal activo → complete_deal()
#   - Si no                                 → esconderse (HIDING)
#
# También expone una API mínima para futuros sistemas de policía:
#   - is_player_inside()
#   - is_player_hidden_here()
#   - get_hide_strength()
#   - blocks_detection()
# ================================================================

signal hide_state_changed(is_hidden: bool)

@export_group("Interaction")
@export var interaction_label: String = "Esconderse"
@export var exit_interaction_label: String = "Salir del escondite"
@export var interaction_priority: int = 9

@export_group("Police / Detection")
@export_range(0.0, 1.0, 0.05) var hide_strength: float = 1.0
@export var blocks_police_detection: bool = true
@export var allow_client_service: bool = true

@onready var _area: Area2D = $Area2D

var _key_prompt: Node = null
var _nell_inside: bool = false
var _is_hidden_here: bool = false


# ================================================================
# READY
# ================================================================
func _ready() -> void:
	add_to_group("hide_zone")

	_key_prompt = get_node_or_null("KeyPrompt")
	if _key_prompt:
		_key_prompt.hide_prompt()

	if not _area:
		push_error("HideZone: no se encontró Area2D")
		return

	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)


func _exit_tree() -> void:
	InteractionManager.unregister(self)

	if _is_hidden_here and StateManager.is_hiding():
		StateManager.exit_hiding("hide_zone_removed")


# ================================================================
# API PÚBLICA — POLICÍA / DETECCIÓN
# ================================================================
func is_player_inside() -> bool:
	return _nell_inside


func is_player_hidden_here() -> bool:
	return _is_hidden_here and StateManager.is_hiding()


func get_hide_strength() -> float:
	return clampf(hide_strength, 0.0, 1.0)


func blocks_detection() -> bool:
	return blocks_police_detection and is_player_hidden_here()


func can_hide_player() -> bool:
	return _nell_inside and StateManager.can_toggle_hide()


func get_interaction_label() -> String:
	if StateManager.is_hiding() and _is_hidden_here:
		return exit_interaction_label

	return interaction_label


# ================================================================
# DETECCIÓN
# ================================================================
func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_nell_inside = true
		_register_interaction()
		if _key_prompt:
			_key_prompt.show_prompt()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_nell_inside = false
		InteractionManager.unregister(self)

		# Si Nell salía de este escondite concreto, dejar de estar escondida.
		if _is_hidden_here and StateManager.is_hiding():
			StateManager.exit_hiding("exit_hide_zone_by_leaving_area")
			_set_hidden_visual(false)

		if _key_prompt:
			_key_prompt.hide_prompt()


func _register_interaction() -> void:
	InteractionManager.register(
		self,
		interaction_priority,
		_on_interact,
		get_interaction_label()
	)


func _refresh_interaction_label() -> void:
	if not _nell_inside:
		return

	_register_interaction()


# ================================================================
# INTERACCIÓN — F
# ================================================================
func _on_interact() -> void:
	if not _nell_inside:
		return

	# Buscar cliente con deal activo.
	var client := _find_client_with_deal()

	if client and allow_client_service:
		_start_client_deal(client)
	else:
		_toggle_hide()


# ================================================================
# ACTO CON CLIENTE
# ================================================================
func _find_client_with_deal() -> NPCClient:
	for npc in get_tree().get_nodes_in_group("npc_client"):
		var client := npc as NPCClient
		if client and client.has_active_deal():
			return client
	return null


func _start_client_deal(client: NPCClient) -> void:
	InteractionManager.unregister(self)
	await client.complete_deal()

	# complete_deal puede ocultar/restaurar mundo. Si Nell sigue dentro de la zona,
	# recuperamos la interacción sin obligarla a salir y entrar otra vez.
	if _nell_inside and is_inside_tree():
		_register_interaction()


# ================================================================
# ESCONDERSE
# ================================================================
func _toggle_hide() -> void:
	if StateManager.is_hiding():
		if _is_hidden_here:
			StateManager.exit_hiding("exit_hide_zone")
			_set_hidden_visual(false)
		return

	if StateManager.can_toggle_hide():
		if StateManager.enter_hiding("enter_hide_zone"):
			_set_hidden_visual(true)


func _set_hidden_visual(is_hidden: bool) -> void:
	_is_hidden_here = is_hidden
	hide_state_changed.emit(_is_hidden_here)
	_refresh_interaction_label()

	# Oscurecer/aclarar el sprite del gradiente para indicar estado.
	var sprite := get_node_or_null("Sprite2D")
	if not sprite:
		return

	var tw := create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(sprite, "modulate:a", 1.5 if is_hidden else 1.0, 0.3)
