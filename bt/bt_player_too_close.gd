@tool
extends BTCondition
## Succeeds if the player is in range but horizontally closer than the
## agent's minimum stand-off distance (dive_trigger_min_x) — close enough
## that the agent should back away rather than hold or dive.
## Thin wrapper around the agent's own _player_too_close() so the distance
## math stays owned by the agent script, not duplicated here.

func _generate_name() -> String:
	return "PlayerTooClose"


func _tick(_delta: float) -> Status:
	if agent.call("_player_too_close"):
		return SUCCESS
	return FAILURE
