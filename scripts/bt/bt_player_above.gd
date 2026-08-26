@tool
extends BTCondition
## Succeeds if the player is in range and high enough above the agent to
## warrant a hop-up-to-reach jump, rather than a horizontal chase.
## Thin wrapper around the agent's own _is_player_above() so the raycast/
## height-threshold math stays owned by the agent script, not duplicated here.

func _generate_name() -> String:
	return "PlayerAbove"


func _tick(_delta: float) -> Status:
	if agent.call("_is_player_above"):
		return SUCCESS
	return FAILURE
