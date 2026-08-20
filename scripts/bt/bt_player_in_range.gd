@tool
extends BTCondition
## Succeeds if Global.player exists and is within the agent's detection_range.
## Generic-ish on purpose (reads detection_range/move_speed dynamically off
## the agent rather than casting to FlyingEnemy) so it isn't locked to one
## enemy type if it turns out to be reusable later.

func _generate_name() -> String:
	return "PlayerInRange"


func _tick(_delta: float) -> Status:
	if not Global.player:
		return FAILURE
	var range_value: float = agent.get("detection_range")
	if agent.global_position.distance_to(Global.player.global_position) <= range_value:
		return SUCCESS
	return FAILURE
