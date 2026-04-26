extends Node

# ================================================================
# STATE MANAGER — Autoload
# ================================================================
# Autoridad única del estado global del juego.
#
# Reglas:
# - No mueve al player. Eso pertenece a PlayerManager.
# - No abre UI directamente. Solo autoriza estados.
# - No pausa audio. Eso pertenece a WorldAudioManager.
# - No oculta/muestra mundo. Eso pertenece a LevelRoot / BuildingEntrance.
#
# HIDING = Nell está escondida en una HideZone.
# ================================================================


# ================================================================
# ESTADOS GLOBALES
# ================================================================
enum State {
	MENU,
	GAMEPLAY,
	HIDING,
	DEBUG_MENU,
	PAUSED,
	JOURNAL,
	DIALOG,
	SHOP,
	SLEEPING,
	TRANSITIONING,
	CLIENT_SERVICE,
	CUTSCENE,
	GAME_OVER,
}


# ================================================================
# SEÑALES
# ================================================================
signal state_changed(from_state: State, to_state: State)
signal state_pushed(from_state: State, to_state: State)
signal state_popped(from_state: State, to_state: State)
signal invalid_transition_requested(from_state: State, to_state: State, reason: String)


# ================================================================
# CONFIG
# ================================================================
const DEBUG_LOGS: bool = true

@export var initial_state: State = State.GAMEPLAY


# ================================================================
# RUNTIME
# ================================================================
var _current_state: State
var _previous_state: State
var _state_stack: Array[State] = []


# ================================================================
# READY
# ================================================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_current_state = initial_state
	_previous_state = initial_state

	_apply_mouse_mode(_current_state)

	if OS.is_debug_build() and DEBUG_LOGS:
		print("🎮 StateManager iniciado en: %s" % get_state_name(_current_state))


# ================================================================
# GETTERS
# ================================================================
func current() -> State:
	return _current_state


func previous() -> State:
	return _previous_state


func current_name() -> String:
	return get_state_name(_current_state)


func previous_name() -> String:
	return get_state_name(_previous_state)


func get_state_name(state: State) -> String:
	return State.keys()[state]


func is_state(state: State) -> bool:
	return _current_state == state


func is_any_state(states: Array[State]) -> bool:
	return states.has(_current_state)


func is_gameplay() -> bool:
	return _current_state == State.GAMEPLAY


func is_menu() -> bool:
	return _current_state == State.MENU


func is_hiding() -> bool:
	return _current_state == State.HIDING


func is_debug_menu() -> bool:
	return _current_state == State.DEBUG_MENU


func is_paused() -> bool:
	return _current_state == State.PAUSED


func is_journal() -> bool:
	return _current_state == State.JOURNAL


func is_dialog() -> bool:
	return _current_state == State.DIALOG


func is_shop() -> bool:
	return _current_state == State.SHOP


func is_sleeping() -> bool:
	return _current_state == State.SLEEPING


func is_transitioning() -> bool:
	return _current_state == State.TRANSITIONING


func is_client_service() -> bool:
	return _current_state == State.CLIENT_SERVICE


func is_cutscene() -> bool:
	return _current_state == State.CUTSCENE


func is_game_over() -> bool:
	return _current_state == State.GAME_OVER


# ================================================================
# CLASIFICADORES DE ESTADO
# ================================================================
func is_ui_state() -> bool:
	return (
		_current_state == State.MENU
		or _current_state == State.PAUSED
		or _current_state == State.JOURNAL
		or _current_state == State.SHOP
		or _current_state == State.DEBUG_MENU
		or _current_state == State.GAME_OVER
	)


func is_world_locked_state() -> bool:
	return (
		_current_state == State.PAUSED
		or _current_state == State.JOURNAL
		or _current_state == State.SLEEPING
		or _current_state == State.TRANSITIONING
		or _current_state == State.CLIENT_SERVICE
		or _current_state == State.CUTSCENE
		or _current_state == State.GAME_OVER
	)


func is_hard_lock_state() -> bool:
	return (
		_current_state == State.SLEEPING
		or _current_state == State.TRANSITIONING
		or _current_state == State.CLIENT_SERVICE
		or _current_state == State.CUTSCENE
		or _current_state == State.GAME_OVER
	)


func is_player_control_state() -> bool:
	return _current_state == State.GAMEPLAY


func is_dialogue_related_state() -> bool:
	return (
		_current_state == State.DIALOG
		or _current_state == State.SHOP
		or _current_state == State.CLIENT_SERVICE
	)


# ================================================================
# PERMISOS DEL JUEGO
# ================================================================
func can_move_player() -> bool:
	return _current_state == State.GAMEPLAY


func can_interact() -> bool:
	return (
		_current_state == State.GAMEPLAY
		or _current_state == State.HIDING
	)


func can_toggle_hide() -> bool:
	return (
		_current_state == State.GAMEPLAY
		or _current_state == State.HIDING
	)


func can_open_pause() -> bool:
	return (
		_current_state == State.GAMEPLAY
		or _current_state == State.HIDING
	)


func can_open_journal() -> bool:
	return _current_state == State.GAMEPLAY


func can_start_dialog() -> bool:
	return _current_state == State.GAMEPLAY


func can_open_shop() -> bool:
	return (
		_current_state == State.GAMEPLAY
		or _current_state == State.DIALOG
	)


func can_start_sleep() -> bool:
	return (
		_current_state == State.GAMEPLAY
		or _current_state == State.DIALOG
	)


func can_start_client_service() -> bool:
	return (
		_current_state == State.GAMEPLAY
		or _current_state == State.DIALOG
	)


func can_start_transition() -> bool:
	return (
		_current_state == State.GAMEPLAY
		or _current_state == State.HIDING
		or _current_state == State.MENU
		or _current_state == State.CUTSCENE
	)


func can_advance_time() -> bool:
	return (
		_current_state == State.GAMEPLAY
		or _current_state == State.HIDING
		or _current_state == State.SLEEPING
		or _current_state == State.DIALOG
	)


func can_process_world() -> bool:
	return (
		_current_state == State.GAMEPLAY
		or _current_state == State.HIDING
		or _current_state == State.DIALOG
	)


func should_block_gameplay_input() -> bool:
	return _current_state != State.GAMEPLAY


# ================================================================
# CAMBIO DE ESTADO PRINCIPAL
# ================================================================
func change_to(target_state: State, reason: String = "") -> bool:
	if target_state == _current_state:
		return true

	if not can_change_to(target_state):
		_emit_invalid_transition(target_state, reason)
		return false

	_set_state(target_state, reason)
	return true


func can_change_to(target_state: State) -> bool:
	if target_state == _current_state:
		return true

	match _current_state:
		State.MENU:
			return (
				target_state == State.GAMEPLAY
				or target_state == State.TRANSITIONING
				or target_state == State.CUTSCENE
			)

		State.GAMEPLAY:
			return (
				target_state == State.MENU
				or target_state == State.HIDING
				or target_state == State.PAUSED
				or target_state == State.JOURNAL
				or target_state == State.DIALOG
				or target_state == State.SHOP
				or target_state == State.SLEEPING
				or target_state == State.TRANSITIONING
				or target_state == State.CLIENT_SERVICE
				or target_state == State.CUTSCENE
				or target_state == State.GAME_OVER
				or target_state == State.DEBUG_MENU
			)

		State.HIDING:
			return (
				target_state == State.GAMEPLAY
				or target_state == State.PAUSED
				or target_state == State.TRANSITIONING
				or target_state == State.CUTSCENE
				or target_state == State.GAME_OVER
				or target_state == State.DEBUG_MENU
			)

		State.PAUSED:
			return (
				target_state == State.GAMEPLAY
				or target_state == State.HIDING
				or target_state == State.MENU
			)

		State.JOURNAL:
			return (
				target_state == State.GAMEPLAY
				or target_state == State.PAUSED
			)

		State.DIALOG:
			return (
				target_state == State.GAMEPLAY
				or target_state == State.SHOP
				or target_state == State.SLEEPING
				or target_state == State.CLIENT_SERVICE
				or target_state == State.CUTSCENE
				or target_state == State.TRANSITIONING
				or target_state == State.GAME_OVER
			)

		State.SHOP:
			return (
				target_state == State.GAMEPLAY
				or target_state == State.DIALOG
				or target_state == State.PAUSED
			)

		State.SLEEPING:
			return (
				target_state == State.GAMEPLAY
				or target_state == State.TRANSITIONING
				or target_state == State.CUTSCENE
				or target_state == State.GAME_OVER
			)

		State.TRANSITIONING:
			return (
				target_state == State.GAMEPLAY
				or target_state == State.HIDING
				or target_state == State.MENU
				or target_state == State.DIALOG
				or target_state == State.SHOP
				or target_state == State.SLEEPING
				or target_state == State.CLIENT_SERVICE
				or target_state == State.CUTSCENE
				or target_state == State.GAME_OVER
			)

		State.CLIENT_SERVICE:
			return (
				target_state == State.GAMEPLAY
				or target_state == State.TRANSITIONING
				or target_state == State.CUTSCENE
				or target_state == State.GAME_OVER
			)

		State.CUTSCENE:
			return (
				target_state == State.GAMEPLAY
				or target_state == State.MENU
				or target_state == State.DIALOG
				or target_state == State.TRANSITIONING
				or target_state == State.GAME_OVER
			)

		State.GAME_OVER:
			return (
				target_state == State.MENU
				or target_state == State.GAMEPLAY
			)
		State.DEBUG_MENU:
			return (
				target_state == State.GAMEPLAY
				or target_state == State.HIDING
	)
	return false


# ================================================================
# STACK DE ESTADOS
# ================================================================
# Útil para estados temporales:
#
# GAMEPLAY -> JOURNAL -> GAMEPLAY
# GAMEPLAY -> PAUSED  -> GAMEPLAY
# HIDING   -> PAUSED  -> HIDING
# DIALOG   -> SHOP    -> DIALOG
#
# No usar para:
# - muerte
# - cambio de escena complejo
# - sueño completo
# - client service
# ================================================================
func push_state(target_state: State, reason: String = "") -> bool:
	if target_state == _current_state:
		return true

	if not can_change_to(target_state):
		_emit_invalid_transition(target_state, reason)
		return false

	var from_state: State = _current_state
	_state_stack.append(from_state)

	_set_state(target_state, reason)
	state_pushed.emit(from_state, target_state)

	return true


func pop_state(reason: String = "") -> bool:
	if _state_stack.is_empty():
		push_warning("StateManager.pop_state(): la pila está vacía. No se puede volver al estado anterior.")
		return false

	var from_state: State = _current_state
	var target_state: State = _state_stack.pop_back()

	if target_state == from_state:
		push_warning("StateManager.pop_state(): el estado anterior es igual al actual: %s" % get_state_name(from_state))
		return false

	if not can_change_to(target_state):
		_emit_invalid_transition(target_state, reason)
		return false

	_set_state(target_state, reason)
	state_popped.emit(from_state, target_state)

	return true


func clear_stack() -> void:
	_state_stack.clear()


func has_stack() -> bool:
	return not _state_stack.is_empty()


func stack_size() -> int:
	return _state_stack.size()


# ================================================================
# HELPERS DE SALIDA EXPLÍCITA
# ================================================================
func return_to_gameplay(reason: String = "") -> bool:
	clear_stack()
	return change_to(State.GAMEPLAY, reason)


func return_to_menu(reason: String = "") -> bool:
	clear_stack()
	return change_to(State.MENU, reason)


func go_to_game_over(reason: String = "") -> bool:
	clear_stack()
	return change_to(State.GAME_OVER, reason)


func enter_hiding(reason: String = "enter_hiding") -> bool:
	return change_to(State.HIDING, reason)


func exit_hiding(reason: String = "exit_hiding") -> bool:
	return change_to(State.GAMEPLAY, reason)

# ================================================================
# FORZADOS
# ================================================================
# Usar solo para carga de partida, debug o recuperación de errores.
# ================================================================
func force_state(target_state: State, reason: String = "") -> void:
	var from_state: State = _current_state

	clear_stack()
	_set_state_without_validation(target_state, reason)

	push_warning("StateManager.force_state(): %s -> %s. Motivo: %s" % [
		get_state_name(from_state),
		get_state_name(target_state),
		reason
	])


func force_gameplay_after_load() -> void:
	force_state(State.GAMEPLAY, "load_game")


# ================================================================
# INTERNO
# ================================================================
func _set_state(target_state: State, reason: String = "") -> void:
	var from_state: State = _current_state

	_previous_state = from_state
	_current_state = target_state

	_apply_mouse_mode(_current_state)
	state_changed.emit(from_state, target_state)

	_debug_log_transition(from_state, target_state, reason)


func _set_state_without_validation(target_state: State, reason: String = "") -> void:
	var from_state: State = _current_state

	_previous_state = from_state
	_current_state = target_state

	_apply_mouse_mode(_current_state)
	state_changed.emit(from_state, target_state)

	_debug_log_transition(from_state, target_state, reason)


func _apply_mouse_mode(state: State) -> void:
	match state:
		State.MENU, State.PAUSED, State.JOURNAL, State.SHOP, State.GAME_OVER, State.DEBUG_MENU:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

		State.GAMEPLAY, State.HIDING, State.DIALOG, State.SLEEPING, State.TRANSITIONING, State.CLIENT_SERVICE, State.CUTSCENE:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _emit_invalid_transition(target_state: State, reason: String = "") -> void:
	var msg := "StateManager: transición inválida %s -> %s" % [
		get_state_name(_current_state),
		get_state_name(target_state)
	]

	if reason != "":
		msg += " | Motivo: %s" % reason

	push_warning(msg)
	invalid_transition_requested.emit(_current_state, target_state, reason)


func _debug_log_transition(from_state: State, target_state: State, reason: String = "") -> void:
	if not OS.is_debug_build():
		return

	if not DEBUG_LOGS:
		return

	var msg := "🎮 Estado: %s → %s" % [
		get_state_name(from_state),
		get_state_name(target_state)
	]

	if reason != "":
		msg += "  |  %s" % reason

	print(msg)
