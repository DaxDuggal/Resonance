@tool
extends BTCondition
## Succeeds when the flying enemy's long-range dive can start.
## The enemy owns the horizontal distance gate, awareness, cooldown, and any
## additional altitude/attack-state checks.

func _generate_name() -> String:
	return "DiveReady"


func _tick(_delta: float) -> Status:
	if not agent.has_method("_is_dive_ready"):
		return FAILURE
	return SUCCESS if agent.call("_is_dive_ready") else FAILURE
