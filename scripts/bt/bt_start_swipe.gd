@tool
extends BTAction
## Starts the flying enemy's quick swipe after SwipeReady succeeds.

func _generate_name() -> String:
	return "StartSwipe"


func _tick(_delta: float) -> Status:
	if not agent.has_method("start_swipe"):
		return FAILURE
	return SUCCESS if agent.call("start_swipe") else FAILURE
