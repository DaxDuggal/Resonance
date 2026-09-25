@tool
extends BTAction
## Starts the enemy-specific special attack through a shared BT interface.

func _generate_name() -> String:
	return "SpecialAttack"


func _tick(_delta: float) -> Status:
	if not agent.has_method("start_special_attack"):
		return FAILURE
	return SUCCESS if agent.call("start_special_attack") else FAILURE
