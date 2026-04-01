extends NPC
# ================================================================
# NPC HOSTELKEEPER — npc_hostelkeeper.gd
# Extends NPC base. Nell presses F to start the Dialogic timeline.
#
# DIALOGIC VARIABLES WRITTEN BEFORE TIMELINE:
#   - hostel_price    → float  (2.0 shillings, read as {hostel_price})
#   - hostel_open     → bool   (whether it's open hours)
#   - player_money    → float  (Nell's current money)
#   - player_can_pay  → bool   (dinero >= hostel_price)
#
# DIALOGIC VARIABLE READ AFTER TIMELINE:
#   - hostel_result   → "accepted" | "rejected" | "closed"
#
# SETUP IN INSPECTOR:
#   - dialog_timeline → "res://Dialogues/hostelkeeper_room.dtl"
#   - Place NPC inside Lodge Interior so it's only visible inside
# ================================================================

# ── Constants ─────────────────────────────────────────────────
const HOSTEL_PRICE: float = 2.0
const DIALOGIC_VAR_PRICE:    String = "hostel_price"
const DIALOGIC_VAR_OPEN:     String = "hostel_open"
const DIALOGIC_VAR_MONEY:    String = "player_money"
const DIALOGIC_VAR_CAN_PAY:  String = "player_can_pay"
const DIALOGIC_VAR_RESULT:   String = "hostel_result"

# ================================================================
# READY
# ================================================================

func _ready() -> void:
	super._ready()
	add_to_group("npc_hostelkeepers")

# ================================================================
# START INTERACTION
# Called by player_interaction.gd via InteractionManager (F key).
# Sets Dialogic variables, starts timeline, reads result on end.
# ================================================================

func start_hostel_interaction() -> void:
	var player = PlayerManager.player_instance
	if not is_instance_valid(player):
		return

	if dialog_timeline.is_empty():
		push_warning("NPC Hostelkeeper '%s' has no dialog_timeline set." % name)
		return

	# Face each other
	var facing_right: bool = player.global_position.x > global_position.x
	animation.lock_facing(facing_right)

	# Freeze both
	player.disable_movement()
	movement.freeze()

	# Write Dialogic variables
	var is_open: bool = _hostel_is_open()
	var can_pay: bool = PlayerStats.dinero >= HOSTEL_PRICE

	Dialogic.VAR.set_variable(DIALOGIC_VAR_PRICE,   HOSTEL_PRICE)
	Dialogic.VAR.set_variable(DIALOGIC_VAR_OPEN,    is_open)
	Dialogic.VAR.set_variable(DIALOGIC_VAR_MONEY,   PlayerStats.dinero)
	Dialogic.VAR.set_variable(DIALOGIC_VAR_CAN_PAY, can_pay)
	Dialogic.VAR.set_variable(DIALOGIC_VAR_RESULT,  "")

	# Start timeline
	Dialogic.start(dialog_timeline)

	# Read result when timeline ends
	Dialogic.timeline_ended.connect(_on_timeline_ended, CONNECT_ONE_SHOT)


func _on_timeline_ended() -> void:
	var result: String = str(Dialogic.VAR.get_variable(DIALOGIC_VAR_RESULT))

	match result:
		"accepted":
			_handle_accepted()
		"rejected":
			_handle_rejected()
		"closed":
			_handle_closed()
		_:
			# Fallback — unblock everything
			_restore_state()

# ================================================================
# RESULT HANDLERS
# ================================================================

func _handle_accepted() -> void:
	# Charge money
	var paid: bool = await PlayerStats.gastar_dinero(HOSTEL_PRICE)

	if paid:
		PlayerStats.dias_sin_pagar_hostal = 0
		_restore_state()
		# Hand off to SleepManager — full sleep screen with timer
		SleepManager.start_sleep("hostal")
	else:
		# Shouldn't happen (timeline should block if can't pay),
		# but handle gracefully just in case
		push_warning("Hostelkeeper: accepted but not enough money — state mismatch")
		PlayerStats.dias_sin_pagar_hostal += 1
		_restore_state()


func _handle_rejected() -> void:
	# Player said no — just unblock
	_restore_state()


func _handle_closed() -> void:
	# Timeline ran the "closed" branch (wrong hours)
	# dias_sin_pagar not incremented — Nell chose not to come back
	_restore_state()

# ================================================================
# HELPERS
# ================================================================

func _hostel_is_open() -> bool:
	var hora: float = DayNightManager.hora_actual
	# Open: 22:00 → 10:00
	return hora >= 22.0 or hora < 10.0


func _restore_state() -> void:
	var player = PlayerManager.player_instance
	if is_instance_valid(player):
		player.enable_movement()
	movement.unfreeze()
	animation.unlock_facing()
