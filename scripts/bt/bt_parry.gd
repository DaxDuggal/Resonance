@tool
extends BTAction
## Starts the enemy's defensive parry window. Enemy subclasses can restrict
## this action through can_start_parry() and consume the resulting hit state.

func _generate_name() -> String:
	return "Parry"


func _tick(_delta: float) -> Status:
	if not agent.has_method("start_parry"):
		return FAILURE
	return SUCCESS if agent.call("start_parry") else FAILURE
