@tool
extends BTAction

func _generate_name() -> String:
	return "Attack"


func _tick(_delta: float) -> Status:
	var ready: bool = agent.call("_is_attack_ready")
	if not ready:
		return FAILURE
	agent.call("start_attack")
	return SUCCESS
