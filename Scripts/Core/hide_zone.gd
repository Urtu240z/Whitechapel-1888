extends Node2D
# ================================================================
# HIDE ZONE — hide_zone.gd
# Zona donde Nell puede esconderse o completar un acto con cliente.
#
# Lógica al pulsar F dentro del área:
#   - Si hay cliente cercano con deal activo → complete_deal()
#   - Si no                                 → esconderse (HIDDEN)
# ================================================================

@onready var _area: Area2D = $Area2D

var _nell_inside: bool = false

# ================================================================
# READY
# ================================================================
func _ready() -> void:
	if not _area:
		push_error("HideZone: no se encontró Area2D")
		return
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)

# ================================================================
# DETECCIÓN
# ================================================================
func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_nell_inside = true
		InteractionManager.register(self, InteractionManager.Priority.BUILDING, _on_interact)

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_nell_inside = false
		InteractionManager.unregister(self)
		# Si salía escondida, dejar de estarlo
		if StateManager.is_state(StateManager.State.HIDDEN):
			StateManager.exit(StateManager.State.HIDDEN)

# ================================================================
# INTERACCIÓN — F
# ================================================================
func _on_interact() -> void:
	if not _nell_inside:
		return

	# Buscar cliente con deal activo
	var client := _find_client_with_deal()

	if client:
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
	# complete_deal hace queue_free del cliente — la zona queda libre

# ================================================================
# ESCONDERSE
# ================================================================
func _toggle_hide() -> void:
	if StateManager.is_state(StateManager.State.HIDDEN):
		# Salir de escondite
		StateManager.exit(StateManager.State.HIDDEN)
		_set_hidden_visual(false)
	elif StateManager.can_enter(StateManager.State.HIDDEN):
		StateManager.enter(StateManager.State.HIDDEN)
		_set_hidden_visual(true)

func _set_hidden_visual(is_hidden: bool) -> void:
	# Oscurecer/aclarar el sprite del gradiente para indicar estado
	var sprite := get_node_or_null("Sprite2D")
	if not sprite:
		return
	var tw := create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(sprite, "modulate:a", 1.5 if is_hidden else 1.0, 0.3)
