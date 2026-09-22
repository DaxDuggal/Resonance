@tool
extends BTCondition
## Succeeds when the flying enemy's close-range swipe can start.
## The enemy owns the exact range, facing, cooldown, and awareness rules.

func _generate_name() -> String:
	return "SwipeReady"


func _tick(_delta: float) -> Status:
	if not agent.has_method("_is_swipe_ready"):
		return FAILURE
	return SUCCESS if agent.call("_is_swipe_ready") else FAILURE
