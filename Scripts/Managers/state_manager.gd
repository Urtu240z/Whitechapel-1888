extends Node
# ================================================================
# STATE MANAGER — Autoload
# Máquina de estados global del juego.
# ================================================================

enum State {
	MENU,
	GAMEPLAY,
	PAUSED,
	JOURNAL,
	DIALOG,
	SLEEPING,
	SHOP,
	TRANSITIONING,
	CLIENT_SERVICE,
}

signal state_changed(from: State, to: State)

var _current: State = State.GAMEPLAY
var _previous: State = State.GAMEPLAY

func _ready() -> void:
	state_changed.connect(_on_state_changed)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN 

func _on_state_changed(_from: State, to: State) -> void:
	match to:
		State.MENU, State.PAUSED, State.JOURNAL, State.SHOP:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		State.GAMEPLAY, State.TRANSITIONING, State.SLEEPING, State.DIALOG, State.CLIENT_SERVICE:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

# ================================================================
# API PÚBLICA
# ================================================================

func current() -> State:
	return _current

func is_state(state: State) -> bool:
	return _current == state

func is_gameplay() -> bool:
	return _current == State.GAMEPLAY

func can_enter(state: State) -> bool:
	match state:
		State.MENU:
			return true
		State.GAMEPLAY:
			return _current == State.MENU or _current == State.TRANSITIONING or _current == State.CLIENT_SERVICE
		State.PAUSED:
			return _current == State.GAMEPLAY
		State.JOURNAL:
			return _current == State.GAMEPLAY
		State.DIALOG:
			return _current == State.GAMEPLAY
		State.SLEEPING:
			return _current == State.GAMEPLAY or _current == State.DIALOG
		State.SHOP:
			return _current == State.GAMEPLAY or _current == State.DIALOG
		State.TRANSITIONING:
			return _current != State.SLEEPING
		State.CLIENT_SERVICE:
			return _current == State.DIALOG or _current == State.GAMEPLAY
	return false

func enter(state: State) -> bool:
	if not can_enter(state):
		push_warning("StateManager: no se puede entrar a %s desde %s" % [
			State.keys()[state], State.keys()[_current]
		])
		return false

	_previous = _current
	_current = state
	state_changed.emit(_previous, _current)

	if OS.is_debug_build():
		print("🎮 Estado: %s → %s" % [State.keys()[_previous], State.keys()[_current]])

	return true

func exit(state: State) -> bool:
	if _current != state:
		push_warning("StateManager: intentando salir de %s pero el estado actual es %s" % [
			State.keys()[state], State.keys()[_current]
		])
		return false

	_previous = _current
	_current = State.GAMEPLAY
	state_changed.emit(_previous, _current)

	if OS.is_debug_build():
		print("🎮 Estado: %s → %s" % [State.keys()[_previous], State.keys()[_current]])

	return true

func force_gameplay() -> void:
	var prev = _current
	_previous = prev
	_current = State.GAMEPLAY
	state_changed.emit(prev, _current)

	if OS.is_debug_build():
		print("🎮 Estado: %s → %s" % [State.keys()[prev], State.keys()[_current]])

	push_warning("StateManager: forzado a GAMEPLAY desde %s" % State.keys()[prev])
