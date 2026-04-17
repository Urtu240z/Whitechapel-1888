extends Node
# ================================================================
# INTERACTION MANAGER — Autoload
# Centraliza todas las interacciones con F.
# Cada interactuable se registra al entrar al área del jugador
# y se desregistra al salir.
# ================================================================

enum Priority { PICKUP = 1, NPC = 5, BUILDING = 10 }

var _interactables: Array[Dictionary] = []
# Cada entrada: { "node": Node, "priority": int, "callback": Callable }

# ================================================================
# REGISTRAR / DESREGISTRAR
# ================================================================

func register(node: Node, priority: int, callback: Callable) -> void:
	for entry in _interactables:
		if entry["node"] == node:
			return

	_interactables.append({ "node": node, "priority": priority, "callback": callback })


func unregister(node: Node) -> void:
	_interactables = _interactables.filter(func(e): return e["node"] != node)

# ================================================================
# PROCESO — llamado desde el player
# ================================================================

func try_interact() -> bool:
	if _interactables.is_empty():
		return false

	# Limpiar nodos inválidos
	_interactables = _interactables.filter(func(e): return is_instance_valid(e["node"]))

	# Ordenar: mayor prioridad primero, empate → más cercano al jugador
	var player = PlayerManager.player_instance
	_interactables.sort_custom(func(a, b):
		if a["priority"] != b["priority"]:
			return a["priority"] > b["priority"]
		if player:
			var da = player.global_position.distance_to(a["node"].global_position)
			var db = player.global_position.distance_to(b["node"].global_position)
			return da < db
		return false
	)

	_interactables[0]["callback"].call()
	return true
