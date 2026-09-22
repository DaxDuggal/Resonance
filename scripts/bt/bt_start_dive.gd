@tool
extends BTAction
## Starts the dive attack after DiveReady succeeds. The enemy script owns the
## fast vertical rise and the subsequent lower dive; this leaf only selects
## that attack intent.

func _generate_name() -> String:
	return "StartDive"


func _tick(_delta: float) -> Status:
	if not agent.has_method("start_dive"):
		return FAILURE
	return SUCCESS if agent.call("start_dive") else FAILURE
