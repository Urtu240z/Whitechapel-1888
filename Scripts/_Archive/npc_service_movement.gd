extends Node
class_name NPCServiceMovement

# ============================================================================
# NPC SERVICE MOVEMENT
# Este NPC no se mueve como los NPC genéricos.
# Este módulo existe para mantener una interfaz simple de freeze/unfreeze.
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
