@tool
extends BTAction
## Flips the agent's facing_direction and zeroes horizontal velocity, then
## suppresses _update_facing() for turn_lock_time so re-facing the player
## doesn't instantly undo the turn next frame (the player is still across
## whatever hazard triggered this, so without the lock this would flip back
## and forth forever instead of ever actually walking away).
## Instant, one-shot — always returns SUCCESS.

func _generate_name() -> String:
	return "TurnAround"


func _tick(_delta: float) -> Status:
	agent.set("facing_direction", -int(agent.get("facing_direction")))
	agent.velocity.x = 0.0
	agent.set("turn_lock_timer", agent.get("turn_lock_time"))
	return SUCCESS
