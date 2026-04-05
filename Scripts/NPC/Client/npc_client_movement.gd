extends Node
class_name NPCClientMovement

# ============================================================================
# NPC CLIENT MOVEMENT
# Los clientes son estáticos por ahora.
# Este módulo existe para mantener la interfaz freeze/unfreeze
# compatible con player_interaction.gd.
# ============================================================================

# ============================================================================
# ESTADO
# ============================================================================
var npc: CharacterBody2D = null
var is_frozen: bool = false

# ============================================================================
# INIT
# ============================================================================
func initialize(owner_npc: CharacterBody2D) -> void:
	npc = owner_npc

# ============================================================================
# API
# ============================================================================
func freeze() -> void:
	is_frozen = true
	if npc:
		npc.velocity = Vector2.ZERO

func unfreeze() -> void:
	is_frozen = false
	if npc:
		npc.velocity = Vector2.ZERO
