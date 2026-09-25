@tool
extends BTCondition
## Succeeds if the player is in range but horizontally farther than the
## agent's chase threshold (min_chase_distance) — far enough that the
## agent should close the distance rather than hold or dive.
## Thin wrapper around the agent's own _player_too_far() so the distance
## math stays owned by the agent script, not duplicated here.

func _generate_name() -> String:
	return "PlayerTooFar"


func _tick(_delta: float) -> Status:
	if agent.call("_player_too_far"):
		return SUCCESS
	return FAILURE
