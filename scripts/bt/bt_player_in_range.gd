@tool
extends BTCondition
## Succeeds if the agent is currently aware of the player — not just in
## range, but actually able to see them (facing-relative sight cone, blocked
## by World geometry, plus a point-blank override) per Enemy._update_awareness().
## Delegates to the agent's own _player_in_range() rather than recomputing
## anything here, so this leaf and the agent's internal facing/attack logic
## always agree on what "in range" means.

func _generate_name() -> String:
	return "PlayerInRange"


func _tick(_delta: float) -> Status:
	if agent.call("_player_in_range"):
		return SUCCESS
	return FAILURE
