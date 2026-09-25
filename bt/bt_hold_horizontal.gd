@tool
extends BTAction
## Eases the agent's horizontal velocity to 0 — the "in the comfortable
## band, nothing to do" fallback (also covers "player not in range at
## all"). Smoothed via move_toward rather than an instant snap (see
## bt_halt_horizontal.gd for that version, used by grounded agents) so
## holding position doesn't look like the agent hit a wall mid-air.
## Continuous action — always returns RUNNING.

func _generate_name() -> String:
	return "HoldHorizontal"


func _tick(delta: float) -> Status:
	var move_speed: float = agent.get("move_speed")
	var accel_mult: float = agent.get("flight_accel_mult")
	agent.velocity.x = move_toward(agent.velocity.x, 0.0, move_speed * accel_mult * delta)
	return RUNNING
