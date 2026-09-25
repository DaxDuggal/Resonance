@tool
extends BTAction
## Starts the enemy-specific basic attack through a shared BT interface.

func _generate_name() -> String:
	return "BasicAttack"


func _tick(_delta: float) -> Status:
	if not agent.has_method("start_basic_attack"):
		return FAILURE
	return SUCCESS if agent.call("start_basic_attack") else FAILURE
